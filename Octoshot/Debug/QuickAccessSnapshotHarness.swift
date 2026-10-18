#if DEBUG
import AppKit
import CoreText
import SwiftUI
import OctoshotCore

@MainActor
enum QuickAccessSnapshotHarness {
    static func runIfRequested() {
        guard let directory = ProcessInfo.processInfo.environment["OCTOSHOT_QA_SNAPSHOT_DIR"] else { return }
        do {
            let destination = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let actions = QuickAccessActions(
                onCopy: {}, onSave: {}, onAnnotate: {}, onPin: {}, onOCR: {}, onClose: {}
            )
            let entries = [
                QuickAccessEntry(image: try image(size: NSSize(width: 1600, height: 480), label: "WIDE"), actions: actions),
                QuickAccessEntry(image: try image(size: NSSize(width: 600, height: 1400), label: "TALL"), actions: actions),
                QuickAccessEntry(image: try image(size: NSSize(width: 1200, height: 800), label: "3:2"), actions: actions)
            ]
            for expanded in [false, true] {
                let presentation = QuickAccessStackPresentation()
                presentation.syncItemIDs(entries.map { QuickAccessStackItemID($0.id) })
                if expanded { presentation.expand() }
                let view = QuickAccessStackView(
                    entries: entries, stackPresentation: presentation, placement: .bottomRight,
                    maxThumbWidth: 240, maxThumbHeight: 180,
                    animatesAppearance: false,
                    onDismissEntry: { _ in }, onDismissAll: {}, onUserChoseAlternateAction: { _ in },
                    onContentSizeChange: { _ in }, onStackExpandedChange: { _ in }
                )
                .environment(\.quickAccessDragOverlayEnabled, false)
                .padding(24)
                .background(LinearGradient(
                    colors: [Color(red: 0.12, green: 0.2, blue: 0.35), Color(red: 0.4, green: 0.2, blue: 0.48)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let rendered = renderer.cgImage,
                      let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: destination.appendingPathComponent(expanded ? "expanded.png" : "collapsed.png"))
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Quick Access snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func image(size: NSSize, label: String) throws -> NSImage {
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            CGColor(srgbRed: 0.1, green: 0.7, blue: 0.75, alpha: 1),
            CGColor(srgbRed: 0.3, green: 0.2, blue: 0.7, alpha: 1)
        ] as CFArray, locations: [0, 1]) else { throw CocoaError(.fileWriteUnknown) }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica-Bold" as CFString, min(size.width, size.height) * 0.2, nil
            ),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: (size.width - bounds.width) / 2 - bounds.minX,
                                       y: (size.height - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)
        guard let rendered = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        let image = NSImage(size: size)
        image.addRepresentation(NSBitmapImageRep(cgImage: rendered))
        return image
    }
}
#endif
