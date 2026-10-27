import Foundation

public final class DiaryRecorder {
    private let source: DiaryActivitySource
    private let exclusion: DiaryExclusionPolicy
    private let aggregator: DiaryWindowAggregator
    private let store: DiaryStore
    private let janitor: DiaryJanitor
    private let clock: () -> Date
    private var pending: [DiaryWindowSkeleton] = []
    private var frames: [URL: Date] = [:]

    public init(source: DiaryActivitySource, store: DiaryStore, janitor: DiaryJanitor,
                exclusion: DiaryExclusionPolicy = DiaryExclusionPolicy(),
                aggregator: DiaryWindowAggregator = DiaryWindowAggregator(), clock: @escaping () -> Date = Date.init) {
        self.source = source
        self.store = store
        self.janitor = janitor
        self.exclusion = exclusion
        self.aggregator = aggregator
        self.clock = clock
    }

    @discardableResult
    public func recordNext() throws -> Bool {
        try persistPending()
        guard let sample = try source.nextSample() else { return false }
        let sanitized = exclusion.sanitize(sample)
        pending += try aggregator.observe(sanitized, at: sample.timestamp)
        if let frame = sample.keyframeURL {
            if sanitized == nil { try janitor.markProcessed(frame) }
            else { frames[frame] = sample.timestamp }
        }
        try persistPending()
        return true
    }

    public func recordUnavailable(at date: Date? = nil) throws {
        try persistPending()
        pending += try aggregator.observe(nil, at: date ?? clock())
        try persistPending()
    }

    public func finish(at date: Date? = nil) throws {
        try persistPending()
        pending += try aggregator.finish(at: date ?? clock())
        try persistPending()
        for frame in Array(frames.keys) {
            try janitor.markProcessed(frame)
            frames.removeValue(forKey: frame)
        }
    }

    private func persistPending() throws {
        while let window = pending.first {
            try store.insert(window)
            pending.removeFirst()
            if let frame = window.keyframe?.keyframeURL { try janitor.markProcessed(frame) }
            for (frame, timestamp) in frames.filter({ $0.value < window.end }) {
                try janitor.markProcessed(frame)
                if frames[frame] == timestamp { frames.removeValue(forKey: frame) }
            }
        }
    }
}
