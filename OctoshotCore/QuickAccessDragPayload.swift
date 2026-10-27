import AppKit
import ImageIO
import UniformTypeIdentifiers

public struct QuickAccessDragPayload: Sendable {
    public static let pasteboardTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]
    public static let maximumAge: TimeInterval = 60 * 60
    private static let preparationQueue = DispatchQueue(label: "com.neardws.Octoshot.drag-export", qos: .userInitiated)

    public let fileURL: URL
    public let pngData: Data
    public let tiffData: Data
    public let preparedAt: Date

    public static func filename(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "'Screenshot 'yyyy-MM-dd' at 'HH.mm.ss'.png'"
        return formatter.string(from: date)
    }

    public static func prepare(
        _ snapshot: ImageFormats.Snapshot,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        now: @escaping @Sendable () -> Date = { Date() }
    ) async throws -> QuickAccessDragPayload {
        let pngData = try await ImageFormats.encodeAsync(snapshot, format: .png, jpegQuality: 1)
        return try await withCheckedThrowingContinuation { continuation in
            preparationQueue.async {
                continuation.resume(with: Result {
                    let preparedAt = now()
                    let output = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(output, UTType.tiff.identifier as CFString, 1, nil) else {
                        throw CaptureError.captureFailed("Failed to create drag TIFF encoder")
                    }
                    CGImageDestinationAddImage(destination, snapshot.image, [
                        kCGImagePropertyDPIWidth: Double(snapshot.image.width) * 72 / snapshot.pointSize.width,
                        kCGImagePropertyDPIHeight: Double(snapshot.image.height) * 72 / snapshot.pointSize.height
                    ] as CFDictionary)
                    guard CGImageDestinationFinalize(destination) else {
                        throw CaptureError.captureFailed("Failed to encode drag TIFF")
                    }
                    let root = temporaryDirectory.appendingPathComponent("Octoshot-Drag", isDirectory: true)
                    try validateRoot(root)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try cleanup(temporaryDirectory: temporaryDirectory, now: preparedAt)
                    let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                    let fileURL = directory.appendingPathComponent(filename(at: preparedAt))
                    do {
                        try pngData.write(to: fileURL, options: .atomic)
                    } catch {
                        try? FileManager.default.removeItem(at: directory)
                        throw error
                    }
                    return QuickAccessDragPayload(fileURL: fileURL, pngData: pngData,
                                                  tiffData: output as Data, preparedAt: preparedAt)
                })
            }
        }
    }

    public static func cleanup(temporaryDirectory: URL, now: Date = Date()) throws {
        let root = temporaryDirectory.appendingPathComponent("Octoshot-Drag", isDirectory: true)
        try validateRoot(root)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            let values = try directory.resourceValues(forKeys: keys)
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  let modifiedAt = values.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) > maximumAge else { continue }
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func validateRoot(_ root: URL) throws {
        if (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw CocoaError(.fileWriteInvalidFileName)
        }
    }
}

public final class QuickAccessDragPasteboardWriter: NSObject, NSPasteboardWriting {
    private let payload: QuickAccessDragPayload

    public init(payload: QuickAccessDragPayload) {
        self.payload = payload
        super.init()
    }

    public func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        QuickAccessDragPayload.pasteboardTypes
    }

    public func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL: return (payload.fileURL as NSURL).pasteboardPropertyList(forType: type)
        case .png: return payload.pngData
        case .tiff: return payload.tiffData
        default: return nil
        }
    }
}
