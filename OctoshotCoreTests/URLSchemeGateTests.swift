import XCTest
@testable import OctoshotCore

final class URLSchemeGateTests: XCTestCase {
    private func kind(_ string: String) -> URLSchemeGate.RequestKind {
        URLSchemeGate.classify(URL(string: string)!)
    }

    func testClassifiesCaptureRequests() {
        XCTAssertEqual(kind("octoshot://capture"), .silentCapture)
        XCTAssertEqual(kind("octoshot://capture?mode=fullscreen"), .silentCapture)
        XCTAssertEqual(kind("octoshot://capture?mode=display&display_id=2"), .silentCapture)
        XCTAssertEqual(kind("octoshot://capture?mode=area"), .interactive)
        XCTAssertEqual(kind("octoshot://capture?mode=Window"), .interactive)
        XCTAssertEqual(kind("octoshot://capture?mode=bogus"), .unsupported)
    }

    func testClassifiesRecordRequests() {
        XCTAssertEqual(kind("octoshot://record"), .silentCapture)
        XCTAssertEqual(kind("octoshot://record?action=start&rect=0,0,100,100"), .silentCapture)
        XCTAssertEqual(kind("octoshot://record?action=start&mode=area"), .interactive)
        XCTAssertEqual(kind("octoshot://record?action=stop"), .stopRecording)
        XCTAssertEqual(kind("octoshot://record?action=pause"), .unsupported)
    }

    func testRejectsOtherSchemesAndHosts() {
        XCTAssertEqual(kind("https://capture?mode=fullscreen"), .unsupported)
        XCTAssertEqual(kind("octoshot://settings"), .unsupported)
    }

    func testAskPolicyConfirmsSilentCapturesFromUntrustedCallers() {
        XCTAssertEqual(URLSchemeGate.decision(for: .silentCapture, policy: .ask, callerIsTrusted: false), .ask)
        XCTAssertEqual(URLSchemeGate.decision(for: .silentCapture, policy: .ask, callerIsTrusted: true), .run)
        XCTAssertEqual(URLSchemeGate.decision(for: .interactive, policy: .ask, callerIsTrusted: false), .run)
    }

    func testOffPolicyStillAllowsStoppingARecording() {
        XCTAssertEqual(URLSchemeGate.decision(for: .silentCapture, policy: .off, callerIsTrusted: true), .refuse)
        XCTAssertEqual(URLSchemeGate.decision(for: .interactive, policy: .off, callerIsTrusted: true), .refuse)
        XCTAssertEqual(URLSchemeGate.decision(for: .stopRecording, policy: .off, callerIsTrusted: false), .run)
    }

    func testAllowPolicyRunsEverythingSupported() {
        XCTAssertEqual(URLSchemeGate.decision(for: .silentCapture, policy: .allow, callerIsTrusted: false), .run)
        XCTAssertEqual(URLSchemeGate.decision(for: .unsupported, policy: .allow, callerIsTrusted: true), .refuse)
    }
}
