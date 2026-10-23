import AppKit
import Foundation
import OctoshotCore
import OctoshotEmbeddedMLX

enum YijiangDiaryPrototypeCommand {
    static func run(_ args: [String]) async throws {
        guard args.contains("--developer") else {
            throw CaptureError.captureFailed(
                "yijiang-diary-prototype is developer-only. Pass --developer (enable Developer mode in the app for UI features)."
            )
        }
        guard let inputPath = value(for: "--input", in: args) else {
            throw CaptureError.captureFailed("--input DIR required (folder of timestamped PNGs)")
        }
        let inputURL = URL(fileURLWithPath: inputPath, isDirectory: true)
        let outputPath = value(for: "--output", in: args)
            ?? inputURL.appendingPathComponent("yijiang-digest.md").path
        let captionerName = value(for: "--captioner", in: args) ?? "stub"
        let windowMinutes = Int(value(for: "--window-minutes", in: args) ?? "10") ?? 10

        let captioner: YijiangDiaryFrameCaptioning
        switch captionerName.lowercased() {
        case "stub":
            captioner = StubYijiangDiaryCaptioner()
        case "smolvlm", "smolvlm2", "mlx":
            await MainActor.run { registerMLXVisionBackend() }
            captioner = SmolVLMYijiangDiaryCaptioner()
        default:
            throw CaptureError.captureFailed("Unknown --captioner \(captionerName). Use stub or smolvlm.")
        }

        let started = Date()
        let result = try await YijiangDiaryPrototypePipeline.run(
            inputDirectory: inputURL,
            captioner: captioner,
            options: .init(windowMinutes: max(1, windowMinutes))
        )
        try result.digestMarkdown.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        let elapsed = Date().timeIntervalSince(started)
        printJSON([
            "output": outputPath,
            "frames": result.frameCount,
            "keyframes": result.keyframeCount,
            "windows": result.windows.count,
            "captioner": captionerName,
            "elapsedSeconds": elapsed,
        ])
    }

    @MainActor
    private static func registerMLXVisionBackend() {
        if EmbeddedAIProvider.vision == nil {
            EmbeddedAIProvider.vision = MLXEmbeddedVisionBackend.shared
        }
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func printJSON(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
