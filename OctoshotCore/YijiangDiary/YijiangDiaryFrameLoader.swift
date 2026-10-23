import Foundation

public enum YijiangDiaryFrameLoaderError: LocalizedError {
    case directoryNotFound(URL)
    case noFrames(URL)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let url):
            return "Input folder does not exist: \(url.path)"
        case .noFrames(let url):
            return "No timestamped PNG frames found in \(url.path)"
        }
    }
}

/// Loads prototype frames from a folder of PNGs (+ optional `.meta.json` sidecars).
public enum YijiangDiaryFrameLoader {
    private static let imageExtensions = ["png", "jpg", "jpeg", "webp"]

    public static func loadFrames(from directory: URL, fileManager: FileManager = .default) throws -> [YijiangDiaryFrame] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw YijiangDiaryFrameLoaderError.directoryNotFound(directory)
        }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let images = urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        var frames: [YijiangDiaryFrame] = []
        for imageURL in images {
            let base = imageURL.deletingPathExtension().lastPathComponent
            let metaURL = directory.appendingPathComponent("\(base).meta.json")
            let meta = loadMeta(at: metaURL)
            let timestamp = meta?.timestamp ?? parseTimestamp(from: base) ?? .distantPast
            let app = meta?.frontmostApp ?? parseAppSuffix(from: base)
            frames.append(YijiangDiaryFrame(
                timestamp: timestamp,
                imageURL: imageURL,
                frontmostApp: app,
                accessibilityText: meta?.accessibilityText
            ))
        }
        frames.sort { $0.timestamp < $1.timestamp }
        guard !frames.isEmpty else { throw YijiangDiaryFrameLoaderError.noFrames(directory) }
        return frames
    }

    private struct SidecarMeta: Decodable {
        let timestamp: Date?
        let frontmostApp: String?
        let accessibilityText: String?
    }

    private static func loadMeta(at url: URL) -> SidecarMeta? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SidecarMeta.self, from: data)
    }

    /// `2025-10-17T09-05-00+0800`, `20251017-090500`, `2025-10-17T09:05:00Z`
    public static func parseTimestamp(from basename: String) -> Date? {
        let withoutApp = basename.split(separator: "_", maxSplits: 1).first.map(String.init) ?? basename
        let formats: [(String, String)] = [
            ("yyyy-MM-dd'T'HH-mm-ssZZZZZ", withoutApp),
            ("yyyy-MM-dd'T'HH:mm:ssZZZZZ", withoutApp),
            ("yyyy-MM-dd'T'HH:mm:ssX", withoutApp),
            ("yyyyMMdd-HHmmss", withoutApp),
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for (format, value) in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        if let iso = ISO8601DateFormatter().date(from: withoutApp) { return iso }
        return nil
    }

    /// `2025-10-17T09-05-00_Xcode` → Xcode
    private static func parseAppSuffix(from basename: String) -> String? {
        let parts = basename.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let app = String(parts[1])
        return app.isEmpty ? nil : app
    }
}
