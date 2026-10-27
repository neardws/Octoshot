import Foundation

public struct DiaryMarkdownExporter {
    public init() {}

    public func render(_ report: DiaryDailyReport) -> String {
        var lines = ["# 一酱日记 · \(DiaryReportText.date(report.day, calendar: report.calendar, format: "yyyy年M月d日"))",
                     "", "我是东太平洋红章鱼一酱（Octopus rubescens）。只记有据可查的今天。", "",
                     "## 今天在干嘛", "", escape(report.overviewLine), "", escape(report.focusPattern.summaryLine), "",
                     "## 各 App 都干了啥", ""]
        for insight in report.appInsights {
            lines += ["### \(escape(insight.appName))（\(DiaryReportText.duration(insight.totalDuration))）", ""]
            lines += insight.bullets.map { "- " + escape($0) }
            lines.append("")
        }
        lines += ["## 时间线", ""]
        if report.timeline.isEmpty { lines += ["今天还没有记录。没有记录，不代表什么都没做。", ""] }
        for segment in report.timeline {
            let window = segment.skeleton
            let start = DiaryReportText.date(window.start, calendar: report.calendar, format: "HH:mm")
            let end = DiaryReportText.date(window.end, calendar: report.calendar, format: "HH:mm")
            lines += ["### \(start)–\(end)", ""]
            lines += window.entries.map { "- " + escape(DiaryReportText.facts($0)) }
            if let roast = segment.roast { lines += ["", "_一酱：\(escape(roast))_"] }
            lines.append("")
        }
        lines += ["", "## 一酱总结", "", escape(report.closingRoast ?? "今天的记录到这里。"), ""]
        return lines.joined(separator: "\n")
    }

    private func escape(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        for character in ["\\", "`", "*", "_", "[", "]", "<", ">", "|", "#", "!"] {
            result = result.replacingOccurrences(of: character, with: "\\" + character)
        }
        return result
    }
}
