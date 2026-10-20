import AppKit
import SwiftUI
import OctoshotCore

/// Borderless always-on-top panel that accepts keyboard focus (Esc to dismiss).
private final class PinnedScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PinnedScreenshotManager {
    static let shared = PinnedScreenshotManager()

    private var controllers: [PinnedScreenshotWindowController] = []
    private var pinOffsetIndex = 0

    private init() {}

    /// Window IDs of visible pins, which stay in captures even though they float above other windows.
    static var visibleWindowIDs: Set<CGWindowID> {
        Set(NSApp.windows.compactMap { $0 as? PinnedScreenshotPanel }
            .filter(\.isVisible)
            .map { CGWindowID($0.windowNumber) })
    }

    func pin(image: NSImage) {
        let controller = PinnedScreenshotWindowController(
            image: image,
            screenIndex: pinOffsetIndex
        )
        pinOffsetIndex = (pinOffsetIndex + 1) % 12
        controller.onDidClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.show()
    }
}

@MainActor
final class PinnedScreenshotWindowController: NSObject, NSWindowDelegate {
    var onDidClose: (() -> Void)?

    private let image: NSImage
    private let screenIndex: Int
    private var panel: PinnedScreenshotPanel?
    private var escapeMonitor: Any?
    private var opacity: Double = 1

    init(image: NSImage, screenIndex: Int) {
        self.image = image
        self.screenIndex = screenIndex
        super.init()
    }

    func show() {
        let screen = screenForMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        let contentSize = Self.displaySize(for: image, on: screen)

        let panel = PinnedScreenshotPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        FullScreenOverlaySupport.configureFloatingOverlayPanel(panel)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let model = PinnedScreenshotModel(opacity: opacity)
        model.onCopy = { [weak self] in self?.copyImage() }
        model.onSave = { [weak self] in self?.saveImage() }
        model.onClose = { [weak self] in self?.close() }
        model.onOpacityChange = { [weak self] value in
            self?.opacity = value
        }
        model.onActivate = { [weak panel] in
            panel?.makeKeyAndOrderFront(nil)
        }

        let root = PinnedScreenshotRootView(image: image, model: model)
        panel.contentView = NSHostingView(rootView: root)

        let origin = Self.initialOrigin(
            size: contentSize,
            screen: screen,
            index: screenIndex
        )
        panel.setFrame(NSRect(origin: origin, size: contentSize), display: false)
        panel.orderFrontRegardless()

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.panel?.isKeyWindow == true else { return event }
            self.close()
            return nil
        }

        self.panel = panel
    }

    func close() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        onDidClose?()
    }

    private func copyImage() {
        ImageExportActions.copy(image)
    }

    private func saveImage() {
        let url = AppSettings.shared.defaultSaveURL(prefix: "Pinned")
        ImageExportActions.perform {
            do {
                let actualURL = try await ImageFormats.writeUniqueAsync(
                    image: self.image,
                    to: url,
                    format: AppSettings.shared.format,
                    jpegQuality: AppSettings.shared.jpegQuality
                )
                RecentCapturesStore.record(url: actualURL)
                NSWorkspace.shared.activateFileViewerSelecting([actualURL])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    private static func displaySize(for image: NSImage, on screen: NSScreen) -> NSSize {
        let frame = screen.visibleFrame
        let maxW = frame.width * 0.65
        let maxH = frame.height * 0.65
        let w = max(image.size.width, 1)
        let h = max(image.size.height, 1)
        let scale = min(1, min(maxW / w, maxH / h))
        return NSSize(width: max(floor(w * scale), 80), height: max(floor(h * scale), 60))
    }

    private static func initialOrigin(size: NSSize, screen: NSScreen, index: Int) -> NSPoint {
        let frame = screen.visibleFrame
        let step: CGFloat = 28
        let offset = CGFloat(index % 12) * step
        let x = frame.midX - size.width / 2 + offset
        let y = frame.midY - size.height / 2 - offset
        let clampedX = min(max(x, frame.minX), frame.maxX - size.width)
        let clampedY = min(max(y, frame.minY), frame.maxY - size.height)
        return NSPoint(x: clampedX, y: clampedY)
    }

    private func screenForMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

@MainActor
final class PinnedScreenshotModel: ObservableObject {
    @Published var opacity: Double
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpacityChange: ((Double) -> Void)?
    var onActivate: (() -> Void)?

    init(opacity: Double) {
        self.opacity = opacity
    }
}

private struct PinnedScreenshotRootView: View {
    let image: NSImage
    @ObservedObject var model: PinnedScreenshotModel
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .opacity(model.opacity)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

            if isHovering {
                VStack(alignment: .trailing, spacing: 8) {
                    controlBar
                    opacityControl
                }
                .padding(10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.onActivate?() }
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            pinButton(symbol: "doc.on.doc", help: "复制 / Copy") { model.onCopy?() }
            pinButton(symbol: "square.and.arrow.down", help: "保存 / Save") { model.onSave?() }
            pinButton(symbol: "xmark", help: "关闭 / Close") { model.onClose?() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var opacityControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 11, weight: .semibold))
            Slider(
                value: Binding(
                    get: { model.opacity },
                    set: { newValue in
                        model.opacity = newValue
                        model.onOpacityChange?(newValue)
                    }
                ),
                in: 0.35...1
            )
            .frame(width: 88)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .help("不透明度 / Opacity")
    }

    private func pinButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
