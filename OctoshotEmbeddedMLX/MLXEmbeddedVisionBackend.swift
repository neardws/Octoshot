import AppKit
import Foundation
import OctoshotCore

/// Shared MLX vision backend for the app and CLI prototype commands.
@MainActor
public final class MLXEmbeddedVisionBackend: EmbeddedVisionBackend, @unchecked Sendable {
    public static let shared = MLXEmbeddedVisionBackend()

    private init() {}

    public func isReady() -> Bool {
        EmbeddedAIModelPaths.isInstalled(.smolVLM2_500M_4bit)
    }

    public func complete(prompt: String, image: NSImage) async throws -> String {
        guard isReady() else { throw EmbeddedAIError.modelNotInstalled(.smolVLM2_500M_4bit) }
        return try await MLXVLMLoader.shared.respond(prompt: prompt, image: image)
    }

    public func stream(prompt: String, image: NSImage) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await complete(prompt: prompt, image: image)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
