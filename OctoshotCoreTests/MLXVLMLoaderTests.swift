import AppKit
import XCTest
import OctoshotEmbeddedMLX

final class MLXVLMLoaderTests: XCTestCase {
    #if EMBEDDED_MLX
    @MainActor
    func testInvalidLimitsFailBeforeLoadingModel() async {
        let limits: [(Int, TimeInterval?, TimeInterval)] = [
            (0, 120, 300), (-1, 120, 300),
            (256, 0, 300), (256, .infinity, 300), (256, .nan, 300),
            (256, 86401, 300), (256, nil, -1), (256, nil, .infinity),
            (256, nil, .nan), (256, nil, 86401)
        ]
        for (maxTokens, timeout, idleDelay) in limits {
            do {
                _ = try await MLXVLMLoader.shared.respond(
                    prompt: "test", image: NSImage(size: NSSize(width: 1, height: 1)),
                    modelDirectory: URL(fileURLWithPath: "/nonexistent-octoshot-model"),
                    maxTokens: maxTokens, timeout: timeout, idleUnloadDelay: idleDelay)
                XCTFail("Invalid limits must fail before loading")
            } catch {
                XCTAssertEqual((error as NSError).domain, "Octoshot.MLX")
                XCTAssertEqual((error as NSError).code, 1)
            }
        }
    }

    @MainActor
    func testAlreadyCancelledRequestDoesNotLoadModel() async {
        let task = Task { @MainActor in
            try await MLXVLMLoader.shared.respond(
                prompt: "test", image: NSImage(size: NSSize(width: 1, height: 1)),
                modelDirectory: URL(fileURLWithPath: "/nonexistent-octoshot-model"))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled request must fail before loading")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
    #else
    @MainActor
    func testDisabledBuildRemainsSourceCompatible() async {
        do {
            _ = try await MLXVLMLoader.shared.respond(
                prompt: "test", image: NSImage(), modelDirectory: URL(fileURLWithPath: "/unused"))
            XCTFail("Disabled builds must report unavailable")
        } catch MLXVLMLoaderError.inferenceUnavailableInThisBuild {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    #endif
}
