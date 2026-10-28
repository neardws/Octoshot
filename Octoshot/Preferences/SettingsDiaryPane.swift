import SwiftUI
import OctoshotCore

struct SettingsDiaryPane: View {
    @ObservedObject var model: DiaryReportCoordinator = .shared
    var preview: DiaryOllamaPreview?
    @State private var configuration = DiaryOllamaConfiguration.load()
    @State private var ollamaStatus: DiaryOllamaStatus = .notRunning
    @State private var busy = false
    @State private var message: String?
    @State private var failureReason: String?

    private var currentStatus: DiaryOllamaStatus { preview?.status ?? ollamaStatus }
    private let pullCommand = "ollama pull openbmb/minicpm-v4.7:1b"

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(title: OctoshotL10n.text("Yijiang Diary"),
                               subtitle: OctoshotL10n.text("A local diary, with eight helping hands"),
                               systemImage: "book.closed")
            Toggle(OctoshotL10n.text("Enable diary"), isOn: binding(\.enabled))
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
            Text(OctoshotL10n.text("Yijiang roast · Local Ollama (optional)")).font(.headline)
            Text(OctoshotL10n.text("Install Ollama ≥ 0.40.5 yourself, then pull MiniCPM-V 4.7 1B (about 1.8GB, Q4_K_M). Octoshot never installs Ollama or downloads this model. Ask AI keeps SmolVLM2."))
                .font(.callout).foregroundStyle(.secondary)
            Toggle(OctoshotL10n.text("Add Yijiang roasts"), isOn: $model.roastEnabled)
            TextField(OctoshotL10n.text("Local Ollama address"), text: $configuration.baseURL)
                .disabled(busy)
            TextField(OctoshotL10n.text("Ollama model (include tag)"), text: $configuration.model)
                .disabled(busy)
            Text(OctoshotL10n.text("Only loopback addresses are allowed. Default: openbmb/minicpm-v4.7:1b; do not use latest (22GB)."))
                .font(.caption).foregroundStyle(.secondary)
            Text(statusText).font(.callout).textSelection(.enabled)
            HStack {
                Link(OctoshotL10n.text("Open Ollama download page"), destination: URL(string: "https://ollama.com/download")!)
                Button(OctoshotL10n.text("Check again")) { check() }.disabled(busy)
                Button(OctoshotL10n.text("Test one roast")) { testRoast() }
                    .disabled(busy || currentStatus != .ready || (preview?.failureReason ?? failureReason ?? model.roastFailureReason) != nil)
            }
            HStack {
                Text(pullCommand).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button(OctoshotL10n.text("Copy command")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("ollama pull openbmb/minicpm-v4.7:1b", forType: .string)
                }
            }
            if busy { ProgressView() }
            if let message = preview?.message ?? message { Text(message).font(.callout).textSelection(.enabled) }
            if let reason = preview?.failureReason ?? failureReason ?? model.roastFailureReason {
                Text(reason).font(.callout).foregroundStyle(.orange)
            }
            Text(OctoshotL10n.text("Ollama receives only the AX/OCR skeleton and an optional existing key frame on this Mac. Three consecutive failures disable roasts for today; rule-based roasts and text reports remain available."))
                .font(.caption).foregroundStyle(.secondary)
            Text(OctoshotL10n.text("Diary stays on this Mac, encrypted and never uploaded. Markdown exports are unencrypted."))
                .font(.callout).foregroundStyle(.secondary)
            Text(OctoshotL10n.text("This milestone reads existing records without starting live capture. Missing roasts never block a text report."))
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
        .onAppear { if preview == nil { check() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            if preview == nil { failureReason = model.roastFailureReason }
        }
        .onChange(of: configuration) { _, value in
            guard preview == nil else { return }
            value.save()
            ollamaStatus = .notRunning
            message = OctoshotL10n.text("Address or model changed. Check again before testing.")
        }
    }

    private var statusText: String {
        switch currentStatus {
        case .notRunning: return OctoshotL10n.text("Ollama is not installed or not running.")
        case .versionTooOld(let found): return OctoshotL10n.format("Ollama %@ is too old; version 0.40.5 or later is required.", found)
        case .modelMissing: return OctoshotL10n.text("Ollama is running; the configured model has not been pulled.")
        case .ready: return OctoshotL10n.text("Ollama is ready; the configured model is available.")
        case .error(let reason): return OctoshotL10n.format("Ollama check failed: %@", reason)
        }
    }

    private func check() {
        guard preview == nil else { return }
        busy = true
        message = nil
        let client = DiaryOllamaClient(configuration: configuration)
        Task { @MainActor in
            defer { busy = false }
            ollamaStatus = await client.detect()
            failureReason = model.roastFailureReason
        }
    }

    private func testRoast() {
        guard preview == nil else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            let start = Date()
            let aggregator = DiaryWindowAggregator(clock: { start.addingTimeInterval(600) })
            do {
                _ = try aggregator.append(DiaryActivitySample(timestamp: start, appBundleID: "example",
                    appName: "示例应用", windowTitle: "日记设置测试", focusedText: "这是合成测试骨架，不读取屏幕"))
                let windows = try aggregator.observe(nil, at: start.addingTimeInterval(600))
                let service = DiaryOllamaRuntime.service
                let roasts = await service.prepare(windows: windows)
                message = service.lastFailureReason.map { OctoshotL10n.format("Ollama test failed; using a rule-based roast: %@", $0) }
                    ?? windows.first.flatMap { roasts.roast(for: $0) }
                failureReason = service.disabledReason
            } catch { message = error.localizedDescription }
        }
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

struct DiaryOllamaPreview {
    var status: DiaryOllamaStatus = .notRunning
    var message: String?
    var failureReason: String?
}
