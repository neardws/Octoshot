import AppKit
import OctoshotCore

enum SpeculativeResult {
    case latex(String)
    case tableMarkdown(String)
    case redactedImage(NSImage)
    case codeText(String)

    var pasteboardString: String? {
        switch self {
        case .latex(let s), .tableMarkdown(let s), .codeText(let s): return s
        case .redactedImage: return nil
        }
    }
}

@MainActor
final class SpeculativeActionState: ObservableObject {
    enum Phase {
        case hidden
        case classifying
        case running(kind: CaptureContentKind, detail: String)
        case ready(kind: CaptureContentKind, result: SpeculativeResult)
        case suggestionOnly(kind: CaptureContentKind, reason: String)
        case failed(String)
    }

    @Published var phase: Phase = .hidden
    @Published var classification: CaptureContentClassification?

    fileprivate var workTask: Task<Void, Never>?
}

@MainActor
final class SpeculativeCapturePipeline {
    static let shared = SpeculativeCapturePipeline()

    private var tasks: [UUID: Task<Void, Never>] = [:]

    func start(entryID: UUID, image: NSImage, state: SpeculativeActionState) {
        cancel(entryID: entryID)
        let task = Task { await run(entryID: entryID, image: image, state: state) }
        tasks[entryID] = task
        state.workTask = task
    }

    func cancel(entryID: UUID) {
        tasks[entryID]?.cancel()
        tasks[entryID] = nil
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func run(entryID: UUID, image: NSImage, state: SpeculativeActionState) async {
        let settings = AppSettings.shared
        guard settings.speculativePostProcessingEnabled else {
            state.phase = .hidden
            return
        }

        state.phase = .classifying
        let classification = await CaptureContentClassifier.classify(image: image)
        state.classification = classification

        guard classification.confidence >= settings.speculativeConfidenceThreshold else {
            state.phase = .suggestionOnly(
                kind: classification.kind,
                reason: "Low confidence (\(Int(classification.confidence * 100))%)"
            )
            ClassificationLog.append(classification, speculativeStarted: false)
            return
        }

        guard classification.kind != .plain else {
            state.phase = .hidden
            ClassificationLog.append(classification, speculativeStarted: false)
            return
        }

        ClassificationLog.append(classification, speculativeStarted: true)
        state.phase = .running(kind: classification.kind, detail: "Starting…")

        if Task.isCancelled { return }

        do {
            let result = try await perform(kind: classification.kind, image: image, state: state)
            if Task.isCancelled { return }
            state.phase = .ready(kind: classification.kind, result: result)
        } catch is CancellationError {
            state.phase = .hidden
        } catch {
            if Task.isCancelled { return }
            state.phase = .failed(error.localizedDescription)
        }
    }

    private func perform(
        kind: CaptureContentKind,
        image: NSImage,
        state: SpeculativeActionState
    ) async throws -> SpeculativeResult {
        switch kind {
        case .formula:
            return try await performLaTeX(image: image, state: state)
        case .table:
            return try await performTable(image: image, state: state)
        case .sensitive:
            return try await performRedact(image: image, state: state)
        case .code:
            return try await performCode(image: image, state: state)
        case .plain:
            throw CancellationError()
        }
    }

    private func performLaTeX(image: NSImage, state: SpeculativeActionState) async throws -> SpeculativeResult {
        state.phase = .running(kind: .formula, detail: "Converting to LaTeX…")
        let prompt = AppSettings.shared.aiLatexPrompt
        do {
            let latex = try await AgentProcessing.toLaTeX(image: image, prompt: prompt)
            return .latex(latex)
        } catch {
            if case EmbeddedAIError.modelNotInstalled = error {
                state.phase = .suggestionOnly(kind: .formula, reason: "Download LaTeX or VLM models in Settings → AI")
                throw CancellationError()
            }
            throw error
        }
    }

    private func performTable(image: NSImage, state: SpeculativeActionState) async throws -> SpeculativeResult {
        state.phase = .running(kind: .table, detail: "Extracting table…")
        do {
            let markdown = try await AgentProcessing.extractTable(image: image)
            return .tableMarkdown(markdown)
        } catch {
            if case EmbeddedAIError.modelNotInstalled = error {
                state.phase = .suggestionOnly(kind: .table, reason: "Download the on-device VLM in Settings → AI")
                throw CancellationError()
            }
            throw error
        }
    }

    private func performRedact(image: NSImage, state: SpeculativeActionState) async throws -> SpeculativeResult {
        state.phase = .running(kind: .sensitive, detail: "Detecting sensitive data…")
        let candidates = try await RedactionDetector.detect(in: image, settings: AgentConfiguration.redactionSettings())
        let enabled = candidates.filter(\.isEnabled)
        let redacted = try RedactionCompositor.apply(enabled, to: image)
        return .redactedImage(redacted)
    }

    private func performCode(image: NSImage, state: SpeculativeActionState) async throws -> SpeculativeResult {
        state.phase = .running(kind: .code, detail: "Reading code…")
        let ocr = try await OCRService.recognizeText(in: image)
        guard !ocr.text.isEmpty else { throw CaptureError.captureFailed("No text detected") }
        return .codeText(ocr.text)
    }
}
