import AppKit
import ScreenCaptureKit

public enum CaptureError: LocalizedError {
    case noDisplays
    case noWindows
    case captureFailed(String)
    case emptySelection

    public var errorDescription: String? {
        switch self {
        case .noDisplays: return "No displays available for capture."
        case .noWindows: return "No on-screen windows found."
        case .captureFailed(let reason): return "Capture failed: \(reason)"
        case .emptySelection: return "Selection area is too small."
        }
    }
}

public final class ScreenCaptureService {
    public static let shared = ScreenCaptureService()

    /// Window IDs of this process's own floating windows that should still appear in captures
    /// (pinned screenshots). Every other floating window this process owns — capture overlays,
    /// Quick Access, recording controls — is left out. Normal-level windows always stay in.
    public var capturableOwnWindowIDs: @MainActor () -> Set<CGWindowID> = { [] }

    private init() {}

    public func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// The display under the mouse pointer, falling back to the main display.
    public static func displayUnderMouse(in content: SCShareableContent) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return content.displays.first { $0.displayID == screen?.displayID } ?? content.displays.first
    }

    /// A display filter that leaves out Octoshot's own floating UI (see `capturableOwnWindowIDs`).
    /// Excluding by application, rather than by window, also covers windows that were just
    /// ordered out and are no longer listed in `content` but may still be composited.
    public func displayFilter(for display: SCDisplay, content: SCShareableContent) async -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        let keepIDs = await capturableOwnWindowIDs()
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == pid }
        let keep = ownWindows.filter { $0.windowLayer == 0 || keepIDs.contains($0.windowID) }
        guard let ownApp = content.applications.first(where: { $0.processID == pid }) else {
            let drop = ownWindows.filter { window in !keep.contains { $0.windowID == window.windowID } }
            return SCContentFilter(display: display, excludingWindows: drop)
        }
        return SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: keep)
    }

    /// Full-resolution image of one display, in pixels.
    public func captureDisplayImage(
        _ display: SCDisplay,
        content: SCShareableContent,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let scale = screenForDisplayID(display.displayID)?.backingScaleFactor ?? 2.0
        let filter = await displayFilter(for: display, content: content)
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = showsCursor
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Captures `display`, or the display under the mouse when `display` is nil.
    public func captureFullscreen(display: SCDisplay? = nil, showsCursor: Bool = false) async throws -> NSImage {
        let content = try await shareableContent()
        guard let targetDisplay = display ?? Self.displayUnderMouse(in: content) else {
            throw CaptureError.noDisplays
        }
        let cgImage = try await captureDisplayImage(targetDisplay, content: content, showsCursor: showsCursor)
        return NSImage(cgImage: cgImage, size: NSSize(width: targetDisplay.width, height: targetDisplay.height))
    }

    public func captureWindow(_ window: SCWindow, includeShadow: Bool = true, showsCursor: Bool = false) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // With the shadow, the filter's `contentRect` is larger than `window.frame`; size the output
        // from it so the image is not squeezed.
        let config = SCStreamConfiguration()
        config.ignoreShadowsSingleWindow = !includeShadow
        config.showsCursor = showsCursor
        config.captureResolution = .best
        let rect = includeShadow ? filter.contentRect : CGRect(origin: .zero, size: window.frame.size)
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((rect.width * scale).rounded())
        config.height = Int((rect.height * scale).rounded())
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: rect.size)
    }

    public func captureRegion(globalRect: CGRect, showsCursor: Bool = false) async throws -> NSImage {
        guard globalRect.width >= 2, globalRect.height >= 2 else {
            throw CaptureError.emptySelection
        }
        let content = try await shareableContent()
        let screens = NSScreen.screens
        var pieces: [(CGRect, NSImage)] = []

        for screen in screens {
            let intersection = globalRect.intersection(screen.frame)
            if intersection.isNull || intersection.width < 1 || intersection.height < 1 { continue }
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let local = DisplayGeometry.rectInScreenSpace(globalRect: intersection, screen: screen)
            let source = DisplayGeometry.sourceRectForCapture(
                screenLocalBottomLeft: local,
                displayHeight: screen.frame.height
            )
            let scale = screen.backingScaleFactor
            let filter = await displayFilter(for: display, content: content)
            let config = SCStreamConfiguration()
            config.sourceRect = source
            config.width = Int(intersection.width * scale)
            config.height = Int(intersection.height * scale)
            config.showsCursor = showsCursor
            config.captureResolution = .best
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let piece = NSImage(cgImage: cgImage, size: intersection.size)
            let offsetInSelection = CGRect(
                x: intersection.origin.x - globalRect.origin.x,
                y: intersection.origin.y - globalRect.origin.y,
                width: intersection.width,
                height: intersection.height
            )
            pieces.append((offsetInSelection, piece))
        }

        guard !pieces.isEmpty else { throw CaptureError.noDisplays }
        return composite(pieces: pieces, canvasSize: globalRect.size)
    }

    private func composite(pieces: [(CGRect, NSImage)], canvasSize: CGSize) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        for (rect, piece) in pieces {
            let drawRect = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.width,
                height: rect.height
            )
            piece.draw(in: drawRect)
        }
        image.unlockFocus()
        return image
    }

    private func screenForDisplayID(_ displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
