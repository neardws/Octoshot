import AppKit

public enum DisplayGeometry {
    /// Height of the virtual desktop in AppKit global coordinates (bottom-left origin).
    public static var virtualDesktopHeight: CGFloat {
        NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
    }

    /// ScreenCaptureKit window frames use a top-left origin; AppKit uses bottom-left.
    public static func cocoaRect(fromTopLeftFrame frame: CGRect) -> CGRect {
        let height = virtualDesktopHeight
        return CGRect(
            x: frame.origin.x,
            y: height - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    public static func topLeftPoint(fromCocoaGlobal point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: virtualDesktopHeight - point.y)
    }

    /// View-local rect for an `NSView` with `isFlipped == true` filling a screen-sized overlay.
    public static func flippedLocalRect(cocoaGlobal rect: CGRect, screen: NSScreen) -> CGRect {
        let x = rect.origin.x - screen.frame.origin.x
        let flippedY = screen.frame.maxY - rect.origin.y - rect.height
        return CGRect(x: x, y: flippedY, width: rect.width, height: rect.height)
    }

    public static func flippedLocalPoint(cocoaGlobal point: NSPoint, screen: NSScreen) -> NSPoint {
        let x = point.x - screen.frame.origin.x
        let y = screen.frame.maxY - point.y
        return NSPoint(x: x, y: y)
    }

    /// Converts a rect in AppKit global coordinates (bottom-left origin) to a rect
    /// relative to the given screen's frame, still in bottom-left origin.
    public static func rectInScreenSpace(globalRect: CGRect, screen: NSScreen) -> CGRect {
        let frame = screen.frame
        return CGRect(
            x: globalRect.origin.x - frame.origin.x,
            y: globalRect.origin.y - frame.origin.y,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    /// ScreenCaptureKit `sourceRect` uses top-left origin within the display.
    public static func sourceRectForCapture(screenLocalBottomLeft: CGRect, displayHeight: CGFloat) -> CGRect {
        CGRect(
            x: screenLocalBottomLeft.origin.x,
            y: displayHeight - screenLocalBottomLeft.origin.y - screenLocalBottomLeft.height,
            width: screenLocalBottomLeft.width,
            height: screenLocalBottomLeft.height
        )
    }

    /// Pixel rect (top-left origin) inside a full-display image for a rect in AppKit global
    /// coordinates. The scale comes from the image itself, so it matches what was captured.
    public static func pixelRect(cocoaGlobal rect: CGRect, screenFrame: CGRect, imagePixelSize: CGSize) -> CGRect {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return .zero }
        let scaleX = imagePixelSize.width / screenFrame.width
        let scaleY = imagePixelSize.height / screenFrame.height
        return CGRect(
            x: (rect.minX - screenFrame.minX) * scaleX,
            y: (screenFrame.maxY - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }

    public static func normalizedSelection(from start: NSPoint, to end: NSPoint) -> CGRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let w = abs(end.x - start.x)
        let h = abs(end.y - start.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
