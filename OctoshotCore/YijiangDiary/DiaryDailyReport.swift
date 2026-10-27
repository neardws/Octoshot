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
    public let overviewLine: String
    public let focusPattern: DiaryFocusPattern
    public let appInsights: [DiaryAppInsight]
    public let closingRoast: String?
    public let generatedAt: Date
}

public protocol DiaryRoastProvider {
    func roast(for window: DiaryWindowSkeleton) -> String?
    func closingRoast(for windows: [DiaryWindowSkeleton]) -> String?
    func closingRoast(for windows: [DiaryWindowSkeleton], appInsights: [DiaryAppInsight],
                      focusPattern: DiaryFocusPattern) -> String?
}

extension DiaryRoastProvider {
    public func closingRoast(for windows: [DiaryWindowSkeleton], appInsights: [DiaryAppInsight],
                             focusPattern: DiaryFocusPattern) -> String? {
        closingRoast(for: windows)
    }
}

public struct DiaryPlaceholderRoastProvider: DiaryRoastProvider {
    public init() {}

    public func roast(for window: DiaryWindowSkeleton) -> String? {
        guard let entry = window.entries.first(where: { DiaryInsightAnalyzer.detail($0) != nil })
                ?? window.entries.first else { return nil }
        guard let detail = DiaryInsightAnalyzer.detail(entry) else {
            return "只记下了 \(entry.appName)，文字没跟上，八只手也不敢编剧情。"
        }
        let endings = ["八只手先记下，进展可不靠开着窗口证明。",
                       "八只手负责记账，不负责把打开算成搞定。",
                       "八只手不加戏，标题再忙也不自带完成章。"]
        let ending = endings[Int(DiaryTextFingerprint.fingerprint(detail) % UInt64(endings.count))]
        return "\(entry.appName) 里有「\(detail)」，\(ending)"
    }

    public func closingRoast(for windows: [DiaryWindowSkeleton]) -> String? {
        let analysis = DiaryInsightAnalyzer.analyze(windows)
        return closingRoast(for: windows, appInsights: analysis.appInsights, focusPattern: analysis.focusPattern)
    }

    public func closingRoast(for windows: [DiaryWindowSkeleton], appInsights: [DiaryAppInsight],
                             focusPattern: DiaryFocusPattern) -> String? {
        let entries = DiaryInsightAnalyzer.rankedEntries(windows.flatMap(\.entries).filter {
            $0.appBundleID == appInsights.first?.appBundleID
        })
        guard let entry = entries.first(where: { DiaryInsightAnalyzer.detail($0) != nil }) ?? entries.first else {
            return "今天没有留下文字记录，八只手难得一起放假。"
        }
        let topic = String((DiaryInsightAnalyzer.detail(entry) ?? entry.appName).prefix(18))
        return focusPattern.switchCount > 0
            ? "「\(topic)」记下了；条目间换了 \(focusPattern.switchCount) 次 App，八只手忙着翻页，不替进展盖章。"
            : "「\(topic)」记下了；条目没换 App，八只手不把挂着窗口算成战绩。"
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
        let analysis = DiaryInsightAnalyzer.analyze(ordered)
        return DiaryDailyReport(day: start, calendar: calendar,
                                timeline: ordered.map { .init(skeleton: $0, roast: roastProvider?.roast(for: $0)) },
                                appDurations: totals, appNames: names,
                                overviewLine: analysis.overviewLine, focusPattern: analysis.focusPattern,
                                appInsights: analysis.appInsights,
                                closingRoast: roastProvider?.closingRoast(for: ordered, appInsights: analysis.appInsights,
                                                                         focusPattern: analysis.focusPattern), generatedAt: clock())
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
