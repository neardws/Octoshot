import AppKit

public enum ImageFormats {
    public static func writeUnique(image: NSImage, to url: URL, format: ScreenshotFormat, jpegQuality: Double) throws -> URL {
        guard let data = data(for: image, format: format, jpegQuality: jpegQuality) else {
            throw CaptureError.captureFailed("Failed to encode image")
        }
        return try CaptureOutput.writeUnique(data, to: url)
    }
    public static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    public static func jpegData(from image: NSImage, quality: Double) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
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
