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

public enum QuickAccessStackGeometry {
    /// Individual card frames in SwiftUI coordinates, normalized to the full heterogeneous fan bounds.
    public static func collapsedCardFrames(sizes: [CGSize], placement: QuickAccessPlacement) -> [CGRect] {
        guard let front = sizes.first else { return [] }
        let trailing = placement == .bottomRight || placement == .rightSidebar
        let bottom = !placement.isSidebar
        let frames = sizes.prefix(maxCollapsedLayers).enumerated().map { index, size in
            let offset = collapsedOffset(index: index, total: sizes.count, placement: placement)
            return CGRect(
                x: (trailing ? front.width - size.width : 0) + offset.width,
                y: (bottom ? front.height - size.height : 0) + offset.height,
                width: size.width, height: size.height
            )
        }
        let bounds = frames.reduce(CGRect.null) { $0.union($1) }
        return frames.map { $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
    }

    /// Maximum cards drawn in the collapsed stack peek.
    public static let maxCollapsedLayers = 5

    public static let collapsedStepX: CGFloat = 5
    public static let collapsedStepY: CGFloat = 4

    /// Unit fan direction for back cards (into the display) per placement.
    public static func collapsedFanDirection(placement: QuickAccessPlacement) -> (x: CGFloat, y: CGFloat) {
        switch placement {
        case .bottomRight:
            return (-1, -1)
        case .bottomLeft:
            return (1, -1)
        case .leftSidebar:
            return (1, 1)
        case .rightSidebar:
            return (-1, 1)
        }
    }

    /// Visual offset for a card at `index` (0 = front / newest) when the stack is collapsed.
    /// Offsets are relative to the front card's top-leading corner in the collapsed `ZStack`.
    public static func collapsedOffset(index: Int, total: Int, placement: QuickAccessPlacement) -> CGSize {
        guard total > 1, index > 0 else { return .zero }
        let layer = CGFloat(min(index, maxCollapsedLayers))
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
