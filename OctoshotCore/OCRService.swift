import AppKit
import Vision

public enum OCRService {
    public static func recognizeText(in image: NSImage) async throws -> AgentOCRResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return result(from: [])
        }
        return try await recognizeText { request in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
        }
    }

    internal static func recognizeText(
        perform: @escaping @Sendable (VNRequest) throws -> Void
    ) async throws -> AgentOCRResult {
        try await Task.detached {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            try perform(request)
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return result(from: lines)
        }.value
    }

    internal static func result(from lines: [String]) -> AgentOCRResult {
        AgentOCRResult(text: lines.joined(separator: "\n"), lines: lines)
    }
}
