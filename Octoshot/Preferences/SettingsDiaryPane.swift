import SwiftUI
import OctoshotCore

struct SettingsDiaryPane: View {
    @ObservedObject var model: DiaryReportCoordinator = .shared
    @ObservedObject private var downloads = ModelDownloadService.shared
    var preview: DiaryModelPreview?
    @State private var installed = EmbeddedAIModelPaths.isInstalled(.miniCPMV46_4bit)
    @State private var downloading = false
    @State private var fraction = 0.0
    @State private var status: String?
    @State private var showRoastChoice = false
    @State private var day = Calendar.current.startOfDay(for: Date())

    private var hasModel: Bool { preview?.installed ?? installed }
    private var isDownloading: Bool { preview?.downloading ?? (downloading || downloads.active == .miniCPMV46_4bit) }

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(title: OctoshotL10n.text("Yijiang Diary"),
                               subtitle: OctoshotL10n.text("A local diary, with eight helping hands"),
                               systemImage: "book.closed")
            Toggle(OctoshotL10n.text("Enable diary"), isOn: Binding(get: { model.settings.enabled }, set: { enabled in
                var settings = model.settings
                settings.enabled = enabled
                model.update(settings)
                if enabled && !hasModel { showRoastChoice = true }
            }))
            DatePicker(OctoshotL10n.text("Daily report time"), selection: time, displayedComponents: .hourAndMinute)
            Picker(OctoshotL10n.text("Keep diary records"), selection: binding(\.retentionDays)) {
                Text(OctoshotL10n.text("7 days")).tag(Int?.some(7))
                Text(OctoshotL10n.text("30 days")).tag(Int?.some(30))
                Text(OctoshotL10n.text("90 days")).tag(Int?.some(90))
                Text(OctoshotL10n.text("Forever")).tag(Int?.none)
            }
            Button(OctoshotL10n.text("Read today's diary")) { model.open(day: Date()) }
                .disabled(model.buildingReport)
            if model.buildingReport { ProgressView(OctoshotL10n.text("Preparing diary; text remains available if roasting fails…")) }
            Text(OctoshotL10n.text("Yijiang roast · MiniCPM (optional)")).font(.headline)
            Text(OctoshotL10n.text("MiniCPM-V-4.6 · About 2.2GB · Apache-2.0\nDiary only; Ask AI keeps SmolVLM2. Weights are not bundled."))
                .font(.callout).foregroundStyle(.secondary)
            Text(DiaryMiniCPMRuntime.compatibilityNote).font(.callout).foregroundStyle(.orange)
            if hasModel {
                Toggle(OctoshotL10n.text("Add Yijiang roasts"), isOn: $model.roastEnabled)
                Text(OctoshotL10n.text("MiniCPM installed")).foregroundStyle(.secondary)
                Button(OctoshotL10n.text("Delete MiniCPM model"), role: .destructive) { deleteModel() }
                    .disabled(isDownloading || model.buildingReport)
            } else {
                Button(OctoshotL10n.text("Download MiniCPM for Yijiang roasts (about 2.2GB)")) { download() }
                    .disabled(isDownloading)
                Text(OctoshotL10n.text("Text diary works without a download. Resume later without downloading verified files again."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isDownloading { ProgressView(value: preview?.fraction ?? fraction) }
            if let message = preview?.status ?? status { Text(message).font(.callout).textSelection(.enabled) }
            if let available = try? DiaryModelDownload.availableBytes(at: FileManager.default.homeDirectoryForCurrentUser) {
                Text(OctoshotL10n.format("Free space: %@; an extra 512MB is reserved before downloading.",
                                       ByteCountFormatter.string(fromByteCount: available, countStyle: .file)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let reason = preview?.failureReason ?? model.roastFailureReason ?? DiaryMiniCPMRuntime.service.disabledReason {
                Text(reason).font(.callout).foregroundStyle(.orange).id(day)
            }
            Text(OctoshotL10n.text("Diary stays on this Mac, encrypted and never uploaded. Markdown exports are unencrypted."))
                .font(.callout).foregroundStyle(.secondary)
            Text(OctoshotL10n.text("This milestone reads existing records without starting live capture. Missing roasts never block a text report."))
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .octoshotModelDownloadProgress)) { notification in
            guard let progress = notification.object as? ModelDownloadProgress, progress.model == .miniCPMV46_4bit else { return }
            fraction = progress.fraction
            status = progress.status
        }
        .onAppear {
            installed = EmbeddedAIModelPaths.isInstalled(.miniCPMV46_4bit)
            if let progress = downloads.latestProgress, progress.model == .miniCPMV46_4bit {
                fraction = progress.fraction
                status = progress.status
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
            let today = Calendar.current.startOfDay(for: now)
            if day != today { day = today }
        }
        .confirmationDialog(OctoshotL10n.text("Diary is enabled. The roast model can be downloaded later."), isPresented: $showRoastChoice) {
            Button(OctoshotL10n.text("Text diary only")) { model.roastEnabled = false }
            Button(OctoshotL10n.text("Download MiniCPM for Yijiang roasts (about 2.2GB)")) { download() }
        }
    }

    private func download() {
        downloading = true
        status = nil
        Task { @MainActor in
            defer { downloading = false; installed = EmbeddedAIModelPaths.isInstalled(.miniCPMV46_4bit) }
            do {
                try await ModelDownloadService.shared.download(.miniCPMV46_4bit)
                model.roastEnabled = true
            } catch { status = error.localizedDescription }
        }
    }

    private func deleteModel() {
        do {
            try DiaryMiniCPMRuntime.loader.unload(modelDirectory: EmbeddedAIModelPaths.directory(for: .miniCPMV46_4bit))
            try ModelDownloadService.shared.delete(.miniCPMV46_4bit)
            model.roastEnabled = false
            installed = false
        } catch { status = error.localizedDescription }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<DiarySettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in
            var settings = model.settings
            settings[keyPath: keyPath] = value
            model.update(settings)
        })
    }

    private var time: Binding<Date> {
        Binding(get: {
            let parts = model.settings.dailyReportTime.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var settings = model.settings
            settings.dailyReportTime = String(format: "%02d:%02d", parts.hour!, parts.minute!)
            model.update(settings)
        })
    }
}

struct DiaryModelPreview {
    var installed = false
    var downloading = false
    var fraction = 0.0
    var status: String?
    var failureReason: String?
}
