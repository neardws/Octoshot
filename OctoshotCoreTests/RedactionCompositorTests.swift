import AppKit
import XCTest
@testable import OctoshotCore

final class RedactionCompositorTests: XCTestCase {
    /// White image, 200×100 pt at 2× (400×200 px).
    private func whiteImage() -> NSImage {
        let context = CGContext(
            data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 200, height: 100))
    }

    /// Brightness at a pixel, counting rows from the top.
    private func brightness(_ image: NSImage, x: Int, yFromTop: Int) -> CGFloat {
        let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        return rep.colorAt(x: x, y: yFromTop)!.usingColorSpace(.deviceRGB)!.brightnessComponent
    }

    func testFillsRectMeasuredFromTopLeft() {
        let candidate = RedactionCandidate(rect: CGRect(x: 0, y: 0, width: 50, height: 25), kind: .email, detail: "")

        let output = RedactionCompositor.apply([candidate], to: whiteImage())

        XCTAssertEqual(brightness(output, x: 10, yFromTop: 10), 0, accuracy: 0.01, "top-left corner is redacted")
        XCTAssertEqual(brightness(output, x: 10, yFromTop: 190), 1, accuracy: 0.01, "bottom-left corner is untouched")
        XCTAssertEqual(brightness(output, x: 110, yFromTop: 10), 1, accuracy: 0.01, "outside the rect is untouched")
    }

    func testKeepsPixelResolution() {
        let output = RedactionCompositor.apply([], to: whiteImage())
        let cg = output.cgImage(forProposedRect: nil, context: nil, hints: nil)!

        XCTAssertEqual(output.size, NSSize(width: 200, height: 100))
        XCTAssertEqual(cg.width, 400)
        XCTAssertEqual(cg.height, 200)
    }

    /// Detector and compositor must agree: text at the top of the image gets covered.
    func testDetectedEmailIsCoveredWhereItAppears() async throws {
        let size = NSSize(width: 800, height: 400)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        // AppKit drawing has a bottom-left origin, so y: 340 is near the top edge.
        ("jane.doe@example.com" as NSString).draw(
            at: NSPoint(x: 40, y: 340),
            withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black]
        )
        image.unlockFocus()

        let settings = RedactionSettingsSnapshot(
            redactPhones: false, redactEmails: true, redactNationalIDs: false, redactCreditCards: false,
            redactAPIKeys: false, redactIPAddresses: false, redactFaces: false
        )
        let candidates = try await RedactionDetector.detect(in: image, settings: settings)
        try XCTSkipIf(candidates.isEmpty, "Text recognition found nothing on this machine")

        let output = RedactionCompositor.apply(candidates, to: image)
        let cg = output.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let scale = CGFloat(cg.width) / size.width
        // Middle of the email text, measured from the top: 400 - 340 - ~half the line height.
        let textRow = Int((400 - 340 - 14) * scale)
        let bottomRow = Int(380 * scale)

        XCTAssertLessThan(brightness(output, x: Int(150 * scale), yFromTop: textRow), 0.05, "email is blacked out")
        XCTAssertGreaterThan(brightness(output, x: Int(150 * scale), yFromTop: bottomRow), 0.95, "mirrored area is untouched")
    }
}
