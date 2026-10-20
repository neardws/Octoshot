import CoreGraphics
import Foundation

/// Where the post-capture quick-access panel is anchored on a display.
public enum QuickAccessPlacement: String, CaseIterable, Identifiable, Codable, Sendable {
    case bottomLeft
    case bottomRight
    case leftSidebar
    case rightSidebar

    public var id: String { rawValue }

    /// Maps legacy `QuickAccessCorner` raw values saved before sidebar placements existed.
    public static func migrated(fromLegacyRawValue raw: String) -> QuickAccessPlacement {
        if let placement = QuickAccessPlacement(rawValue: raw) {
            return placement
        }
        switch raw {
        case "topLeft":
            return .leftSidebar
        case "topRight":
            return .rightSidebar
        case "bottomLeft":
            return .bottomLeft
        default:
            return .bottomRight
        }
    }

    public var isSidebar: Bool {
        switch self {
        case .leftSidebar, .rightSidebar:
            return true
        case .bottomLeft, .bottomRight:
            return false
        }
    }
}

public struct QuickAccessScreenInfo: Sendable, Equatable {
    public let displayID: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(displayID: UInt32, frame: CGRect, visibleFrame: CGRect) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum QuickAccessScreenSelection {
    /// Picks the screen containing `capturePoint`, else `mousePoint`, else the first screen.
    public static func selectScreen(
        screens: [QuickAccessScreenInfo],
        capturePoint: CGPoint?,
        mousePoint: CGPoint?
    ) -> QuickAccessScreenInfo? {
        guard !screens.isEmpty else { return nil }
        if let point = capturePoint, let match = screens.first(where: { $0.frame.contains(point) }) {
            return match
        }
        if let point = mousePoint, let match = screens.first(where: { $0.frame.contains(point) }) {
            return match
        }
        return screens.first
    }
}

public struct QuickAccessPanelScreenTracker: Sendable {
    public private(set) var displayID: UInt32?

    public init() {}

    @discardableResult
    public mutating func screenForNewCapture(
        screens: [QuickAccessScreenInfo],
        capturePoint: CGPoint?,
        mousePoint: CGPoint?
    ) -> QuickAccessScreenInfo? {
        let screen = QuickAccessScreenSelection.selectScreen(
            screens: screens, capturePoint: capturePoint, mousePoint: mousePoint
        )
        displayID = screen?.displayID
        return screen
    }

    public mutating func screenForReposition(screens: [QuickAccessScreenInfo]) -> QuickAccessScreenInfo? {
        let screen = screens.first { $0.displayID == displayID } ?? screens.first
        displayID = screen?.displayID
        return screen
    }
}

public enum QuickAccessThumbnailSizing {
    /// Preserves aspect ratio and allows upscaling small images, matching the original thumbnail behavior.
    public static func aspectFit(imageSize: CGSize, maxSize: CGSize) -> CGSize {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              maxSize.width.isFinite, maxSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              maxSize.width > 0, maxSize.height > 0 else { return .zero }
        let scale = min(maxSize.width / imageSize.width, maxSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

public enum QuickAccessCaptureCoordinates {
    /// Quartz global coordinates reflect around the primary display's top edge, not the desktop union.
    public static func appKitPoint(fromQuartz point: CGPoint, primaryFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryFrame.maxY - point.y)
    }
}

public enum QuickAccessPanelGeometry {
    /// AppKit global origin (bottom-left) for a borderless panel of `panelSize`.
    public static func panelOrigin(
        placement: QuickAccessPlacement,
        visibleFrame: CGRect,
        panelSize: CGSize,
        margin: CGFloat
    ) -> CGPoint {
        let inset = visibleFrame.insetBy(dx: margin, dy: margin)
        let maxX = inset.maxX - panelSize.width
        let maxY = inset.maxY - panelSize.height
        let minX = inset.minX
        let minY = inset.minY

        var origin: CGPoint
        switch placement {
        case .bottomLeft:
            origin = CGPoint(x: minX, y: minY)
        case .bottomRight:
            origin = CGPoint(x: maxX, y: minY)
        case .leftSidebar:
            origin = CGPoint(x: minX, y: maxY)
        case .rightSidebar:
            origin = CGPoint(x: maxX, y: maxY)
        }

        origin.x = min(max(origin.x, minX), maxX)
        origin.y = min(max(origin.y, minY), maxY)
        return origin
    }

    /// Clamps a panel origin so the full `panelSize` rect stays inside `visibleFrame` with `margin`.
    public static func clampedPanelOrigin(
        proposedOrigin: CGPoint,
        visibleFrame: CGRect,
        panelSize: CGSize,
        margin: CGFloat
    ) -> CGPoint {
        let inset = visibleFrame.insetBy(dx: margin, dy: margin)
        let maxX = inset.maxX - panelSize.width
        let maxY = inset.maxY - panelSize.height
        let minX = inset.minX
        let minY = inset.minY
        return CGPoint(
            x: min(max(proposedOrigin.x, minX), maxX),
            y: min(max(proposedOrigin.y, minY), maxY)
        )
    }
}

public enum QuickAccessToolbarStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case below
    case bubbles

    public var id: String { rawValue }
}

public enum QuickAccessLayout {
    public static let gap: CGFloat = 12
    public static let padding: CGFloat = 44
    public static let headerHeight: CGFloat = 32
    public static let bubbleDiameter: CGFloat = 26

    public static func toolbarRects(for rect: CGRect, style: QuickAccessToolbarStyle,
                                    placement: QuickAccessPlacement) -> [CGRect] {
        if style == .below { return [belowToolbarFrame(for: rect, placement: placement)] }
        return [QuickAccessRingGeometry(imageRect: rect).outerBounds]
    }

    public static func hoverFrames(sizes: [CGSize], expanded: Bool, placement: QuickAccessPlacement,
                                   hoveredIndex: Int?, style: QuickAccessToolbarStyle) -> [CGRect] {
        let cards = frames(sizes: sizes, expanded: expanded, placement: placement)
        guard style == .below, expanded, let hoveredIndex, cards.indices.contains(hoveredIndex) else {
            return cards
        }
        let card = cards[hoveredIndex]
        let toolbar = toolbarRects(for: card, style: style, placement: placement)
            .reduce(CGRect.null) { $0.union($1) }
        let shift = toolbar.maxY - card.maxY
        return cards.enumerated().map { index, frame in
            frame.offsetBy(dx: 0, dy: index >= hoveredIndex ? -shift : 0)
        }
    }

    public static func reservedContentSize(sizes: [CGSize], expanded: Bool,
                                          placement: QuickAccessPlacement,
                                          style: QuickAccessToolbarStyle) -> CGSize {
        let base = contentSize(sizes: sizes, expanded: expanded, placement: placement)
        guard style == .below, !sizes.isEmpty else { return base }
        var extraAbove: CGFloat = 0
        var extraBelow: CGFloat = 0
        let original = frames(sizes: sizes, expanded: expanded, placement: placement)
        let visibleCount = expanded ? sizes.count : min(sizes.count, QuickAccessStackGeometry.maxCollapsedLayers)
        for hoveredIndex in (expanded ? Array(sizes.indices) : [0]) {
            let cards = expanded ? hoverFrames(sizes: sizes, expanded: true, placement: placement,
                                              hoveredIndex: hoveredIndex, style: style) : original
            let bounds = (Array(cards.prefix(visibleCount)) +
                toolbarRects(for: cards[hoveredIndex], style: style, placement: placement))
                .reduce(CGRect.null) { $0.union($1) }
            extraAbove = max(extraAbove, original.prefix(visibleCount).map(\.minY).min()! - bounds.minY)
            extraBelow = max(extraBelow, bounds.maxY - original[0].maxY)
        }
        return CGSize(width: base.width, height: base.height + extraAbove + extraBelow)
    }

    public static func presentedFrames(sizes: [CGSize], placement: QuickAccessPlacement,
                                       progress: CGFloat, canvasHeight: CGFloat,
                                       hoveredIndex: Int?, style: QuickAccessToolbarStyle) -> [CGRect] {
        let collapsed = frames(sizes: sizes, expanded: false, placement: placement)
        let expanded = hoverFrames(sizes: sizes, expanded: true, placement: placement,
                                   hoveredIndex: hoveredIndex, style: style)
        let collapsedBase = contentSize(sizes: sizes, expanded: false, placement: placement)
        let expandedBase = contentSize(sizes: sizes, expanded: true, placement: placement)
        guard let front = frames(sizes: sizes, expanded: false, placement: placement).first else { return [] }
        let bottomReserve = style == .below ? belowToolbarFrame(for: front, placement: placement).maxY - front.maxY : 0
        return zip(collapsed, expanded).map { start, end in
            let startY = start.minY + canvasHeight - collapsedBase.height - bottomReserve
            let endY = end.minY + canvasHeight - expandedBase.height - bottomReserve
            return CGRect(x: start.minX + (end.minX - start.minX) * progress,
                          y: startY + (endY - startY) * progress,
                          width: start.width + (end.width - start.width) * progress,
                          height: start.height + (end.height - start.height) * progress)
        }
    }

    public static func frames(sizes: [CGSize], expanded: Bool, placement: QuickAccessPlacement) -> [CGRect] {
        guard let front = sizes.first else { return [] }
        let width = max(196, sizes.map(\.width).max() ?? 0)
        let trailing = placement == .bottomRight || placement == .rightSidebar
        var bottom: CGFloat = 0
        let rawFrames = sizes.enumerated().map { index, size in
            let depth = min(index, QuickAccessStackGeometry.maxCollapsedLayers - 1)
            let fitBehindFront = min(1, min(front.width / size.width, front.height / size.height))
            let scale = expanded ? 1 : fitBehindFront * (1 - CGFloat(depth) * 0.025)
            let cardSize = CGSize(width: size.width * scale, height: size.height * scale)
            let cardBottom = expanded ? bottom : -CGFloat(depth) * QuickAccessStackGeometry.collapsedStepY
            bottom -= size.height + gap
            return CGRect(x: trailing ? width - cardSize.width : 0,
                          y: cardBottom - cardSize.height, width: cardSize.width, height: cardSize.height)
        }
        let visible = expanded ? rawFrames : Array(rawFrames.prefix(QuickAccessStackGeometry.maxCollapsedLayers))
        let height = max(front.height, -(visible.map(\.minY).min() ?? 0))
        return rawFrames.map { $0.offsetBy(dx: padding, dy: height + padding + headerHeight) }
    }

    public static func contentSize(sizes: [CGSize], expanded: Bool, placement: QuickAccessPlacement) -> CGSize {
        guard !sizes.isEmpty else { return .zero }
        let cards = frames(sizes: sizes, expanded: expanded, placement: placement)
        let visible = expanded ? cards : Array(cards.prefix(QuickAccessStackGeometry.maxCollapsedLayers))
        let bounds = visible.reduce(CGRect.null) { $0.union($1) }
        return CGSize(width: max(196, sizes.map(\.width).max() ?? 0) + padding * 2,
                      height: bounds.height + padding * 2 + headerHeight)
    }

    public static func transitionSize(sizes: [CGSize], placement: QuickAccessPlacement) -> CGSize {
        let collapsed = contentSize(sizes: sizes, expanded: false, placement: placement)
        let expanded = contentSize(sizes: sizes, expanded: true, placement: placement)
        return CGSize(width: max(collapsed.width, expanded.width), height: max(collapsed.height, expanded.height))
    }

    public static func interpolatedFrames(sizes: [CGSize], placement: QuickAccessPlacement,
                                          progress: CGFloat, canvasHeight: CGFloat) -> [CGRect] {
        let collapsed = frames(sizes: sizes, expanded: false, placement: placement)
        let expanded = frames(sizes: sizes, expanded: true, placement: placement)
        let collapsedHeight = contentSize(sizes: sizes, expanded: false, placement: placement).height
        let expandedHeight = contentSize(sizes: sizes, expanded: true, placement: placement).height
        return zip(collapsed, expanded).map { start, end in
            let startY = start.minY + canvasHeight - collapsedHeight
            let endY = end.minY + canvasHeight - expandedHeight
            return CGRect(x: start.minX + (end.minX - start.minX) * progress,
                          y: startY + (endY - startY) * progress,
                          width: start.width + (end.width - start.width) * progress,
                          height: start.height + (end.height - start.height) * progress)
        }
    }

    public static func belowToolbarFrame(for rect: CGRect, placement: QuickAccessPlacement) -> CGRect {
        let trailing = placement == .bottomRight || placement == .rightSidebar
        return CGRect(x: trailing ? rect.maxX - 196 : rect.minX, y: rect.maxY + 6, width: 196, height: 36)
    }

    public static func toolbarContains(_ point: CGPoint, imageRect: CGRect,
                                        style: QuickAccessToolbarStyle, placement: QuickAccessPlacement,
                                        visibleBounds: CGRect? = nil) -> Bool {
        if style == .below {
            return belowToolbarFrame(for: imageRect, placement: placement).insetBy(dx: 0, dy: -6).contains(point)
        }
        let ring = QuickAccessRingGeometry(imageRect: imageRect, visibleBounds: visibleBounds)
        return ring.segment(at: point) != nil
    }

    public static func sampledFrames(sizes: [CGSize], placement: QuickAccessPlacement,
                                     time: CGFloat, canvasHeight: CGFloat) -> [CGRect] {
        sizes.indices.map { index in
            let delay = CGFloat(index) * 0.03
            let progress = springProgress(min(1, max(0, (time * 0.85 - delay) / 0.65)))
            return interpolatedFrames(sizes: sizes, placement: placement, progress: progress,
                                      canvasHeight: canvasHeight)[index]
        }
    }

    public static func springProgress(_ time: CGFloat) -> CGFloat {
        if time <= 0 { return 0 }
        if time >= 1 { return 1 }
        return 1 - exp(-8 * time) * (cos(10 * time) + 0.8 * sin(10 * time))
    }
}

public struct QuickAccessRingGeometry {
    public static let maximumDiameter: CGFloat = 170
    public static let thickness: CGFloat = 36
    public let imageRect: CGRect
    public let outerRadius: CGFloat
    public var innerRadius: CGFloat { max(outerRadius - Self.thickness, outerRadius * 0.3) }
    public let segmentCount = 6
    public var segmentAngle: CGFloat { 2 * .pi / CGFloat(segmentCount) }
    public var outerBounds: CGRect { bounds(radius: outerRadius) }
    public var innerBounds: CGRect { bounds(radius: innerRadius) }

    public init(imageRect: CGRect, visibleBounds: CGRect? = nil) {
        self.imageRect = imageRect
        let desiredRadius = min(max(imageRect.width, imageRect.height), Self.maximumDiameter) / 2
        if let visibleBounds {
            outerRadius = max(0, min(desiredRadius, imageRect.midX - visibleBounds.minX,
                visibleBounds.maxX - imageRect.midX, imageRect.midY - visibleBounds.minY,
                visibleBounds.maxY - imageRect.midY))
        } else {
            outerRadius = max(0, desiredRadius)
        }
    }

    private func bounds(radius: CGFloat) -> CGRect {
        CGRect(x: imageRect.midX - radius, y: imageRect.midY - radius,
               width: radius * 2, height: radius * 2)
    }

    public func centerAngle(for index: Int) -> CGFloat {
        -.pi / 2 + CGFloat(index) * segmentAngle
    }

    public func point(at angle: CGFloat, on bounds: CGRect) -> CGPoint {
        let radius = bounds.width / 2
        return CGPoint(x: bounds.midX + cos(angle) * radius,
                       y: bounds.midY + sin(angle) * radius)
    }

    public func center(for index: Int) -> CGPoint {
        let inner = point(at: centerAngle(for: index), on: innerBounds)
        let outer = point(at: centerAngle(for: index), on: outerBounds)
        return CGPoint(x: (inner.x + outer.x) / 2, y: (inner.y + outer.y) / 2)
    }

    public func segment(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let horizontal = point.x - imageRect.midX
        let vertical = point.y - imageRect.midY
        let distance = hypot(horizontal, vertical)
        guard outerRadius > 0, distance <= outerRadius, distance >= innerRadius else { return nil }
        let angle = atan2(vertical, horizontal) + .pi / 2 + segmentAngle / 2
        let normalized = (angle.truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)
        return min(segmentCount - 1, Int(normalized / segmentAngle))
    }
}

public enum QuickAccessStackGeometry {
    /// Individual card frames in SwiftUI coordinates, normalized to the full heterogeneous fan bounds.
    public static func collapsedCardFrames(sizes: [CGSize], placement: QuickAccessPlacement) -> [CGRect] {
        guard let front = sizes.first else { return [] }
        let trailing = placement == .bottomRight || placement == .rightSidebar
        let frames = sizes.prefix(maxCollapsedLayers).enumerated().map { index, size in
            let offset = collapsedOffset(index: index, total: sizes.count, placement: placement)
            return CGRect(
                x: (trailing ? front.width - size.width : 0) + offset.width,
                y: front.height - size.height + offset.height,
                width: size.width, height: size.height
            )
        }
        let bounds = frames.reduce(CGRect.null) { $0.union($1) }
        return frames.map { $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
    }

    /// Maximum cards drawn in the collapsed stack peek.
    public static let maxCollapsedLayers = 4

    public static let collapsedStepX: CGFloat = 0
    public static let collapsedStepY: CGFloat = 8

    /// Unit fan direction for back cards (into the display) per placement.
    public static func collapsedFanDirection(placement: QuickAccessPlacement) -> (x: CGFloat, y: CGFloat) {
        (0, -1)
    }

    /// Visual offset for a card at `index` (0 = front / newest) when the stack is collapsed.
    /// Offsets are relative to the front card's top-leading corner in the collapsed `ZStack`.
    public static func collapsedOffset(index: Int, total: Int, placement: QuickAccessPlacement) -> CGSize {
        guard total > 1, index > 0 else { return .zero }
        let layer = CGFloat(min(index, min(total, maxCollapsedLayers) - 1))
        let fan = collapsedFanDirection(placement: placement)
        return CGSize(
            width: fan.x * layer * collapsedStepX,
            height: fan.y * layer * collapsedStepY
        )
    }

    /// Z-index ordering: front card highest.
    public static func collapsedZIndex(index: Int, total: Int) -> Double {
        Double(total - index)
    }

    /// Bounding size of the collapsed fan for a uniform front-card size.
    public static func collapsedStackContentSize(
        frontCardSize: CGSize,
        total: Int,
        placement: QuickAccessPlacement
    ) -> CGSize {
        guard total > 1 else { return frontCardSize }
        let layers = min(total, maxCollapsedLayers)
        var minX: CGFloat = 0
        var minY: CGFloat = 0
        var maxX = frontCardSize.width
        var maxY = frontCardSize.height

        if layers > 1 {
            for index in 1..<layers {
                let offset = collapsedOffset(index: index, total: total, placement: placement)
                let rect = CGRect(
                    x: offset.width,
                    y: offset.height,
                    width: frontCardSize.width,
                    height: frontCardSize.height
                )
                minX = min(minX, rect.minX)
                minY = min(minY, rect.minY)
                maxX = max(maxX, rect.maxX)
                maxY = max(maxY, rect.maxY)
            }
        }

        return CGSize(width: maxX - minX, height: maxY - minY)
    }

    /// Pins the front card to the panel anchor when the collapsed fan is placed in a fixed frame.
    public enum CollapsedStackAnchor: Sendable, Equatable {
        case bottomLeading
        case bottomTrailing
        case topLeading
        case topTrailing
    }

    public static func collapsedStackAnchor(placement: QuickAccessPlacement) -> CollapsedStackAnchor {
        switch placement {
        case .bottomLeft:
            return .bottomLeading
        case .bottomRight:
            return .bottomTrailing
        case .leftSidebar:
            return .topLeading
        case .rightSidebar:
            return .topTrailing
        }
    }

    /// Offset for the count badge relative to the front card's top-leading corner.
    public static func stackBadgeOffset(
        frontCardSize: CGSize,
        placement: QuickAccessPlacement
    ) -> CGSize {
        let inset: CGFloat = 8
        switch placement {
        case .bottomLeft, .leftSidebar:
            return CGSize(width: inset, height: inset)
        case .bottomRight, .rightSidebar:
            return CGSize(width: frontCardSize.width - inset, height: inset)
        }
    }
}

/// Whether a dragged quick-access thumbnail should be removed after drop.
public enum QuickAccessDragOutcome: Equatable, Sendable {
    case keep
    case removeFromStack

    /// `operation` is the drag session's ended-at mask (`NSDragOperation`); empty means cancel / drop on source.
    public static func fromEndedDragOperation(_ operation: UInt) -> QuickAccessDragOutcome {
        operation == 0 ? .keep : .removeFromStack
    }
}
