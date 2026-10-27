import Foundation

public struct DiaryMarkdownExporter {
    public init() {}

    public func render(_ report: DiaryDailyReport) -> String {
        var lines = ["# 一酱日记 · \(DiaryReportText.date(report.day, calendar: report.calendar, format: "yyyy年M月d日"))",
                     "", "我是东太平洋红章鱼一酱（Octopus rubescens）。只记有据可查的今天。", "",
                     "## 今天八只手都干了啥", ""]
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
        lines += ["## App 用时", "", "| App | 用时 |", "| --- | --- |"]
        for app in report.appDurations.keys.sorted() {
            lines.append("| \(escape(report.appNames[app] ?? app)) | \(DiaryReportText.duration(report.appDurations[app]!)) |")
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
