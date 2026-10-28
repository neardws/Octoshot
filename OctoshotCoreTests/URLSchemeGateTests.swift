import XCTest
@testable import OctoshotCore

final class URLSchemeGateTests: XCTestCase {
    func testDiaryNeverUsesCaptureConsentEvenWhenAutomationIsOff() {
        for action in ["today", "show", "timeline", "export", "status", "pause", "resume", "purge"] {
            let kind = URLSchemeGate.classify(URL(string: "octoshot://diary?action=\(action)")!)
            XCTAssertEqual(kind, .diary)
            XCTAssertNotEqual(kind, .silentCapture)
            for policy in URLSchemeAutomationPolicy.allCases {
                XCTAssertEqual(URLSchemeGate.decision(for: kind, policy: policy, callerIsTrusted: false), .run)
            }
        }
    }
    func testBrowserNeverGetsAlwaysAllowEvenWithValidSignature() {
        XCTAssertFalse(URLSchemeGate.canAlwaysAllow(identity: "browser", requirement: "signed", isBrowser: true))
        XCTAssertFalse(URLSchemeGate.isTrusted(identity: "browser", requirement: "signed", isBrowser: true,
                                               storedRequirement: "signed", signatureMatches: true))
    }

    func testKnownBrowsersAndArbitraryWebHandlersAreBlocked() {
        for identifier in ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
                           "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser",
                           "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "com.kagi.kagimacOS"] {
            let browser = URLSchemeGate.isBrowser(identifier: identifier, isRegisteredWebHandler: false)
            XCTAssertTrue(browser, identifier)
            XCTAssertFalse(URLSchemeGate.canAlwaysAllow(identity: identifier, requirement: "signed", isBrowser: browser))
        }
        XCTAssertTrue(URLSchemeGate.isBrowser(identifier: "custom.handler", isRegisteredWebHandler: true))
        XCTAssertFalse(URLSchemeGate.isBrowser(identifier: "custom.research", isRegisteredWebHandler: false))
    }

    func testMissingIdentityAndMismatchedSignatureAsk() {
        for identity: String? in [nil, "caller"] {
            let trusted = URLSchemeGate.isTrusted(identity: identity, requirement: "signed", isBrowser: false,
                                                  storedRequirement: "other", signatureMatches: false)
            XCTAssertEqual(URLSchemeGate.decision(for: .silentCapture, policy: .ask, callerIsTrusted: trusted), .ask)
        }
        XCTAssertFalse(URLSchemeGate.isTrusted(identity: nil, requirement: "signed", isBrowser: false,
                                               storedRequirement: "signed", signatureMatches: true))
        XCTAssertFalse(URLSchemeGate.canAlwaysAllow(identity: "caller", requirement: nil, isBrowser: false))
        XCTAssertTrue(URLSchemeGate.isTrusted(identity: "caller", requirement: "signed", isBrowser: false,
                                              storedRequirement: "signed", signatureMatches: true))
    }
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
        XCTAssertEqual(kind("octoshot://record?action=start&mode=area"), .silentCapture)
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

    func testLegacyAllowPolicyCannotBypassIdentityChecks() {
        XCTAssertEqual(URLSchemeGate.decision(for: .silentCapture, policy: .allow, callerIsTrusted: false), .ask)
        XCTAssertEqual(URLSchemeGate.decision(for: .silentCapture, policy: .allow, callerIsTrusted: true), .run)
        XCTAssertEqual(URLSchemeGate.decision(for: .unsupported, policy: .allow, callerIsTrusted: true), .refuse)
    }
}
