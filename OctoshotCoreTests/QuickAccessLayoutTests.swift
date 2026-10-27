import CoreGraphics
import XCTest
@testable import OctoshotCore

final class QuickAccessLayoutTests: XCTestCase {
    private let primary = QuickAccessScreenInfo(
        displayID: 1,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050)
    )

    private let secondary = QuickAccessScreenInfo(
        displayID: 2,
        frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1050)
    )

    private let card = CGSize(width: 200, height: 150)

    func testAspectFitPreservesEachImageRatioAndAllowsUpscaling() {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 1600, height: 480), CGSize(width: 240, height: 72)),
            (CGSize(width: 600, height: 1400), CGSize(width: 180.0 * 600.0 / 1400.0, height: 180)),
            (CGSize(width: 1200, height: 800), CGSize(width: 240, height: 160)),
            (CGSize(width: 800, height: 800), CGSize(width: 180, height: 180)),
            (CGSize(width: 16, height: 8), CGSize(width: 240, height: 120))
        ]
        for (image, expected) in cases {
            let actual = QuickAccessThumbnailSizing.aspectFit(
                imageSize: image, maxSize: CGSize(width: 240, height: 180)
            )
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.001)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.001)
        }
    }

    func testAspectFitRejectsInvalidSizes() {
        let invalidSizes: [CGSize] = [
            .zero, CGSize(width: 0, height: 100), CGSize(width: -1, height: 100),
            CGSize(width: CGFloat.nan, height: 100), CGSize(width: 100, height: CGFloat.infinity)
        ]
        for invalid in invalidSizes {
            XCTAssertEqual(QuickAccessThumbnailSizing.aspectFit(imageSize: invalid, maxSize: card), .zero)
            XCTAssertEqual(QuickAccessThumbnailSizing.aspectFit(imageSize: card, maxSize: invalid), .zero)
        }
    }

    func testScreenTrackerPinsCaptureUntilNextCaptureOrDisplayRemoval() {
        var tracker = QuickAccessPanelScreenTracker()
        XCTAssertEqual(tracker.screenForNewCapture(
            screens: [primary, secondary], capturePoint: CGPoint(x: 2100, y: 200),
            mousePoint: CGPoint(x: 100, y: 100)
        ), secondary)
        XCTAssertEqual(tracker.displayID, secondary.displayID)
        for _ in 0..<3 {
            XCTAssertEqual(tracker.screenForReposition(screens: [primary, secondary]), secondary)
        }
        XCTAssertEqual(tracker.screenForNewCapture(
            screens: [primary, secondary], capturePoint: CGPoint(x: 100, y: 100),
            mousePoint: CGPoint(x: 2100, y: 200)
        ), primary)
        tracker.screenForNewCapture(
            screens: [primary, secondary], capturePoint: CGPoint(x: 2100, y: 200), mousePoint: nil
        )
        XCTAssertEqual(tracker.screenForReposition(screens: [primary]), primary)
        XCTAssertEqual(tracker.displayID, primary.displayID)
        XCTAssertEqual(tracker.screenForReposition(screens: [secondary, primary]), primary)
        XCTAssertEqual(tracker.screenForNewCapture(
            screens: [primary, secondary], capturePoint: CGPoint(x: 100, y: 100),
            mousePoint: CGPoint(x: 2100, y: 200)
        ), primary)
        XCTAssertNil(tracker.screenForReposition(screens: []))
    }

    func testScreenTrackerUsesMouseOnlyAtCaptureTime() {
        var tracker = QuickAccessPanelScreenTracker()
        XCTAssertEqual(tracker.screenForNewCapture(
            screens: [primary, secondary], capturePoint: nil, mousePoint: CGPoint(x: 2100, y: 200)
        ), secondary)
        XCTAssertEqual(tracker.screenForReposition(screens: [primary, secondary]), secondary)
        XCTAssertEqual(tracker.screenForNewCapture(
            screens: [primary, secondary], capturePoint: nil, mousePoint: nil
        ), primary)
        XCTAssertNil(tracker.screenForNewCapture(screens: [], capturePoint: nil, mousePoint: nil))
    }

    func testQuartzAnchorConversionUsesPrimaryTopNotDesktopTop() {
        let above = QuickAccessScreenInfo(
            displayID: 3, frame: CGRect(x: -600, y: 1080, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -600, y: 1080, width: 1920, height: 1050)
        )
        let point = QuickAccessCaptureCoordinates.appKitPoint(
            fromQuartz: CGPoint(x: -100, y: -200), primaryFrame: primary.frame
        )
        XCTAssertEqual(point, CGPoint(x: -100, y: 1280))
        var tracker = QuickAccessPanelScreenTracker()
        XCTAssertEqual(tracker.screenForNewCapture(
            screens: [primary, above], capturePoint: point, mousePoint: CGPoint(x: 100, y: 100)
        ), above)
        XCTAssertEqual(QuickAccessCaptureCoordinates.appKitPoint(
            fromQuartz: CGPoint(x: 2000, y: 1500), primaryFrame: primary.frame
        ), CGPoint(x: 2000, y: -420))
    }

    func testPanelAnchorRemainsFixedWhenGrowingAndShrinking() {
        for placement in QuickAccessPlacement.allCases {
            for screen in [primary, secondary] {
                var anchors: [CGPoint] = []
                for size in [CGSize(width: 272, height: 200), CGSize(width: 292, height: 800), CGSize(width: 180, height: 120)] {
                    let origin = QuickAccessPanelGeometry.panelOrigin(
                        placement: placement, visibleFrame: screen.visibleFrame, panelSize: size, margin: 16
                    )
                    let rect = CGRect(origin: origin, size: size)
                    XCTAssertTrue(screen.visibleFrame.insetBy(dx: 16, dy: 16).contains(rect))
                    anchors.append(CGPoint(
                        x: placement == .bottomRight || placement == .rightSidebar ? rect.maxX : rect.minX,
                        y: placement.isSidebar ? rect.maxY : rect.minY
                    ))
                }
                XCTAssertEqual(anchors[0], anchors[1])
                XCTAssertEqual(anchors[1], anchors[2])
            }
        }
    }

    func testCollapsedFanBoundsIncludeEachCardsOwnSize() {
        let sizes = [CGSize(width: 240, height: 72), CGSize(width: 77, height: 180), CGSize(width: 240, height: 160)]
        for placement in QuickAccessPlacement.allCases {
            let frames = QuickAccessStackGeometry.collapsedCardFrames(sizes: sizes, placement: placement)
            XCTAssertEqual(frames.map(\.size), sizes)
            let bounds = frames.reduce(CGRect.null) { $0.union($1) }
            XCTAssertEqual(bounds.origin, .zero)
            XCTAssertGreaterThanOrEqual(bounds.height, 180)
        }
        XCTAssertTrue(QuickAccessStackGeometry.collapsedCardFrames(sizes: [], placement: .bottomRight).isEmpty)
    }

    func testScreenSelectionPrefersCapturePoint() {
        let point = CGPoint(x: 2000, y: 500)
        let picked = QuickAccessScreenSelection.selectScreen(
            screens: [primary, secondary],
            capturePoint: point,
            mousePoint: CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(picked?.displayID, 2)
    }

    func testScreenSelectionFallsBackToMouse() {
        let picked = QuickAccessScreenSelection.selectScreen(
            screens: [primary, secondary],
            capturePoint: nil,
            mousePoint: CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(picked?.displayID, 1)
    }

    func testPanelOriginBottomRightUsesVisibleFrame() {
        let size = CGSize(width: 200, height: 120)
        let origin = QuickAccessPanelGeometry.panelOrigin(
            placement: .bottomRight,
            visibleFrame: primary.visibleFrame,
            panelSize: size,
            margin: 16
        )
        XCTAssertEqual(origin.x, 1920 - 16 - 200, accuracy: 0.5)
        XCTAssertEqual(origin.y, 16, accuracy: 0.5)
    }

    func testPanelOriginLeftSidebarTopAligned() {
        let size = CGSize(width: 180, height: 400)
        let origin = QuickAccessPanelGeometry.panelOrigin(
            placement: .leftSidebar,
            visibleFrame: primary.visibleFrame,
            panelSize: size,
            margin: 16
        )
        XCTAssertEqual(origin.x, 16, accuracy: 0.5)
        XCTAssertEqual(origin.y, 1050 - 16 - 400, accuracy: 0.5)
    }

    func testPanelOriginBottomLeft() {
        let size = CGSize(width: 160, height: 100)
        let origin = QuickAccessPanelGeometry.panelOrigin(
            placement: .bottomLeft,
            visibleFrame: primary.visibleFrame,
            panelSize: size,
            margin: 16
        )
        XCTAssertEqual(origin.x, 16, accuracy: 0.5)
        XCTAssertEqual(origin.y, 16, accuracy: 0.5)
    }

    func testClampedPanelOriginKeepsPanelOnScreen() {
        let size = CGSize(width: 400, height: 300)
        let proposed = CGPoint(x: -50, y: -20)
        let clamped = QuickAccessPanelGeometry.clampedPanelOrigin(
            proposedOrigin: proposed,
            visibleFrame: primary.visibleFrame,
            panelSize: size,
            margin: 16
        )
        XCTAssertEqual(clamped.x, 16, accuracy: 0.5)
        XCTAssertEqual(clamped.y, 16, accuracy: 0.5)
    }

    func testLegacyCornerMigration() {
        XCTAssertEqual(QuickAccessPlacement.migrated(fromLegacyRawValue: "topLeft"), .leftSidebar)
        XCTAssertEqual(QuickAccessPlacement.migrated(fromLegacyRawValue: "topRight"), .rightSidebar)
        XCTAssertEqual(QuickAccessPlacement.migrated(fromLegacyRawValue: "bottomRight"), .bottomRight)
        XCTAssertEqual(QuickAccessPlacement.migrated(fromLegacyRawValue: "unknown"), .bottomRight)
    }

    func testCollapsedStackBottomRightAlignsEdgeAndMovesUp() {
        let offset = QuickAccessStackGeometry.collapsedOffset(index: 1, total: 3, placement: .bottomRight)
        XCTAssertEqual(offset.width, 0)
        XCTAssertLessThan(offset.height, 0)
    }

    func testCollapsedStackBottomLeftAlignsEdgeAndMovesUp() {
        let offset = QuickAccessStackGeometry.collapsedOffset(index: 1, total: 3, placement: .bottomLeft)
        XCTAssertEqual(offset.width, 0)
        XCTAssertLessThan(offset.height, 0)
    }

    func testCollapsedStackSidebarAlsoBuildsBottomUp() {
        let left = QuickAccessStackGeometry.collapsedOffset(index: 1, total: 3, placement: .leftSidebar)
        XCTAssertEqual(left.width, 0)
        XCTAssertLessThan(left.height, 0)

        let right = QuickAccessStackGeometry.collapsedOffset(index: 1, total: 3, placement: .rightSidebar)
        XCTAssertEqual(right.width, 0)
        XCTAssertLessThan(right.height, 0)
    }

    func testCollapsedStackOffsetsIncreaseWithDepth() {
        let first = QuickAccessStackGeometry.collapsedOffset(index: 1, total: 4, placement: .bottomRight)
        let second = QuickAccessStackGeometry.collapsedOffset(index: 2, total: 4, placement: .bottomRight)
        XCTAssertEqual(second.width, first.width)
        XCTAssertGreaterThan(abs(second.height), abs(first.height))
    }

    func testCollapsedStackContentSizeGrowsWithStackDepth() {
        let single = QuickAccessStackGeometry.collapsedStackContentSize(
            frontCardSize: card,
            total: 1,
            placement: .bottomRight
        )
        XCTAssertEqual(single, card)

        let triple = QuickAccessStackGeometry.collapsedStackContentSize(
            frontCardSize: card,
            total: 3,
            placement: .bottomRight
        )
        XCTAssertEqual(triple.width, card.width)
        XCTAssertGreaterThan(triple.height, card.height)
    }

    func testCollapsedStackAnchorMatchesPlacement() {
        XCTAssertEqual(
            QuickAccessStackGeometry.collapsedStackAnchor(placement: .bottomRight),
            .bottomTrailing
        )
        XCTAssertEqual(
            QuickAccessStackGeometry.collapsedStackAnchor(placement: .leftSidebar),
            .topLeading
        )
    }

    func testCollapsedZIndexFrontIsHighest() {
        let total = 4
        XCTAssertGreaterThan(
            QuickAccessStackGeometry.collapsedZIndex(index: 0, total: total),
            QuickAccessStackGeometry.collapsedZIndex(index: 2, total: total)
        )
    }

    func testDragOutcomeRemovesOnlyOnSuccessfulDrop() {
        XCTAssertEqual(QuickAccessDragOutcome.fromEndedDragOperation(0), .keep)
        XCTAssertEqual(QuickAccessDragOutcome.fromEndedDragOperation(1), .removeFromStack)
        XCTAssertEqual(QuickAccessDragOutcome.fromEndedDragOperation(4), .removeFromStack)
    }
}
