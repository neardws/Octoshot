import AppKit
import OctoshotCore

@MainActor
enum SettingsOpener {
    private static var didInstallCloseObserver = false

    static func installAccessoryRestoreOnClose() {
        guard !didInstallCloseObserver else { return }
        didInstallCloseObserver = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            guard window.title == OctoshotL10n.text("Octoshot Settings") else { return }
            if NSApp.activationPolicy() == .regular {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Opens settings using a dedicated `NSWindowController` (reliable for LSUIElement apps).
    static func open(section: SettingsSection? = nil) {
        if let section {
            NotificationCenter.default.post(name: .octoshotOpenSettingsSection, object: section)
        }
        installAccessoryRestoreOnClose()
        SettingsWindowController.shared.show()
    }
}
