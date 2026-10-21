import AppKit
import ImageIO
import XCTest
@testable import OctoshotCore

@MainActor
final class AnnotationCanvasExportTests: XCTestCase {
    private func decode(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func rgba(_ image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: image.colorSpace!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
    }

    func testEditorAndCoreExportsAreEightBitAndMatchLegacyPNG() throws {
        for spaceName in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8,
                bytesPerRow: 256, space: CGColorSpace(name: spaceName)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 32, y: 24, width: 32, height: 24))
            let source = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: CGSize(width: 32, height: 24))
            let stroke = AnnotationStroke(tool: .rectangle, start: CGPoint(x: 4, y: 4),
                end: CGPoint(x: 20, y: 16), text: "", color: .red, lineWidth: 2)
            let spec = try JSONDecoder().decode(AgentAnnotationSpec.self, from: Data(
                "{\"annotations\":[{\"type\":\"rectangle\",\"from\":[4,4],\"to\":[20,16],\"color\":\"#FF0000\",\"lineWidth\":2}]}".utf8))
            for editor in [true, false] {
                let legacyImage = NSImage(size: source.size)
                legacyImage.lockFocusFlipped(editor)
                source.draw(in: CGRect(origin: .zero, size: source.size), from: .zero,
                            operation: editor ? .copy : .sourceOver, fraction: 1, respectFlipped: editor, hints: nil)
                if editor {
                    try AnnotationDrawing.draw(stroke: stroke, in: CGRect(origin: .zero, size: source.size), sourceImage: source)
                } else {
                    NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setStroke()
                    let path = NSBezierPath(rect: CGRect(x: 4, y: 4, width: 16, height: 12))
                    path.lineWidth = 2
                    path.stroke()
                }
                legacyImage.unlockFocus()
                let legacyRep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(legacyImage.tiffRepresentation)))
                let legacyPNG = try decode(XCTUnwrap(legacyRep.representation(using: .png, properties: [:])))
                let output: NSImage
                if editor {
                    let canvas = AnnotationCanvasView(frame: CGRect(origin: .zero, size: source.size))
                    canvas.baseImage = source
                    canvas.strokes = [stroke]
                    output = try XCTUnwrap(canvas.currentImage())
                } else {
                    output = try AnnotationRenderer.apply(spec: spec, to: source)
                }
                let raw = try XCTUnwrap(output.cgImage(forProposedRect: nil, context: nil, hints: nil))
                XCTAssertEqual(raw.bitsPerComponent, 8)
                XCTAssertEqual(raw.bitsPerPixel, 32)
                let snapshot = try ImageFormats.snapshot(output)
                XCTAssertTrue(raw === snapshot.image)
                for format in [ScreenshotFormat.png, .jpeg] {
                    let data = try ImageFormats.encode(snapshot, format: format, jpegQuality: 0.85)
                    let decoded = try decode(data)
                    XCTAssertEqual(decoded.bitsPerComponent, 8)
                    XCTAssertEqual(decoded.width, legacyPNG.width)
                    XCTAssertEqual(decoded.height, legacyPNG.height)
                    XCTAssertEqual(decoded.colorSpace?.copyICCData(), legacyPNG.colorSpace?.copyICCData())
                    XCTAssertEqual(try XCTUnwrap(NSBitmapImageRep(data: data)).size, legacyRep.size)
                    if format == .png {
                        XCTAssertTrue(try XCTUnwrap(NSBitmapImageRep(data: data)).hasAlpha)
                        XCTAssertEqual(decoded.bitmapInfo, legacyPNG.bitmapInfo)
                        XCTAssertEqual(decoded.bytesPerRow, legacyPNG.bytesPerRow)
                        XCTAssertEqual(try XCTUnwrap(decoded.dataProvider?.data),
                                       try XCTUnwrap(legacyPNG.dataProvider?.data))
                        let pixels = try rgba(decoded)
                        XCTAssertEqual(pixels, try rgba(legacyPNG))
                        let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
                        XCTAssertTrue(alpha.contains(0))
                        XCTAssertTrue(alpha.contains { $0 > 0 && $0 < 255 })
                    }
                }
            }
        }
    }

    func testLazySnapshotDrawsOnlyOnMainBeforeAsyncEncoding() async throws {
        var draws = 0
        let image = NSImage(size: CGSize(width: 16, height: 12), flipped: false) { rect in
            XCTAssertTrue(Thread.isMainThread)
            draws += 1
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let snapshot = try ImageFormats.snapshot(image)
        XCTAssertGreaterThan(draws, 0)
        let materializedDraws = draws
        let expected = try rgba(snapshot.image)
        for format in [ScreenshotFormat.png, .jpeg] {
            let data = try await ImageFormats.encodeAsync(snapshot, format: format, jpegQuality: 1)
            XCTAssertEqual(try decode(data).bitsPerComponent, 8)
            XCTAssertEqual(draws, materializedDraws)
            if format == .png { XCTAssertEqual(try rgba(decode(data)), expected) }
        }
        _ = try await Task.detached { try ImageFormats.snapshot(image) }.value
    }

    func testCompositeSnapshotIsImmutableAcrossImageMutation() throws {
        let rect = CGRect(x: 0, y: 0, width: 16, height: 12)
        let image = try ImageFormats.composite(size: rect.size, flipped: false) {
            NSColor.red.setFill()
            rect.fill()
        }
        let before = try ImageFormats.snapshot(image)
        let originalPixels = try rgba(before.image)
        image.lockFocus()
        NSColor.blue.setFill()
        rect.fill()
        image.unlockFocus()
        let after = try ImageFormats.snapshot(image)
        XCTAssertEqual(try rgba(before.image), originalPixels)
        XCTAssertNotEqual(try rgba(after.image), originalPixels)
    }

    func testHighDepthSnapshotMaterializesEightBitWithSourceProfile() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 16,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder16Little.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        let pixels = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(pixels.bitsPerComponent, 16)
        let snapshot = try ImageFormats.snapshot(NSImage(cgImage: pixels, size: CGSize(width: 8, height: 6)))
        XCTAssertEqual(snapshot.image.bitsPerComponent, 8)
        XCTAssertEqual(snapshot.image.colorSpace?.copyICCData(), pixels.colorSpace?.copyICCData())
        let png = try decode(ImageFormats.encode(snapshot, format: .png, jpegQuality: 1))
        XCTAssertEqual(png.bitsPerComponent, 8)
        XCTAssertEqual(try rgba(png), try rgba(pixels))
    }

    private func source() -> NSImage {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 64, height: 64))
    }

    func testFailedCompositeCannotBeExportedAndUndoRecovers() throws {
        let canvas = AnnotationCanvasView()
        canvas.redactionRenderer = RedactionRenderer(render: { _, _ in nil })
        canvas.baseImage = source()
        XCTAssertNotNil(try canvas.currentImage())
        for tool in [AnnotationTool.blur, .pixelate] {
            canvas.strokes = [AnnotationStroke(tool: tool, start: CGPoint(x: 2, y: 2), end: CGPoint(x: 20, y: 20),
                                               text: "", color: .red, lineWidth: 4)]
            XCTAssertThrowsError(try canvas.currentImage())
            canvas.undo()
            XCTAssertNotNil(try canvas.currentImage())
            canvas.redo()
            XCTAssertThrowsError(try canvas.currentImage())
            canvas.strokes = []
        }
        canvas.redactionRegions = [CGRect(x: 2, y: 2, width: 12, height: 12)]
        XCTAssertThrowsError(try canvas.currentImage())
        canvas.baseImage = source()
        XCTAssertThrowsError(try canvas.currentImage())
        canvas.redactionRegions = []
        XCTAssertNotNil(try canvas.currentImage())
    }
}
