import Foundation

public protocol DiaryReportNotificationScheduling {
    func replaceReportNotification(fireDate: Date?, calendar: Calendar) async throws
}

public struct DiaryReportScheduler {
    public let calendar: Calendar
    private let clock: () -> Date

    public init(calendar: Calendar = .current, clock: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.clock = clock
    }

    public func nextFireDate(settings: DiarySettings) throws -> Date {
        try settings.validate()
        let time = settings.dailyReportTime.split(separator: ":").compactMap { Int($0) }
        return calendar.nextDate(after: clock(), matching: DateComponents(hour: time[0], minute: time[1], second: 0),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
    }

    public func reschedule(settings: DiarySettings, using notifications: DiaryReportNotificationScheduling) async throws {
        try await notifications.replaceReportNotification(fireDate: settings.enabled ? nextFireDate(settings: settings) : nil,
                                                           calendar: calendar)
    }
}
