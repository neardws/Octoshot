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
        try await AgentPermission.requireScreenCapture()
        let content = try await ScreenCaptureService.shared.shareableContent()
        let image: NSImage
        var windowMeta: (id: UInt32, title: String, app: String)?
        var displayMeta: UInt32?

        switch options.mode {
        case .fullscreen, .display:
            let display = content.displays.first { $0.displayID == options.displayID }
                ?? ScreenCaptureService.displayUnderMouse(in: content)
            guard let target = display else { throw CaptureError.noDisplays }
            displayMeta = target.displayID
            image = try await ScreenCaptureService.shared.captureFullscreen(display: target)
        case .window:
            guard let wid = options.windowID else { throw CaptureError.captureFailed("windowID required") }
            guard let window = ShareableWindowFilter.pickableWindows(from: content).first(where: { $0.windowID == wid }) else {
                throw CaptureError.noWindows
            }
            windowMeta = (window.windowID, window.title ?? "", window.owningApplication?.applicationName ?? "")
            image = try await ScreenCaptureService.shared.captureWindow(window)
        case .region:
            guard let region = options.region, region.width >= 2, region.height >= 2 else {
                throw CaptureError.emptySelection
            }
            image = try await ScreenCaptureService.shared.captureRegion(globalRect: region)
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
        let url = preferredURL ?? defaultOutputURL()
        let format = AgentConfiguration.screenshotFormat
        if format == "jpeg" || format == "jpg" {
            try ImageFormats.writeJPEG(image: image, to: url, quality: AgentConfiguration.jpegQuality)
        } else {
            try ImageFormats.writePNG(image: image, to: url)
        }
        return url
    }

    private static func defaultOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Octoshot \(formatter.string(from: Date())).png"
        return AgentConfiguration.saveDirectory.appendingPathComponent(name)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 0 }
        return CGDirectDisplayID(number.uint32Value)
    }
}
