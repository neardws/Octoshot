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

    func testPlaceholderUsesOnlyKnownAppAndDuration() throws {
        let roast = try XCTUnwrap(DiaryPlaceholderRoastProvider().roast(for: window(hour: 9)))
        XCTAssertTrue(roast.contains("Cursor"))
        XCTAssertTrue(roast.contains("10 分"))
        XCTAssertTrue(roast.contains("八只手"))
        for unknown in ["Safari", "Terminal", "微信", "Chrome", "示例窗口", "example.com"] {
            XCTAssertFalse(roast.contains(unknown))
        }
    }

    func testMarkdownFactsHeadingsAndRoasts() {
        let report = DiaryReportBuilder(calendar: calendar).build(windows: [window(hour: 9)], day: day,
                                                                 roastProvider: DiaryPlaceholderRoastProvider())
        let markdown = DiaryMarkdownExporter().render(report)
        for expected in ["# 一酱日记 · 2026年10月27日", "## 今天八只手都干了啥", "09:00–09:10", "Cursor",
                         "示例窗口", "示例文字", "example.com", "## App 用时", "## 一酱总结", "_一酱："] {
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

    func testStoreDayRangeUsesInjectedKeyAndCalendar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiaryStore(directory: root, keyProvider: InMemoryDiaryKeyProvider())
        for hour in [-1, 0, 23, 24] { try store.insert(window(hour: hour)) }
        XCTAssertEqual(try store.fetch(day: day, calendar: calendar).map(\.start), [window(hour: 0).start, window(hour: 23).start])
    }
}
