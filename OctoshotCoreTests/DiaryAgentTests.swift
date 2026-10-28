import XCTest
@testable import OctoshotCore

final class DiaryAgentTests: XCTestCase {
    private var root: URL!
    private var store: DiaryStore!
    private var settings = DiarySettings()
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var service: DiaryAgentService {
        DiaryAgentService(store: { self.store }, loadSettings: { self.settings },
                          saveSettings: { self.settings = $0 }, calendar: calendar, clock: { self.now })
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        store = try DiaryStore(directory: root.appendingPathComponent("store"), keyProvider: InMemoryDiaryKeyProvider())
        settings = DiarySettings()
        settings.enabled = true
        let sample = DiaryActivitySample(timestamp: now, appBundleID: "test.editor", appName: "Editor",
            windowTitle: "Title \"quoted\"\n新行", focusedText: "private", keyframeURL: URL(fileURLWithPath: "/private/frame.png"))
        try store.insert(DiaryWindowSkeleton(start: now, end: now.addingTimeInterval(600), appDurations: ["test.editor": 600],
            entries: [DiaryWindowEntry(appBundleID: "test.editor", appName: "Editor", windowTitle: sample.windowTitle,
                textSnippets: ["code\\test", "中文"], urlHost: "example.com", duration: 600)], keyframe: sample))
    }

    override func tearDownWithError() throws {
        store = nil
        try FileManager.default.removeItem(at: root)
    }

    func testReportStableShapeAndRoundTripWithoutImages() throws {
        let response = service.handle(DiaryAgentRequest(action: .today))
        let json = try response.jsonText()
        let decoded = try JSONDecoder().decode(DiaryAgentReport.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, response.report)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["date", "summary", "focusPattern", "apps", "segments"])
        XCTAssertEqual(decoded.apps.first?.duration, 600)
        XCTAssertEqual(decoded.segments.first?.title, "Title \"quoted\"\n新行")
        XCTAssertFalse(json.contains("keyframe"))
        XCTAssertFalse(json.contains("/private/frame.png"))
        let shown = service.handle(DiaryAgentRequest(action: .show, date: decoded.date))
        XCTAssertEqual(shown.report, response.report)
        XCTAssertTrue(try XCTUnwrap(response.markdown).contains("东太平洋红章鱼"))
        XCTAssertEqual(service.handle(DiaryAgentRequest(action: .export, date: decoded.date)).markdown, response.markdown)
    }

    func testTimelineStableShapeAndOverlap() throws {
        let response = service.handle(DiaryAgentRequest(action: .timeline,
            from: DiaryAgentJSON.timestamp(now.addingTimeInterval(300)), to: DiaryAgentJSON.timestamp(now.addingTimeInterval(900))))
        let json = try response.jsonText()
        let decoded = try JSONDecoder().decode(DiaryAgentTimeline.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, response.timeline)
        XCTAssertEqual(decoded.windows.count, 1)
        XCTAssertEqual(decoded.windows.first?.snippets, "code\\test\n中文")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["from", "to", "windows"])
        let window = try XCTUnwrap((object["windows"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(window.keys), ["start", "end", "app", "title", "snippets", "urlHost"])
        let outside = service.handle(DiaryAgentRequest(action: .timeline,
            from: DiaryAgentJSON.timestamp(now.addingTimeInterval(600)), to: DiaryAgentJSON.timestamp(now.addingTimeInterval(900))))
        XCTAssertEqual(outside.timeline?.windows.count, 0)
    }

    func testStatusGoldenAndPauseResumeExpiry() throws {
        settings.retentionDays = nil
        XCTAssertEqual(try service.handle(DiaryAgentRequest(action: .status)).jsonText(),
            #"{"dailyReportTime":"22:00","enabled":true,"paused":false,"pausedUntil":null,"retentionDays":null}"#)
        let response = service.handle(DiaryAgentRequest(action: .pause, minutes: 10))
        XCTAssertEqual(response.status?.paused, true)
        XCTAssertEqual(settings.pausedUntil, now.addingTimeInterval(600))
        let json = try response.jsonText()
        XCTAssertEqual(try JSONDecoder().decode(DiaryAgentStatus.self, from: Data(json.utf8)), response.status)
        now = now.addingTimeInterval(601)
        XCTAssertEqual(service.handle(DiaryAgentRequest(action: .status)).status?.paused, false)
        XCTAssertNil(service.handle(DiaryAgentRequest(action: .resume)).status?.pausedUntil)
        XCTAssertNil(settings.pausedUntil)
    }

    func testDisabledDoesNotOpenStoreAndReturnsClearErrors() throws {
        settings.enabled = false
        let service = DiaryAgentService(store: { XCTFail("Disabled diary must not open the store"); return self.store },
            loadSettings: { self.settings }, saveSettings: { _ in XCTFail("Must not mutate") })
        for action: DiaryAgentRequest.Action in [.today, .show, .timeline, .export, .pause, .resume, .purge, .status] {
            XCTAssertTrue(service.handle(DiaryAgentRequest(action: action)).error?.contains("disabled") == true)
        }
    }

    func testPurgeRequiresConfirmationAtBothBoundaries() throws {
        XCTAssertThrowsError(try DiaryCLIArguments.parse(["purge"]))
        XCTAssertThrowsError(try DiaryCLIArguments.parse(["purge", "--confirm=false"]))
        XCTAssertNotNil(service.handle(DiaryAgentRequest(action: .purge)).error)
        XCTAssertEqual(try store.fetch(day: now, calendar: calendar).count, 1)
        let request = try DiaryCLIArguments.parse(["purge", "--confirm"]).request
        XCTAssertNil(service.handle(request).error)
        XCTAssertTrue(try store.fetch(day: now, calendar: calendar).isEmpty)
    }

    func testArgumentsRejectInvalidOrAmbiguousInputs() throws {
        for args in [["show", "2026-02-30"], ["show"], ["today", "--confirm"], ["pause", "0"],
                     ["pause", "1.5"], ["export"], ["export", "--format", "csv"], ["status", "--json", "--json"],
                     ["timeline", "--from", "yesterday", "--to", "today"]] {
            XCTAssertThrowsError(try DiaryCLIArguments.parse(args), args.joined(separator: " "))
        }
        XCTAssertTrue(try DiaryCLIArguments.parse(["today", "--json"]).json)
        XCTAssertTrue(try DiaryCLIArguments.parse(["export", "--format", "json", "--date", "2026-10-29"]).json)
        XCTAssertFalse(try DiaryCLIArguments.parse(["export", "--format", "md"]).json)
        XCTAssertNotNil(service.handle(DiaryAgentRequest(action: .pause, minutes: -1)).error)
        XCTAssertNotNil(service.handle(DiaryAgentRequest(action: .show, date: "2026-13-01")).error)
        XCTAssertNotNil(service.handle(DiaryAgentRequest(action: .timeline, from: "2026-10-29T01:00:00Z",
                                                        to: "2026-10-29T00:00:00Z")).error)
        XCTAssertNotNil(try DiaryAgentJSON.instant("2026-10-29T00:00:00.123+08:00"))
    }

    func testLegacySettingsDecodeAndPausePersists() throws {
        let original = try JSONEncoder().encode(DiarySettings())
        XCTAssertNil(try JSONDecoder().decode(DiarySettings.self, from: original).pausedUntil)
        _ = service.handle(DiaryAgentRequest(action: .pause))
        let restored = try JSONDecoder().decode(DiarySettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.pausedUntil, now.addingTimeInterval(3600))
    }

    func testMailboxRoundTripsAndConsumesRequest() throws {
        let mailbox = DiaryAgentMailbox(directory: root.appendingPathComponent("ipc"))
        for action: DiaryAgentRequest.Action in [.today, .show, .timeline, .status, .pause, .resume] {
            let request = DiaryAgentRequest(action: action, date: DiaryAgentJSON.dayFormatter(calendar).string(from: now),
                from: DiaryAgentJSON.timestamp(now), to: DiaryAgentJSON.timestamp(now.addingTimeInterval(600)))
            let identifier = try mailbox.prepare(request)
            XCTAssertNil(try mailbox.response(for: identifier))
            try mailbox.serve(mailbox.url(for: identifier), using: service)
            let response = try XCTUnwrap(mailbox.response(for: identifier))
            XCTAssertNil(response.error)
            XCTAssertNoThrow(try response.jsonText())
            XCTAssertThrowsError(try mailbox.serve(mailbox.url(for: identifier), using: service))
            mailbox.remove(identifier)
        }
    }

    func testMailboxRejectsArbitraryURLsAndSymlinks() throws {
        let mailbox = DiaryAgentMailbox(directory: root.appendingPathComponent("ipc"))
        let identifier = try mailbox.prepare(DiaryAgentRequest(action: .status))
        defer { mailbox.remove(identifier) }
        for text in ["octoshot://diary?action=purge&confirm=true", "octoshot://diary?request=../../outside",
                     "octoshot://diary?request=\(identifier)&reply=file:///tmp/leak"] {
            XCTAssertThrowsError(try mailbox.serve(URL(string: text)!, using: service))
        }
        let input = mailbox.directory.appendingPathComponent(identifier).appendingPathComponent("request.json")
        try FileManager.default.removeItem(at: input)
        try FileManager.default.createSymbolicLink(at: input, withDestinationURL: store.databaseURL)
        XCTAssertThrowsError(try mailbox.serve(mailbox.url(for: identifier), using: service))
    }

    func testMailboxReturnsJSONErrors() throws {
        let mailbox = DiaryAgentMailbox(directory: root.appendingPathComponent("ipc"))
        let identifier = try mailbox.prepare(DiaryAgentRequest(action: .purge))
        defer { mailbox.remove(identifier) }
        try mailbox.serve(mailbox.url(for: identifier), using: service)
        let response = try XCTUnwrap(mailbox.response(for: identifier))
        XCTAssertEqual(response.error, "purge requires --confirm")
        XCTAssertThrowsError(try response.jsonText())
    }

    func testMCPDefinitionsAndServiceCalls() throws {
        let definitions = try JSONEncoder().encode(DiaryMCPTools.definitions)
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: definitions) as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, DiaryMCPTools.names)
        XCTAssertEqual(DiaryMCPTools.names.count, 4)
        let schema = try XCTUnwrap(tools[1]["inputSchema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["from", "to"])
        for name in ["diary_get_report", "diary_status", "diary_pause"] {
            let request = try DiaryMCPTools.request(name: name, arguments: .object([:]))
            XCTAssertNoThrow(try service.handle(request).jsonText())
        }
        XCTAssertEqual(settings.pausedUntil, now.addingTimeInterval(3600))
        let timeline = try DiaryMCPTools.request(name: "diary_get_timeline", arguments: .object([
            "from": .string(DiaryAgentJSON.timestamp(now)), "to": .string(DiaryAgentJSON.timestamp(now.addingTimeInterval(600)))]))
        XCTAssertEqual(service.handle(timeline).timeline?.windows.count, 1)
        XCTAssertThrowsError(try DiaryMCPTools.request(name: "diary_pause", arguments: .object(["minutes": .number(0.5)])))
        XCTAssertThrowsError(try DiaryMCPTools.request(name: "diary_pause", arguments: .object(["minutes": .string("60")])))
        XCTAssertThrowsError(try DiaryMCPTools.request(name: "diary_get_report", arguments: .object(["date": .number(1)])))
        XCTAssertThrowsError(try DiaryMCPTools.request(name: "diary_get_timeline", arguments: .object([:])))
        XCTAssertThrowsError(try DiaryMCPTools.request(name: "diary_purge", arguments: .object([:])))
    }
}
