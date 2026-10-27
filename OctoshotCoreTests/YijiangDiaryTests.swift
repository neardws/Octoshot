import CryptoKit
import Foundation
import XCTest
@testable import OctoshotCore

final class YijiangDiaryTests: XCTestCase {
    private func sample(_ seconds: TimeInterval, app: String = "test.editor", title: String = "Draft",
                        text: String? = "Synthetic notes", frame: URL? = nil) -> DiaryActivitySample {
        DiaryActivitySample(timestamp: Date(timeIntervalSince1970: seconds), appBundleID: app,
                            appName: app, windowTitle: title, focusedText: text, keyframeURL: frame)
    }

    func testDefaultExclusionsAndPrefixes() {
        let policy = DiaryExclusionPolicy()
        for bundleID in DiaryExclusionPolicy.defaultExcludedBundleIDs.union([
            "com.agilebits.onepassword-osx", "com.agilebits.onepassword8", "com.1password.browser",
            "com.lastpass.extension", "com.dashlane.mac"
        ]) {
            XCTAssertNil(policy.sanitize(sample(0, app: bundleID)), bundleID)
        }
        XCTAssertNotNil(policy.sanitize(sample(0)))
        XCTAssertTrue(policy.allows(bundleID: "com.1passwordish.editor"))
    }

    func testUserExclusionsPrivateAndSecureInput() {
        XCTAssertNil(DiaryExclusionPolicy(userExcludedBundleIDs: ["test.editor"]).sanitize(sample(0)))
        var privateSample = sample(0)
        privateSample.isPrivateBrowsing = true
        XCTAssertNil(DiaryExclusionPolicy().sanitize(privateSample))
        privateSample.isPrivateBrowsing = false
        privateSample.isSecureInput = true
        XCTAssertNil(DiaryExclusionPolicy().sanitize(privateSample))
    }

    func testMatcherMaskingAndOverlappingMatches() {
        for secret in ["synthetic@example.com", "+86 13812345678", "4111 1111 1111 1111",
                       "sk-abcdefghijklmnopqrstuvwxyz", "ghp_abcdefghijklmnopqrstuvwxyz", "AKIA1234567890ABCDEF"] {
            let sanitized = DiaryExclusionPolicy().sanitize(sample(0, title: secret, text: secret))
            XCTAssertEqual(sanitized?.windowTitle, "•••", secret)
            XCTAssertEqual(sanitized?.focusedText, "•••", secret)
        }
    }

    func testMaskBeforeUnicodeTruncation() {
        let sanitized = DiaryExclusionPolicy(focusedTextLimit: 8).sanitize(sample(0, text: "😀😀synthetic@example.com more"))
        XCTAssertEqual(sanitized?.focusedText, "😀😀••• mo")
        XCTAssertEqual(DiaryExclusionPolicy().sanitize(sample(0, text: String(repeating: "日", count: 3_000)))?.focusedText?.count, 2_000)
    }

    func testURLHostOnlyAndDecodeSanitization() throws {
        var input = sample(0)
        input = DiaryActivitySample(timestamp: input.timestamp, appBundleID: input.appBundleID,
                                    appName: input.appName, windowTitle: input.windowTitle,
                                    urlHost: "https://user:secret@EXAMPLE.com:8443/private?q=secret#fragment")
        XCTAssertEqual(input.urlHost, "example.com")
        XCTAssertEqual(DiaryActivitySample.hostOnly("example.com/path?secret=yes"), "example.com")
        XCTAssertNil(DiaryActivitySample.hostOnly("not a host"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        json["urlHost"] = "https://example.org/hidden?q=private"
        let decoded = try JSONDecoder().decode(DiaryActivitySample.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.urlHost, "example.org")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self).contains("hidden"))
    }

    func testWindowBoundarySplitsDwell() throws {
        let aggregator = DiaryWindowAggregator(dwellThreshold: 0)
        XCTAssertTrue(try aggregator.append(sample(590)).isEmpty)
        let closed = try aggregator.append(sample(610, app: "test.browser"))
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed[0].start, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(closed[0].end, Date(timeIntervalSince1970: 600))
        XCTAssertEqual(closed[0].appDurations["test.editor"], 10)
        let final = try aggregator.finish(at: Date(timeIntervalSince1970: 660))
        XCTAssertEqual(final[0].appDurations, ["test.editor": 10, "test.browser": 50])
    }

    func testExactBoundaryAndMultipleWindows() throws {
        let aggregator = DiaryWindowAggregator()
        _ = try aggregator.append(sample(0))
        let closed = try aggregator.append(sample(1_800, app: "test.browser"))
        XCTAssertEqual(closed.count, 3)
        XCTAssertEqual(closed.map { $0.appDurations["test.editor"] }, [600, 600, 600])
        XCTAssertTrue(try aggregator.finish(at: Date(timeIntervalSince1970: 1_800)).isEmpty)
    }

    func testPerAppDurationsDistinctOrderingAndThreshold() throws {
        let aggregator = DiaryWindowAggregator()
        _ = try aggregator.append(sample(0))
        _ = try aggregator.append(sample(100, app: "test.browser", title: "Docs"))
        _ = try aggregator.append(sample(300))
        _ = try aggregator.append(sample(580, title: "Brief"))
        let windows = try aggregator.finish(at: Date(timeIntervalSince1970: 600))
        XCTAssertEqual(windows[0].appDurations, ["test.editor": 400, "test.browser": 200])
        XCTAssertEqual(windows[0].entries.map(\.windowTitle), ["Draft", "Docs"])
        XCTAssertEqual(windows[0].entries.map(\.duration), [380, 200])
    }

    func testIdenticalAndNearIdenticalDedupChangedTitle() throws {
        let text = (0..<100).map { "Synthetic paragraph \($0) discusses offline diary aggregation and deterministic unit testing." }.joined(separator: " ")
        let near = text + "!"
        XCTAssertLessThanOrEqual((DiaryTextFingerprint.fingerprint(text) ^ DiaryTextFingerprint.fingerprint(near)).nonzeroBitCount, 3)
        XCTAssertTrue(DiaryTextFingerprint.unchanged("Hello   WORLD\n", " hello world "))
        XCTAssertFalse(DiaryTextFingerprint.unchanged("", "something"))
        let aggregator = DiaryWindowAggregator()
        _ = try aggregator.append(sample(0, text: text))
        _ = try aggregator.append(sample(60, text: text))
        _ = try aggregator.append(sample(120, text: near))
        _ = try aggregator.append(sample(300, title: "New title", text: near))
        let windows = try aggregator.finish(at: Date(timeIntervalSince1970: 600))
        XCTAssertEqual(windows[0].entries.count, 2)
        XCTAssertEqual(windows[0].entries[0].textSnippets, [text])
        XCTAssertEqual(windows[0].entries[0].duration, 300)
    }

    func testChangedTextKeepsRepresentativeSnippets() throws {
        let aggregator = DiaryWindowAggregator()
        _ = try aggregator.append(sample(0, text: "Oranges and lemons"))
        _ = try aggregator.append(sample(100, text: "Quantum mechanics lecture"))
        let windows = try aggregator.finish(at: Date(timeIntervalSince1970: 600))
        XCTAssertEqual(windows[0].entries.count, 1)
        XCTAssertEqual(windows[0].entries[0].textSnippets.count, 2)
    }

    func testLongestDwellKeyframeAndTie() throws {
        let first = URL(fileURLWithPath: "/synthetic/first.png")
        let second = URL(fileURLWithPath: "/synthetic/second.png")
        let aggregator = DiaryWindowAggregator()
        _ = try aggregator.append(sample(0, title: "First", frame: first))
        _ = try aggregator.append(sample(100, title: "Second", frame: second))
        _ = try aggregator.append(sample(300, title: "Third", frame: first))
        let windows = try aggregator.finish(at: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(windows[0].keyframe?.keyframeURL, second)
        XCTAssertEqual(windows[0].keyframe?.windowTitle, "Second")
    }

    func testDedupAccumulatesDwellForKeyframe() throws {
        let aggregator = DiaryWindowAggregator()
        _ = try aggregator.append(sample(0, frame: URL(fileURLWithPath: "/synthetic/a.png")))
        _ = try aggregator.append(sample(30))
        let windows = try aggregator.finish(at: Date(timeIntervalSince1970: 90))
        XCTAssertNotNil(windows[0].keyframe)
        XCTAssertEqual(windows[0].entries[0].duration, 90)
    }

    func testUnavailableStopsAttributionAndOutOfOrderThrows() throws {
        let aggregator = DiaryWindowAggregator()
        _ = try aggregator.append(sample(0))
        _ = try aggregator.observe(nil, at: Date(timeIntervalSince1970: 100))
        XCTAssertThrowsError(try aggregator.append(sample(99)))
        let closed = try aggregator.append(sample(1_800))
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed[0].appDurations["test.editor"], 100)
    }

    func testConfigurableIntervalAndClock() throws {
        let aggregator = DiaryWindowAggregator(interval: 120, dwellThreshold: 0, clock: { Date(timeIntervalSince1970: 240) })
        _ = try aggregator.append(sample(100))
        XCTAssertEqual(try aggregator.finish().map { $0.appDurations["test.editor"] }, [20, 120])
    }

    func testSettingsDefaultsAndSuiteRoundTrip() throws {
        let suite = "YijiangDiaryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = try DiarySettings.load(from: defaults)
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.windowInterval, 600)
        XCTAssertEqual(settings.dwell, 60)
        XCTAssertEqual(settings.retentionDays, 30)
        XCTAssertEqual(settings.failedFrameTTL, 86_400)
        XCTAssertEqual(settings.dailyReportTime, "22:00")
        settings.userExcludedBundleIDs = ["test.private"]
        for retention in [7, 30, 90, nil] as [Int?] {
            settings.retentionDays = retention
            try settings.save(to: defaults)
            XCTAssertEqual(try DiarySettings.load(from: defaults), settings)
        }
        settings.windowInterval = 0
        XCTAssertThrowsError(try settings.save(to: defaults))
    }
}
