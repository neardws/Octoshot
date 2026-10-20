import XCTest
import Vision
@testable import OctoshotCore

final class OCRServiceTests: XCTestCase {
    private enum PerformError: Error, Equatable {
        case failed
    }

    func testPerformErrorPropagates() async {
        do {
            _ = try await OCRService.recognizeText { _ in
                throw PerformError.failed
            }
            XCTFail("Expected perform to throw")
        } catch {
            XCTAssertEqual(error as? PerformError, .failed)
        }
    }

    func testCompletionAttemptThenThrowPropagatesOnlyPerformError() async {
        do {
            _ = try await OCRService.recognizeText { request in
                XCTAssertNil(request.completionHandler)
                request.completionHandler?(request, nil)
                request.completionHandler?(request, PerformError.failed)
                throw PerformError.failed
            }
            XCTFail("Expected perform to throw after completion attempts")
        } catch {
            XCTAssertEqual(error as? PerformError, .failed)
        }
    }

    @MainActor
    func testPerformRunsOffMainThreadWithAccurateConfiguration() async throws {
        let result = try await OCRService.recognizeText { request in
            XCTAssertFalse(Thread.isMainThread)
            let textRequest = try XCTUnwrap(request as? VNRecognizeTextRequest)
            XCTAssertNil(textRequest.completionHandler)
            XCTAssertEqual(textRequest.recognitionLevel, .accurate)
            XCTAssertTrue(textRequest.usesLanguageCorrection)
            XCTAssertEqual(textRequest.recognitionLanguages, ["zh-Hans", "en-US"])
        }
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.lines, [])
    }

    func testResultPreservesLinesAndJoinsWithNewlines() {
        let result = OCRService.result(from: ["a", "b"])
        XCTAssertEqual(result.text, "a\nb")
        XCTAssertEqual(result.lines, ["a", "b"])
    }

    func testEmptyLinesProduceEmptyResult() {
        let result = OCRService.result(from: [])
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.lines, [])
    }
}
