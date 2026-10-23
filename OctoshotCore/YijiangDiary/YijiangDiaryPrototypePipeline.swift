import AppKit
import Foundation

public enum YijiangDiaryPrototypePipeline {
    public struct Options: Sendable {
        public var windowMinutes: Int
        public var day: Date?
        public var calendar: Calendar

        public init(windowMinutes: Int = 10, day: Date? = nil, calendar: Calendar = .current) {
            self.windowMinutes = windowMinutes
            self.day = day
            self.calendar = calendar
        }
    }

    public static func run(
        inputDirectory: URL,
        captioner: YijiangDiaryFrameCaptioning,
        options: Options = .init()
    ) async throws -> YijiangDiaryPrototypeResult {
        let frames = try YijiangDiaryFrameLoader.loadFrames(from: inputDirectory)
        var snapshots: [YijiangDiaryFrameSnapshot] = []
        for frame in frames {
            let resolved = await resolveText(for: frame)
            snapshots.append(resolved)
        }
        let keyframeIndices = YijiangDiaryKeyframeSelector.selectKeyframeIndices(from: snapshots)
        let keyframeSet = Set(keyframeIndices)

        var entries: [YijiangDiaryWindowEntry] = []
        for (index, snapshot) in snapshots.enumerated() {
            entries.append(YijiangDiaryWindowEntry(
                timestamp: snapshot.frame.timestamp,
                frontmostApp: snapshot.frame.frontmostApp,
                textPreview: snapshot.resolvedText,
                textSource: snapshot.textSource,
                vlmCaption: nil,
                isKeyframe: keyframeSet.contains(index)
            ))
        }

        let preliminaryWindows = YijiangDiaryWindowing.assignWindows(
            to: entries,
            windowMinutes: options.windowMinutes,
            calendar: options.calendar
        )

        var captionedEntries = entries
        for window in preliminaryWindows {
            guard let repIndex = YijiangDiaryWindowing.representativeKeyframeIndex(
                in: snapshots,
                keyframeIndices: keyframeIndices,
                windowStart: window.start,
                windowEnd: window.end
            ) else { continue }
            let snapshot = snapshots[repIndex]
            let image = try AgentCaptureEngine.loadImage(path: snapshot.frame.imageURL.path)
            let mergedText = window.entries.map(\.textPreview).joined(separator: "\n")
            let context = YijiangDiaryCaptionContext(
                windowStart: window.start,
                windowEnd: window.end,
                frontmostApp: snapshot.frame.frontmostApp,
                textPreview: mergedText,
                ocrLines: mergedText.split(separator: "\n").map(String.init)
            )
            let caption = try await captioner.caption(image: image, context: context)
            if let entryIndex = captionedEntries.firstIndex(where: { $0.timestamp == snapshot.frame.timestamp }) {
                let old = captionedEntries[entryIndex]
                captionedEntries[entryIndex] = YijiangDiaryWindowEntry(
                    timestamp: old.timestamp,
                    frontmostApp: old.frontmostApp,
                    textPreview: old.textPreview,
                    textSource: old.textSource,
                    vlmCaption: caption,
                    isKeyframe: true
                )
            }
        }

        let windows = YijiangDiaryWindowing.assignWindows(
            to: captionedEntries,
            windowMinutes: options.windowMinutes,
            calendar: options.calendar
        )
        let day = options.day ?? frames.first?.timestamp ?? Date()
        let digest = YijiangDiaryDigestBuilder.buildDigest(windows: windows, day: day, calendar: options.calendar)
        return YijiangDiaryPrototypeResult(
            windows: windows,
            digestMarkdown: digest,
            keyframeCount: keyframeIndices.count,
            frameCount: frames.count
        )
    }

    private static func resolveText(for frame: YijiangDiaryFrame) async -> YijiangDiaryFrameSnapshot {
        if let ax = frame.accessibilityText?.trimmingCharacters(in: .whitespacesAndNewlines), !ax.isEmpty {
            return YijiangDiaryFrameSnapshot(frame: frame, resolvedText: ax, textSource: .accessibility)
        }
        do {
            let image = try AgentCaptureEngine.loadImage(path: frame.imageURL.path)
            let ocr = try await OCRService.recognizeText(in: image)
            let text = ocr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return YijiangDiaryFrameSnapshot(frame: frame, resolvedText: "", textSource: .none)
            }
            return YijiangDiaryFrameSnapshot(frame: frame, resolvedText: text, textSource: .ocr)
        } catch {
            return YijiangDiaryFrameSnapshot(frame: frame, resolvedText: "", textSource: .none)
        }
    }
}
