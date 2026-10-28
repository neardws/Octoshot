import Foundation
import OctoshotCore

enum OctoshotL10n {
    static var isSettingsSnapshot: Bool {
        #if DEBUG
        (ProcessInfo.processInfo.environment["OCTOSHOT_QA_SNAPSHOT_SETTINGS"] == "1"
            || ProcessInfo.processInfo.environment["OCTOSHOT_QA_SNAPSHOT_DIARY"] == "1")
            && ProcessInfo.processInfo.environment["OCTOSHOT_QA_SNAPSHOT_DIR"] != nil
        #else
        false
        #endif
    }

    static var snapshotLocale: Locale {
        #if DEBUG
        Locale(identifier: ProcessInfo.processInfo.environment["OCTOSHOT_QA_SNAPSHOT_LOCALE"]
               ?? (ProcessInfo.processInfo.environment["OCTOSHOT_QA_SNAPSHOT_DIARY"] == "1" ? "zh-Hans" : "en"))
        #else
        .current
        #endif
    }

    private static var bundle: Bundle {
        #if DEBUG
        if isSettingsSnapshot,
           let path = Bundle.main.path(forResource: snapshotLocale.identifier, ofType: "lproj"),
           let localized = Bundle(path: path) {
            return localized
        }
        #endif
        return .main
    }

    static func text(_ key: String, comment: String = "") -> String {
        #if DEBUG
        if isSettingsSnapshot && snapshotLocale.language.languageCode?.identifier == "en" {
            return key
        }
        #endif
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    static var latexDefaultPrompt: String {
        text("You are a LaTeX OCR engine. Return ONLY valid LaTeX math markup for the formula in the image.\nDo not include markdown fences or explanations. Use amsmath-compatible syntax when needed.")
    }

    static func settingsError(_ error: Error) -> String {
        guard let embedded = error as? EmbeddedAIError else { return error.localizedDescription }
        switch embedded {
        case .downloadFailed(let detail):
            return format("Model download failed: %@", detail)
        case .specialistFailed(let detail):
            return format("LaTeX specialist failed: %@", detail)
        case .modelNotInstalled(let model):
            return format("%@ is not installed. Download it in Settings → AI.", modelName(model))
        case .inferenceUnavailableInThisBuild:
            return text("On-device inference is not available in this build. Install models in Settings → AI or enable Ollama fallback.")
        case .backendMissing:
            return text("Embedded AI backend is not registered.")
        }
    }

    static func ollamaPullStatus(_ status: String) -> String {
        switch status {
        case "pulling manifest": return text("pulling manifest")
        case "verifying sha256 digest": return text("verifying sha256 digest")
        case "writing manifest": return text("writing manifest")
        case "removing any unused layers": return text("removing any unused layers")
        case "success": return text("success")
        default:
            if status.hasPrefix("pulling ") {
                return format("pulling %@", String(status.dropFirst("pulling ".count)))
            }
            return status
        }
    }

    static func modelName(_ model: EmbeddedModelID) -> String {
        switch model {
        case .smolVLM2_500M_4bit: text("SmolVLM2-500M (MLX 4-bit)")
        case .pix2texMFR_Q4, .miniCPMV46_4bit: model.displayName
        }
    }

    static func modelLicense(_ model: EmbeddedModelID) -> String {
        switch model {
        case .smolVLM2_500M_4bit: text("Apache-2.0 (Hugging FaceTB / mlx-community weights)")
        case .pix2texMFR_Q4, .miniCPMV46_4bit: model.licenseNote
        }
    }

    static var ocrAction: String {
        text("OCR", comment: "Quick action: recognize text in screenshot")
    }

    static var ocrWindowTitle: String {
        text("Recognize Text", comment: "OCR result window title")
    }

    static var ocrRecognizing: String {
        text("Recognizing…", comment: "OCR in progress")
    }

    static var ocrRecognizeAgain: String {
        text("Recognize Again", comment: "Re-run OCR on image")
    }

    static var ocrSelectAll: String {
        text("Select All", comment: "Select all recognized text")
    }

    static var ocrCopy: String {
        text("Copy", comment: "Copy recognized text")
    }

    static var ocrNoTextFound: String {
        text("No text found in this image.", comment: "OCR empty result")
    }

    static var ocrRecognitionFailed: String {
        text("Text recognition failed.", comment: "OCR error headline")
    }

    static func urlSchemeConfirmTitle(appName: String) -> String {
        String(
            format: text("Allow “%@” to capture your screen?", comment: "URL scheme confirmation title"),
            appName
        )
    }

    static var urlSchemeConfirmTitleUnknownApp: String {
        text("Allow an app to capture your screen?", comment: "URL scheme confirmation title, caller unknown")
    }

    static var urlSchemeConfirmCaptureBody: String {
        text("It asked Octoshot to take a full-screen screenshot and save it to your save folder.",
            comment: "URL scheme confirmation body for a capture"
        )
    }

    static var urlSchemeConfirmRecordBody: String {
        text("It asked Octoshot to start recording your screen.", comment: "URL scheme confirmation body for a recording")
    }

    static var urlSchemeAllow: String {
        text("Allow", comment: "URL scheme confirmation: approve")
    }

    static var urlSchemeDontAllow: String {
        text("Don’t Allow", comment: "URL scheme confirmation: decline")
    }

    static func urlSchemeAlwaysAllow(appName: String) -> String {
        String(format: text("Always allow “%@”", comment: "URL scheme confirmation checkbox"), appName)
    }

    static var urlSchemePolicyLabel: String {
        text("Requests from other apps", comment: "URL scheme policy picker label")
    }

    static func urlSchemePolicyName(_ policy: URLSchemeAutomationPolicy) -> String {
        switch policy {
        case .ask: return text("Ask every time", comment: "URL scheme policy")
        case .allow: return text("Always allow", comment: "URL scheme policy")
        case .off: return text("Off", comment: "URL scheme policy")
        }
    }

    static var urlSchemeExplanation: String {
        text("Any app or web page can open octoshot:// links. Octoshot asks before a link takes a full-screen or display screenshot or starts a recording (including area recording), unless you ticked “Always allow” for that app in the prompt. Approved apps are verified by code signature, web browsers can't be approved, and the “Always allow” setting still asks every other app. Screenshot links that only open area or window selection don't ask, because nothing is captured until you select. Stopping a recording is always allowed; “Off” ignores all other links.",
            comment: "URL scheme settings explanation"
        )
    }

    static func urlSchemeForgetTrusted(count: Int) -> String {
        String(format: text("Forget always-allowed apps (%d)", comment: "URL scheme: clear allowlist"), count)
    }

    static var urlSchemeSectionTitle: String {
        text("URL scheme (octoshot://)", comment: "Settings section header")
    }

    static var historyWindowTitle: String {
        text("Screenshot History", comment: "History browser window title")
    }

    static var historyMenuItem: String {
        text("Screenshot History…", comment: "Menu item to open history")
    }

    static var historyEmptySelection: String {
        text("Select a screenshot", comment: "History detail placeholder")
    }

    static var historyEmptyLibrary: String {
        text("No screenshots in the save folder", comment: "History empty state")
    }

    static var historyRefresh: String {
        text("Refresh", comment: "Reload history list")
    }

    static var historyOpenFolder: String {
        text("Open Save Folder", comment: "Reveal screenshot save directory")
    }

    static var historyDelete: String {
        text("Delete", comment: "Delete screenshot file")
    }

    static var historyRevealInFinder: String {
        text("Show in Finder", comment: "Reveal file in Finder")
    }

    static var historyDeleteConfirmTitle: String {
        text("Delete screenshot?", comment: "Delete confirmation title")
    }

    static func historyDeleteConfirmMessage(_ name: String) -> String {
        String(
            format: text("%@ will be moved to the Trash.", comment: "Delete confirmation body"),
            name
        )
    }

    static var historyDeleteFailed: String {
        text("Could not delete the file.", comment: "Delete error headline")
    }

    static var historyPinAction: String {
        text("Pin to Screen", comment: "Pin screenshot on desktop")
    }

    static var historyCancel: String {
        text("Cancel", comment: "Cancel destructive action")
    }

    static var checkForUpdates: String {
        text("Check for Updates…", comment: "Sparkle manual update check")
    }

    static var quickAccessPlacementTitle: String {
        text("Quick access position", comment: "Settings picker label for overlay placement")
    }

    static func quickAccessPlacementName(_ placement: QuickAccessPlacement) -> String {
        switch placement {
        case .bottomLeft:
            return text("Bottom left", comment: "Quick access panel bottom-left corner")
        case .bottomRight:
            return text("Bottom right", comment: "Quick access panel bottom-right corner")
        case .leftSidebar:
            return text("Left sidebar", comment: "Quick access vertical strip on left")
        case .rightSidebar:
            return text("Right sidebar", comment: "Quick access vertical strip on right")
        }
    }

    static var quickAccessStackCaptures: String {
        text("Stack multiple captures", comment: "Settings toggle for Finder-style thumbnail stack")
    }

    static var quickAccessCloseAll: String {
        text("Close all", comment: "Dismiss every quick-access thumbnail at once")
    }

    static var quickAccessCollapseStack: String {
        text("Collapse stack", comment: "Collapse expanded quick-access thumbnail stack")
    }

    static var quickAccessDismissCapture: String {
        text("Remove from panel", comment: "Remove one capture from quick-access stack without deleting the file")
    }

    // MARK: - Quick access panel

    static var quickAccessToolbarTitle: String { text("Toolbar style") }
    static var quickAccessToolbarBelow: String { text("Below image") }
    static var quickAccessToolbarRing: String { text("Ring") }

    static var quickAccessCopy: String {
        text("Copy to Clipboard", comment: "Quick access: copy screenshot")
    }

    static var quickAccessSave: String {
        text("Save to Disk", comment: "Quick access: save screenshot")
    }

    static var quickAccessAnnotate: String {
        text("Annotate", comment: "Quick access: open annotation editor")
    }

    static var quickAccessPin: String {
        text("Pin to Screen", comment: "Quick access: pin screenshot on desktop")
    }

    static var quickAccessAskAI: String {
        text("Ask AI", comment: "Quick access: open local AI assistant")
    }

    static var quickAccessCopyMarkdown: String {
        text("Copy Markdown", comment: "Quick access: copy Markdown image snippet")
    }

    static var quickAccessCopyPath: String {
        text("Copy File Path", comment: "Quick access: copy saved file path")
    }

    static var quickAccessClose: String {
        text("Dismiss", comment: "Quick access: close panel")
    }

    static var cancel: String {
        text("Cancel", comment: "Cancel action")
    }

    // MARK: - Shortcuts settings

    static var shortcutsPaneTitle: String {
        text("Shortcuts", comment: "Settings shortcuts pane title")
    }

    static var shortcutsPaneSubtitle: String {
        text("Global capture hotkeys and macOS screenshot bindings",
            comment: "Settings shortcuts pane subtitle"
        )
    }

    static var hotkeyCaptureFullscreen: String {
        text("Capture fullscreen", comment: "Hotkey row")
    }

    static var hotkeyCaptureArea: String {
        text("Capture area", comment: "Hotkey row")
    }

    static var hotkeyCaptureWindow: String {
        text("Capture window", comment: "Hotkey row")
    }

    static var hotkeyRecordHint: String {
        text("Click Record, then press a shortcut that includes ⌘, ⌥, ⌃, or ⇧. Press Esc to cancel.",
            comment: "Hotkey recorder hint"
        )
    }

    static var hotkeyRecord: String {
        text("Record", comment: "Start hotkey recording")
    }

    static var hotkeyRecording: String {
        text("Press keys…", comment: "Hotkey recording in progress")
    }

    static var hotkeyRecordCancelled: String {
        text("Recording cancelled.", comment: "Hotkey recorder cancelled")
    }

    static var hotkeyResetDefaults: String {
        text("Reset to Defaults", comment: "Reset hotkeys")
    }

    static var hotkeyOctoshotSection: String {
        text("Octoshot hotkeys", comment: "Settings section")
    }

    static var hotkeyConflictNeedsModifier: String {
        text("Include at least one modifier key (⌘, ⌥, ⌃, or ⇧).",
            comment: "Hotkey validation"
        )
    }

    static var hotkeyConflictOctoshot: String {
        text("That shortcut is already used by another Octoshot capture action.",
            comment: "Hotkey conflict"
        )
    }

    static var hotkeyConflictSystem: String {
        text("That shortcut matches an enabled macOS screenshot shortcut.",
            comment: "Hotkey conflict with system"
        )
    }

    static var hotkeyConflictGeneric: String {
        text("That shortcut is not available.", comment: "Hotkey conflict generic")
    }

    static var systemHotkeySection: String {
        text("macOS screenshot shortcuts", comment: "Settings section")
    }

    static var systemHotkeyTakeoverSection: String {
        text("Take over system shortcuts", comment: "Settings section")
    }

    static var systemHotkeyEnabled: String {
        text("Enabled", comment: "System hotkey state")
    }

    static var systemHotkeyDisabled: String {
        text("Disabled", comment: "System hotkey state")
    }

    static var systemHotkeyStockDefault: String {
        text("System default (not in plist)", comment: "Stock symbolic hotkey")
    }

    static var systemHotkeyRefresh: String {
        text("Refresh system bindings", comment: "Reload symbolic hotkeys")
    }

    static var systemHotkeyConflictBanner: String {
        text("System shortcuts still enabled for the same keys — captures may open both apps.",
            comment: "Conflict warning"
        )
    }

    static var systemHotkeyUseOctoshotKeys: String {
        text("Use Octoshot for ⌘⇧3 / ⌘⇧4 / ⌘⇧5", comment: "Apply default hotkeys")
    }

    static var systemHotkeyManualDisableHint: String {
        text("This sets Octoshot to the standard screenshot keys. Disable the matching items under System Settings → Keyboard → Keyboard Shortcuts → Screenshots, or turn them off below.",
            comment: "Manual disable hint"
        )
    }

    static var systemHotkeyOpenKeyboardSettings: String {
        text("Open Keyboard Shortcuts…", comment: "Open System Settings")
    }

    static var systemHotkeyDisableAdvanced: String {
        text("Disable system screenshot hotkeys…", comment: "One-click disable")
    }

    static var systemHotkeyRestore: String {
        text("Restore system screenshot hotkeys", comment: "Restore backup")
    }

    static var systemHotkeyDisableConfirmTitle: String {
        text("Disable macOS screenshot shortcuts?", comment: "Confirm disable title")
    }

    static var systemHotkeyDisableConfirmBody: String {
        text("Octoshot will save the previous state for screenshot shortcut IDs (28, 29, 30, 31, 184), turn them off, and apply the change immediately. Use Restore to undo only those IDs.",
            comment: "Confirm disable body"
        )
    }

    static var systemHotkeyDisableAction: String {
        text("Disable", comment: "Disable system shortcuts")
    }

    static var systemHotkeyOpenSettingsAction: String {
        text("Open System Settings", comment: "Conflict alert button")
    }

    static var systemHotkeyDismissAction: String {
        text("Not Now", comment: "Dismiss conflict alert")
    }

    static var systemHotkeySuppressFuture: String {
        text("Do not show this again", comment: "Suppress conflict alerts")
    }

    static var systemHotkeyConflictTitle: String {
        text("Screenshot shortcut conflict", comment: "Conflict alert title")
    }

    static var systemHotkeyConflictLaunchBody: String {
        text("macOS screenshot shortcuts are still active for: %@. Octoshot may capture at the same time as the system UI. Disable the system shortcuts or change Octoshot’s keys in Settings → Shortcuts.",
            comment: "Launch conflict body; %@ is key list"
        )
    }

    static var systemHotkeyConflictOnboardingBody: String {
        text("These macOS screenshot shortcuts overlap Octoshot: %@. Turn them off now to avoid double captures.",
            comment: "Onboarding conflict body"
        )
    }

    static var systemHotkeyDisableSuccess: String {
        text("System screenshot shortcuts disabled. A per-ID backup was saved in Application Support/Octoshot.",
            comment: "Disable success"
        )
    }

    static var systemHotkeyRestoreSuccess: String {
        text("Restored system screenshot shortcuts from backup.", comment: "Restore success")
    }

    static var systemHotkeyDisableFailedTitle: String {
        text("Could not disable system shortcuts", comment: "Disable error title")
    }

    static var systemHotkeyMissingPlist: String {
        text("Could not find com.apple.symbolichotkeys.plist.", comment: "Plist missing")
    }

    static var systemHotkeyParseFailed: String {
        text("Could not parse symbolic hotkeys plist.", comment: "Plist parse error")
    }

    static var systemHotkeyNoBackup: String {
        text("No saved backup of system screenshot shortcuts.", comment: "No backup")
    }

    static var onboardingShortcutsTitle: String {
        text("Shortcuts", comment: "Onboarding shortcuts step title")
    }

    static var onboardingShortcutsBody: String {
        text("Use Octoshot with the familiar ⌘⇧3 / ⌘⇧4 / ⌘⇧5 keys. If macOS screenshot shortcuts are still on, turn them off so only Octoshot responds.",
            comment: "Onboarding shortcuts body"
        )
    }

    static var onboardingOpenShortcutsSettings: String {
        text("Open Settings → Shortcuts", comment: "Onboarding button")
    }

    static func systemScreenshotHotkeyTitle(_ id: Int) -> String {
        switch id {
        case ScreenshotSymbolicHotkeyID.saveFullScreenToFile.rawValue:
            return text("Save picture of screen as file (⌘⇧3)", comment: "System hotkey 28")
        case ScreenshotSymbolicHotkeyID.copyFullScreenToClipboard.rawValue:
            return text("Copy picture of screen (⌃⌘⇧3)", comment: "System hotkey 29")
        case ScreenshotSymbolicHotkeyID.saveSelectionToFile.rawValue:
            return text("Save picture of selected area (⌘⇧4)", comment: "System hotkey 30")
        case ScreenshotSymbolicHotkeyID.copySelectionToClipboard.rawValue:
            return text("Copy picture of selection (⌃⌘⇧4)", comment: "System hotkey 31")
        case ScreenshotSymbolicHotkeyID.screenshotAndRecordingOptions.rawValue:
            return text("Screenshot & recording options (⌘⇧5)", comment: "System hotkey 184")
        default:
            return String(format: text("Hotkey %d", comment: "Unknown hotkey id"), id)
        }
    }
}
