import Foundation

public struct DiaryAppInsight: Equatable {
    public let appBundleID: String
    public let appName: String
    public let totalDuration: TimeInterval
    public let bullets: [String]
}

public struct DiaryFocusPattern: Equatable {
    public struct BouncePair: Equatable {
        public let firstAppName: String
        public let secondAppName: String
        public let switchCount: Int
    }

    public let switchCount: Int
    public let uniqueAppCount: Int
    public let longestFocus: TimeInterval
    public let longestFocusAppName: String?
    public let topBouncePair: BouncePair?
    public let fragmentationLabel: String
    public let summaryLine: String
}

enum DiaryInsightAnalyzer {
    struct Analysis {
        let overviewLine: String
        let appInsights: [DiaryAppInsight]
        let focusPattern: DiaryFocusPattern
    }

    static func analyze(_ windows: [DiaryWindowSkeleton]) -> Analysis {
        let entries = windows.flatMap(\.entries)
        let groups = Dictionary(grouping: entries, by: \.appBundleID)
        var insights: [DiaryAppInsight] = []
        for (bundleID, group) in groups {
            let ranked = rankedEntries(group)
            let titles = distinct(ranked.map(\.windowTitle))
            let snippets = distinct(ranked.flatMap(\.textSnippets))
            let hosts = distinct(ranked.compactMap(\.urlHost))
            var bullets: [String] = []
            if !titles.isEmpty { bullets.append("窗口：" + titles.prefix(3).map { "《\($0)》" }.joined(separator: "、")) }
            if !snippets.isEmpty { bullets.append("骨架文字提到：" + snippets.prefix(4).joined(separator: "；")) }
            if !hosts.isEmpty { bullets.append("浏览：" + hosts.prefix(3).joined(separator: "、")) }
            if bullets.isEmpty { bullets.append("只记下了 App 名，窗口文字不足") }
            if bullets.count == 1 { bullets.append("文字线索有限，不据此推断具体操作或完成情况") }
            let total = windows.reduce(0) { $0 + ($1.appDurations[bundleID] ?? 0) }
            insights.append(DiaryAppInsight(appBundleID: bundleID, appName: group[0].appName,
                                            totalDuration: total, bullets: bullets))
        }
        insights.sort { $0.totalDuration == $1.totalDuration ? $0.appBundleID < $1.appBundleID : $0.totalDuration > $1.totalDuration }
        let themes = insights.prefix(2).map { insight -> String in
            let ranked = rankedEntries(groups[insight.appBundleID]!)
            guard let entry = ranked.first(where: { detail($0) != nil }), let detail = detail(entry) else {
                return "\(insight.appName) 只留下 App 名，文字不足"
            }
            let snippet = distinct(ranked.flatMap(\.textSnippets)).first
            var theme = "\(insight.appName) 留下「\(String(detail.prefix(36)))」的线索"
            if let snippet, snippet != detail { theme += "，文字提到「\(String(snippet.prefix(40)))」" }
            return theme
        }
        let overview = insights.isEmpty
            ? "今天还没有记录，八只手暂时无从下笔。没有记录，不代表什么都没做。"
            : "今天主要记下了这些：" + themes.joined(separator: "；") + "。这些是窗口文字，不代表任务已经完成。"
        return Analysis(overviewLine: overview, appInsights: insights, focusPattern: focus(windows))
    }

    static func detail(_ entry: DiaryWindowEntry) -> String? {
        ([entry.windowTitle] + entry.textSnippets + [entry.urlHost].compactMap { $0 })
            .map(compact).first(where: { !$0.isEmpty })
    }

    static func rankedEntries(_ entries: [DiaryWindowEntry]) -> [DiaryWindowEntry] {
        entries.enumerated().sorted {
            $0.element.duration == $1.element.duration ? $0.offset < $1.offset : $0.element.duration > $1.element.duration
        }.map(\.element)
    }

    private static func compact(_ text: String) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(72))
    }

    private static func distinct(_ texts: [String]) -> [String] {
        var result: [String] = []
        for text in texts.map(compact) where !text.isEmpty {
            if !result.contains(where: { DiaryTextFingerprint.unchanged($0, text) }) { result.append(text) }
        }
        return result
    }

    private static func focus(_ windows: [DiaryWindowSkeleton]) -> DiaryFocusPattern {
        var names: [String: String] = [:]
        var previousApp: String?
        var stretchApp: String?
        var previousEnd: Date?
        var stretch: TimeInterval = 0
        var longest: TimeInterval = 0
        var longestApp: String?
        var total: TimeInterval = 0
        var switches = 0
        var pairs: [[String]: Int] = [:]
        for window in windows {
            if previousEnd != window.start || window.entries.isEmpty {
                stretch = 0
                stretchApp = nil
            }
            for entry in window.entries {
                let app = entry.appBundleID
                if names[app] == nil { names[app] = entry.appName }
                if let previousApp, previousApp != app {
                    switches += 1
                    pairs[[previousApp, app].sorted(), default: 0] += 1
                }
                let duration = entry.duration.isFinite ? max(0, entry.duration) : 0
                stretch = stretchApp == app ? stretch + duration : duration
                if longestApp == nil || stretch > longest {
                    longest = stretch
                    longestApp = app
                }
                total += duration
                previousApp = app
                stretchApp = app
            }
            previousEnd = window.end
        }
        let bestPair = pairs.keys.sorted {
            pairs[$0] == pairs[$1] ? $0.lexicographicallyPrecedes($1) : pairs[$0]! > pairs[$1]!
        }.first
        let bounce = bestPair.map {
            DiaryFocusPattern.BouncePair(firstAppName: names[$0[0]]!, secondAppName: names[$0[1]]!, switchCount: pairs[$0]!)
        }
        let rate = Double(switches) / max(total / 3600, 1)
        let label = names.isEmpty ? "暂无记录" : switches == 0 ? "专注线索较连贯"
            : rate < 4 ? "偶有切换" : rate < 10 ? "比较碎" : "来回跳"
        var summary = "还没有足够的窗口条目，一酱先不评价专注。"
        if let longestApp {
            summary = "按保留条目估计，今天\(label)，\(names.count) 个 App 间切换 \(switches) 次"
            if let bounce {
                summary += "，其中 \(bounce.firstAppName) / \(bounce.secondAppName) 间切换最多（\(bounce.switchCount) 次）"
            }
            summary += "；最长同 App 连段在 \(names[longestApp]!)，累计 \(DiaryReportText.duration(longest))。"
            summary += "骨架会合并同窗并过滤短停留，不等于完整切换或实际连续专注；记录空档不连算。"
        }
        return DiaryFocusPattern(switchCount: switches, uniqueAppCount: names.count, longestFocus: longest,
                                 longestFocusAppName: longestApp.flatMap { names[$0] }, topBouncePair: bounce,
                                 fragmentationLabel: label, summaryLine: summary)
    }
}
