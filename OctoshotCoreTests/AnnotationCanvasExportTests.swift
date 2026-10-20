import AppKit
import XCTest
@testable import OctoshotCore

@MainActor
final class AnnotationCanvasExportTests: XCTestCase {
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
