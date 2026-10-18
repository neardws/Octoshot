import Foundation
import OctoshotCore

enum OctoshotL10n {
    static var ocrAction: String {
        String(localized: "OCR", comment: "Quick action: recognize text in screenshot")
    }

    static var ocrWindowTitle: String {
        String(localized: "Recognize Text", comment: "OCR result window title")
    }

    static var ocrRecognizing: String {
        String(localized: "Recognizing…", comment: "OCR in progress")
    }

    static var ocrRecognizeAgain: String {
        String(localized: "Recognize Again", comment: "Re-run OCR on image")
    }

    static var ocrSelectAll: String {
        String(localized: "Select All", comment: "Select all recognized text")
    }

    static var ocrCopy: String {
        String(localized: "Copy", comment: "Copy recognized text")
    }

    static var ocrNoTextFound: String {
        String(localized: "No text found in this image.", comment: "OCR empty result")
    }

    static var ocrRecognitionFailed: String {
        String(localized: "Text recognition failed.", comment: "OCR error headline")
    }

    static var historyWindowTitle: String {
        String(localized: "Screenshot History", comment: "History browser window title")
    }

    static var historyMenuItem: String {
        String(localized: "Screenshot History…", comment: "Menu item to open history")
    }

    static var historyEmptySelection: String {
        String(localized: "Select a screenshot", comment: "History detail placeholder")
    }

    static var historyEmptyLibrary: String {
        String(localized: "No screenshots in the save folder", comment: "History empty state")
    }

    static var historyRefresh: String {
        String(localized: "Refresh", comment: "Reload history list")
    }

    static var historyOpenFolder: String {
        String(localized: "Open Save Folder", comment: "Reveal screenshot save directory")
    }

    static var historyDelete: String {
        String(localized: "Delete", comment: "Delete screenshot file")
    }

    static var historyRevealInFinder: String {
        String(localized: "Show in Finder", comment: "Reveal file in Finder")
    }

    static var historyDeleteConfirmTitle: String {
        String(localized: "Delete screenshot?", comment: "Delete confirmation title")
    }

    static func historyDeleteConfirmMessage(_ name: String) -> String {
        String(
            format: String(localized: "%@ will be moved to the Trash.", comment: "Delete confirmation body"),
            name
        )
    }

    static var historyDeleteFailed: String {
        String(localized: "Could not delete the file.", comment: "Delete error headline")
    }

    static var historyPinAction: String {
        String(localized: "Pin to Screen", comment: "Pin screenshot on desktop")
    }

    static var historyCancel: String {
        String(localized: "Cancel", comment: "Cancel destructive action")
    }

    static var checkForUpdates: String {
        String(localized: "Check for Updates…", comment: "Sparkle manual update check")
    }

    static var quickAccessPlacementTitle: String {
        String(localized: "Quick access position", comment: "Settings picker label for overlay placement")
    }

    static func quickAccessPlacementName(_ placement: QuickAccessPlacement) -> String {
        switch placement {
        case .bottomLeft:
            return String(localized: "Bottom left", comment: "Quick access panel bottom-left corner")
        case .bottomRight:
            return String(localized: "Bottom right", comment: "Quick access panel bottom-right corner")
        case .leftSidebar:
            return String(localized: "Left sidebar", comment: "Quick access vertical strip on left")
        case .rightSidebar:
            return String(localized: "Right sidebar", comment: "Quick access vertical strip on right")
        }
    }

    static var quickAccessStackCaptures: String {
        String(localized: "Stack multiple captures", comment: "Settings toggle for Finder-style thumbnail stack")
    }

    static var quickAccessCloseAll: String {
        String(localized: "Close all", comment: "Dismiss every quick-access thumbnail at once")
    }

    static var quickAccessCollapseStack: String {
        String(localized: "Collapse stack", comment: "Collapse expanded quick-access thumbnail stack")
    }

    static var quickAccessDismissCapture: String {
        String(localized: "Remove from panel", comment: "Remove one capture from quick-access stack without deleting the file")
    }

    // MARK: - Quick access panel

    static var quickAccessToolbarTitle: String { String(localized: "Toolbar style") }
    static var quickAccessToolbarBelow: String { String(localized: "Below image") }
    static var quickAccessToolbarBubbles: String { String(localized: "Perimeter bubbles") }

    static var quickAccessCopy: String {
        String(localized: "Copy to Clipboard", comment: "Quick access: copy screenshot")
    }

    static var quickAccessSave: String {
        String(localized: "Save to Disk", comment: "Quick access: save screenshot")
    }

    static var quickAccessAnnotate: String {
        String(localized: "Annotate", comment: "Quick access: open annotation editor")
    }

    static var quickAccessPin: String {
        String(localized: "Pin to Screen", comment: "Quick access: pin screenshot on desktop")
    }

    static var quickAccessAskAI: String {
        String(localized: "Ask AI", comment: "Quick access: open local AI assistant")
    }

    static var quickAccessCopyMarkdown: String {
        String(localized: "Copy Markdown", comment: "Quick access: copy Markdown image snippet")
    }

    static var quickAccessCopyPath: String {
        String(localized: "Copy File Path", comment: "Quick access: copy saved file path")
    }

    static var quickAccessClose: String {
        String(localized: "Dismiss", comment: "Quick access: close panel")
    }

    static var cancel: String {
        String(localized: "Cancel", comment: "Cancel action")
    }

    // MARK: - Shortcuts settings

    static var shortcutsPaneTitle: String {
        String(localized: "Shortcuts", comment: "Settings shortcuts pane title")
    }

    static var shortcutsPaneSubtitle: String {
        String(
            localized: "Global capture hotkeys and macOS screenshot bindings",
            comment: "Settings shortcuts pane subtitle"
        )
    }

    static var hotkeyCaptureFullscreen: String {
        String(localized: "Capture fullscreen", comment: "Hotkey row")
    }

    static var hotkeyCaptureArea: String {
        String(localized: "Capture area", comment: "Hotkey row")
    }

    static var hotkeyCaptureWindow: String {
        String(localized: "Capture window", comment: "Hotkey row")
    }

    static var hotkeyRecordHint: String {
        String(
            localized: "Click Record, then press a shortcut that includes ⌘, ⌥, ⌃, or ⇧. Press Esc to cancel.",
            comment: "Hotkey recorder hint"
        )
    }

    static var hotkeyRecord: String {
        String(localized: "Record", comment: "Start hotkey recording")
    }

    static var hotkeyRecording: String {
        String(localized: "Press keys…", comment: "Hotkey recording in progress")
    }

    static var hotkeyRecordCancelled: String {
        String(localized: "Recording cancelled.", comment: "Hotkey recorder cancelled")
    }

    static var hotkeyResetDefaults: String {
        String(localized: "Reset to Defaults", comment: "Reset hotkeys")
    }

    static var hotkeyOctoshotSection: String {
        String(localized: "Octoshot hotkeys", comment: "Settings section")
    }

    static var hotkeyConflictNeedsModifier: String {
        String(
            localized: "Include at least one modifier key (⌘, ⌥, ⌃, or ⇧).",
            comment: "Hotkey validation"
        )
    }

    static var hotkeyConflictOctoshot: String {
        String(
            localized: "That shortcut is already used by another Octoshot capture action.",
            comment: "Hotkey conflict"
        )
    }

    static var hotkeyConflictSystem: String {
        String(
            localized: "That shortcut matches an enabled macOS screenshot shortcut.",
            comment: "Hotkey conflict with system"
        )
    }

    static var hotkeyConflictGeneric: String {
        String(localized: "That shortcut is not available.", comment: "Hotkey conflict generic")
    }

    static var systemHotkeySection: String {
        String(localized: "macOS screenshot shortcuts", comment: "Settings section")
    }

    static var systemHotkeyTakeoverSection: String {
        String(localized: "Take over system shortcuts", comment: "Settings section")
    }

    static var systemHotkeyEnabled: String {
        String(localized: "Enabled", comment: "System hotkey state")
    }

    static var systemHotkeyDisabled: String {
        String(localized: "Disabled", comment: "System hotkey state")
    }

    static var systemHotkeyStockDefault: String {
        String(localized: "System default (not in plist)", comment: "Stock symbolic hotkey")
    }

    static var systemHotkeyRefresh: String {
        String(localized: "Refresh system bindings", comment: "Reload symbolic hotkeys")
    }

    static var systemHotkeyConflictBanner: String {
        String(
            localized: "System shortcuts still enabled for the same keys — captures may open both apps.",
            comment: "Conflict warning"
        )
    }

    static var systemHotkeyUseOctoshotKeys: String {
        String(localized: "Use Octoshot for ⌘⇧3 / ⌘⇧4 / ⌘⇧5", comment: "Apply default hotkeys")
    }

    static var systemHotkeyManualDisableHint: String {
        String(
            localized: "This sets Octoshot to the standard screenshot keys. Disable the matching items under System Settings → Keyboard → Keyboard Shortcuts → Screenshots, or turn them off below.",
            comment: "Manual disable hint"
        )
    }

    static var systemHotkeyOpenKeyboardSettings: String {
        String(localized: "Open Keyboard Shortcuts…", comment: "Open System Settings")
    }

    static var systemHotkeyDisableAdvanced: String {
        String(localized: "Disable system screenshot hotkeys…", comment: "One-click disable")
    }

    static var systemHotkeyRestore: String {
        String(localized: "Restore system screenshot hotkeys", comment: "Restore backup")
    }

    static var systemHotkeyDisableConfirmTitle: String {
        String(localized: "Disable macOS screenshot shortcuts?", comment: "Confirm disable title")
    }

    static var systemHotkeyDisableConfirmBody: String {
        String(
            localized: "Octoshot will save the previous state for screenshot shortcut IDs (28, 29, 30, 31, 184), turn them off, and apply the change immediately. Use Restore to undo only those IDs.",
            comment: "Confirm disable body"
        )
    }

    static var systemHotkeyDisableAction: String {
        String(localized: "Disable", comment: "Disable system shortcuts")
    }

    static var systemHotkeyOpenSettingsAction: String {
        String(localized: "Open System Settings", comment: "Conflict alert button")
    }

    static var systemHotkeyDismissAction: String {
        String(localized: "Not Now", comment: "Dismiss conflict alert")
    }

    static var systemHotkeySuppressFuture: String {
        String(localized: "Do not show this again", comment: "Suppress conflict alerts")
    }

    static var systemHotkeyConflictTitle: String {
        String(localized: "Screenshot shortcut conflict", comment: "Conflict alert title")
    }

    static var systemHotkeyConflictLaunchBody: String {
        String(
            localized: "macOS screenshot shortcuts are still active for: %@. Octoshot may capture at the same time as the system UI. Disable the system shortcuts or change Octoshot’s keys in Settings → Shortcuts.",
            comment: "Launch conflict body; %@ is key list"
        )
    }

    static var systemHotkeyConflictOnboardingBody: String {
        String(
            localized: "These macOS screenshot shortcuts overlap Octoshot: %@. Turn them off now to avoid double captures.",
            comment: "Onboarding conflict body"
        )
    }

    static var systemHotkeyDisableSuccess: String {
        String(
            localized: "System screenshot shortcuts disabled. A per-ID backup was saved in Application Support/Octoshot.",
            comment: "Disable success"
        )
    }

    static var systemHotkeyRestoreSuccess: String {
        String(localized: "Restored system screenshot shortcuts from backup.", comment: "Restore success")
    }

    static var systemHotkeyDisableFailedTitle: String {
        String(localized: "Could not disable system shortcuts", comment: "Disable error title")
    }

    static var systemHotkeyMissingPlist: String {
        String(localized: "Could not find com.apple.symbolichotkeys.plist.", comment: "Plist missing")
    }

    static var systemHotkeyParseFailed: String {
        String(localized: "Could not parse symbolic hotkeys plist.", comment: "Plist parse error")
    }

    static var systemHotkeyNoBackup: String {
        String(localized: "No saved backup of system screenshot shortcuts.", comment: "No backup")
    }

    static var onboardingShortcutsTitle: String {
        String(localized: "Shortcuts", comment: "Onboarding shortcuts step title")
    }

    static var onboardingShortcutsBody: String {
        String(
            localized: "Use Octoshot with the familiar ⌘⇧3 / ⌘⇧4 / ⌘⇧5 keys. If macOS screenshot shortcuts are still on, turn them off so only Octoshot responds.",
            comment: "Onboarding shortcuts body"
        )
    }

    static var onboardingOpenShortcutsSettings: String {
        String(localized: "Open Settings → Shortcuts", comment: "Onboarding button")
    }

    static func systemScreenshotHotkeyTitle(_ id: Int) -> String {
        switch id {
        case ScreenshotSymbolicHotkeyID.saveFullScreenToFile.rawValue:
            return String(localized: "Save picture of screen as file (⌘⇧3)", comment: "System hotkey 28")
        case ScreenshotSymbolicHotkeyID.copyFullScreenToClipboard.rawValue:
            return String(localized: "Copy picture of screen (⌃⌘⇧3)", comment: "System hotkey 29")
        case ScreenshotSymbolicHotkeyID.saveSelectionToFile.rawValue:
            return String(localized: "Save picture of selected area (⌘⇧4)", comment: "System hotkey 30")
        case ScreenshotSymbolicHotkeyID.copySelectionToClipboard.rawValue:
            return String(localized: "Copy picture of selection (⌃⌘⇧4)", comment: "System hotkey 31")
        case ScreenshotSymbolicHotkeyID.screenshotAndRecordingOptions.rawValue:
            return String(localized: "Screenshot & recording options (⌘⇧5)", comment: "System hotkey 184")
        default:
            return String(format: String(localized: "Hotkey %d", comment: "Unknown hotkey id"), id)
        }
    }
}
