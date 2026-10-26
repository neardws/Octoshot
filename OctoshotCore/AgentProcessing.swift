import AppKit
import Foundation

public enum AgentProcessing {
    public static func autoRedact(image: NSImage) async throws -> NSImage {
        let candidates = try await RedactionDetector.detect(in: image, settings: AgentConfiguration.redactionSettings())
        return try RedactionCompositor.apply(candidates.filter(\.isEnabled), to: image)
    }

    public static func askAI(image: NSImage, prompt: String) async throws -> String {
        let reachable = await AgentOllama.isReachable()
        let settings = EmbeddedAISettings.fromUserDefaults(ollamaReachable: reachable)
        return try await EmbeddedAIRouter.askAI(image: image, prompt: prompt, settings: settings)
    }

    public static func toLaTeX(image: NSImage, prompt: String? = nil) async throws -> String {
        let p = prompt ?? UserDefaults.standard.string(forKey: "aiLatexPrompt") ?? AIPrompts.latex
        let reachable = await AgentOllama.isReachable()
        let settings = EmbeddedAISettings.fromUserDefaults(ollamaReachable: reachable)
        return try await EmbeddedAIRouter.toLaTeX(image: image, vlmPrompt: p, settings: settings)
    }

    public static func extractTable(image: NSImage) async throws -> String {
        let reachable = await AgentOllama.isReachable()
        let settings = EmbeddedAISettings.fromUserDefaults(ollamaReachable: reachable)
        return try await EmbeddedAIRouter.extractTable(image: image, settings: settings)
    }

    public static func extractTableAndSaveClip(image: NSImage) async throws -> URL {
        let source = CaptureSourceRecorder.current()
        let reachable = await AgentOllama.isReachable()
        let settings = EmbeddedAISettings.fromUserDefaults(ollamaReachable: reachable)
        let description = try await EmbeddedAIRouter.askAI(image: image, prompt: AIPrompts.figureDescribe, settings: settings)
        let tableMarkdown = try? await EmbeddedAIRouter.extractTable(image: image, settings: settings)
        let csv = tableMarkdown.flatMap(convertMarkdownTableToCSV)
        return try ClipLibrary.save(
            image: image,
            source: source,
            tableMarkdown: tableMarkdown,
            tableCSV: csv,
            notes: description
        )
    }

    static func convertMarkdownTableToCSV(_ markdown: String) -> String? {
        let lines = markdown.split(separator: "\n").map(String.init)
        let rows = lines.filter { $0.contains("|") }
        guard !rows.isEmpty else { return nil }
        var parsedRows = rows.map { row in
            var fields = row.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if fields.first?.isEmpty == true { fields.removeFirst() }
            if fields.last?.isEmpty == true { fields.removeLast() }
            return fields.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if parsedRows.count > 1,
           parsedRows[1].count == parsedRows[0].count,
           parsedRows[1].allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) {
            parsedRows.remove(at: 1)
        }
        return CSVEncoder.encode(parsedRows)
    }
}

/// Applies redaction boxes by drawing solid black fills (agent-friendly; no pixelate shader).
/// Keeps the source's pixel resolution. Candidate rects use a top-left origin, like the detector.
public enum RedactionCompositor {
    public static func apply(_ candidates: [RedactionCandidate], to image: NSImage) throws -> NSImage {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.captureFailed("Unable to decode image for redaction")
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard candidates.allSatisfy({ candidate in
            let rect = candidate.rect
            return [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
                && rect.size.width > 0 && rect.size.height > 0
        }) else { throw CaptureError.captureFailed("Invalid redaction rectangle") }
        guard let context = CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CaptureError.captureFailed("Unable to allocate redaction context") }

        let scaleX = CGFloat(source.width) / size.width
        let scaleY = CGFloat(source.height) / size.height
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for candidate in candidates {
            // CGContext has a bottom-left origin, so flip each top-left rect.
            let rect = candidate.rect
            context.fill(CGRect(
                x: rect.minX * scaleX,
                y: (size.height - rect.maxY) * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            ))
        }
        guard let output = context.makeImage() else { throw CaptureError.captureFailed("Unable to render redacted image") }
        return NSImage(cgImage: output, size: size)
    }
}
