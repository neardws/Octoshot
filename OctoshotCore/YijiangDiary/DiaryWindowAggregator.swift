import Foundation

public struct DiaryWindowEntry: Codable, Equatable {
    public var appBundleID: String
    public var appName: String
    public var windowTitle: String
    public var textSnippets: [String]
    public var urlHost: String?
    public var duration: TimeInterval
}

public struct DiaryWindowSkeleton: Codable, Equatable {
    public var start: Date
    public var end: Date
    public var appDurations: [String: TimeInterval]
    public var entries: [DiaryWindowEntry]
    public var keyframe: DiaryActivitySample?
}

public enum DiaryTextFingerprint {
    public static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func fingerprint(_ text: String) -> UInt64 {
        let characters = Array(normalized(text))
        guard !characters.isEmpty else { return 0 }
        let tokens = characters.count < 3 ? [String(characters)] : (0...(characters.count - 3)).map {
            String(characters[$0..<($0 + 3)])
        }
        var weights = [Int](repeating: 0, count: 64)
        for token in tokens {
            var hash: UInt64 = 14_695_981_039_346_656_037
            for byte in token.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
            hash ^= hash >> 33
            hash = hash &* 0xff51afd7ed558ccd
            hash ^= hash >> 33
            for bit in 0..<64 { weights[bit] += hash & (UInt64(1) << bit) == 0 ? -1 : 1 }
        }
        return (0..<64).reduce(UInt64(0)) { $1 >= 0 && weights[$1] > 0 ? $0 | (UInt64(1) << $1) : $0 }
    }

    public static func unchanged(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second else { return first == nil && second == nil }
        if normalized(first).isEmpty || normalized(second).isEmpty { return normalized(first) == normalized(second) }
        return (fingerprint(first) ^ fingerprint(second)).nonzeroBitCount <= 3
    }
}

public enum DiaryAggregationError: Error { case outOfOrder }

public final class DiaryWindowAggregator {
    public let interval: TimeInterval
    public let dwellThreshold: TimeInterval
    private let clock: () -> Date
    private var cursor: Date?
    private var active: DiaryActivitySample?
    private var window: DiaryWindowSkeleton?
    private var longestDwell: TimeInterval = 0
    private var activeDwell: TimeInterval = 0

    public init(interval: TimeInterval = 600, dwellThreshold: TimeInterval = 60,
                clock: @escaping () -> Date = Date.init) {
        precondition(interval.isFinite && interval > 0 && dwellThreshold.isFinite && dwellThreshold >= 0)
        self.interval = interval
        self.dwellThreshold = dwellThreshold
        self.clock = clock
    }

    public func append(_ sample: DiaryActivitySample) throws -> [DiaryWindowSkeleton] {
        try observe(sample, at: sample.timestamp)
    }

    public func observe(_ sample: DiaryActivitySample?, at date: Date) throws -> [DiaryWindowSkeleton] {
        let closed = try advance(to: date)
        if let previous = active, let sample,
           previous.appBundleID == sample.appBundleID, previous.windowTitle == sample.windowTitle,
           DiaryTextFingerprint.unchanged(previous.focusedText, sample.focusedText) {
            if active?.keyframeURL == nil { active?.keyframeURL = sample.keyframeURL }
        } else {
            active = sample
            activeDwell = 0
        }
        return closed
    }

    public func finish(at date: Date? = nil) throws -> [DiaryWindowSkeleton] {
        var closed = try advance(to: date ?? clock())
        if let completed = finalize() { closed.append(completed) }
        active = nil
        activeDwell = 0
        return closed
    }

    private func advance(to date: Date) throws -> [DiaryWindowSkeleton] {
        guard date.timeIntervalSince1970.isFinite else { throw DiaryAggregationError.outOfOrder }
        guard var position = cursor else { cursor = date; return [] }
        guard date >= position else { throw DiaryAggregationError.outOfOrder }
        var closed: [DiaryWindowSkeleton] = []
        while position < date {
            let start = Date(timeIntervalSince1970: floor(position.timeIntervalSince1970 / interval) * interval)
            let end = start.addingTimeInterval(interval)
            let segmentEnd = min(end, date)
            if let sample = active {
                if window == nil {
                    window = DiaryWindowSkeleton(start: start, end: end, appDurations: [:], entries: [], keyframe: nil)
                }
                accumulate(sample, duration: segmentEnd.timeIntervalSince(position))
            }
            position = segmentEnd
            if position == end {
                if let completed = finalize() { closed.append(completed) }
                activeDwell = 0
            }
        }
        cursor = date
        return closed
    }

    private func accumulate(_ sample: DiaryActivitySample, duration: TimeInterval) {
        guard var current = window else { return }
        current.appDurations[sample.appBundleID, default: 0] += duration
        let entryIndex: Int
        if let existing = current.entries.firstIndex(where: { $0.appBundleID == sample.appBundleID && $0.windowTitle == sample.windowTitle }) {
            entryIndex = existing
        } else {
            current.entries.append(DiaryWindowEntry(appBundleID: sample.appBundleID, appName: sample.appName,
                                                    windowTitle: sample.windowTitle, textSnippets: [],
                                                    urlHost: sample.urlHost, duration: 0))
            entryIndex = current.entries.count - 1
        }
        current.entries[entryIndex].duration += duration
        if let text = sample.focusedText, !text.isEmpty,
           !current.entries[entryIndex].textSnippets.contains(where: { DiaryTextFingerprint.unchanged($0, text) }) {
            current.entries[entryIndex].textSnippets.append(text)
        }
        activeDwell += duration
        if sample.keyframeURL != nil, activeDwell > longestDwell, activeDwell >= dwellThreshold {
            current.keyframe = sample
            longestDwell = activeDwell
        }
        window = current
    }

    private func finalize() -> DiaryWindowSkeleton? {
        defer { window = nil; longestDwell = 0 }
        guard var current = window else { return nil }
        current.entries.removeAll { $0.duration < dwellThreshold }
        return current
    }
}
