import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormats {
    public struct Snapshot: @unchecked Sendable {
        public let image: CGImage
        public let pointSize: CGSize

        public init(image: CGImage, pointSize: CGSize) {
            self.image = image
            self.pointSize = pointSize
        }
    }

    private static let encodingQueue = DispatchQueue(label: "com.neardws.Octoshot.image-export", qos: .userInitiated,
                                                     autoreleaseFrequency: .workItem)

    public static func snapshot(_ image: NSImage) throws -> Snapshot {
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.captureFailed("Failed to extract image pixels")
        }
        return Snapshot(image: pixels, pointSize: image.size)
    }

    public static func encode(_ snapshot: Snapshot, format: ScreenshotFormat, jpegQuality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output,
            (format == .png ? UTType.png.identifier : UTType.jpeg.identifier) as CFString, 1, nil) else {
            throw CaptureError.captureFailed("Failed to create image encoder")
        }
        let size = snapshot.pointSize
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw CaptureError.captureFailed("Invalid image point size")
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: Double(snapshot.image.width) * 72 / size.width,
            kCGImagePropertyDPIHeight: Double(snapshot.image.height) * 72 / size.height,
            kCGImagePropertyOrientation: 1
        ]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0, jpegQuality))
        }
        CGImageDestinationAddImage(destination, snapshot.image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.captureFailed("Failed to encode image")
        }
        return output as Data
    }

    public static func encodeAsync(_ snapshot: Snapshot, format: ScreenshotFormat, jpegQuality: Double) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            encodingQueue.async {
                continuation.resume(with: Result { try encode(snapshot, format: format, jpegQuality: jpegQuality) })
            }
        }
    }

    public static func writeAsync(_ snapshot: Snapshot, to url: URL, format: ScreenshotFormat,
                                  jpegQuality: Double, unique: Bool = false) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            encodingQueue.async {
                continuation.resume(with: Result {
                    let data = try encode(snapshot, format: format, jpegQuality: jpegQuality)
                    if unique { return try CaptureOutput.writeUnique(data, to: url) }
                    try writeData(data, to: url)
                    return url
                })
            }
        }
    }

    @MainActor
    public static func writeUniqueAsync(image: NSImage, to url: URL, format: ScreenshotFormat,
                                        jpegQuality: Double) async throws -> URL {
        try await writeAsync(snapshot(image), to: url, format: format, jpegQuality: jpegQuality, unique: true)
    }

    @MainActor
    public static func copyToPasteboardAsync(_ image: NSImage) async throws {
        let data = try await encodeAsync(snapshot(image), format: .png, jpegQuality: 1)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
    }

    public static func writeUnique(image: NSImage, to url: URL, format: ScreenshotFormat, jpegQuality: Double) throws -> URL {
        guard let data = data(for: image, format: format, jpegQuality: jpegQuality) else {
            throw CaptureError.captureFailed("Failed to encode image")
        }
        return try CaptureOutput.writeUnique(data, to: url)
    }
    public static func pngData(from image: NSImage) -> Data? {
        try? encode(snapshot(image), format: .png, jpegQuality: 1)
    }

    public static func jpegData(from image: NSImage, quality: Double) -> Data? {
        try? encode(snapshot(image), format: .jpeg, jpegQuality: quality)
    }

    public static func data(for image: NSImage, format: ScreenshotFormat, jpegQuality: Double) -> Data? {
        switch format {
        case .png: return pngData(from: image)
        case .jpeg: return jpegData(from: image, quality: jpegQuality)
        }
    }

    public static func writePNG(image: NSImage, to url: URL) throws {
        guard let data = pngData(from: image) else {
            throw NSError(domain: "Octoshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try writeData(data, to: url)
    }

    public static func writeJPEG(image: NSImage, to url: URL, quality: Double) throws {
        guard let data = jpegData(from: image, quality: quality) else {
            throw NSError(domain: "Octoshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"])
        }
        try writeData(data, to: url)
    }

    public static func write(image: NSImage, to url: URL, format: ScreenshotFormat, jpegQuality: Double) throws {
        guard let data = data(for: image, format: format, jpegQuality: jpegQuality) else {
            throw NSError(domain: "Octoshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        try writeData(data, to: url)
    }

    private static func writeData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    public static func copyToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard let data = pngData(from: image) else {
            pasteboard.writeObjects([image])
            return
        }
        pasteboard.setData(data, forType: .png)
    }
}
