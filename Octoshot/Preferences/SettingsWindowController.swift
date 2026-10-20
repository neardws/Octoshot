import AppKit
import SwiftUI
import OctoshotCore

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = OctoshotL10n.text("Octoshot Settings")
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .line
        window.center()

        let hosting = NSHostingController(rootView: OctoshotSettingsView())
        window.contentViewController = hosting
        // Keep the window toolbar-free; SwiftUI must not add a toolbar band above the panes.
        window.toolbar = nil

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }

        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        if !window.isVisible {
            showWindow(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
