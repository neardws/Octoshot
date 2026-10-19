import AppKit
import Foundation
import OctoshotCore
import OctoshotEmbeddedMLX

@MainActor
final class LocalVLMService: EmbeddedVisionBackend, @unchecked Sendable {
    static let shared = LocalVLMService()

    private init() {}

    func isReady() -> Bool {
        EmbeddedAIModelPaths.isInstalled(.smolVLM2_500M_4bit)
    }

    func complete(prompt: String, image: NSImage) async throws -> String {
        guard isReady() else { throw EmbeddedAIError.modelNotInstalled(.smolVLM2_500M_4bit) }
        do {
            return try await MLXVLMLoader.shared.respond(
                prompt: prompt,
                image: image,
                modelDirectory: EmbeddedAIModelPaths.directory(for: .smolVLM2_500M_4bit)
            )
        } catch let error as MLXVLMLoaderError {
            switch error {
            case .inferenceUnavailableInThisBuild:
                throw EmbeddedAIError.inferenceUnavailableInThisBuild
            case .sessionUnavailable, .imageEncodingFailed:
                throw EmbeddedAIError.backendMissing
            }
        }
    }

    func stream(prompt: String, image: NSImage) -> AsyncThrowingStream<String, Error> {
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
