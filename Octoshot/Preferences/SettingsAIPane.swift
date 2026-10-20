import AppKit
import SwiftUI
import OctoshotCore

struct SettingsAIPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var latexPrompt = ""
    @State private var clipsPath = ""
    @State private var ollamaModels: [OllamaModel] = []
    @State private var ollamaStatus = OctoshotL10n.text("Not checked")
    @State private var isChecking = false
    @State private var ollamaReachable = false
    @State private var isPulling = false
    @State private var pullStatus = ""
    @State private var downloadStatus: [EmbeddedModelID: String] = [:]
    @State private var downloadFraction: [EmbeddedModelID: Double] = [:]
    @State private var downloading: EmbeddedModelID?

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(
                title: OctoshotL10n.text("AI"),
                subtitle: OctoshotL10n.text("On-device SmolVLM2 + pix2tex LaTeX specialist; optional Ollama fallback"),
                systemImage: "brain"
            )

            Section {
                Toggle(OctoshotL10n.text("Use on-device vision model (SmolVLM2)"), isOn: $settings.embeddedAIUseOnDeviceVLM)
                modelRow(.smolVLM2_500M_4bit)
                modelRow(.pix2texMFR_Q4)
                HStack {
                    Text(OctoshotL10n.text("LaTeX runtime (llama-mtmd-cli)"))
                    Spacer()
                    if Pix2TexLlamaRunner.llamaMtmdCLI() != nil {
                        Text(OctoshotL10n.text("Ready")).foregroundStyle(.green).font(.caption)
                    } else {
                        Button(OctoshotL10n.text("Install")) {
                            Task {
                                do {
                                    _ = try await LaTeXEngineInstaller.shared.ensureCLI()
                                } catch {
                                    downloadStatus[.pix2texMFR_Q4] = OctoshotL10n.settingsError(error)
                                }
                            }
                        }
                    }
                }
                Text(OctoshotL10n.format("Weights download to %@ and are never bundled in the app.", EmbeddedAIModelPaths.modelsRoot().path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(OctoshotL10n.text("Embedded models"), systemImage: "internaldrive")
            }

            Section {
                Toggle(OctoshotL10n.text("Ollama fallback (OpenAI-compatible)"), isOn: $settings.embeddedAIOllamaFallbackEnabled)
                HStack {
                    Circle()
                        .fill(ollamaReachable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(ollamaStatus)
                    Spacer()
                    Button(isChecking ? OctoshotL10n.text("Checking…") : OctoshotL10n.text("Test Ollama")) {
                        Task { await refreshOllama() }
                    }
                    .disabled(isChecking)
                }
                if settings.embeddedAIOllamaFallbackEnabled {
                    TextField(OctoshotL10n.text("Base URL"), text: $baseURL)
                    TextField(OctoshotL10n.text("Vision model"), text: $model)
                    SecureField(OctoshotL10n.text("API key (optional)"), text: $apiKey)
                    if !ollamaModels.isEmpty {
                        Picker(OctoshotL10n.text("Installed models"), selection: $model) {
                            ForEach(ollamaModels) { m in
                                Text(m.name).tag(m.name)
                            }
                        }
                    }
                    Button(isPulling ? OctoshotL10n.text("Pulling…") : OctoshotL10n.text("Pull qwen2.5vl")) {
                        Task { await pullRecommended() }
                    }
                    .disabled(isPulling)
                    if !pullStatus.isEmpty {
                        Text(pullStatus).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(OctoshotL10n.text("Enable only if you want cloud-free Ollama when embedded models are missing or MLX is unavailable."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label(OctoshotL10n.text("Ollama (optional)"), systemImage: "server.rack")
            }

            Section {
                TextField(OctoshotL10n.text("LaTeX prompt (VLM fallback)"), text: $latexPrompt, axis: .vertical)
                    .lineLimit(3...6)
                Text(OctoshotL10n.text("Formula mode uses pix2tex-mfr first, then SmolVLM2, then Ollama if enabled."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(OctoshotL10n.text("LaTeX"), systemImage: "function")
            }

            Section {
                HStack {
                    Text(clipsPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(OctoshotL10n.text("Choose…")) { chooseClipsFolder() }
                }
            } header: {
                Label(OctoshotL10n.text("Clips library"), systemImage: "photo.stack")
            }
        }
        .onAppear(perform: loadFields)
        .onDisappear(perform: persist)
        .onReceive(NotificationCenter.default.publisher(for: .octoshotModelDownloadProgress)) { note in
            guard let progress = note.object as? ModelDownloadProgress else { return }
            downloadFraction[progress.model] = progress.fraction
            downloadStatus[progress.model] = progress.status
            if progress.fraction >= 1 {
                downloading = nil
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ id: EmbeddedModelID) -> some View {
        let installed = EmbeddedAIModelPaths.isInstalled(id)
        let bytes = EmbeddedAIModelPaths.diskUsageBytes(for: id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: installed ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(installed ? .green : .secondary)
                Text(OctoshotL10n.modelName(id))
                Spacer()
                Text(installed ? byteString(bytes) : "~\(id.approximateSizeMB) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let status = downloadStatus[id], downloading == id || !status.isEmpty {
                ProgressView(value: downloadFraction[id] ?? 0)
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button(downloading == id ? OctoshotL10n.text("Downloading…") : (installed ? OctoshotL10n.text("Re-download") : OctoshotL10n.text("Download"))) {
                    Task { await downloadModel(id) }
                }
                .disabled(downloading != nil)
                if installed {
                    Button(OctoshotL10n.text("Delete")) {
                        try? ModelDownloadService.shared.delete(id)
                    }
                }
            }
            Text(OctoshotL10n.modelLicense(id)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func loadFields() {
        baseURL = settings.aiBaseURL.absoluteString
        model = settings.aiVisionModel
        apiKey = settings.aiAPIKey
        latexPrompt = settings.aiLatexPrompt == AIPrompts.latex ? OctoshotL10n.latexDefaultPrompt : settings.aiLatexPrompt
        clipsPath = settings.clipsLibraryDirectory.path
        if !OctoshotL10n.isSettingsSnapshot {
            Task { await refreshOllama() }
        }
    }

    private func persist() {
        guard !OctoshotL10n.isSettingsSnapshot else { return }
        if let url = URL(string: baseURL) { settings.aiBaseURL = url }
        settings.aiVisionModel = model
        settings.aiAPIKey = apiKey
        settings.aiLatexPrompt = latexPrompt == OctoshotL10n.latexDefaultPrompt ? AIPrompts.latex : latexPrompt
    }

    @MainActor
    private func downloadModel(_ id: EmbeddedModelID) async {
        downloading = id
        downloadStatus[id] = OctoshotL10n.text("Starting…")
        do {
            try await ModelDownloadService.shared.download(id)
            downloadStatus[id] = OctoshotL10n.text("Ready")
        } catch {
            downloadStatus[id] = OctoshotL10n.settingsError(error)
            downloading = nil
        }
    }

    @MainActor
    private func refreshOllama() async {
        guard !OctoshotL10n.isSettingsSnapshot else { return }
        isChecking = true
        defer { isChecking = false }
        persist()
        if let models = await OllamaService.listModels(baseURL: settings.aiBaseURL) {
            ollamaReachable = true
            ollamaModels = models
            ollamaStatus = models.isEmpty
                ? OctoshotL10n.text("Connected to Ollama — no models yet.")
                : OctoshotL10n.format("Connected — %d model(s).", models.count)
        } else {
            ollamaReachable = false
            ollamaModels = []
            ollamaStatus = OctoshotL10n.text("Ollama not reachable.")
        }
    }

    @MainActor
    private func pullRecommended() async {
        isPulling = true
        pullStatus = ""
        defer { isPulling = false }
        do {
            try await OllamaService.pullModel("qwen2.5vl", baseURL: settings.aiBaseURL) { status in
                Task { @MainActor in pullStatus = OctoshotL10n.ollamaPullStatus(status) }
            }
            model = "qwen2.5vl:latest"
            settings.aiVisionModel = model
            pullStatus = OctoshotL10n.text("Pull finished.")
            await refreshOllama()
        } catch {
            pullStatus = error.localizedDescription
        }
    }

    private func chooseClipsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = settings.clipsLibraryDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.clipsLibraryDirectory = url
            clipsPath = url.path
        }
    }
}
