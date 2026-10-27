import XCTest
@testable import OctoshotCore

final class YijiangDiaryReportTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))! }

    private func window(hour: Int, app: String = "Cursor", duration: Double = 600) -> DiaryWindowSkeleton {
        let start = day.addingTimeInterval(Double(hour) * 3600)
        return DiaryWindowSkeleton(start: start, end: start.addingTimeInterval(600), appDurations: [app: duration],
            entries: [DiaryWindowEntry(appBundleID: app, appName: app, windowTitle: "示例窗口",
                                       textSnippets: ["示例文字"], urlHost: "example.com", duration: duration)])
    }

    func testBuilderTotalsOrderAndDeterminism() {
        let windows = [window(hour: 14), window(hour: 10, app: "Safari", duration: 240), window(hour: 9)]
        let builder = DiaryReportBuilder(calendar: calendar, clock: { self.day })
        let report = builder.build(windows: windows, day: day)
        XCTAssertEqual(report.appDurations, ["Cursor": 1200, "Safari": 240])
        XCTAssertEqual(report.timeline.map(\.skeleton.start), windows.map(\.start).sorted())
        XCTAssertEqual(report.generatedAt, day)
        XCTAssertEqual(report, builder.build(windows: windows, day: day))
        XCTAssertNil(report.closingRoast)
        XCTAssertTrue(report.timeline.allSatisfy { $0.roast == nil })
    }

    func testEmptyDay() {
        let report = DiaryReportBuilder(calendar: calendar).build(windows: [], day: day, roastProvider: DiaryPlaceholderRoastProvider())
        XCTAssertTrue(report.timeline.isEmpty)
        XCTAssertTrue(report.appDurations.isEmpty)
        XCTAssertTrue(report.appInsights.isEmpty)
        XCTAssertTrue(report.overviewLine.contains("今天还没有记录"))
        XCTAssertEqual(report.focusPattern.switchCount, 0)
        XCTAssertEqual(report.focusPattern.uniqueAppCount, 0)
        XCTAssertEqual(report.focusPattern.longestFocus, 0)
        XCTAssertNil(report.focusPattern.longestFocusAppName)
        XCTAssertNil(report.focusPattern.topBouncePair)
        XCTAssertTrue(report.focusPattern.summaryLine.contains("先不评价"))
        XCTAssertTrue(report.closingRoast!.contains("八只手"))
    }

    func testWindowsBelongToStartDayWithoutInventedProration() {
        var crossing = window(hour: 23)
        crossing.start = day.addingTimeInterval(24 * 3600 - 300)
        crossing.end = day.addingTimeInterval(24 * 3600 + 300)
        let builder = DiaryReportBuilder(calendar: calendar)
        let report = builder.build(windows: [window(hour: -1), window(hour: 24), crossing], day: day)
        XCTAssertEqual(report.timeline.count, 1)
        XCTAssertEqual(report.appDurations["Cursor"], 600)
        XCTAssertTrue(builder.build(windows: [crossing], day: day.addingTimeInterval(24 * 3600)).timeline.isEmpty)
    }

    func testPlaceholderUsesDistinctiveSkeletonTitle() throws {
        let roast = try XCTUnwrap(DiaryPlaceholderRoastProvider().roast(for: window(hour: 9)))
        XCTAssertTrue(roast.contains("Cursor"))
        XCTAssertTrue(roast.contains("示例窗口"))
        XCTAssertTrue(roast.contains("八只手"))
        for unknown in ["Safari", "Terminal", "微信", "Chrome", "提交成功", "上传报告"] {
            XCTAssertFalse(roast.contains(unknown))
        }
    }

    func testMarkdownFactsHeadingsAndRoasts() {
        let report = DiaryReportBuilder(calendar: calendar).build(windows: [window(hour: 9)], day: day,
                                                                 roastProvider: DiaryPlaceholderRoastProvider())
        let markdown = DiaryMarkdownExporter().render(report)
        for expected in ["# 一酱日记 · 2026年10月27日", "## 今天在干嘛", "## 各 App 都干了啥", "## 时间线", "09:00–09:10", "Cursor",
                         "示例窗口", "示例文字", "example.com", "## 一酱总结", "_一酱：",
                         report.overviewLine, report.focusPattern.summaryLine] {
            XCTAssertTrue(markdown.contains(expected), expected)
        }
    }

    func testMarkdownEmptyAndEscaping() {
        let builder = DiaryReportBuilder(calendar: calendar)
        let empty = DiaryMarkdownExporter().render(builder.build(windows: [], day: day))
        XCTAssertTrue(empty.contains("今天还没有记录"))
        let escaped = DiaryMarkdownExporter().render(builder.build(windows: [window(hour: 9, app: "App|_*<\n#")], day: day))
        XCTAssertTrue(escaped.contains("App\\|\\_\\*\\< \\#"))
    }

    private func fixture(_ apps: [String], durations: [Double], offset: Double = 0) -> DiaryWindowSkeleton {
        let start = day.addingTimeInterval(9 * 3600 + offset)
        let entries = zip(apps, durations).map { app, duration in
            DiaryWindowEntry(appBundleID: "example." + app, appName: app, windowTitle: "示例项目 · 日报布局",
                             textSnippets: ["聚合日报", "焦点切换"], urlHost: app == "Safari" ? "docs.example.com" : nil,
                             duration: duration)
        }
        let totals = entries.reduce(into: [String: Double]()) { $0[$1.appBundleID, default: 0] += $1.duration }
        return DiaryWindowSkeleton(start: start, end: start.addingTimeInterval(durations.reduce(0, +)),
                                   appDurations: totals, entries: entries)
    }

    func testBouncingDayInsightsFocusAndDeterminism() throws {
        var first = fixture(["Cursor", "Safari", "Cursor", "Safari", "Cursor"], durations: [120, 60, 180, 60, 240])
        first.keyframe = DiaryActivitySample(timestamp: first.start, appBundleID: "invented.invalid", appName: "微信",
                                            windowTitle: "秘密支付接口", focusedText: "部署成功", urlHost: "invented.invalid")
        let second = fixture(["Cursor", "Notes"], durations: [300, 60], offset: 660)
        let builder = DiaryReportBuilder(calendar: calendar, clock: { self.day })
        let report = builder.build(windows: [second, first], day: day, roastProvider: DiaryPlaceholderRoastProvider())
        XCTAssertEqual(report.focusPattern.switchCount, 5)
        XCTAssertEqual(report.focusPattern.uniqueAppCount, 3)
        XCTAssertEqual(report.focusPattern.longestFocus, 540)
        XCTAssertEqual(report.focusPattern.longestFocusAppName, "Cursor")
        let pair = try XCTUnwrap(report.focusPattern.topBouncePair)
        XCTAssertEqual(pair.firstAppName, "Cursor")
        XCTAssertEqual(pair.secondAppName, "Safari")
        XCTAssertEqual(pair.switchCount, 4)
        XCTAssertEqual(report.appInsights.map(\.appName), ["Cursor", "Safari", "Notes"])
        XCTAssertEqual(report.appInsights.first?.totalDuration, 840)
        XCTAssertTrue(report.overviewLine.contains("日报布局"))
        XCTAssertTrue(report.focusPattern.summaryLine.contains("Cursor / Safari"))
        XCTAssertTrue(report.focusPattern.summaryLine.contains("骨架会合并"))
        XCTAssertTrue(report.closingRoast!.contains("日报布局"))
        XCTAssertTrue(report.closingRoast!.contains("5 次"))
        for insight in report.appInsights {
            XCTAssertTrue((2...5).contains(insight.bullets.count))
            let text = insight.bullets.joined()
            XCTAssertTrue(text.contains("示例项目 · 日报布局"))
            XCTAssertTrue(text.contains("聚合日报"))
            XCTAssertTrue(text.contains("焦点切换"))
            for invented in ["秘密支付接口", "invented.invalid", "部署成功", "微信"] {
                XCTAssertFalse(text.contains(invented))
                XCTAssertFalse(report.overviewLine.contains(invented))
                XCTAssertFalse(report.closingRoast!.contains(invented))
                XCTAssertFalse(report.timeline.compactMap(\.roast).joined().contains(invented))
            }
        }
        XCTAssertTrue(report.appInsights[1].bullets.joined().contains("docs.example.com"))
        XCTAssertEqual(report, builder.build(windows: [first, second], day: day, roastProvider: DiaryPlaceholderRoastProvider()))
    }

    func testFocusDoesNotBridgeMissingWindowsOrEmptySkeletons() {
        let first = fixture(["Cursor"], durations: [600])
        let later = fixture(["Cursor"], durations: [600], offset: 3600)
        let builder = DiaryReportBuilder(calendar: calendar)
        XCTAssertEqual(builder.build(windows: [first, later], day: day).focusPattern.longestFocus, 600)
        let empty = fixture([], durations: [], offset: 600)
        let adjacent = fixture(["Cursor"], durations: [600], offset: 600)
        XCTAssertEqual(builder.build(windows: [first, empty, adjacent], day: day).focusPattern.longestFocus, 600)
    }

    func testSparseTextDeduplicationAndRoastFallbacks() throws {
        var sample = fixture(["Cursor", "Cursor"], durations: [300, 300])
        sample.entries[1].windowTitle = "  示例项目 · 日报布局  "
        let builder = DiaryReportBuilder(calendar: calendar)
        let bullets = builder.build(windows: [sample], day: day).appInsights[0].bullets
        XCTAssertEqual(bullets[0], "窗口：《示例项目 · 日报布局》")
        XCTAssertEqual(bullets[1], "骨架文字提到：聚合日报；焦点切换")
        sample.entries = [sample.entries[0]]
        sample.entries[0].windowTitle = ""
        let provider = DiaryPlaceholderRoastProvider()
        XCTAssertTrue(try XCTUnwrap(provider.roast(for: sample)).contains("聚合日报"))
        sample.entries[0].textSnippets = []
        sample.entries[0].urlHost = "only.example.com"
        XCTAssertTrue(try XCTUnwrap(provider.roast(for: sample)).contains("only.example.com"))
        sample.entries[0].urlHost = nil
        let report = builder.build(windows: [sample], day: day, roastProvider: provider)
        XCTAssertEqual(report.appInsights[0].bullets[0], "只记下了 App 名，窗口文字不足")
        XCTAssertTrue(report.timeline[0].roast!.contains("文字没跟上"))
        let empty = builder.build(windows: [fixture([], durations: [])], day: day, roastProvider: provider)
        XCTAssertTrue(empty.appInsights.isEmpty)
        XCTAssertNil(empty.timeline[0].roast)
        XCTAssertEqual(empty.focusPattern.uniqueAppCount, 0)
    }

    func testAllAppsAndStableTiesAreRetained() {
        let apps = ["Safari", "Cursor", "Notes", "Terminal", "Preview", "Finder"]
        let report = DiaryReportBuilder(calendar: calendar).build(
            windows: [fixture(apps, durations: Array(repeating: 60, count: apps.count))], day: day)
        XCTAssertEqual(report.appInsights.map(\.appName), apps.sorted())
        XCTAssertEqual(report.focusPattern.topBouncePair?.firstAppName, "Cursor")
        XCTAssertEqual(report.focusPattern.topBouncePair?.secondAppName, "Notes")
    }

    func testMarkdownEscapesInsightAndRoastSourceText() {
        var sample = fixture(["Cursor"], durations: [60])
        sample.entries[0].windowTitle = "布局_*[链接]<tag>\n#标题"
        let report = DiaryReportBuilder(calendar: calendar).build(windows: [sample], day: day,
                                                                 roastProvider: DiaryPlaceholderRoastProvider())
        let markdown = DiaryMarkdownExporter().render(report)
        XCTAssertTrue(markdown.contains("布局\\_\\*\\[链接\\]\\<tag\\> \\#标题"))
        XCTAssertFalse(markdown.contains("\n#标题"))
        XCTAssertEqual(markdown.components(separatedBy: "_一酱：").count - 1, 1)
    }

    func testStoreDayRangeUsesInjectedKeyAndCalendar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiaryStore(directory: root, keyProvider: InMemoryDiaryKeyProvider())
        for hour in [-1, 0, 23, 24] { try store.insert(window(hour: hour)) }
        XCTAssertEqual(try store.fetch(day: day, calendar: calendar).map(\.start), [window(hour: 0).start, window(hour: 23).start])
    }
}
