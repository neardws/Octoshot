import AppKit
import Foundation

#if EMBEDDED_MLX
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

    public final class Loader {
        #if EMBEDDED_MLX
        private var session: ChatSession?
        private var loadTask: Task<Void, Error>?
        #endif

        public func respond(prompt: String, image: NSImage, modelDirectory: URL) async throws -> String {
            #if EMBEDDED_MLX
            try await ensureLoaded(modelDirectory: modelDirectory)
            guard let session else { throw MLXVLMLoaderError.sessionUnavailable }
            let imageURL = try writeTempPNG(image)
            return try await session.respond(to: prompt, image: .url(imageURL))
            #else
            throw MLXVLMLoaderError.inferenceUnavailableInThisBuild
            #endif
        }

        #if EMBEDDED_MLX
        private func ensureLoaded(modelDirectory: URL) async throws {
            if session != nil { return }
            if let loadTask {
                try await loadTask.value
                return
            }
            let task = Task { @MainActor in
                let configuration = ModelConfiguration(directory: modelDirectory)
                let container = try await VLMModelFactory.shared.loadContainer(configuration: configuration)
                self.session = ChatSession(container)
            }
            loadTask = task
            try await task.value
            loadTask = nil
        }

        private func writeTempPNG(_ image: NSImage) throws -> URL {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                throw MLXVLMLoaderError.imageEncodingFailed
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("octoshot-vlm-\(UUID().uuidString).png")
            try png.write(to: url)
            return url
        }
        #endif
    }
}
