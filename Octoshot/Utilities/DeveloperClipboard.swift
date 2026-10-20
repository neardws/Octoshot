import AppKit
import OctoshotCore

@MainActor
enum DeveloperClipboard {
    /// Writes the image if needed and copies a GitHub-friendly Markdown image line to the pasteboard.
    @discardableResult
    static func copyMarkdownSnippet(
        for image: NSImage,
        existingURL: URL? = nil
    ) async throws -> URL {
        let url: URL
        if let existingURL {
            url = existingURL
        } else {
            url = try await writeCaptureToDefaultLocation(image: image)
        }
        let link = markdownLink(for: url)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)
        return url
    }

    static func copyFilePath(for image: NSImage, existingURL: URL? = nil) async throws -> URL {
        let url: URL
        if let existingURL {
            url = existingURL
        } else {
            url = try await writeCaptureToDefaultLocation(image: image)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        return url
    }

    static func markdownLink(for url: URL) -> String {
        let settings = AppSettings.shared
        let pathComponent: String
        if settings.markdownImageUseAbsolutePath {
            pathComponent = url.path
        } else {
            pathComponent = url.lastPathComponent
        }
        let alt = url.deletingPathExtension().lastPathComponent
        return "![\(alt)](\(pathComponent))"
    }

    private static func writeCaptureToDefaultLocation(image: NSImage) async throws -> URL {
        let settings = AppSettings.shared
        let url = settings.defaultSaveURL()
        return try await ImageFormats.writeUniqueAsync(
            image: image,
            to: url,
            format: settings.format,
            jpegQuality: settings.jpegQuality
        )
    }
}
