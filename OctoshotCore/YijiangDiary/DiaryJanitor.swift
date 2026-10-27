import Foundation

public struct DiaryCleanupPolicy {
    public let retentionDays: Int?
    public let failedFrameTTL: TimeInterval

    public init(retentionDays: Int? = 30, failedFrameTTL: TimeInterval = 86_400) {
        precondition(retentionDays == nil || [7, 30, 90].contains(retentionDays!))
        precondition(failedFrameTTL.isFinite && failedFrameTTL >= 0)
        self.retentionDays = retentionDays
        self.failedFrameTTL = failedFrameTTL
    }
}

public enum DiaryCleanupError: Error { case frameOutsideRoot }

public final class DiaryJanitor {
    public let framesDirectory: URL
    private let store: DiaryStore
    private let policy: DiaryCleanupPolicy
    private let fileManager: FileManager
    private let clock: () -> Date

    public init(store: DiaryStore, root: URL? = nil, policy: DiaryCleanupPolicy = DiaryCleanupPolicy(),
                fileManager: FileManager = .default, clock: @escaping () -> Date = Date.init) throws {
        self.store = store
        self.policy = policy
        self.fileManager = fileManager
        self.clock = clock
        framesDirectory = (root ?? store.directory).appendingPathComponent("frames", isDirectory: true)
        try DiaryStore.prepareDirectory(framesDirectory, fileManager: fileManager)
    }

    public func markProcessed(_ frameURL: URL) throws {
        let resolved = frameURL.resolvingSymlinksInPath().standardizedFileURL
        guard frameURL.isFileURL,
              resolved.deletingLastPathComponent() == framesDirectory.resolvingSymlinksInPath().standardizedFileURL else {
            throw DiaryCleanupError.frameOutsideRoot
        }
        guard fileManager.fileExists(atPath: frameURL.path) else { return }
        let values = try frameURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DiaryCleanupError.frameOutsideRoot }
        try fileManager.removeItem(at: frameURL)
    }

    public func runCleanup(now: Date? = nil) throws {
        let now = now ?? clock()
        let frames = try fileManager.contentsOfDirectory(at: framesDirectory,
                                                         includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
        for frame in frames {
            let values = try frame.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true,
               let modified = values.contentModificationDate,
               now.timeIntervalSince(modified) >= policy.failedFrameTTL {
                try markProcessed(frame)
            }
        }
        if let days = policy.retentionDays { try store.purge(olderThan: now.addingTimeInterval(-Double(days) * 86_400)) }
    }
}
