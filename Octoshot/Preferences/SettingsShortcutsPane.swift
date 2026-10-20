import AppKit
import SwiftUI
import OctoshotCore

struct SettingsShortcutsPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var recordingTarget: HotkeyTarget?
    @State private var systemEntries: [SystemScreenshotHotkeys.Entry] = []
    @State private var plistMessage: String?
    @State private var recorderNote: String?

    enum HotkeyTarget: String {
        case area, window, fullscreen

        var settingsKey: String { rawValue }
    }

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(
                title: OctoshotL10n.shortcutsPaneTitle,
                subtitle: OctoshotL10n.shortcutsPaneSubtitle,
                systemImage: "command"
            )

            Section {
                hotkeyRow(OctoshotL10n.hotkeyCaptureFullscreen, binding: $settings.hotkeyFullscreen, target: .fullscreen)
                hotkeyRow(OctoshotL10n.hotkeyCaptureArea, binding: $settings.hotkeyArea, target: .area)
                hotkeyRow(OctoshotL10n.hotkeyCaptureWindow, binding: $settings.hotkeyWindow, target: .window)
                Text(OctoshotL10n.hotkeyRecordHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let recorderNote {
                    Text(recorderNote)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(OctoshotL10n.hotkeyResetDefaults) { settings.resetHotkeysToDefaults() }
            } header: {
                Label(OctoshotL10n.hotkeyOctoshotSection, systemImage: "keyboard")
            }

            Section {
                ForEach(systemEntries) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(HotkeyFormatter.displayString(for: entry.binding))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if entry.usesStockDefaults {
                                Text(OctoshotL10n.systemHotkeyStockDefault)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(entry.enabled ? OctoshotL10n.systemHotkeyEnabled : OctoshotL10n.systemHotkeyDisabled)
                            .foregroundStyle(entry.enabled ? .primary : .secondary)
                    }
                }
                Button(OctoshotL10n.systemHotkeyRefresh) { reloadSystem() }
            } header: {
                Label(OctoshotL10n.systemHotkeySection, systemImage: "apple.logo")
            }

            Section {
                let conflicts = SystemScreenshotHotkeys.conflicts(with: settings)
                if !conflicts.isEmpty {
                    Label(OctoshotL10n.systemHotkeyConflictBanner, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                Button(OctoshotL10n.systemHotkeyUseOctoshotKeys) {
                    SystemScreenshotHotkeys.applyOctoshotTakeover()
                    SystemScreenshotHotkeys.openKeyboardSettings()
                }

                Text(OctoshotL10n.systemHotkeyManualDisableHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(OctoshotL10n.systemHotkeyOpenKeyboardSettings) {
                    SystemScreenshotHotkeys.openKeyboardSettings()
                }

                Button(OctoshotL10n.systemHotkeyDisableAdvanced) {
                    confirmDisableSystemHotkeys()
                }

                if !OctoshotL10n.isSettingsSnapshot && SystemScreenshotHotkeys.hasBackup {
                    Button(OctoshotL10n.systemHotkeyRestore) {
                        restoreSystemHotkeys()
                    }
                }

                if let plistMessage {
                    Text(plistMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label(OctoshotL10n.systemHotkeyTakeoverSection, systemImage: "arrow.triangle.swap")
            }
        }
        .onAppear { reloadSystem() }
    }

    private func reloadSystem() {
        systemEntries = SystemScreenshotHotkeys.loadEntries()
    }

    private func hotkeyRow(_ title: String, binding: Binding<HotkeyBinding>, target: HotkeyTarget) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(HotkeyFormatter.displayString(for: binding.wrappedValue))
                .font(.system(.body, design: .monospaced))
            Button(recordingTarget == target ? OctoshotL10n.hotkeyRecording : OctoshotL10n.hotkeyRecord) {
                recorderNote = nil
                recordingTarget = target
                HotkeyRecorder.shared.start(
                    onRecord: { event in
                        applyRecorded(event, target: target)
                    },
                    onCancel: {
                        recordingTarget = nil
                        recorderNote = OctoshotL10n.hotkeyRecordCancelled
                    }
                )
            }
        }
    }

    private func applyRecorded(_ event: NSEvent, target: HotkeyTarget) {
        let newBinding = HotkeyBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: HotkeyFormatter.modifiersFromEvent(event)
        )
        let octo = SystemScreenshotHotkeys.octoshotHotkeySet(from: settings)
        let system = SystemScreenshotHotkeys.resolvedSystemEntries()
        if let code = SymbolicHotkeyPlist.recordingConflict(
            candidate: newBinding,
            replacing: target.settingsKey,
            octoshot: octo,
            systemEntries: system
        ) {
            recorderNote = recordingConflictMessage(code)
            recordingTarget = nil
            HotkeyRecorder.shared.stop()
            return
        }
        switch target {
        case .area: settings.hotkeyArea = newBinding
        case .window: settings.hotkeyWindow = newBinding
        case .fullscreen: settings.hotkeyFullscreen = newBinding
        }
        recordingTarget = nil
        recorderNote = nil
        HotkeyRecorder.shared.stop()
        reloadSystem()
    }

    private func recordingConflictMessage(_ code: String) -> String {
        switch code {
        case "modifier_required": return OctoshotL10n.hotkeyConflictNeedsModifier
        case "octoshot_duplicate": return OctoshotL10n.hotkeyConflictOctoshot
        case "system_duplicate": return OctoshotL10n.hotkeyConflictSystem
        default: return OctoshotL10n.hotkeyConflictGeneric
        }
    }

    private func confirmDisableSystemHotkeys() {
        if ScreenshotHotkeyConflictPresenter.confirmAndDisableSystemHotkeys() {
            plistMessage = OctoshotL10n.systemHotkeyDisableSuccess
        }
        reloadSystem()
    }

    private func restoreSystemHotkeys() {
        do {
            try SystemScreenshotHotkeys.restoreSystemScreenshotHotkeys()
            plistMessage = OctoshotL10n.systemHotkeyRestoreSuccess
            reloadSystem()
        } catch {
            plistMessage = error.localizedDescription
        }
    }
}
