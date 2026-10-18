import CoreGraphics
import XCTest
@testable import OctoshotCore

final class QuickAccessV3LayoutTests: XCTestCase {
    private let sizes = [CGSize(width: 240, height: 72), CGSize(width: 540 / 7, height: 180),
                         CGSize(width: 240, height: 160)]

    func testBelowHoverOpensToolbarHeightPlusSpacing() {
        for placement in QuickAccessPlacement.allCases {
            let resting = QuickAccessLayout.frames(sizes: sizes, expanded: true, placement: placement)
            for hovered in sizes.indices {
                let cards = QuickAccessLayout.hoverFrames(sizes: sizes, expanded: true, placement: placement,
                    hoveredIndex: hovered, style: .below)
                let toolbar = QuickAccessLayout.belowToolbarFrame(for: cards[hovered], placement: placement)
                XCTAssertEqual(resting[hovered].minY - cards[hovered].minY, toolbar.height + 6, accuracy: 0.001)
                for index in sizes.indices {
                    XCTAssertEqual(cards[index].minY, resting[index].minY - (index >= hovered ? 42 : 0), accuracy: 0.001)
                    if index != hovered { XCTAssertFalse(toolbar.intersects(cards[index])) }
                }
                if hovered > 0 {
                    XCTAssertEqual(cards[hovered - 1].minY - cards[hovered].maxY,
                                   QuickAccessLayout.gap + toolbar.height + 6, accuracy: 0.001)
                }
            }
        }
    }

    func testBubbleHoverNeverIntersectsAnotherCardOrBubble() {
        for placement in QuickAccessPlacement.allCases {
            for expanded in [false, true] {
                for hovered in (expanded ? Array(sizes.indices) : [0]) {
                    let cards = QuickAccessLayout.hoverFrames(sizes: sizes, expanded: expanded, placement: placement,
                        hoveredIndex: hovered, style: .bubbles)
                    let bubbles = QuickAccessLayout.toolbarRects(for: cards[hovered], style: .bubbles, placement: placement)
                    for bubbleIndex in bubbles.indices {
                        for (index, card) in cards.enumerated() where expanded || index == hovered {
                            XCTAssertFalse(bubbles[bubbleIndex].intersects(card))
                        }
                        for other in bubbles.indices where other != bubbleIndex {
                            XCTAssertFalse(bubbles[bubbleIndex].intersects(bubbles[other]))
                        }
                    }
                }
            }
        }
        for size in [CGSize(width: 1, height: 1), CGSize(width: 1, height: 180), CGSize(width: 240, height: 1)] {
            let bubbles = QuickAccessLayout.toolbarRects(for: CGRect(origin: .zero, size: size),
                style: .bubbles, placement: .bottomRight)
            for index in bubbles.indices {
                for other in bubbles.indices where index != other { XCTAssertFalse(bubbles[index].intersects(bubbles[other])) }
            }
        }
    }

    func testCollapsedPresentedFramesAreUnchangedByHover() {
        for placement in QuickAccessPlacement.allCases {
            for style in QuickAccessToolbarStyle.allCases {
                for cards in [sizes, [sizes[0]], Array(repeating: sizes[2], count: 6)] {
                    let reserved = QuickAccessLayout.reservedContentSize(sizes: cards, expanded: false,
                        placement: placement, style: style)
                    let resting = QuickAccessLayout.presentedFrames(sizes: cards, placement: placement,
                        progress: 0, canvasHeight: reserved.height, hoveredIndex: nil, style: style)
                    for hovered in cards.indices {
                        XCTAssertEqual(QuickAccessLayout.presentedFrames(sizes: cards, placement: placement,
                            progress: 0, canvasHeight: reserved.height, hoveredIndex: hovered, style: style), resting)
                        XCTAssertEqual(QuickAccessLayout.hoverFrames(sizes: cards, expanded: false,
                            placement: placement, hoveredIndex: hovered, style: style),
                            QuickAccessLayout.frames(sizes: cards, expanded: false, placement: placement))
                    }
                }
            }
        }
    }

    func testRestingLayoutIsUnchangedAndReservationContainsEveryHover() {
        for placement in QuickAccessPlacement.allCases {
            for expanded in [false, true] {
                for style in QuickAccessToolbarStyle.allCases {
                    XCTAssertEqual(QuickAccessLayout.hoverFrames(sizes: sizes, expanded: expanded, placement: placement,
                        hoveredIndex: nil, style: style),
                        QuickAccessLayout.frames(sizes: sizes, expanded: expanded, placement: placement))
                    let reserved = QuickAccessLayout.reservedContentSize(sizes: sizes, expanded: expanded,
                        placement: placement, style: style)
                    let bounds = CGRect(origin: .zero, size: reserved)
                    for hovered in (expanded ? Array(sizes.indices) : [0]) {
                        let cards = QuickAccessLayout.presentedFrames(sizes: sizes, placement: placement,
                            progress: expanded ? 1 : 0, canvasHeight: reserved.height,
                            hoveredIndex: hovered, style: style)
                        let visible = Array(cards.prefix(expanded ? cards.count : QuickAccessStackGeometry.maxCollapsedLayers))
                        let rects = visible + QuickAccessLayout.toolbarRects(for: cards[hovered], style: style, placement: placement)
                        for rect in rects { XCTAssertTrue(bounds.contains(rect), "\(style) \(expanded) \(hovered): \(rect) outside \(bounds)") }
                        let extent = rects.reduce(CGRect.null) { $0.union($1) }
                        XCTAssertGreaterThanOrEqual(reserved.height + 0.001,
                            extent.height + QuickAccessLayout.padding * 2 + QuickAccessLayout.headerHeight)
                    }
                }
            }
        }
    }

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
