import CoreGraphics
import XCTest
@testable import OctoshotCore

final class DisplayGeometryTests: XCTestCase {
    func testPixelRectFlipsToTopLeftAndAppliesImageScale() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = CGRect(x: 100, y: 800, width: 10, height: 20)

        let pixel = DisplayGeometry.pixelRect(
            cocoaGlobal: rect,
            screenFrame: screen,
            imagePixelSize: CGSize(width: 2880, height: 1800)
        )

        XCTAssertEqual(pixel, CGRect(x: 200, y: 160, width: 20, height: 40))
    }

    func testPixelRectIsRelativeToSecondaryScreenOrigin() {
        // Secondary display to the left of and above the main one.
        let screen = CGRect(x: -1920, y: 900, width: 1920, height: 1080)
        let rect = CGRect(x: -1920, y: 900, width: 1, height: 1)

        let pixel = DisplayGeometry.pixelRect(
            cocoaGlobal: rect,
            screenFrame: screen,
            imagePixelSize: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(pixel, CGRect(x: 0, y: 1079, width: 1, height: 1))
    }

    func testPixelRectReturnsZeroForEmptyScreen() {
        let pixel = DisplayGeometry.pixelRect(
            cocoaGlobal: CGRect(x: 0, y: 0, width: 1, height: 1),
            screenFrame: .zero,
            imagePixelSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(pixel, .zero)
    }
}
