import CoreGraphics
import Foundation

/// Identifies one capture in the quick-access stack (UI holds images separately).
public struct QuickAccessStackItemID: Hashable, Sendable, Equatable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Expand/collapse and membership for the post-capture quick-access stack.
public struct QuickAccessCaptureStack: Equatable, Sendable {
    public var itemIDs: [QuickAccessStackItemID]
    public var isExpanded: Bool
    public var stackCapturesEnabled: Bool
    public var maxCount: Int

    public init(
        itemIDs: [QuickAccessStackItemID] = [],
        isExpanded: Bool = false,
        stackCapturesEnabled: Bool = true,
        maxCount: Int = 6
    ) {
        self.itemIDs = itemIDs
        self.isExpanded = isExpanded
        self.stackCapturesEnabled = stackCapturesEnabled
        self.maxCount = max(1, maxCount)
    }

    public var count: Int { itemIDs.count }

    public var showsCollapsedStack: Bool {
        stackCapturesEnabled && itemIDs.count > 1 && !isExpanded
    }

    public mutating func prepend(_ id: QuickAccessStackItemID) {
        itemIDs.insert(id, at: 0)
        trimToMax()
    }

    public mutating func trimToMax() {
        guard itemIDs.count > maxCount else { return }
        itemIDs.removeLast(itemIDs.count - maxCount)
    }

    /// Removes one item. Returns `true` when the stack is empty afterward.
    @discardableResult
    public mutating func dismissItem(_ id: QuickAccessStackItemID) -> Bool {
        itemIDs.removeAll { $0 == id }
        if itemIDs.count <= 1 {
            isExpanded = false
        }
        return itemIDs.isEmpty
    }

    public mutating func expand() {
        guard itemIDs.count > 1 else { return }
        isExpanded = true
    }

    public mutating func collapse() {
        isExpanded = false
    }

    public mutating func clear() {
        itemIDs.removeAll()
        isExpanded = false
    }

    public mutating func syncItemIDs(_ ids: [QuickAccessStackItemID]) {
        itemIDs = ids
        if itemIDs.count <= 1 {
            isExpanded = false
        }
    }
}

public enum QuickAccessStackPanelLayout {
    public static let interCardSpacing: CGFloat = 12
    public static let outerPadding: CGFloat = 12
    /// Vertical space for the close-all / collapse row when more than one capture is shown.
    public static let multiCaptureHeaderHeight: CGFloat = 22

    /// Height of the scrollable card column inside the panel (excluding outer padding).
    public static func expandedCardsColumnHeight(cardHeights: [CGFloat]) -> CGFloat {
        guard !cardHeights.isEmpty else { return 0 }
        let cards = cardHeights.reduce(0, +)
        let gaps = interCardSpacing * CGFloat(max(0, cardHeights.count - 1))
        return cards + gaps
    }

    /// Total panel content height for a vertically stacked, expanded presentation.
    public static func expandedPanelContentHeight(
        cardHeights: [CGFloat],
        includesMultiCaptureHeader: Bool
    ) -> CGFloat {
        var height = expandedCardsColumnHeight(cardHeights: cardHeights)
        if includesMultiCaptureHeader, cardHeights.count > 1 {
            height += multiCaptureHeaderHeight + interCardSpacing
        }
        return height + outerPadding * 2
    }

    public static func collapsedPanelContentSize(
        frontCardSize: CGSize,
        total: Int,
        placement: QuickAccessPlacement
    ) -> CGSize {
        let stack = QuickAccessStackGeometry.collapsedStackContentSize(
            frontCardSize: frontCardSize,
            total: total,
            placement: placement
        )
        let header = total > 1 ? multiCaptureHeaderHeight + interCardSpacing : 0
        return CGSize(
            width: stack.width + outerPadding * 2,
            height: stack.height + header + outerPadding * 2
        )
    }
}
