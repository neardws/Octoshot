import XCTest
@testable import OctoshotCore

final class YijiangDiaryReportSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))! }

    func testBeforeAfterAndExactReportTime() throws {
        for hour in [21, 22, 23] {
            let scheduler = DiaryReportScheduler(calendar: calendar, clock: { self.day.addingTimeInterval(Double(hour) * 3600) })
            XCTAssertEqual(try scheduler.nextFireDate(settings: DiarySettings()), day.addingTimeInterval(Double(hour < 22 ? 22 : 46) * 3600))
        }
    }

    func testSettingsChangeAndCancellation() async throws {
        let scheduler = DiaryReportScheduler(calendar: calendar, clock: { self.day.addingTimeInterval(20 * 3600) })
        let fake = FakeNotifications()
        var settings = DiarySettings()
        settings.enabled = true
        try await scheduler.reschedule(settings: settings, using: fake)
        XCTAssertEqual(fake.dates.last!, day.addingTimeInterval(22 * 3600))
        settings.dailyReportTime = "21:30"
        try await scheduler.reschedule(settings: settings, using: fake)
        XCTAssertEqual(fake.dates.last!, day.addingTimeInterval(21.5 * 3600))
        settings.enabled = false
        try await scheduler.reschedule(settings: settings, using: fake)
        XCTAssertNil(fake.dates.last!)
        XCTAssertEqual(fake.dates.count, 3)
    }

    func testInvalidTimeRejected() {
        var settings = DiarySettings()
        settings.dailyReportTime = "25:00"
        XCTAssertThrowsError(try DiaryReportScheduler().nextFireDate(settings: settings))
    }

    func testDaylightSavingGapAndRepeat() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        var settings = DiarySettings()
        settings.dailyReportTime = "02:30"
        let gap = try DiaryReportScheduler(calendar: calendar, clock: { spring }).nextFireDate(settings: settings)
        XCTAssertEqual(calendar.component(.hour, from: gap), 3)
        XCTAssertEqual(calendar.component(.minute, from: gap), 0)
        XCTAssertTrue(calendar.isDate(gap, inSameDayAs: spring))
        let autumn = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        settings.dailyReportTime = "01:30"
        let repeated = try DiaryReportScheduler(calendar: calendar, clock: { autumn }).nextFireDate(settings: settings)
        XCTAssertEqual(repeated.timeIntervalSince(autumn), 90 * 60)
    }

    private final class FakeNotifications: DiaryReportNotificationScheduling {
        var dates: [Date?] = []
        func replaceReportNotification(fireDate: Date?, calendar: Calendar) async throws { dates.append(fireDate) }
    }
}
