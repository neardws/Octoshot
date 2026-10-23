import Foundation

public enum YijiangDiaryDigestBuilder {
    public static func buildDigest(
        windows: [YijiangDiaryTimelineWindow],
        day: Date,
        calendar: Calendar = .current
    ) -> String {
        let dayTitle = formatDay(day, calendar: calendar)
        var lines: [String] = []
        lines.append("# 一酱今日吐槽日报")
        lines.append("")
        lines.append("> 日期：\(dayTitle) · 本报告由本机原型管线生成，一酱面无表情地写完就下班了。")
        lines.append("")
        if windows.isEmpty {
            lines.append("一酱：今天屏幕比我的脸还干净。你到底是休假了还是在摸鱼？")
            return lines.joined(separator: "\n")
        }
        lines.append("## 时间线")
        lines.append("")
        for window in windows {
            lines.append("### \(formatRange(window.start, window.end))")
            for entry in window.entries {
                let app = entry.frontmostApp ?? "未知应用"
                let tag = entry.isKeyframe ? "关键帧" : "记录"
                let preview = truncate(entry.textPreview, max: 120)
                lines.append("- **\(formatTime(entry.timestamp))** · \(app) · \(tag)")
                if !preview.isEmpty {
                    lines.append("  - \(preview)")
                }
                if let caption = entry.vlmCaption, !caption.isEmpty {
                    lines.append("  - _一酱瞄了一眼：_ \(caption)")
                }
            }
            lines.append("")
        }
        lines.append("## 一酱总结")
        lines.append("")
        lines.append(sarcasticSummary(for: windows))
        return lines.joined(separator: "\n")
    }

    private static func sarcasticSummary(for windows: [YijiangDiaryTimelineWindow]) -> String {
        let apps = Set(windows.flatMap { $0.entries.compactMap(\.frontmostApp) })
        let keyframes = windows.flatMap(\.entries).filter(\.isKeyframe).count
        let appList = apps.sorted().joined(separator: "、")
        if apps.isEmpty {
            return "一酱：应用名全丢了。下次别只给我空白截图，我不是占卜章鱼。"
        }
        return """
        一酱：你今天在 **\(appList)** 之间来回横跳，我数到 **\(keyframes)** 个值得吐槽的关键帧。\
        活动看起来还算正常——至少没把锁屏当生产力工具。\
        详细罪证见上方时间线；本机摘要质量若太糙，别怪模型小，怪你今天窗口切太勤。
        """
    }

    private static func formatDay(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func formatRange(_ start: Date, _ end: Date) -> String {
        "\(formatTime(start)) – \(formatTime(end))"
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func truncate(_ text: String, max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max)) + "…"
    }
}
