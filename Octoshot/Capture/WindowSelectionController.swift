import AppKit
import ScreenCaptureKit
import OctoshotCore

final class WindowSelectionController {
    var onComplete: ((SCWindow, CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    private var overlayWindows: [WindowOverlayWindow] = []
    private var windows: [SCWindow] = []
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var highlighted: SCWindow?
    private var lastMouseGlobal: NSPoint = NSEvent.mouseLocation

    func begin(windows: [SCWindow], displayID: UInt32? = nil) {
        end()
        self.windows = windows
        lastMouseGlobal = NSEvent.mouseLocation
        for screen in NSScreen.screens where displayID == nil || screen == displayID.flatMap(ScreenCaptureService.screen(for:)) {
            let window = WindowOverlayWindow(screen: screen)
            window.controller = self
            overlayWindows.append(window)
        }
        FullScreenOverlaySupport.presentCaptureOverlays(overlayWindows)

        updateHighlightAtMouse()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved]) { [weak self] event in
            if event.type == .keyDown, event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            if event.type == .mouseMoved {
                self?.noteMouse(NSEvent.mouseLocation)
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.noteMouse(NSEvent.mouseLocation)
        }
    }

    func noteMouse(_ point: NSPoint) {
        lastMouseGlobal = point
        FullScreenOverlaySupport.focusOverlay(at: point, in: overlayWindows)
        updateHighlightAtMouse()
    }

    private func updateHighlightAtMouse() {
        setHighlighted(ShareableWindowFilter.window(at: lastMouseGlobal, in: windows))
    }

    func setHighlighted(_ window: SCWindow?) {
        highlighted = window
        overlayWindows.forEach { $0.contentView?.needsDisplay = true }
    }

    func select(_ window: SCWindow) {
        let anchor = lastMouseGlobal
        end()
        onComplete?(window, anchor)
    }

    func cancel() {
        end()
        onCancel?()
    }

    func highlightedWindow() -> SCWindow? { highlighted }

    func windowAtMouse() -> SCWindow? {
        ShareableWindowFilter.window(at: lastMouseGlobal, in: windows)
    }

    private func end() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMonitor = nil
        globalKeyMonitor = nil
        globalMouseMonitor = nil
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        highlighted = nil
    }
}

final class WindowOverlayWindow: NSPanel {
    weak var controller: WindowSelectionController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        FullScreenOverlaySupport.configureCaptureOverlayPanel(self)
        contentView = WindowOverlayView()
        (contentView as? WindowOverlayView)?.overlayWindow = self
    }
}

final class WindowOverlayView: NSView {
    weak var overlayWindow: WindowOverlayWindow?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        guard let controller = overlayWindow?.controller,
              let window = controller.highlightedWindow(),
              let screen = overlayWindow?.screen else { return }

        let cocoa = DisplayGeometry.cocoaRect(fromTopLeftFrame: window.frame)
        let local = DisplayGeometry.flippedLocalRect(cocoaGlobal: cocoa, screen: screen)

        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: local, xRadius: 8, yRadius: 8).fill()

        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(roundedRect: local, xRadius: 8, yRadius: 8)
        border.lineWidth = 3
        border.stroke()

        let title = ShareableWindowFilter.displayLabel(for: window)
        drawTitle(title, above: local)
    }

    override func mouseMoved(with event: NSEvent) {
        overlayWindow?.controller?.noteMouse(NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if let scWindow = overlayWindow?.controller?.windowAtMouse() {
            overlayWindow?.controller?.select(scWindow)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        overlayWindow?.controller?.cancel()
    }

    private func drawTitle(_ title: String, above rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let bgRect = CGRect(
            x: rect.minX,
            y: max(4, rect.minY - size.height - 10),
            width: min(size.width + 14, bounds.width - rect.minX - 4),
            height: size.height + 8
        )
        let bg = NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6)
        NSColor.systemBlue.withAlphaComponent(0.92).setFill()
        bg.fill()
        (title as NSString).draw(in: bgRect.insetBy(dx: 7, dy: 4), withAttributes: attributes)
    }
}
