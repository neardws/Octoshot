import Foundation

public struct YijiangDiaryFrame: Sendable, Equatable {
    public let timestamp: Date
    public let imageURL: URL
    public let frontmostApp: String?
    public let accessibilityText: String?

    public init(timestamp: Date, imageURL: URL, frontmostApp: String?, accessibilityText: String?) {
        self.timestamp = timestamp
        self.imageURL = imageURL
        self.frontmostApp = frontmostApp
        self.accessibilityText = accessibilityText
    }
}

public enum YijiangDiaryTextSource: String, Sendable, Codable {
    case accessibility
    case ocr
    case none
}

public struct YijiangDiaryFrameSnapshot: Sendable, Equatable {
    public let frame: YijiangDiaryFrame
    public let resolvedText: String
    public let textSource: YijiangDiaryTextSource

    public init(frame: YijiangDiaryFrame, resolvedText: String, textSource: YijiangDiaryTextSource) {
        self.frame = frame
        self.resolvedText = resolvedText
        self.textSource = textSource
    }
}

public struct YijiangDiaryWindowEntry: Sendable, Equatable {
    public let timestamp: Date
    public let frontmostApp: String?
    public let textPreview: String
    public let textSource: YijiangDiaryTextSource
    public let vlmCaption: String?
    public let isKeyframe: Bool

    public init(
        timestamp: Date,
        frontmostApp: String?,
        textPreview: String,
        textSource: YijiangDiaryTextSource,
        vlmCaption: String?,
        isKeyframe: Bool
    ) {
        self.timestamp = timestamp
        self.frontmostApp = frontmostApp
        self.textPreview = textPreview
        self.textSource = textSource
        self.vlmCaption = vlmCaption
        self.isKeyframe = isKeyframe
    }
}

public struct YijiangDiaryTimelineWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let entries: [YijiangDiaryWindowEntry]

    public init(start: Date, end: Date, entries: [YijiangDiaryWindowEntry]) {
        self.start = start
        self.end = end
        self.entries = entries
    }
}

public struct YijiangDiaryCaptionContext: Sendable {
    public let windowStart: Date
    public let windowEnd: Date
    public let frontmostApp: String?
    public let textPreview: String
    public let ocrLines: [String]

    public init(
        windowStart: Date,
        windowEnd: Date,
        frontmostApp: String?,
        textPreview: String,
        ocrLines: [String]
    ) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.frontmostApp = frontmostApp
        self.textPreview = textPreview
        self.ocrLines = ocrLines
    }
}

public struct YijiangDiaryPrototypeResult: Sendable {
    public let windows: [YijiangDiaryTimelineWindow]
    public let digestMarkdown: String
    public let keyframeCount: Int
    public let frameCount: Int

    public init(windows: [YijiangDiaryTimelineWindow], digestMarkdown: String, keyframeCount: Int, frameCount: Int) {
        self.windows = windows
        self.digestMarkdown = digestMarkdown
        self.keyframeCount = keyframeCount
        self.frameCount = frameCount
    }
}
