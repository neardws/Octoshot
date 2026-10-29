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

    func testRingDoesNotReserveOrChangeLayouts() {
        for placement in QuickAccessPlacement.allCases {
            for cardSizes in [sizes, [sizes[1]], Array(repeating: CGSize(width: 240, height: 180), count: 4)] {
                for expanded in [false, true] {
                    let base = QuickAccessLayout.contentSize(sizes: cardSizes, expanded: expanded, placement: placement)
                    XCTAssertEqual(QuickAccessLayout.reservedContentSize(sizes: cardSizes, expanded: expanded,
                        placement: placement, style: .bubbles), base)
                    for hovered in cardSizes.indices {
                        XCTAssertEqual(QuickAccessLayout.hoverFrames(sizes: cardSizes, expanded: expanded,
                            placement: placement, hoveredIndex: hovered, style: .bubbles),
                            QuickAccessLayout.frames(sizes: cardSizes, expanded: expanded, placement: placement))
                        for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
                            XCTAssertEqual(QuickAccessLayout.presentedFrames(sizes: cardSizes, placement: placement,
                                progress: progress, canvasHeight: base.height, hoveredIndex: hovered, style: .bubbles),
                                QuickAccessLayout.interpolatedFrames(sizes: cardSizes, placement: placement,
                                    progress: progress, canvasHeight: base.height))
                        }
                    }
                }
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
                        let toolbar = style == .bubbles ?
                            [QuickAccessRingGeometry(imageRect: cards[hovered], visibleBounds: bounds).outerBounds] :
                            QuickAccessLayout.toolbarRects(for: cards[hovered], style: style, placement: placement)
                        let rects = visible + toolbar
                        for rect in rects { XCTAssertTrue(bounds.contains(rect), "\(style) \(expanded) \(hovered): \(rect) outside \(bounds)") }
                        let extent = rects.reduce(CGRect.null) { $0.union($1) }
                        if style == .below {
                            XCTAssertGreaterThanOrEqual(reserved.height + 0.001,
                                extent.height + QuickAccessLayout.padding * 2 + QuickAccessLayout.headerHeight)
                        }
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

    func testSpringProgressIsMonotonicAndNeverOvershoots() {
        var previous: CGFloat = 0
        for step in 0...10_000 {
            let time = CGFloat(step) / 10_000
            let progress = QuickAccessLayout.springProgress(time)
            XCTAssertGreaterThanOrEqual(progress, 0, "time: \(time)")
            XCTAssertLessThanOrEqual(progress, 1, "time: \(time)")
            XCTAssertGreaterThanOrEqual(progress, previous, "time: \(time)")
            previous = progress
        }
        XCTAssertEqual(QuickAccessLayout.springProgress(-1), 0)
        XCTAssertEqual(QuickAccessLayout.springProgress(2), 1)
    }

    func testRingIsCircularCenteredAndHasSixEqualSlots() {
        for size in sizes + [CGSize(width: 240, height: 180), CGSize(width: 240, height: 1), CGSize(width: 1, height: 180)] {
            let rect = CGRect(origin: CGPoint(x: 44, y: 44), size: size)
            let ring = QuickAccessRingGeometry(imageRect: rect)
            XCTAssertEqual(ring.segmentCount, 6)
            XCTAssertEqual(ring.outerBounds.width, ring.outerBounds.height)
            XCTAssertEqual(ring.innerBounds.width, ring.innerBounds.height)
            XCTAssertEqual(ring.outerBounds.midX, rect.midX)
            XCTAssertEqual(ring.outerBounds.midY, rect.midY)
            XCTAssertEqual(ring.outerBounds.width, min(max(size.width, size.height), 170))
            XCTAssertEqual(ring.outerRadius - ring.innerRadius, 36, accuracy: 0.001)
            XCTAssertNil(ring.segment(at: CGPoint(x: rect.midX, y: rect.midY)))
            for index in 0..<ring.segmentCount {
                let point = ring.center(for: index)
                XCTAssertTrue(ring.outerBounds.contains(point))
                XCTAssertEqual(ring.segment(at: point), index)
                XCTAssertEqual(ring.centerAngle(for: index + 1) - ring.centerAngle(for: index),
                               .pi / 3, accuracy: 0.001)
                XCTAssertEqual(point.x + ring.center(for: (index + 3) % 6).x, rect.midX * 2, accuracy: 0.001)
                XCTAssertEqual(point.y + ring.center(for: (index + 3) % 6).y, rect.midY * 2, accuracy: 0.001)
            }
        }
    }

    func testRingShrinksToVisibleBoundsWithoutMovingItsCenter() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 240)
        for center in [CGPoint(x: 160, y: 140), CGPoint(x: 35, y: 140),
                       CGPoint(x: 290, y: 140), CGPoint(x: 160, y: 40), CGPoint(x: 160, y: 245)] {
            let card = CGRect(x: center.x - 120, y: center.y - 90, width: 240, height: 180)
            let ring = QuickAccessRingGeometry(imageRect: card, visibleBounds: bounds)
            XCTAssertTrue(bounds.contains(ring.outerBounds))
            XCTAssertEqual(ring.outerBounds.midX, center.x)
            XCTAssertEqual(ring.outerBounds.midY, center.y)
            XCTAssertEqual(ring.outerBounds.width, ring.outerBounds.height)
            for index in 0..<6 {
                let point = ring.center(for: index)
                XCTAssertEqual(ring.segment(at: point), index)
                XCTAssertTrue(QuickAccessLayout.toolbarContains(point, imageRect: card,
                    style: .bubbles, placement: .bottomRight, visibleBounds: bounds))
            }
        }
    }

    func testShrunkRingHoverIncludesInnerEdgeOutsideShortCard() {
        let card = CGRect(x: 44, y: 90, width: 240, height: 72)
        let bounds = CGRect(x: 10, y: 10, width: 308, height: 180)
        let ring = QuickAccessRingGeometry(imageRect: card, visibleBounds: bounds)
        let point = CGPoint(x: card.midX, y: card.midY + 40)
        XCTAssertFalse(card.contains(point))
        XCTAssertNotNil(ring.segment(at: point))
        XCTAssertTrue(QuickAccessLayout.toolbarContains(point, imageRect: card, style: .bubbles,
            placement: .bottomRight, visibleBounds: bounds))
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
        let ring = QuickAccessRingGeometry(imageRect: frame)
        for index in 0..<ring.segmentCount {
            let center = ring.center(for: index)
            XCTAssertTrue(QuickAccessLayout.toolbarContains(center, imageRect: frame,
                style: .bubbles, placement: .bottomRight))
        }
        XCTAssertFalse(QuickAccessLayout.toolbarContains(CGPoint(x: frame.minX - 30, y: frame.minY - 30),
            imageRect: frame, style: .bubbles, placement: .bottomRight))
        XCTAssertFalse(QuickAccessLayout.toolbarContains(CGPoint(x: frame.midX, y: frame.midY),
            imageRect: frame, style: .bubbles, placement: .bottomRight))
    }

    func testRingHitTestingAcrossEverySegmentAndSeam() {
        let ring = QuickAccessRingGeometry(imageRect: CGRect(x: 44, y: 76, width: 240, height: 180))
        for index in 0..<ring.segmentCount {
            for fraction in [-0.499, -0.25, 0, 0.25, 0.499] {
                let angle = ring.centerAngle(for: index) + fraction * ring.segmentAngle
                let inner = ring.point(at: angle, on: ring.innerBounds)
                let outer = ring.point(at: angle, on: ring.outerBounds)
                let point = CGPoint(x: (inner.x + outer.x) / 2, y: (inner.y + outer.y) / 2)
                XCTAssertEqual(ring.segment(at: point), index)
            }
        }
        XCTAssertNil(ring.segment(at: CGPoint(x: ring.outerBounds.maxX + 1, y: ring.outerBounds.midY)))
        XCTAssertNil(ring.segment(at: CGPoint(x: CGFloat.infinity, y: 0)))
    }
}
