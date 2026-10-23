import Foundation

public enum YijiangDiaryWindowing {
    public static func assignWindows(
        to entries: [YijiangDiaryWindowEntry],
        windowMinutes: Int,
        calendar: Calendar = .current
    ) -> [YijiangDiaryTimelineWindow] {
        guard windowMinutes > 0, !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var buckets: [Date: [YijiangDiaryWindowEntry]] = [:]
        for entry in sorted {
            let start = floorToWindow(entry.timestamp, minutes: windowMinutes, calendar: calendar)
            buckets[start, default: []].append(entry)
        }
        return buckets.keys.sorted().map { start in
            let end = calendar.date(byAdding: .minute, value: windowMinutes, to: start) ?? start
            return YijiangDiaryTimelineWindow(start: start, end: end, entries: buckets[start] ?? [])
        }
    }

    public static func floorToWindow(_ date: Date, minutes: Int, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minute = components.minute else { return date }
        let flooredMinute = (minute / minutes) * minutes
        var adjusted = components
        adjusted.minute = flooredMinute
        adjusted.second = 0
        adjusted.nanosecond = 0
        return calendar.date(from: adjusted) ?? date
    }

    /// Picks the snapshot index in `snapshots` that best represents a timeline window for VLM captioning.
    public static func representativeKeyframeIndex(
        in snapshots: [YijiangDiaryFrameSnapshot],
        keyframeIndices: [Int],
        windowStart: Date,
        windowEnd: Date
    ) -> Int? {
        let inWindow = keyframeIndices.filter { idx in
            let ts = snapshots[idx].frame.timestamp
            return ts >= windowStart && ts < windowEnd
        }
        if let last = inWindow.last { return last }
        return keyframeIndices.last { snapshots[$0].frame.timestamp < windowEnd }
    }
}
