import AppKit
import Vision
import OctoshotCore

enum CaptureContentKind: String, Codable, CaseIterable {
    case formula
    case table
    case sensitive
    case code
    case plain

    var displayName: String {
        switch self {
        case .formula: return "Formula → LaTeX"
        case .table: return "Extract Table"
        case .sensitive: return "Redact Sensitive Data"
        case .code: return "Copy Code Text"
        case .plain: return "Screenshot"
        }
    }

    var systemImage: String {
        switch self {
        case .formula: return "function"
        case .table: return "tablecells"
        case .sensitive: return "eye.slash"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .plain: return "photo"
        }
    }
}

struct CaptureContentClassification: Codable {
    let kind: CaptureContentKind
    let confidence: Double
    let scores: [String: Double]
    let timestamp: Date
}

enum CaptureContentClassifier {
    @MainActor
    static func classify(image: NSImage) async -> CaptureContentClassification {
        let text = await recognizeText(image: image) ?? ""
        let rectangleScore = rectangleTableScore(image: image)
        let sensitiveScore = await sensitiveScore(image: image)
        let formulaScore = formulaScore(text: text)
        let codeScore = codeScore(text: text)
        let plainScore = max(0.15, 1.0 - max(formulaScore, rectangleScore, sensitiveScore, codeScore) * 0.85)

        let scores: [CaptureContentKind: Double] = [
            .formula: formulaScore,
            .table: rectangleScore,
            .sensitive: sensitiveScore,
            .code: codeScore,
            .plain: plainScore
        ]
        let top = scores.max(by: { $0.value < $1.value }) ?? (.plain, plainScore)
        let confidence = normalizedConfidence(top.value, scores: scores)

        let result = CaptureContentClassification(
            kind: top.key,
            confidence: confidence,
            scores: scores.mapKeys { $0.rawValue },
            timestamp: Date()
        )
        return result
    }

    private static func normalizedConfidence(_ top: Double, scores: [CaptureContentKind: Double]) -> Double {
        let sum = scores.values.reduce(0, +)
        guard sum > 0 else { return 0 }
        return min(1, max(0, top / sum))
    }

    private static func formulaScore(text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let mathSymbols = ["∑", "∫", "√", "π", "α", "β", "γ", "θ", "λ", "μ", "σ", "∞", "±", "÷", "×", "\\frac", "\\int"]
        let symbolHits = mathSymbols.filter { text.contains($0) }.count
        let hasEquals = text.contains("=")
        let digitRatio = Double(text.filter { $0.isNumber }.count) / Double(text.count)
        var score = Double(symbolHits) * 0.22
        if hasEquals && text.count < 500 { score += 0.35 }
        if digitRatio > 0.12 && text.count < 400 { score += 0.2 }
        return min(1, score)
    }

    private static func codeScore(text: String) -> Double {
        guard text.count > 20 else { return 0 }
        let keywords = ["func ", "class ", "import ", "return ", "const ", "let ", "var ", "def ", "public ", "private ", "{", "}", "();", "=>"]
        let hits = keywords.filter { text.contains($0) }.count
        let punct = Double(text.filter { "{}[]();".contains($0) }.count) / Double(text.count)
        var score = Double(hits) * 0.12 + punct * 1.2
        if text.contains("\n") && text.split(separator: "\n").count > 3 { score += 0.15 }
        return min(1, score)
    }

    private static func rectangleTableScore(image: NSImage) -> Double {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.45
        request.maximumObservations = 24
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        let count = request.results?.count ?? 0
        if count >= 8 { return 0.95 }
        if count >= 4 { return 0.72 }
        if count >= 2 { return 0.35 }
        return 0
    }

    private static func sensitiveScore(image: NSImage) async -> Double {
        do {
            let candidates = try await RedactionDetector.detect(in: image, settings: AgentConfiguration.redactionSettings())
            let enabled = candidates.filter(\.isEnabled).count
            if enabled >= 3 { return 0.92 }
            if enabled >= 1 { return 0.68 }
        } catch {}
        return 0
    }

    private static func recognizeText(image: NSImage) async -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await Task.detached { () -> String? in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                let strings = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                return strings.joined(separator: "\n")
            } catch {
                return nil
            }
        }.value
    }
}

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}

enum ClassificationLog {
    private static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Octoshot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("classification-log.jsonl")
    }

    static func append(_ classification: CaptureContentClassification, speculativeStarted: Bool = false) {
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: classification.timestamp),
            "kind": classification.kind.rawValue,
            "confidence": classification.confidence,
            "scores": classification.scores,
            "speculativeStarted": speculativeStarted
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8) else { return }
        let out = line + "\n"
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(out.data(using: .utf8)!)
                try? handle.close()
            }
        } else {
            try? out.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
