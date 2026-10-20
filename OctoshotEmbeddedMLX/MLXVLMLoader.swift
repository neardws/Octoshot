import AppKit
import Foundation

#if EMBEDDED_MLX
import MLX
import Metal
import MLXVLM
import MLXLMCommon
#endif

public enum MLXVLMLoaderError: Error {
    case inferenceUnavailableInThisBuild
    case sessionUnavailable
    case imageEncodingFailed
}

/// Loads SmolVLM2 from the supplied model directory.
@MainActor
public enum MLXVLMLoader {
    public static let shared = Loader()

    /// Reuse only the model container: retained sessions carry KV/history across screenshots.
    /// Bound generation tokens so missing EOS cannot grow the live KV cache indefinitely.
    /// Clear per-request sessions and temporary PNGs, and unload idle model weights.
    /// The GPU buffer-cache budget limits reusable buffers, not live tensors or total memory.
    /// Timeouts and cancellation are cooperative, not a GPU or process kill.
    @MainActor
    public final class Loader {
        #if EMBEDDED_MLX
        private var container: ModelContainer?
        private var loadedDirectory: URL?
        private var requestTask: Task<String, Error>?
        private var idleTask: Task<Void, Never>?
        private var hasConfiguredGPU = false
        #endif

        public func respond(
            prompt: String, image: NSImage, modelDirectory: URL,
            maxTokens: Int = 256, timeout: TimeInterval? = 120,
            idleUnloadDelay: TimeInterval = 300
        ) async throws -> String {
            #if EMBEDDED_MLX
            guard maxTokens > 0,
                  timeout.map({ $0.isFinite && $0 > 0 && $0 <= 86400 }) ?? true,
                  idleUnloadDelay.isFinite && idleUnloadDelay >= 0 && idleUnloadDelay <= 86400 else {
                throw NSError(domain: "Octoshot.MLX", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid token limit, timeout, or idle delay."
                ])
            }
            try Task.checkCancellation()
            guard requestTask == nil else {
                throw NSError(domain: "Octoshot.MLX", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "An on-device vision request is already running."
                ])
            }
            guard !MTLCopyAllDevices().isEmpty else {
                throw NSError(domain: "Octoshot.MLX", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "No Metal GPU is available to this process."
                ])
            }
            idleTask?.cancel()
            idleTask = nil
            Memory.cacheLimit = 256 * 1024 * 1024
            hasConfiguredGPU = true
            let task = Task { @MainActor in
                try await self.performRespond(
                    prompt: prompt, image: image, modelDirectory: modelDirectory, maxTokens: maxTokens)
            }
            requestTask = task
            var timedOut = false
            let timeoutTask = timeout.map { seconds in
                Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                        timedOut = true
                        task.cancel()
                    } catch {}
                }
            }
            defer {
                timeoutTask?.cancel()
                requestTask = nil
                Memory.clearCache()
                scheduleIdleUnload(after: idleUnloadDelay)
            }
            do {
                return try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
            } catch {
                if timedOut {
                    throw NSError(domain: "Octoshot.MLX", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "On-device vision request timed out."
                    ])
                }
                throw error
            }
            #else
            throw MLXVLMLoaderError.inferenceUnavailableInThisBuild
            #endif
        }

        public func unload() {
            #if EMBEDDED_MLX
            idleTask?.cancel()
            idleTask = nil
            requestTask?.cancel()
            container = nil
            loadedDirectory = nil
            if hasConfiguredGPU { Memory.clearCache() }
            #endif
        }

        #if EMBEDDED_MLX
        private func scheduleIdleUnload(after seconds: TimeInterval) {
            guard container != nil else { return }
            idleTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    self?.unload()
                } catch {}
            }
        }

        private func performRespond(
            prompt: String, image: NSImage, modelDirectory: URL, maxTokens: Int
        ) async throws -> String {
            try await ensureLoaded(modelDirectory: modelDirectory)
            try Task.checkCancellation()
            guard let container else { throw MLXVLMLoaderError.sessionUnavailable }
            let imageURL = try writeTempPNG(image)
            defer { try? FileManager.default.removeItem(at: imageURL) }
            let session = ChatSession(container, generateParameters: GenerateParameters(
                maxTokens: maxTokens, temperature: 0.1))
            // repetitionPenalty crashes in mlx-swift-lm 2.31.3 VLM path
            // ([broadcast_shapes] (64) vs (prompt len)); rely on maxTokens instead.
            do {
                let response = try await session.respond(to: prompt, image: .url(imageURL))
                await session.clear()
                try Task.checkCancellation()
                return response
            } catch {
                await session.clear()
                throw error
            }
        }

        private func ensureLoaded(modelDirectory: URL) async throws {
            let directory = modelDirectory.standardizedFileURL
            if container != nil && loadedDirectory == directory { return }
            container = nil
            loadedDirectory = nil
            Memory.clearCache()
            let configuration = ModelConfiguration(directory: directory)
            let loaded = try await VLMModelFactory.shared.loadContainer(configuration: configuration)
            try Task.checkCancellation()
            container = loaded
            loadedDirectory = directory
        }

        private func writeTempPNG(_ image: NSImage) throws -> URL {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw MLXVLMLoaderError.imageEncodingFailed
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("octoshot-vlm-\(UUID().uuidString).png")
            try png.write(to: url, options: .atomic)
            return url
        }
        #endif
    }
}
