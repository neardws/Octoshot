import Foundation

public enum YijiangDiaryKeyframeSelector {
    /// Picks indices into `snapshots` for VLM captioning: app switches, meaningful text changes, idle gaps.
    public static func selectKeyframeIndices(
        from snapshots: [YijiangDiaryFrameSnapshot],
        minimumTextJaccardDelta: Double = 0.15,
        idleGapSeconds: TimeInterval = 120
    ) -> [Int] {
        guard !snapshots.isEmpty else { return [] }
        var kept: [Int] = [0]
        for index in 1 ..< snapshots.count {
            let current = snapshots[index]
            let lastIndex = kept[kept.count - 1]
            let previous = snapshots[lastIndex]
            if shouldKeepKeyframe(
                current: current,
                previous: previous,
                minimumTextJaccardDelta: minimumTextJaccardDelta,
                idleGapSeconds: idleGapSeconds
            ) {
                if dedupeAgainstPrevious(current: current, previous: previous) { continue }
                kept.append(index)
            }
        }
        return kept
    }

    private static func shouldKeepKeyframe(
        current: YijiangDiaryFrameSnapshot,
        previous: YijiangDiaryFrameSnapshot,
        minimumTextJaccardDelta: Double,
        idleGapSeconds: TimeInterval
    ) -> Bool {
        let gap = current.frame.timestamp.timeIntervalSince(previous.frame.timestamp)
        if gap >= idleGapSeconds { return true }
        let prevApp = normalizedApp(previous.frame.frontmostApp)
        let currApp = normalizedApp(current.frame.frontmostApp)
        if prevApp != currApp { return true }
        let jaccard = textJaccard(previous.resolvedText, current.resolvedText)
        return jaccard < (1.0 - minimumTextJaccardDelta)
    }

    private static func dedupeAgainstPrevious(
        current: YijiangDiaryFrameSnapshot,
        previous: YijiangDiaryFrameSnapshot
    ) -> Bool {
        normalizedTextHash(current.resolvedText) == normalizedTextHash(previous.resolvedText)
            && normalizedApp(current.frame.frontmostApp) == normalizedApp(previous.frame.frontmostApp)
    }

    public static func textJaccard(_ a: String, _ b: String) -> Double {
        let setA = tokenSet(a)
        let setB = tokenSet(b)
        if setA.isEmpty && setB.isEmpty { return 1 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    public static func normalizedTextHash(_ text: String) -> String {
        tokenSet(text).sorted().joined(separator: "|")
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let parts = lowered.split { $0.isWhitespace || $0.isNewline || $0.isPunctuation }
        return Set(parts.map(String.init).filter { !$0.isEmpty })
    }

    private static func normalizedApp(_ app: String?) -> String {
        (app ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
