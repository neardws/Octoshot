import AppKit
import Foundation

public protocol YijiangDiaryFrameCaptioning: Sendable {
    func caption(image: NSImage, context: YijiangDiaryCaptionContext) async throws -> String
}

/// Deterministic captions for CI and unit tests (no MLX weights).
public struct StubYijiangDiaryCaptioner: YijiangDiaryFrameCaptioning {
    public init() {}

    public func caption(image: NSImage, context: YijiangDiaryCaptionContext) async throws -> String {
        let app = context.frontmostApp ?? "未知应用"
        let snippet = context.textPreview
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(96)
        if snippet.isEmpty {
            return "[stub] \(app)：画面没啥字，一酱只能靠猜。"
        }
        return "[stub] \(app)：\(snippet)"
    }
}

/// Uses existing `AgentProcessing` / SmolVLM2 when embedded vision is registered and installed.
public struct SmolVLMYijiangDiaryCaptioner: YijiangDiaryFrameCaptioning {
    public init() {}

    public func caption(image: NSImage, context: YijiangDiaryCaptionContext) async throws -> String {
        let prompt = """
        你是 Octoshot 吉祥物「一酱」，写一句简短的中文活动摘要（不超过 80 字），语气毒舌但靠谱。
        时间：\(context.windowStart) – \(context.windowEnd)
        前台应用：\(context.frontmostApp ?? "未知")
        屏幕文字摘录：
        \(context.textPreview)
        只输出摘要一句，不要列表。
        """
        return try await AgentProcessing.askAI(image: image, prompt: prompt)
    }
}
