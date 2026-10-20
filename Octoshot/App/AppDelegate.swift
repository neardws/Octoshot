import AppKit
import OctoshotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Updater.shared
        EmbeddedAIRegistrar.install()
        ScreenCaptureService.shared.capturableOwnWindowIDs = { PinnedScreenshotManager.visibleWindowIDs }
        NSApp.setActivationPolicy(.accessory)
        SettingsOpener.installAccessoryRestoreOnClose()
        setupStatusItem()
        setupHelpMenu()
        applyMenuBarVisibility()
        setupHotkeys()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeysChanged),
            name: .octoshotHotkeysDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuBarVisibilityChanged),
            name: .octoshotMenuBarVisibilityDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMenu),
            name: .octoshotRecentCapturesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingStateChanged),
            name: .octoshotRecordingStateDidChange,
            object: nil
        )

        PermissionManager.installActivationRefresh()
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !OnboardingStore.isComplete {
                OnboardingPresenter.presentIfNeeded()
            } else {
                await PermissionManager.presentInitialGuidanceIfNeeded()
                ScreenshotHotkeyConflictPresenter.presentIfNeeded(origin: .launch)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregisterAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let caller = URLSchemeCaller.current()
        for url in urls {
            AgentURLRouter.handle(url, caller: caller)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemImage()
        rebuildMenu()
    }

    @objc private func rebuildMenu() {
        let settings = AppSettings.shared
        let menu = NSMenu()

        menu.addItem(captureItem("Capture Area", shortcut: settings.hotkeyArea, action: #selector(captureArea)))
        menu.addItem(captureItem("Capture Window", shortcut: settings.hotkeyWindow, action: #selector(captureWindow)))
        menu.addItem(captureItem("Capture Fullscreen", shortcut: settings.hotkeyFullscreen, action: #selector(captureFullscreen)))
        menu.addItem(.separator())

        if ScreenCaptureRecorder.shared.isRecording {
            let stopItem = menuItem("Stop Recording", action: #selector(stopRecording))
            stopItem.attributedTitle = NSAttributedString(
                string: "Stop Recording",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            menu.addItem(stopItem)
        } else {
            menu.addItem(menuItem("Record Fullscreen (Video)", action: #selector(recordFullscreenVideo)))
            menu.addItem(menuItem("Record Fullscreen (GIF)", action: #selector(recordFullscreenGIF)))
        }
        menu.addItem(.separator())

        menu.addItem(menuItem("Capture Formula (LaTeX)…", action: #selector(captureLaTeX)))
        menu.addItem(menuItem("Capture Figure / Table to Clips…", action: #selector(capturePaperClip)))
        menu.addItem(.separator())

        let recents = RecentCapturesStore.recentURLs()
        if !recents.isEmpty {
            let recentMenu = NSMenu()
            for url in recents {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentCapture(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
                recentMenu.addItem(item)
            }
            let recentParent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
            recentParent.submenu = recentMenu
            menu.addItem(recentParent)
        }

        let historyItem = menuItem(OctoshotL10n.historyMenuItem, action: #selector(openScreenshotHistory))
        historyItem.keyEquivalent = "y"
        historyItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(historyItem)

        menu.addItem(menuItem("Open Screenshots Folder", action: #selector(openScreenshotsFolder)))
        menu.addItem(menuItem("Clips Library…", action: #selector(openClipsBrowser)))
        menu.addItem(.separator())

        let settingsItem = menuItem("Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)
        menu.addItem(menuItem("Help…", action: #selector(openHelp)))
        menu.addItem(menuItem(OctoshotL10n.checkForUpdates, action: #selector(checkForUpdates)))

        let versionItem = NSMenuItem(title: "Version \(AppVersion.display)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Octoshot", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func captureItem(_ title: String, shortcut: HotkeyBinding, action: Selector) -> NSMenuItem {
        let shortcutLabel = HotkeyFormatter.displayString(for: shortcut)
        let item = NSMenuItem(title: "\(title)  \(shortcutLabel)", action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }
        if ScreenCaptureRecorder.shared.isRecording {
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
            button.image?.isTemplate = true
            button.contentTintColor = .systemRed
            return
        }
        button.contentTintColor = nil
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Octoshot")
            button.image?.isTemplate = true
        }
    }

    @objc private func handleRecordingStateChanged() {
        updateStatusItemImage()
        rebuildMenu()
    }

    @objc private func recordFullscreenVideo() {
        CaptureCoordinator.shared.startFullscreenRecording(video: true)
    }

    @objc private func recordFullscreenGIF() {
        CaptureCoordinator.shared.startFullscreenRecording(video: false)
    }

    @objc private func stopRecording() {
        CaptureCoordinator.shared.stopRecording()
    }

    private func applyMenuBarVisibility() {
        if AppSettings.shared.showMenuBarIcon {
            statusItem?.isVisible = true
        } else {
            statusItem?.isVisible = false
        }
    }

    private func menuItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func setupHotkeys() {
        hotkeyManager.onHotkey = { [weak self] action in
            switch action {
            case .area: self?.captureArea()
            case .window: self?.captureWindow()
            case .fullscreen: self?.captureFullscreen()
            }
        }
        reregisterHotkeys()
    }

    @objc private func handleHotkeysChanged() {
        reregisterHotkeys()
        rebuildMenu()
    }

    @objc private func handleMenuBarVisibilityChanged() {
        applyMenuBarVisibility()
    }

    @objc private func captureArea() {
        CaptureCoordinator.shared.startAreaCapture()
    }

    @objc private func captureWindow() {
        CaptureCoordinator.shared.startWindowCapture()
    }

    @objc private func captureFullscreen() {
        CaptureCoordinator.shared.startFullscreenCapture()
    }

    @objc private func captureLaTeX() {
        FeatureCoordinator.shared.startLaTeXAreaCapture()
    }

    @objc private func capturePaperClip() {
        FeatureCoordinator.shared.startPaperClipAreaCapture()
    }

    @objc private func openRecentCapture(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openScreenshotsFolder() {
        NSWorkspace.shared.open(AppSettings.shared.saveDirectory)
    }

    @objc private func openClipsBrowser() {
        ClipsBrowserWindowController.shared.show()
    }

    @objc private func openScreenshotHistory() {
        ScreenshotHistoryWindowController.shared.show()
    }

    private func reregisterHotkeys() {
        let settings = AppSettings.shared
        hotkeyManager.registerAll(
            area: settings.hotkeyArea,
            window: settings.hotkeyWindow,
            fullscreen: settings.hotkeyFullscreen
        )
    }

    @objc private func openSettings() {
        SettingsOpener.open()
    }

    @objc private func openHelp() {
        HelpOpener.open()
    }

    @objc private func checkForUpdates() {
        Updater.shared.checkForUpdates()
    }

    private func setupHelpMenu() {
        let helpMenu = NSMenu(title: "Help")
        let item = NSMenuItem(title: "Octoshot Help", action: #selector(openHelp), keyEquivalent: "?")
        item.keyEquivalentModifierMask = .command
        item.target = self
        helpMenu.addItem(item)
        NSApp.helpMenu = helpMenu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
