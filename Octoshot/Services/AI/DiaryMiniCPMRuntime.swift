import AppKit
import ImageIO
import OctoshotCore
import OctoshotEmbeddedMLX

@MainActor
enum DiaryMiniCPMRuntime {
    static let loader = MLXVLMLoader.shared
    static var compatibilityNote: String {
        OctoshotL10n.text("Swift MLX does not yet support minicpmv4_6. Downloads are available, but real roasts are blocked; text diaries still work.")
    }
    static let service = DiaryMiniCPMRoastService { prompt, imageData in
        let image = imageData.flatMap { data -> NSImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 448
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: thumbnail, size: .zero)
        }
        return try await loader.respond(
            prompt: prompt, image: image,
            modelDirectory: EmbeddedAIModelPaths.directory(for: .miniCPMV46_4bit),
            maxTokens: DiaryMiniCPMRoastService.maxTokens,
            timeout: DiaryMiniCPMRoastService.timeout,
            idleUnloadDelay: DiaryMiniCPMRoastService.idleUnloadDelay)
    }

    static func keyFrameData(for window: DiaryWindowSkeleton) -> Data? {
        let root = DiaryStore.defaultDirectory.appendingPathComponent("frames").resolvingSymlinksInPath().standardizedFileURL
        guard let url = window.keyframe?.keyframeURL, url.isFileURL,
              url.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent() == root,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 8 * 1024 * 1024 else { return nil }
        return try? Data(contentsOf: url)
    }
}
