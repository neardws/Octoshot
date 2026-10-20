import AppKit
import ScreenCaptureKit
import OctoshotCore

final class AreaSelectionController: NSResponder {
    var onComplete: ((CGRect, AreaCaptureMode) -> Void)?
    var onCancel: (() -> Void)?

    private(set) var captureMode: AreaCaptureMode = AppSettings.shared.rememberAreaCaptureMode
        ? AppSettings.shared.lastAreaCaptureMode
        : .screenshot

    private var overlayWindows: [AreaOverlayWindow] = []
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private(set) var dragStart: NSPoint?
    private var currentPoint: NSPoint?
    private(set) var lastMouseGlobal: NSPoint = NSEvent.mouseLocation
    private(set) var lastSampledColor: ScreenColorInfo?
    private(set) var colorCopyHint: String?
    /// One still image per display, taken as selection starts, so the loupe and color picker
    /// read the real screen instead of the dimmed overlay drawn on top of it.
    private(set) var frozenFrames: [CGDirectDisplayID: CGImage] = [:]
    private var freezeTask: Task<Void, Never>?
    private var selectionFrame: CGRect?

    func begin(displayID: UInt32? = nil, mode: AreaCaptureMode? = nil) {
        end()
        if let mode { captureMode = mode }
        lastMouseGlobal = NSEvent.mouseLocation
        let screens = NSScreen.screens.filter { displayID == nil || $0.displayID == displayID }
        selectionFrame = displayID == nil ? nil : screens.first?.frame
        for screen in screens {
            let window = AreaOverlayWindow(screen: screen)
            window.controller = self
            overlayWindows.append(window)
        }
        FullScreenOverlaySupport.presentCaptureOverlays(overlayWindows)
        freezeFrames(displayIDs: Set(screens.map(\.displayID)))

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                cancel()
                return nil
            }
            if event.type == .keyDown, AppSettings.shared.developerModeEnabled,
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                copyColorUnderCursor()
                return nil
            }
            if event.type == .keyDown,
               let char = event.charactersIgnoringModifiers,
               let mode = AreaCaptureMode.modeForModeBarKey(char) {
                captureMode = mode
                redrawAll()
                return nil
            }
            if event.type == .mouseMoved || event.type == .leftMouseDragged {
                lastMouseGlobal = NSEvent.mouseLocation
                refreshSampledColorIfNeeded()
                redrawAll()
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 53 {
                cancel()
                return
            }
            if AppSettings.shared.developerModeEnabled,
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                copyColorUnderCursor()
                return
            }
            if let char = event.charactersIgnoringModifiers,
               let mode = AreaCaptureMode.modeForModeBarKey(char) {
                captureMode = mode
                redrawAll()
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            guard let self else { return }
            lastMouseGlobal = NSEvent.mouseLocation
            refreshSampledColorIfNeeded()
            focusWindowUnderMouse()
            redrawAll()
        }
        refreshSampledColorIfNeeded()
        redrawAll()
    }

    /// Captures each display without Octoshot's overlays, the one under the mouse first.
    /// The overlays are already up, so this runs in the background and the loupe appears
    /// once its display's frame arrives.
    private func freezeFrames(displayIDs: Set<UInt32>) {
        freezeTask = Task { @MainActor [weak self] in
            guard let content = try? await ScreenCaptureService.shared.shareableContent() else { return }
            let first = ScreenCaptureService.displayUnderMouse(in: content)?.displayID
            let displays = content.displays.filter { $0.displayID == first }
                + content.displays.filter { $0.displayID != first }
            for display in displays where displayIDs.contains(display.displayID) {
                guard let image = try? await ScreenCaptureService.shared.captureDisplayImage(display, content: content, showsCursor: AppSettings.shared.captureShowCursor),
                      let self, !Task.isCancelled
                else { return }
                self.frozenFrames[display.displayID] = image
                self.refreshSampledColorIfNeeded()
                self.redrawAll()
            }
        }
    }

    /// Frozen frame and frame of the screen containing `point`, if that frame has arrived.
    func frozenFrame(at point: NSPoint) -> (image: CGImage, screenFrame: CGRect)? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let image = frozenFrames[screen.displayID]
        else { return nil }
        return (image, screen.frame)
    }

    func refreshSampledColorIfNeeded() {
        guard AppSettings.shared.developerModeEnabled, let frame = frozenFrame(at: lastMouseGlobal) else {
            lastSampledColor = nil
            return
        }
        lastSampledColor = ScreenColorSampler.sample(at: lastMouseGlobal, screenFrame: frame.screenFrame, in: frame.image)
    }

    func copyColorUnderCursor() {
        guard AppSettings.shared.developerModeEnabled else { return }
        refreshSampledColorIfNeeded()
        guard let color = lastSampledColor else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.pasteboardText, forType: .string)
        colorCopyHint = "Copied \(color.hexRGB)"
        redrawAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.colorCopyHint = nil
            self?.redrawAll()
        }
    }

    func beginDrag(at point: NSPoint) {
        dragStart = point
        currentPoint = point
        redrawAll()
    }

    func updateSelection(start: NSPoint, current: NSPoint) {
        if dragStart == nil { dragStart = start }
        currentPoint = current
        lastMouseGlobal = current
        redrawAll()
    }

    func finishSelection(at point: NSPoint) {
        guard let start = dragStart else {
            cancel()
            return
        }
        var rect = DisplayGeometry.normalizedSelection(from: start, to: point)
        if let selectionFrame { rect = rect.intersection(selectionFrame) }
        end()
        if !rect.isNull, rect.width.isFinite, rect.height.isFinite, rect.width >= 2, rect.height >= 2 {
            if AppSettings.shared.rememberAreaCaptureMode {
                AppSettings.shared.lastAreaCaptureMode = captureMode
            }
            onComplete?(rect, captureMode)
        } else {
            onCancel?()
        }
    }

    func cancel() {
        end()
        onCancel?()
    }

    func selectionRectGlobal() -> CGRect? {
        guard let start = dragStart, let current = currentPoint else { return nil }
        return DisplayGeometry.normalizedSelection(from: start, to: current)
    }

    func isDragging() -> Bool { dragStart != nil && currentPoint != nil }

    func setCaptureMode(_ mode: AreaCaptureMode) {
        captureMode = mode
        redrawAll()
    }

    func noteMousePosition(_ global: NSPoint) {
        lastMouseGlobal = global
        refreshSampledColorIfNeeded()
        redrawAll()
    }

    func redrawAll() {
        overlayWindows.forEach { $0.contentView?.needsDisplay = true }
    }

    private func focusWindowUnderMouse() {
        FullScreenOverlaySupport.focusOverlay(at: NSEvent.mouseLocation, in: overlayWindows)
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
        freezeTask?.cancel()
        freezeTask = nil
        frozenFrames = [:]
        dragStart = nil
        currentPoint = nil
    }
}

final class AreaOverlayWindow: NSPanel {
    weak var controller: AreaSelectionController?

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
        contentView = AreaOverlayView()
        (contentView as? AreaOverlayView)?.overlayWindow = self
    }
}

final class AreaOverlayView: NSView {
    weak var overlayWindow: AreaOverlayWindow?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller = overlayWindow?.controller, let screen = overlayWindow?.screen else { return }
        let mouseGlobal = controller.lastMouseGlobal
        let mouseLocal = DisplayGeometry.flippedLocalPoint(cocoaGlobal: mouseGlobal, screen: screen)
        let mouseOnThisScreen = screen.frame.contains(mouseGlobal)

        if let selection = controller.selectionRectGlobal() {
            let dimPath = NSBezierPath(rect: bounds)
            let hole = DisplayGeometry.flippedLocalRect(cocoaGlobal: selection, screen: screen)
            dimPath.append(NSBezierPath(rect: hole))
            dimPath.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.45).setFill()
            dimPath.fill()

            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(roundedRect: hole, xRadius: 2, yRadius: 2)
            border.lineWidth = 2
            border.stroke()

            let label = "\(Int(selection.width)) × \(Int(selection.height))"
            drawLabel(label, near: labelPoint(for: hole))
            drawModeBar(below: hole, controller: controller)
        } else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            bounds.fill()
        }

        if mouseOnThisScreen {
            drawCrosshair(at: mouseLocal)
            drawCursorLabel(at: mouseLocal, global: mouseGlobal, selection: controller.selectionRectGlobal())
            drawMagnifier(at: mouseLocal, global: mouseGlobal, controller: controller)
            if AppSettings.shared.developerModeEnabled, let hint = controller.colorCopyHint {
                drawLabel(hint, near: NSPoint(x: mouseLocal.x + 16, y: mouseLocal.y - 36))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        overlayWindow?.controller?.beginDrag(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        let global = NSEvent.mouseLocation
        if let start = overlayWindow?.controller?.dragStart {
            overlayWindow?.controller?.updateSelection(start: start, current: global)
        }
    }

    override func mouseUp(with event: NSEvent) {
        overlayWindow?.controller?.finishSelection(at: NSEvent.mouseLocation)
    }

    override func mouseMoved(with event: NSEvent) {
        overlayWindow?.controller?.noteMousePosition(NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        overlayWindow?.controller?.cancel()
    }

    private func drawCrosshair(at point: NSPoint) {
        NSColor.white.withAlphaComponent(0.85).setStroke()
        NSColor.black.withAlphaComponent(0.35).setStroke()

        let paths = [
            (NSPoint(x: point.x, y: 0), NSPoint(x: point.x, y: bounds.height)),
            (NSPoint(x: 0, y: point.y), NSPoint(x: bounds.width, y: point.y))
        ]
        for (start, end) in paths {
            let shadow = NSBezierPath()
            shadow.move(to: start)
            shadow.line(to: end)
            shadow.lineWidth = 1.5
            shadow.stroke()

            let line = NSBezierPath()
            line.move(to: start)
            line.line(to: end)
            line.lineWidth = 1
            NSColor.white.withAlphaComponent(0.9).setStroke()
            line.stroke()
        }
    }

    private func drawCursorLabel(at local: NSPoint, global: NSPoint, selection: CGRect?) {
        let text: String
        if let selection {
            text = "\(Int(selection.width)) × \(Int(selection.height)) px"
        } else {
            text = "x: \(Int(global.x))  y: \(Int(global.y))"
        }
        let offset = NSPoint(x: local.x + 16, y: local.y + 16)
        drawLabel(text, near: offset)
    }

    private func labelPoint(for rect: CGRect) -> NSPoint {
        NSPoint(x: min(rect.maxX + 8, bounds.width - 120), y: max(rect.minY - 28, 8))
    }

    private func drawModeBar(below rect: CGRect, controller: AreaSelectionController) {
        let modes: [AreaCaptureMode] = [.screenshot, .scrolling, .recordVideo, .recordGIF, .formulaLaTeX, .figureTable]
        let labels = modes.map { mode -> String in
            let active = controller.captureMode == mode
            return active ? "[\(mode.modeBarLabel)]" : mode.modeBarLabel
        }
        let text = labels.joined(separator: "  ")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let barWidth = size.width + 20
        let barHeight = size.height + 10
        let x = min(max(rect.minX, 8), bounds.width - barWidth - 8)
        let y = max(rect.minY - barHeight - 8, 8)
        let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
        let bg = NSBezierPath(roundedRect: barRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.78).setFill()
        bg.fill()
        (text as NSString).draw(in: barRect.insetBy(dx: 10, dy: 5), withAttributes: attributes)
    }

    private func drawLabel(_ text: String, near point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(x: point.x, y: point.y, width: size.width + 12, height: size.height + 8)
        let bg = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        bg.fill()
        (text as NSString).draw(in: rect.insetBy(dx: 6, dy: 4), withAttributes: attributes)
    }

    private func drawMagnifier(at local: NSPoint, global: NSPoint, controller: AreaSelectionController) {
        let loupeSize: CGFloat = 96
        let zoom: CGFloat = 6
        let sampleSize = loupeSize / zoom
        guard let frame = controller.frozenFrame(at: global) else { return }

        let sampleGlobal = CGRect(
            x: global.x - sampleSize / 2,
            y: global.y - sampleSize / 2,
            width: sampleSize,
            height: sampleSize
        )
        let imageBounds = CGRect(x: 0, y: 0, width: frame.image.width, height: frame.image.height)
        let pixel = DisplayGeometry.pixelRect(
            cocoaGlobal: sampleGlobal,
            screenFrame: frame.screenFrame,
            imagePixelSize: imageBounds.size
        ).integral
        let visible = pixel.intersection(imageBounds)
        guard !visible.isNull, let crop = frame.image.cropping(to: visible) else { return }

        let loupeOrigin = NSPoint(
            x: min(max(8, local.x + 20), bounds.width - loupeSize - 8),
            y: min(max(8, local.y + 20), bounds.height - loupeSize - 8)
        )
        let loupeRect = CGRect(origin: loupeOrigin, size: CGSize(width: loupeSize, height: loupeSize))
        // Near a screen edge only part of the sample exists; place it where it belongs in the loupe.
        // Both the view (flipped) and the image use a top-left origin.
        let drawRect = CGRect(
            x: loupeRect.minX + (visible.minX - pixel.minX) / pixel.width * loupeRect.width,
            y: loupeRect.minY + (visible.minY - pixel.minY) / pixel.height * loupeRect.height,
            width: visible.width / pixel.width * loupeRect.width,
            height: visible.height / pixel.height * loupeRect.height
        )
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: loupeRect, xRadius: 8, yRadius: 8)
        clip.addClip()
        NSColor.black.setFill()
        loupeRect.fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: crop, size: drawRect.size).draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(roundedRect: loupeRect, xRadius: 8, yRadius: 8)
        border.lineWidth = 2
        border.stroke()

        if AppSettings.shared.developerModeEnabled, let color = controller.lastSampledColor {
            let swatch = CGRect(x: loupeRect.minX + 6, y: loupeRect.maxY - 18, width: 12, height: 12)
            NSColor(
                red: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1
            ).setFill()
            NSBezierPath(ovalIn: swatch).fill()

            let colorLine = "\(color.hexRGB)  \(color.rgbText)"
            let labelY = loupeRect.maxY + 6
            let labelX = min(loupeRect.minX, bounds.width - 220)
            drawLabel(colorLine, near: NSPoint(x: labelX, y: labelY))
            if controller.colorCopyHint == nil {
                drawLabel("Press C to copy", near: NSPoint(x: labelX, y: labelY + 26))
            }
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 0 }
        return CGDirectDisplayID(number.uint32Value)
    }
}
