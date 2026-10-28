import AppKit
import ImageIO
import OctoshotCore

@MainActor
enum DiaryOllamaRuntime {
    static let service = DiaryOllamaRoastService { DiaryOllamaClient(configuration: .load()) }

    static func keyFrameData(for window: DiaryWindowSkeleton) -> Data? {
        let root = DiaryStore.defaultDirectory.appendingPathComponent("frames").resolvingSymlinksInPath().standardizedFileURL
        guard let url = window.keyframe?.keyframeURL, url.isFileURL,
              url.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent() == root,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 8 * 1024 * 1024 else { return nil }
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 448
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: thumbnail).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
