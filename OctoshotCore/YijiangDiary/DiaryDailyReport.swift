import Foundation

public struct DiaryDailyReport: Equatable {
    public struct Segment: Equatable {
        public let skeleton: DiaryWindowSkeleton
        public let roast: String?
    }

    public let day: Date
    public let calendar: Calendar
    public let timeline: [Segment]
    public let appDurations: [String: TimeInterval]
    public let appNames: [String: String]
    public let closingRoast: String?
    public let generatedAt: Date
}

public protocol DiaryRoastProvider {
    func roast(for window: DiaryWindowSkeleton) -> String?
    func closingRoast(for windows: [DiaryWindowSkeleton]) -> String?
}

public struct DiaryPlaceholderRoastProvider: DiaryRoastProvider {
    public init() {}

    public func roast(for window: DiaryWindowSkeleton) -> String? {
        guard let entry = window.entries.first else { return nil }
        return "\(entry.appName) 又分到 \(DiaryReportText.duration(entry.duration))，我八只手都替它鼓掌。"
    }

    public func closingRoast(for windows: [DiaryWindowSkeleton]) -> String? {
        windows.isEmpty ? "今天没有留下记录，八只手难得一起放假。" : "今天的 App 用时已经记好，八只手也没替你多算一秒。"
    }
}

public struct DiaryReportBuilder {
    public let calendar: Calendar
    private let clock: () -> Date

    public init(calendar: Calendar = .current, clock: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.clock = clock
    }

    public func build(windows: [DiaryWindowSkeleton], day: Date,
                      roastProvider: DiaryRoastProvider? = nil) -> DiaryDailyReport {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let ordered = windows.enumerated().filter { start <= $0.element.start && $0.element.start < end }
            .sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }
            .map(\.element)
        var totals: [String: TimeInterval] = [:]
        var names: [String: String] = [:]
        for window in ordered {
            for (app, duration) in window.appDurations { totals[app, default: 0] += duration }
            for entry in window.entries where names[entry.appBundleID] == nil { names[entry.appBundleID] = entry.appName }
        }
        return DiaryDailyReport(day: start, calendar: calendar,
                                timeline: ordered.map { .init(skeleton: $0, roast: roastProvider?.roast(for: $0)) },
                                appDurations: totals, appNames: names,
                                closingRoast: roastProvider?.closingRoast(for: ordered), generatedAt: clock())
    }
}

public enum DiaryReportText {
    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        let whole = Int(seconds)
        return whole < 60 ? "\(whole) 秒" : "\(whole / 60) 分 \(whole % 60) 秒"
    }

    public static func date(_ date: Date, calendar: Calendar, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    public static func facts(_ entry: DiaryWindowEntry) -> String {
        ([entry.appName, entry.windowTitle] + entry.textSnippets + [entry.urlHost].compactMap { $0 })
            .filter { !$0.isEmpty }.joined(separator: " · ") + "（\(duration(entry.duration))）"
    }
}

extension DiaryStore {
    public func fetch(day: Date, calendar: Calendar = .current) throws -> [DiaryWindowSkeleton] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return try fetch(range: start..<end).filter { $0.start >= start }
    }
}
