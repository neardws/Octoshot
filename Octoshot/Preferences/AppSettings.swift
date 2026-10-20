import AppKit
import Foundation
import OctoshotCore

extension ScreenshotFormat {
    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }
}

extension Notification.Name {
    static let octoshotHotkeysDidChange = Notification.Name("OctoshotHotkeysDidChange")
    static let octoshotMenuBarVisibilityDidChange = Notification.Name("OctoshotMenuBarVisibilityDidChange")
    static let octoshotQuickAccessPlacementDidChange = Notification.Name("OctoshotQuickAccessPlacementDidChange")
}

@MainActor
final class AppSettings: ObservableObject {
    static let defaults: UserDefaults = {
        #if DEBUG
        if OctoshotL10n.isSettingsSnapshot {
            return SettingsSnapshotDefaults()
        }
        #endif
        return .standard
    }()

    static let shared = AppSettings()

    static let defaultFilenamePattern = "{prefix} {date} {time}"
    static let repositoryURL = URL(string: "https://github.com/neardws/Octoshot")!

    private enum Keys {
        static let saveDirectory = "saveDirectory"
        static let format = "screenshotFormat"
        static let corner = "quickAccessCorner"
        static let stackCaptures = "quickAccessStackCaptures"
        static let toolbarStyle = "quickAccessToolbarStyle"
        static let hotkeyArea = "hotkeyArea"
        static let hotkeyWindow = "hotkeyWindow"
        static let hotkeyFullscreen = "hotkeyFullscreen"
        static let jpegQuality = "jpegQuality"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let playCaptureSound = "playCaptureSound"
        static let afterCaptureQuickAccess = "afterCaptureQuickAccess"
        static let afterCaptureCopy = "afterCaptureCopy"
        static let afterCaptureSave = "afterCaptureSave"
        static let filenamePattern = "filenamePattern"
        static let quickAccessAutoClose = "quickAccessAutoCloseSeconds"
        static let captureWindowWithShadow = "captureWindowWithShadow"
        static let captureShowCursor = "captureShowCursor"
        static let developerMode = "developerModeEnabled"
        static let markdownAbsolutePath = "markdownImageUseAbsolutePath"
    }

    @Published var saveDirectory: URL {
        didSet { AppSettings.defaults.set(saveDirectory.path, forKey: Keys.saveDirectory) }
    }

    @Published var format: ScreenshotFormat {
        didSet { AppSettings.defaults.set(format.rawValue, forKey: Keys.format) }
    }

    @Published var quickAccessPlacement: QuickAccessPlacement {
        didSet {
            AppSettings.defaults.set(quickAccessPlacement.rawValue, forKey: Keys.corner)
            NotificationCenter.default.post(name: .octoshotQuickAccessPlacementDidChange, object: nil)
        }
    }

    @Published var quickAccessStackCaptures: Bool {
        didSet { AppSettings.defaults.set(quickAccessStackCaptures, forKey: Keys.stackCaptures) }
    }

    @Published var quickAccessToolbarStyle: QuickAccessToolbarStyle {
        didSet { AppSettings.defaults.set(quickAccessToolbarStyle.rawValue, forKey: Keys.toolbarStyle) }
    }

    @Published var jpegQuality: Double {
        didSet { AppSettings.defaults.set(jpegQuality, forKey: Keys.jpegQuality) }
    }

    @Published var hotkeyArea: HotkeyBinding {
        didSet {
            persistHotkey(hotkeyArea, key: Keys.hotkeyArea)
            NotificationCenter.default.post(name: .octoshotHotkeysDidChange, object: nil)
        }
    }

    @Published var hotkeyWindow: HotkeyBinding {
        didSet {
            persistHotkey(hotkeyWindow, key: Keys.hotkeyWindow)
            NotificationCenter.default.post(name: .octoshotHotkeysDidChange, object: nil)
        }
    }

    @Published var hotkeyFullscreen: HotkeyBinding {
        didSet {
            persistHotkey(hotkeyFullscreen, key: Keys.hotkeyFullscreen)
            NotificationCenter.default.post(name: .octoshotHotkeysDidChange, object: nil)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            AppSettings.defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            if !OctoshotL10n.isSettingsSnapshot {
                LaunchAtLoginManager.setEnabled(launchAtLogin)
            }
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet {
            AppSettings.defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            NotificationCenter.default.post(name: .octoshotMenuBarVisibilityDidChange, object: nil)
        }
    }

    @Published var playCaptureSound: Bool {
        didSet { AppSettings.defaults.set(playCaptureSound, forKey: Keys.playCaptureSound) }
    }

    @Published var afterCaptureShowQuickAccess: Bool {
        didSet { AppSettings.defaults.set(afterCaptureShowQuickAccess, forKey: Keys.afterCaptureQuickAccess) }
    }

    @Published var afterCaptureCopyToClipboard: Bool {
        didSet { AppSettings.defaults.set(afterCaptureCopyToClipboard, forKey: Keys.afterCaptureCopy) }
    }

    @Published var afterCaptureSaveToDisk: Bool {
        didSet { AppSettings.defaults.set(afterCaptureSaveToDisk, forKey: Keys.afterCaptureSave) }
    }

    @Published var filenamePattern: String {
        didSet { AppSettings.defaults.set(filenamePattern, forKey: Keys.filenamePattern) }
    }

    /// Seconds before the quick-access panel auto-closes. `0` disables auto-close.
    @Published var quickAccessAutoCloseSeconds: Double {
        didSet { AppSettings.defaults.set(quickAccessAutoCloseSeconds, forKey: Keys.quickAccessAutoClose) }
    }

    @Published var captureWindowWithShadow: Bool {
        didSet { AppSettings.defaults.set(captureWindowWithShadow, forKey: Keys.captureWindowWithShadow) }
    }

    /// Whether screenshots include the mouse pointer. Recordings use `recordShowCursor`.
    @Published var captureShowCursor: Bool {
        didSet { AppSettings.defaults.set(captureShowCursor, forKey: Keys.captureShowCursor) }
    }

    @Published var developerModeEnabled: Bool {
        didSet { AppSettings.defaults.set(developerModeEnabled, forKey: Keys.developerMode) }
    }

    @Published var markdownImageUseAbsolutePath: Bool {
        didSet { AppSettings.defaults.set(markdownImageUseAbsolutePath, forKey: Keys.markdownAbsolutePath) }
    }

    private init() {
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        if let path = AppSettings.defaults.string(forKey: Keys.saveDirectory) {
            saveDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveDirectory = desktop
        }

        format = ScreenshotFormat(rawValue: AppSettings.defaults.string(forKey: Keys.format) ?? "") ?? .png
        let cornerRaw = AppSettings.defaults.string(forKey: Keys.corner) ?? ""
        quickAccessPlacement = QuickAccessPlacement.migrated(fromLegacyRawValue: cornerRaw)
        quickAccessStackCaptures = AppSettings.defaults.object(forKey: Keys.stackCaptures) as? Bool ?? true
        quickAccessToolbarStyle = QuickAccessToolbarStyle(
            rawValue: AppSettings.defaults.string(forKey: Keys.toolbarStyle) ?? ""
        ) ?? .below

        let quality = AppSettings.defaults.double(forKey: Keys.jpegQuality)
        jpegQuality = quality > 0 ? quality : 0.85

        hotkeyArea = Self.loadHotkey(key: Keys.hotkeyArea) ?? .areaDefault
        hotkeyWindow = Self.loadHotkey(key: Keys.hotkeyWindow) ?? .windowDefault
        hotkeyFullscreen = Self.loadHotkey(key: Keys.hotkeyFullscreen) ?? .fullscreenDefault

        if AppSettings.defaults.object(forKey: Keys.launchAtLogin) != nil {
            launchAtLogin = AppSettings.defaults.bool(forKey: Keys.launchAtLogin)
        } else {
            launchAtLogin = OctoshotL10n.isSettingsSnapshot ? false : LaunchAtLoginManager.isEnabled
        }

        if AppSettings.defaults.object(forKey: Keys.showMenuBarIcon) != nil {
            showMenuBarIcon = AppSettings.defaults.bool(forKey: Keys.showMenuBarIcon)
        } else {
            showMenuBarIcon = true
        }

        playCaptureSound = AppSettings.defaults.object(forKey: Keys.playCaptureSound) as? Bool ?? true
        afterCaptureShowQuickAccess = AppSettings.defaults.object(forKey: Keys.afterCaptureQuickAccess) as? Bool ?? true
        afterCaptureCopyToClipboard = AppSettings.defaults.bool(forKey: Keys.afterCaptureCopy)
        afterCaptureSaveToDisk = AppSettings.defaults.bool(forKey: Keys.afterCaptureSave)

        filenamePattern = AppSettings.defaults.string(forKey: Keys.filenamePattern) ?? Self.defaultFilenamePattern
        quickAccessAutoCloseSeconds = AppSettings.defaults.object(forKey: Keys.quickAccessAutoClose) as? Double ?? 0
        captureWindowWithShadow = AppSettings.defaults.object(forKey: Keys.captureWindowWithShadow) as? Bool ?? true
        captureShowCursor = AppSettings.defaults.object(forKey: Keys.captureShowCursor) as? Bool ?? false
        developerModeEnabled = AppSettings.defaults.object(forKey: Keys.developerMode) as? Bool ?? false
        markdownImageUseAbsolutePath = AppSettings.defaults.object(forKey: Keys.markdownAbsolutePath) as? Bool ?? true
    }

    func resetHotkeysToDefaults() {
        hotkeyArea = .areaDefault
        hotkeyWindow = .windowDefault
        hotkeyFullscreen = .fullscreenDefault
    }

    private func persistHotkey(_ binding: HotkeyBinding, key: String) {
        if let data = try? JSONEncoder().encode(binding) {
            AppSettings.defaults.set(data, forKey: key)
        }
    }

    private static func loadHotkey(key: String) -> HotkeyBinding? {
        guard let data = AppSettings.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    func defaultSaveURL(prefix: String = "Screenshot") -> URL {
        let filename = resolvedFilename(prefix: prefix)
        return saveDirectory.appendingPathComponent(filename)
    }

    func resolvedFilename(prefix: String) -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH.mm.ss"

        var name = filenamePattern
        name = name.replacingOccurrences(of: "{prefix}", with: prefix)
        name = name.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
        name = name.replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))
        name = name.replacingOccurrences(
            of: "{datetime}",
            with: "\(dateFormatter.string(from: now)) \(timeFormatter.string(from: now))"
        )
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = "\(prefix) \(dateFormatter.string(from: now)) \(timeFormatter.string(from: now))"
        }
        return CaptureOutput.filename(name, format: format)
    }
}
