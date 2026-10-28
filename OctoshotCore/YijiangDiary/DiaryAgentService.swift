import Foundation

public struct DiaryAgentError: LocalizedError, Codable {
    public let error: String
    public var errorDescription: String? { error }
    public init(_ message: String) { error = message }
}

public struct DiaryAgentRequest: Codable {
    public enum Action: String, Codable { case today, show, timeline, export, pause, resume, status, purge }
    public var action: Action
    public var date: String?
    public var from: String?
    public var to: String?
    public var minutes: Int?
    public var confirmed: Bool

    public init(action: Action, date: String? = nil, from: String? = nil, to: String? = nil,
                minutes: Int? = nil, confirmed: Bool = false) {
        self.action = action
        self.date = date
        self.from = from
        self.to = to
        self.minutes = minutes
        self.confirmed = confirmed
    }
}

public struct DiaryAgentWindow: Codable, Equatable {
    public let start: String
    public let end: String
    public let app: String
    public let title: String
    public let snippets: String
    public let urlHost: String?
}

public struct DiaryAgentReport: Codable, Equatable {
    public struct App: Codable, Equatable {
        public let bundleID: String
        public let name: String
        public let duration: TimeInterval
        public let bullets: [String]
    }
    public let date: String
    public let summary: String
    public let focusPattern: String
    public let apps: [App]
    public let segments: [DiaryAgentWindow]
    public let closingRoast: String?
}

public struct DiaryAgentTimeline: Codable, Equatable {
    public let from: String
    public let to: String
    public let windows: [DiaryAgentWindow]
}

public struct DiaryAgentStatus: Codable, Equatable {
    public let enabled: Bool
    public let paused: Bool
    public let pausedUntil: String?
    public let retentionDays: Int?
    public let dailyReportTime: String

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(paused, forKey: .paused)
        try container.encode(pausedUntil, forKey: .pausedUntil)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(dailyReportTime, forKey: .dailyReportTime)
    }
}

public struct DiaryAgentResponse: Codable {
    public var report: DiaryAgentReport?
    public var timeline: DiaryAgentTimeline?
    public var status: DiaryAgentStatus?
    public var markdown: String?
    public var error: String?

    public init(error: String? = nil) { self.error = error }

    public func jsonText() throws -> String {
        if let error { throw DiaryAgentError(error) }
        if let report { return try DiaryAgentJSON.text(report) }
        if let timeline { return try DiaryAgentJSON.text(timeline) }
        if let status { return try DiaryAgentJSON.text(status) }
        throw DiaryAgentError("Invalid diary response")
    }
}

public enum DiaryAgentJSON {
    public static func text<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    public static func instant(_ text: String?) throws -> Date {
        guard let text else { throw DiaryAgentError("from and to require ISO8601 timestamps") }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        guard let date = formatter.date(from: text) else { throw DiaryAgentError("Invalid ISO8601 timestamp: \(text)") }
        return date
    }

    public static func day(_ text: String, calendar: Calendar) throws -> Date {
        let formatter = dayFormatter(calendar)
        guard text.count == 10, let date = formatter.date(from: text), formatter.string(from: date) == text else {
            throw DiaryAgentError("date must be a valid YYYY-MM-DD")
        }
        return date
    }

    public static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

public final class DiaryAgentService {
    private let store: () throws -> DiaryStore
    private let loadSettings: () throws -> DiarySettings
    private let saveSettings: (DiarySettings) throws -> Void
    private let calendar: Calendar
    private let clock: () -> Date

    public init(store: @escaping () throws -> DiaryStore,
                loadSettings: @escaping () throws -> DiarySettings,
                saveSettings: @escaping (DiarySettings) throws -> Void,
                calendar: Calendar = .current, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.loadSettings = loadSettings
        self.saveSettings = saveSettings
        self.calendar = calendar
        self.clock = clock
    }

    public func handle(_ request: DiaryAgentRequest) -> DiaryAgentResponse {
        do { return try execute(request) }
        catch { return DiaryAgentResponse(error: error.localizedDescription) }
    }

    private func execute(_ request: DiaryAgentRequest) throws -> DiaryAgentResponse {
        var settings = try loadSettings()
        guard settings.enabled else {
            throw DiaryAgentError("Diary is disabled. Enable diary in the running Octoshot app.")
        }
        var response = DiaryAgentResponse()
        switch request.action {
        case .today, .show, .export:
            if request.action == .show && request.date == nil { throw DiaryAgentError("show requires a date") }
            let day = try request.date.map { try DiaryAgentJSON.day($0, calendar: calendar) } ?? clock()
            let report = DiaryReportBuilder(calendar: calendar, clock: clock)
                .build(windows: try store().fetch(day: day, calendar: calendar), day: day)
            response.report = DiaryAgentReport(date: DiaryAgentJSON.dayFormatter(calendar).string(from: report.day),
                summary: report.overviewLine, focusPattern: report.focusPattern.summaryLine,
                apps: report.appInsights.map {
                    .init(bundleID: $0.appBundleID, name: $0.appName, duration: $0.totalDuration, bullets: $0.bullets)
                }, segments: windows(report.timeline.map(\.skeleton)), closingRoast: report.closingRoast)
            response.markdown = DiaryMarkdownExporter().render(report)
        case .timeline:
            let from = try DiaryAgentJSON.instant(request.from)
            let to = try DiaryAgentJSON.instant(request.to)
            guard from < to else { throw DiaryAgentError("from must be earlier than to") }
            response.timeline = DiaryAgentTimeline(from: DiaryAgentJSON.timestamp(from), to: DiaryAgentJSON.timestamp(to),
                windows: windows(try store().fetch(range: from..<to)))
        case .pause:
            let minutes = request.minutes ?? 60
            guard (1...525600).contains(minutes) else { throw DiaryAgentError("minutes must be an integer from 1 to 525600") }
            settings.pausedUntil = clock().addingTimeInterval(Double(minutes) * 60)
            try saveSettings(settings)
        case .resume:
            settings.pausedUntil = nil
            try saveSettings(settings)
        case .purge:
            guard request.confirmed else { throw DiaryAgentError("purge requires --confirm") }
            try store().deleteAll()
        case .status:
            break
        }
        if response.report == nil && response.timeline == nil {
            response.status = DiaryAgentStatus(enabled: settings.enabled, paused: settings.isPaused(at: clock()),
                pausedUntil: settings.pausedUntil.map(DiaryAgentJSON.timestamp), retentionDays: settings.retentionDays,
                dailyReportTime: settings.dailyReportTime)
        }
        return response
    }

    private func windows(_ skeletons: [DiaryWindowSkeleton]) -> [DiaryAgentWindow] {
        skeletons.flatMap { skeleton in
            skeleton.entries.map {
                DiaryAgentWindow(start: DiaryAgentJSON.timestamp(skeleton.start), end: DiaryAgentJSON.timestamp(skeleton.end),
                    app: $0.appName, title: $0.windowTitle, snippets: $0.textSnippets.joined(separator: "\n"), urlHost: $0.urlHost)
            }
        }
    }
}
