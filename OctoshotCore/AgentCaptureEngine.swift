import AppKit
import ScreenCaptureKit

public enum AgentCaptureMode: String, Sendable {
    case fullscreen
    case display
    case window
    case region
}

public struct AgentCaptureOptions: Sendable {
    public var mode: AgentCaptureMode
    public var displayID: UInt32?
    public var windowID: UInt32?
    public var region: CGRect?
    public var outputPath: URL?
    public var includeBase64: Bool

    public init(
        mode: AgentCaptureMode,
        displayID: UInt32? = nil,
        windowID: UInt32? = nil,
        region: CGRect? = nil,
        outputPath: URL? = nil,
        includeBase64: Bool = false
    ) {
        self.mode = mode
        self.displayID = displayID
        self.windowID = windowID
        self.region = region
        self.outputPath = outputPath
        self.includeBase64 = includeBase64
    }

    public func validate() throws {
        if mode == .window, windowID == nil { throw CaptureError.captureFailed("windowID required") }
        if mode == .region {
            guard let region,
                  [region.origin.x, region.origin.y, region.size.width, region.size.height].allSatisfy(\.isFinite),
                  region.size.width >= 2, region.size.height >= 2 else { throw CaptureError.emptySelection }
        }
    }
}

public enum AgentCaptureEngine {
    public static func listDisplays() async throws -> [AgentDisplayInfo] {
        try await AgentPermission.requireScreenCapture()
        let content = try await ScreenCaptureService.shared.shareableContent()
        let mainID = NSScreen.main?.displayID ?? 0
        return content.displays.map { display in
            AgentDisplayInfo(
                displayID: display.displayID,
                width: display.width,
                height: display.height,
                isMain: display.displayID == mainID
            )
        }
    }

    public static func listWindows() async throws -> [AgentWindowInfo] {
        try await AgentPermission.requireScreenCapture()
        let content = try await ScreenCaptureService.shared.shareableContent()
        return ShareableWindowFilter.pickableWindows(from: content).map { window in
            AgentWindowInfo(
                windowID: window.windowID,
                title: window.title ?? "",
                appName: window.owningApplication?.applicationName ?? "",
                frame: AgentRect(DisplayGeometry.cocoaRect(fromTopLeftFrame: window.frame))
            )
        }
    }

    public static func capture(options: AgentCaptureOptions) async throws -> AgentCaptureResult {
        try options.validate()
        try CaptureDisplaySelection.validateActive(options.displayID)
        let selectedID = options.displayID ?? ScreenCaptureService.displayID(at: NSEvent.mouseLocation)
        try await AgentPermission.requireScreenCapture()
        let content = try await ScreenCaptureService.shared.shareableContent()
        let image: NSImage
        var windowMeta: (id: UInt32, title: String, app: String)?
        var displayMeta: UInt32?

        switch options.mode {
        case .fullscreen, .display:
            try CaptureDisplaySelection.validate(selectedID, available: content.displays.map(\.displayID))
            let display = content.displays.first { $0.displayID == selectedID }
            guard let target = display else { throw CaptureError.noDisplays }
            displayMeta = target.displayID
            image = try await ScreenCaptureService.shared.captureFullscreen(display: target, showsCursor: AgentConfiguration.captureShowCursor)
        case .window:
            guard let wid = options.windowID else { throw CaptureError.captureFailed("windowID required") }
            guard let window = ShareableWindowFilter.pickableWindows(from: content).first(where: { $0.windowID == wid }) else {
                throw CaptureError.noWindows
            }
            windowMeta = (window.windowID, window.title ?? "", window.owningApplication?.applicationName ?? "")
            image = try await ScreenCaptureService.shared.captureWindow(window, includeShadow: AgentConfiguration.captureWindowWithShadow, showsCursor: AgentConfiguration.captureShowCursor)
        case .region:
            guard let region = options.region, region.width >= 2, region.height >= 2 else {
                throw CaptureError.emptySelection
            }
            image = try await ScreenCaptureService.shared.captureRegion(globalRect: region, showsCursor: AgentConfiguration.captureShowCursor, displayID: options.displayID)
        }

        let path = try persist(image: image, preferredURL: options.outputPath)
        let b64: String? = options.includeBase64 ? ImageFormats.pngData(from: image)?.base64EncodedString() : nil

        return AgentCaptureResult(
            path: path?.path,
            base64PNG: b64,
            width: image.size.width,
            height: image.size.height,
            mode: options.mode.rawValue,
            displayID: displayMeta,
            windowID: windowMeta?.id,
            windowTitle: windowMeta?.title,
            appName: windowMeta?.app
        )
    }

    public static func loadImage(path: String) throws -> NSImage {
        let url = URL(fileURLWithPath: path)
        guard let image = NSImage(contentsOf: url) else {
            throw CaptureError.captureFailed("Could not load image at \(path)")
        }
        return image
    }

    private static func persist(image: NSImage, preferredURL: URL?) throws -> URL? {
        let format: ScreenshotFormat = ["jpeg", "jpg"].contains(AgentConfiguration.screenshotFormat) ? .jpeg : .png
        if let preferredURL {
            let url = CaptureOutput.explicitURL(preferredURL, format: format)
            try ImageFormats.write(image: image, to: url, format: format, jpegQuality: AgentConfiguration.jpegQuality)
            return url
        }
        return try ImageFormats.writeUnique(image: image, to: defaultOutputURL(), format: format, jpegQuality: AgentConfiguration.jpegQuality)
    }

    private static func defaultOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let format: ScreenshotFormat = ["jpeg", "jpg"].contains(AgentConfiguration.screenshotFormat) ? .jpeg : .png
        let name = CaptureOutput.filename("Octoshot \(formatter.string(from: Date()))", format: format)
        return AgentConfiguration.saveDirectory.appendingPathComponent(name)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 0 }
        return CGDirectDisplayID(number.uint32Value)
    }
}
