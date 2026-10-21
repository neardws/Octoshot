import AppKit
import Foundation
import OctoshotCore

struct ScreenshotHistoryEntry: Identifiable, Equatable {
    let id: URL
    let url: URL
    let modifiedAt: Date

    var filename: String { url.lastPathComponent }
}

enum ScreenshotHistoryStore {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "heic", "heif",
    ]

    /// Scans the configured capture save directory (same path as screenshots on disk).
    @MainActor
    static func loadEntries(limit: Int = 500) -> [ScreenshotHistoryEntry] {
        let directory = AppSettings.shared.saveDirectory
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let entries: [ScreenshotHistoryEntry] = urls.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { return nil }
            let date = values?.contentModificationDate ?? .distantPast
            return ScreenshotHistoryEntry(id: url, url: url, modifiedAt: date)
        }

        return entries
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map { $0 }
    }

    static func loadImage(at url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }

    @MainActor
    static func copyToClipboard(url: URL) {
        if let image = NSImage(contentsOf: url) {
            ImageExportActions.copy(image)
        }
    }

    static func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func delete(url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        RecentCapturesStore.remove(path: url.path)
    }
}
