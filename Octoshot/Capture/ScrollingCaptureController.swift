import AppKit
import OctoshotCore

@MainActor
final class ScrollingCaptureController {
    static let shared = ScrollingCaptureController()

    private var region: CGRect = .zero
    private var frames: [NSImage] = []
    private var panel: NSPanel?
    private var scrollMonitor: Any?
    private var autoScrollTimer: Timer?

    func start(region: CGRect) {
        self.region = region
        frames = []
        Task {
            if let first = try? await ScreenCaptureService.shared.captureRegion(globalRect: region, showsCursor: AppSettings.shared.captureShowCursor) {
                frames.append(first)
                showPanel()
                installMonitors()
                if AppSettings.shared.scrollCaptureAutoScroll {
                    startAutoScroll()
                }
            }
        }
    }

    private func showPanel() {
        let view = ScrollCapturePanelView(
            frameCount: { [weak self] in self?.frames.count ?? 0 },
            preview: { [weak self] in self?.frames.last },
            onDone: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        )
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(contentViewController: hosting)
        panel.title = "Scrolling Capture"
        panel.styleMask = [.titled, .closable, .nonactivatingPanel]
        FullScreenOverlaySupport.configureFloatingOverlayPanel(panel)
        panel.setContentSize(NSSize(width: 360, height: 200))
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    private func installMonitors() {
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] _ in
            Task { @MainActor in await self?.captureFrame() }
        }
    }

    private func startAutoScroll() {
        guard AXIsProcessTrusted() else {
            let alert = NSAlert()
            alert.messageText = "Accessibility permission needed"
            alert.informativeText = "Auto-scroll needs Accessibility access to post scroll events. Enable Octoshot in Privacy & Security → Accessibility, or scroll manually."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard let self else { return }
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0)
            event?.post(tap: .cghidEventTap)
            Task { @MainActor in await self.captureFrame() }
        }
    }

    private func captureFrame() async {
        guard let image = try? await ScreenCaptureService.shared.captureRegion(globalRect: region, showsCursor: AppSettings.shared.captureShowCursor) else { return }
        if let last = frames.last, imagesSimilar(last, image) { return }
        frames.append(image)
    }

    private func imagesSimilar(_ a: NSImage, _ b: NSImage) -> Bool {
        a.size == b.size && a.tiffRepresentation == b.tiffRepresentation
    }

    private func finish() {
        let stitched = ScrollStitcher.stitch(frames: frames)
        teardown()
        guard let stitched else { return }
        CaptureCoordinator.shared.presentCapturedImage(stitched, captureAnchor: CGPoint(x: region.midX, y: region.midY))
    }

    private func cancel() {
        teardown()
    }

    private func teardown() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        panel?.orderOut(nil)
        panel = nil
        frames = []
    }
}

import SwiftUI

private struct ScrollCapturePanelView: View {
    let frameCount: () -> Int
    let preview: () -> NSImage?
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scroll the content behind this panel, then click Done.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Frames: \(frameCount())")
                .monospacedDigit()
            if let img = preview() {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
