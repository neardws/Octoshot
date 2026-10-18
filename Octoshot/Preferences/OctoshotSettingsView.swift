import AppKit
import SwiftUI
import OctoshotCore

struct OctoshotSettingsView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        // Plain HStack instead of NavigationSplitView: this view is hosted in an AppKit
        // NSWindow (SettingsWindowController), where NavigationSplitView injects an
        // NSToolbar with a sidebar toggle and a toolbar-height scroll-edge band over the
        // detail column. `.toolbar(.hidden, for: .windowToolbar)` only works for SwiftUI
        // scene windows, so the band covered the top of every pane.
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
            Divider()
            detailView(for: selection)
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: .octoshotOpenSettingsSection)) { note in
            if let section = note.object as? SettingsSection {
                selection = section
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SettingsSection.allCases) { section in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                        Text(section.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } icon: {
                    Image(systemName: section.systemImage)
                }
                .tag(section)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Divider()
                Text("Octoshot \(AppVersion.display)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsPane()
        case .shortcuts:
            SettingsShortcutsPane()
        case .capture:
            CaptureSettingsPane()
        case .recording:
            SettingsRecordingPane()
        case .annotation:
            AnnotationSettingsPane()
        case .ai:
            SettingsAIPane()
        case .developer:
            DeveloperSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var accessCache = ScreenRecordingAccessCache.shared
    @State private var isCheckingPermission = false

    private var hasAccess: Bool {
        accessCache.lastKnownGranted ?? PermissionManager.legacyPreflightAccess
    }

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(
                title: "General",
                subtitle: "Startup, menu bar, capture behavior, and privacy",
                systemImage: "gearshape"
            )

            Section {
                Toggle("Launch Octoshot at login", isOn: $settings.launchAtLogin)
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Toggle("Play sound after capture", isOn: $settings.playCaptureSound)
            } header: {
                Label("App", systemImage: "app")
            }

            Section {
                Toggle("Show quick-access panel", isOn: $settings.afterCaptureShowQuickAccess)
                Toggle("Copy to clipboard", isOn: $settings.afterCaptureCopyToClipboard)
                Toggle("Save to disk", isOn: $settings.afterCaptureSaveToDisk)
                Text("If quick access is off, you can still copy or save using the toggles above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("After capture", systemImage: "sparkles")
            }

            Section {
                HStack {
                    Image(systemName: hasAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hasAccess ? .green : .orange)
                    Text(hasAccess ? "Screen Recording enabled" : "Screen Recording required")
                    Spacer()
                    Button(isCheckingPermission ? "Checking…" : "Refresh") {
                        Task { await refreshPermission() }
                    }
                    .disabled(isCheckingPermission)
                }
                Button("Open System Settings") {
                    PermissionManager.openScreenRecordingSettings()
                }
            } header: {
                Label("Privacy", systemImage: "lock.shield")
            }
        }
        .task { await refreshPermission() }
    }

    @MainActor
    private func refreshPermission() async {
        isCheckingPermission = true
        let granted = await PermissionManager.refreshAccessStatus()
        accessCache.lastKnownGranted = granted
        isCheckingPermission = false
    }
}

// MARK: - Capture (output + quick access)

private struct CaptureSettingsPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(
                title: "Capture",
                subtitle: "Where captures go and how the quick-access panel behaves",
                systemImage: "camera.viewfinder"
            )

            Section {
                Toggle("Include window shadow in window capture", isOn: $settings.captureWindowWithShadow)
                HStack {
                    Text("Save folder")
                    Spacer()
                    Text(settings.saveDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…") { chooseSaveFolder() }
                }
                Picker("Format", selection: $settings.format) {
                    ForEach(ScreenshotFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                if settings.format == .jpeg {
                    Slider(value: $settings.jpegQuality, in: 0.5...1.0) {
                        Text("JPEG quality")
                    }
                }
                TextField("Filename pattern", text: $settings.filenamePattern)
                Text("Tokens: {prefix}, {date}, {time}, {datetime}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Output", systemImage: "folder")
            }

            Section {
                Picker(OctoshotL10n.quickAccessPlacementTitle, selection: $settings.quickAccessPlacement) {
                    ForEach(QuickAccessPlacement.allCases) { placement in
                        Text(OctoshotL10n.quickAccessPlacementName(placement)).tag(placement)
                    }
                }
                Toggle(OctoshotL10n.quickAccessStackCaptures, isOn: $settings.quickAccessStackCaptures)
                HStack {
                    Text("Auto-close delay")
                    Slider(value: $settings.quickAccessAutoCloseSeconds, in: 0...120, step: 5)
                    Text(settings.quickAccessAutoCloseSeconds == 0 ? "Off" : "\(Int(settings.quickAccessAutoCloseSeconds))s")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } header: {
                Label("Quick access", systemImage: "photo.on.rectangle.angled")
            }

            Section {
                Toggle("Speculative smart actions", isOn: speculativeEnabledBinding)
                Text("After capture, classify on-device and pre-run the top suggested action in the background. Results are never copied until you tap Apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if speculativeEnabledBinding.wrappedValue {
                    HStack {
                        Text("Confidence threshold")
                        Slider(value: speculativeThresholdBinding, in: 0.25...0.85, step: 0.05)
                        Text("\(Int(speculativeThresholdBinding.wrappedValue * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text("LaTeX uses pix2tex then SmolVLM2; tables use SmolVLM2. Redaction and OCR stay on Apple Vision.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Smart actions", systemImage: "sparkles")
            }
        }
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }

    private var speculativeEnabledBinding: Binding<Bool> {
        Binding(
            get: { AppSettings.shared.speculativePostProcessingEnabled },
            set: { AppSettings.shared.speculativePostProcessingEnabled = $0 }
        )
    }

    private var speculativeThresholdBinding: Binding<Double> {
        Binding(
            get: { AppSettings.shared.speculativeConfidenceThreshold },
            set: { AppSettings.shared.speculativeConfidenceThreshold = $0 }
        )
    }
}

// MARK: - Annotation

private struct AnnotationSettingsPane: View {
    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(
                title: "Annotation",
                subtitle: "On-device redaction before you share a screenshot",
                systemImage: "pencil.and.outline"
            )
            RedactionSettingsPane()
        }
    }
}

// MARK: - Developer (+ Agent)

struct DeveloperSettingsPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(
                title: "Developer",
                subtitle: "Power-user tools and Agent / CLI install for MCP",
                systemImage: "hammer"
            )

            Section {
                Toggle("Developer mode", isOn: $settings.developerModeEnabled)
                Toggle("Use absolute path in Markdown snippets", isOn: $settings.markdownImageUseAbsolutePath)
                Text("Developer mode adds color picking during area capture, a ruler in Annotate, and Markdown/path copy actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }

            AgentSettingsPane()
        }
    }
}

// MARK: - About

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage(size: NSSize(width: 64, height: 64)))
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Octoshot")
                .font(.title.bold())
            Text("Version \(AppVersion.display)")
                .foregroundStyle(.secondary)
            Link("View on GitHub", destination: AppSettings.repositoryURL)
            Button(OctoshotL10n.checkForUpdates) {
                Updater.shared.checkForUpdates()
            }
            .buttonStyle(.bordered)
            Button("Open User Guide") {
                HelpOpener.open()
            }
            .buttonStyle(.bordered)
            Text("Released under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Embedded AI weights: SmolVLM2 (Apache-2.0, mlx-community) and pix2tex-mfr GGUF (MIT, cstr). MLX Swift LM is Apache-2.0.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

extension Notification.Name {
    static let octoshotOpenSettingsSection = Notification.Name("OctoshotOpenSettingsSection")
}
