import CoreGraphics
import XCTest
@testable import OctoshotCore

final class QuickAccessV3LayoutTests: XCTestCase {
    private let sizes = [CGSize(width: 240, height: 72), CGSize(width: 540 / 7, height: 180),
                         CGSize(width: 240, height: 160)]

    func testExpandedOrderAndTwelvePointGapsForEveryPlacement() {
        for placement in QuickAccessPlacement.allCases {
            let frames = QuickAccessLayout.frames(sizes: sizes, expanded: true, placement: placement)
            XCTAssertEqual(frames.map(\.size), sizes)
            for index in 1..<frames.count {
                XCTAssertEqual(frames[index - 1].minY - frames[index].maxY, 12, accuracy: 0.001)
                XCTAssertLessThan(frames[index].minY, frames[index - 1].minY)
            }
            for frame in frames {
                if placement == .bottomRight || placement == .rightSidebar {
                    XCTAssertEqual(frame.maxX, frames[0].maxX, accuracy: 0.001)
                } else {
                    XCTAssertEqual(frame.minX, frames[0].minX, accuracy: 0.001)
                }
            }
        }
    }

    func testCollapsedDepthScaleEdgeAndLayerCap() {
        let uniform = Array(repeating: CGSize(width: 240, height: 180), count: 6)
        for placement in QuickAccessPlacement.allCases {
            let frames = QuickAccessLayout.frames(sizes: uniform, expanded: false, placement: placement)
            for index in 0..<frames.count {
                let depth = min(index, 3)
                XCTAssertEqual(frames[0].maxY - frames[index].maxY, CGFloat(depth) * 8, accuracy: 0.001)
                XCTAssertEqual(frames[index].width, 240 * (1 - CGFloat(depth) * 0.025), accuracy: 0.001)
                if placement == .bottomRight || placement == .rightSidebar {
                    XCTAssertEqual(frames[index].maxX, frames[0].maxX, accuracy: 0.001)
                } else {
                    XCTAssertEqual(frames[index].minX, frames[0].minX, accuracy: 0.001)
                }
            }
            XCTAssertEqual(frames[3], frames[4])
            XCTAssertEqual(frames[4], frames[5])
            XCTAssertEqual(QuickAccessLayout.contentSize(sizes: uniform, expanded: false, placement: placement),
                           QuickAccessLayout.contentSize(sizes: Array(uniform.prefix(4)), expanded: false, placement: placement))
        }
    }

    func testHeterogeneousBackCardsFitBehindFrontWithoutChangingAspectRatio() {
        let frames = QuickAccessLayout.frames(sizes: sizes, expanded: false, placement: .bottomRight)
        for index in frames.indices {
            XCTAssertLessThanOrEqual(frames[index].width, frames[0].width)
            XCTAssertLessThanOrEqual(frames[index].height, frames[0].height)
            XCTAssertEqual(frames[index].width / frames[index].height,
                           sizes[index].width / sizes[index].height, accuracy: 0.001)
            if index > 0 {
                XCTAssertLessThan(frames[index].minY, frames[index - 1].minY)
            }
        }
        XCTAssertLessThan(QuickAccessLayout.contentSize(sizes: sizes, expanded: false,
                                                       placement: .bottomRight).height, 220)
    }

    func testContentSizesAndEmptyLayouts() {
        let expanded = QuickAccessLayout.contentSize(sizes: sizes, expanded: true, placement: .bottomRight)
        XCTAssertEqual(expanded.width, 328)
        XCTAssertEqual(expanded.height, 72 + 180 + 160 + 24 + 88 + 32)
        XCTAssertEqual(QuickAccessLayout.contentSize(sizes: [], expanded: true, placement: .bottomLeft), .zero)
        XCTAssertTrue(QuickAccessLayout.frames(sizes: [], expanded: false, placement: .bottomLeft).isEmpty)
        for isExpanded in [false, true] {
            let size = QuickAccessLayout.contentSize(sizes: sizes, expanded: isExpanded, placement: .bottomRight)
            let bounds = CGRect(origin: .zero, size: size)
            for frame in QuickAccessLayout.frames(sizes: sizes, expanded: isExpanded, placement: .bottomRight) {
                XCTAssertTrue(bounds.contains(frame))
                XCTAssertEqual(size.height - frame.maxY, QuickAccessLayout.padding +
                    (QuickAccessLayout.frames(sizes: sizes, expanded: isExpanded, placement: .bottomRight)[0].maxY - frame.maxY),
                    accuracy: 0.001)
            }
        }
    }

    func testInterpolationKeepsFrontBottomFixedAndFitsUnionThroughoutSpring() {
        let size = QuickAccessLayout.transitionSize(sizes: sizes, placement: .bottomRight)
        let bounds = CGRect(origin: .zero, size: size)
        let bottom = size.height - QuickAccessLayout.padding
        for step in 0...100 {
            let frames = QuickAccessLayout.sampledFrames(sizes: sizes, placement: .bottomRight,
                                                        time: CGFloat(step) / 100, canvasHeight: size.height)
            XCTAssertEqual(frames[0].maxY, bottom, accuracy: 0.001)
            for frame in frames { XCTAssertTrue(bounds.contains(frame)) }
        }
        let start = QuickAccessLayout.sampledFrames(sizes: sizes, placement: .bottomRight, time: 0, canvasHeight: size.height)
        let finish = QuickAccessLayout.sampledFrames(sizes: sizes, placement: .bottomRight, time: 1, canvasHeight: size.height)
        XCTAssertEqual(start, QuickAccessLayout.interpolatedFrames(sizes: sizes, placement: .bottomRight, progress: 0, canvasHeight: size.height))
        XCTAssertEqual(finish, QuickAccessLayout.frames(sizes: sizes, expanded: true, placement: .bottomRight))
        XCTAssertEqual(QuickAccessLayout.springProgress(0), 0)
        XCTAssertEqual(QuickAccessLayout.springProgress(1), 1)
    }

    func testBubbleRingIsSymmetricOutsideImageAndWithinReservedPadding() {
        for size in sizes + [CGSize(width: 240, height: 1), CGSize(width: 1, height: 180)] {
            let rect = CGRect(origin: CGPoint(x: 44, y: 44), size: size)
            let positions = QuickAccessLayout.bubblePositions(around: rect)
            XCTAssertEqual(positions.count, 6)
            for index in positions.indices {
                let point = positions[index]
                let bubble = CGRect(x: point.x - 13, y: point.y - 13, width: 26, height: 26)
                XCTAssertFalse(rect.intersects(bubble))
                XCTAssertTrue(rect.insetBy(dx: -44, dy: -44).contains(bubble))
                XCTAssertEqual(point.x + positions[(index + 3) % 6].x, rect.midX * 2, accuracy: 0.001)
                XCTAssertEqual(point.y + positions[(index + 3) % 6].y, rect.midY * 2, accuracy: 0.001)
            }
        }
        XCTAssertTrue(QuickAccessLayout.bubblePositions(around: .zero, count: 0).isEmpty)
        XCTAssertEqual(QuickAccessLayout.bubblePositions(around: .zero, count: 8).count, 8)
    }

    func testBelowToolbarFitsPanelEvenForTallNarrowCard() {
        for placement in QuickAccessPlacement.allCases {
            for cards in [sizes, [sizes[1]], [CGSize(width: 1, height: 180)]] {
                let size = QuickAccessLayout.contentSize(sizes: cards, expanded: true, placement: placement)
                for frame in QuickAccessLayout.frames(sizes: cards, expanded: true, placement: placement) {
                    let toolbar = QuickAccessLayout.belowToolbarFrame(for: frame, placement: placement)
                    XCTAssertFalse(toolbar.intersects(frame))
                    XCTAssertTrue(CGRect(origin: .zero, size: size).contains(toolbar))
                }
            }
        }
        XCTAssertEqual(QuickAccessToolbarStyle(rawValue: "below"), .below)
        XCTAssertEqual(QuickAccessToolbarStyle(rawValue: "bubbles"), .bubbles)
    }

    func testHoverCanCrossToolbarGapWithoutOwningEmptyRingCorners() {
        let frame = CGRect(x: 44, y: 76, width: 240, height: 160)
        let toolbar = QuickAccessLayout.belowToolbarFrame(for: frame, placement: .bottomRight)
        XCTAssertTrue(QuickAccessLayout.toolbarContains(CGPoint(x: toolbar.midX, y: frame.maxY + 3),
            imageRect: frame, style: .below, placement: .bottomRight))
        for center in QuickAccessLayout.bubblePositions(around: frame) {
            XCTAssertTrue(QuickAccessLayout.toolbarContains(center, imageRect: frame,
                style: .bubbles, placement: .bottomRight))
        }
        XCTAssertFalse(QuickAccessLayout.toolbarContains(CGPoint(x: frame.minX - 30, y: frame.minY - 30),
            imageRect: frame, style: .bubbles, placement: .bottomRight))
        XCTAssertFalse(QuickAccessLayout.toolbarContains(CGPoint(x: frame.midX, y: frame.maxY + 16),
            imageRect: frame, style: .bubbles, placement: .bottomRight))
    }
}
