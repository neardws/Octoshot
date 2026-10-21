import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormats {
    private final class RasterImage: NSImage {
        var pixels: CGImage?
    }

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
        if !Thread.isMainThread {
            return try DispatchQueue.main.sync { try snapshot(image) }
        }
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.captureFailed("Failed to extract image pixels")
        }
        if let raster = image as? RasterImage, raster.pixels === pixels {
            return Snapshot(image: pixels, pointSize: image.size)
        }
        let context = try bitmapContext(width: pixels.width, height: pixels.height,
                                        colorSpace: pixels.colorSpace ?? CGColorSpaceCreateDeviceRGB())
        context.draw(pixels, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        guard let materialized = context.makeImage() else {
            throw CaptureError.captureFailed("Failed to materialize image pixels")
        }
        return Snapshot(image: materialized, pointSize: image.size)
    }

    public static func composite(size: CGSize, flipped: Bool, drawing: () throws -> Void) throws -> NSImage {
        if !Thread.isMainThread {
            return try DispatchQueue.main.sync { try composite(size: size, flipped: flipped, drawing: drawing) }
        }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw CaptureError.captureFailed("Invalid composite size")
        }
        let probe = NSImage(size: CGSize(width: 1, height: 1))
        probe.lockFocus()
        let focus = NSGraphicsContext.current?.cgContext
        let scaleX = abs(focus?.ctm.a ?? 1)
        let scaleY = abs(focus?.ctm.d ?? 1)
        let colorSpace = focus?.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        probe.unlockFocus()
        let width = ceil(size.width * scaleX)
        let height = ceil(size.height * scaleY)
        guard width > 0, height > 0, width < CGFloat(Int.max / 4), height < CGFloat(Int.max) else {
            throw CaptureError.captureFailed("Invalid composite pixel size")
        }
        let context = try bitmapContext(width: Int(width), height: Int(height), colorSpace: colorSpace)
        context.scaleBy(x: scaleX, y: scaleY)
        if flipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: flipped)
        try drawing()
        guard let pixels = context.makeImage() else {
            throw CaptureError.captureFailed("Failed to materialize composite")
        }
        let image = RasterImage(cgImage: pixels, size: size)
        image.pixels = pixels
        return image
    }

    private static func bitmapContext(width: Int, height: Int, colorSpace: CGColorSpace) throws -> CGContext {
        let rgbSpace = colorSpace.model == .rgb ? colorSpace : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: rgbSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.captureFailed("Failed to allocate 8-bit image pixels")
        }
        return context
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
