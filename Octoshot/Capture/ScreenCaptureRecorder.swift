import AppKit
import AVFoundation
import ScreenCaptureKit
import OctoshotCore

extension Notification.Name {
    static let octoshotRecordingStateDidChange = Notification.Name("OctoshotRecordingStateDidChange")
}

enum RecordingKind {
    case video
    case gif
}

@MainActor
final class ScreenCaptureRecorder: NSObject {
    static let shared = ScreenCaptureRecorder()

    private(set) var isRecording = false
    private var kind: RecordingKind = .video
    private var stream: SCStream?
    private var streamOutput: RecorderStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var gifFrames: [NSImage] = []
    private var gifTimer: Timer?
    private var captureRegion: CGRect?
    /// Display that fullscreen GIF frames come from, fixed when recording starts.
    private var gifDisplayID: CGDirectDisplayID?
    private var captureAnchor: CGPoint = .zero
    private var stopPanel: RecordingStopPanelController?

    private override init() {
        super.init()
    }

    func startRegion(_ region: CGRect, kind: RecordingKind, displayID: UInt32? = nil) {
        guard !isRecording else { return }
        var region = region
        if let displayID {
            guard let screen = ScreenCaptureService.screen(for: displayID) else {
                showError(CaptureError.noDisplays)
                return
            }
            region = region.intersection(screen.frame)
        }
        guard !region.isNull, region.width.isFinite, region.height.isFinite,
              region.width >= 2, region.height >= 2 else {
            showError(CaptureError.emptySelection)
            return
        }
        self.kind = kind
        self.captureRegion = region
        captureAnchor = CGPoint(x: region.midX, y: region.midY)
        if kind == .gif {
            do { try startGIFCapture() } catch { showError(error) }
            return
        }
        Task { await startStream(for: region, kind: kind) }
    }

    func startFullscreen(kind: RecordingKind, displayID: UInt32? = nil) {
        guard !isRecording else { return }
        self.kind = kind
        self.captureRegion = nil
        gifDisplayID = displayID ?? ScreenCaptureService.displayID(at: NSEvent.mouseLocation)
        guard let selectedID = gifDisplayID, let screen = ScreenCaptureService.screen(for: selectedID) else {
            showError(CaptureError.noDisplays)
            return
        }
        captureAnchor = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        if kind == .gif {
            do { try startGIFCapture() } catch { showError(error) }
            return
        }
        Task { await startFullscreenStream(kind: kind) }
    }

    func stop() {
        Task { await stopRecording() }
    }

    private func startFullscreenStream(kind: RecordingKind) async {
        do {
            let content = try await ScreenCaptureService.shared.shareableContent()
            guard let display = content.displays.first(where: { $0.displayID == gifDisplayID }) else {
                throw CaptureError.noDisplays
            }
            let screen = NSScreen.screens.first { $0.displayID == display.displayID }
            let filter = await ScreenCaptureService.shared.displayFilter(for: display, content: content)
            let config = SCStreamConfiguration()
            let scale = screen?.backingScaleFactor ?? 2
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = AppSettings.shared.recordShowCursor
            config.ignoreShadowsDisplay = !AppSettings.shared.captureWindowWithShadow
            config.captureResolution = .best
            try await beginRecording(filter: filter, configuration: config, kind: kind)
        } catch {
            showError(error)
        }
    }

    private func startStream(for region: CGRect, kind: RecordingKind) async {
        do {
            let content = try await ScreenCaptureService.shared.shareableContent()
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(captureAnchor) }),
                  let display = content.displays.first(where: { $0.displayID == screen.displayID })
            else { throw CaptureError.noDisplays }

            let intersection = region.intersection(screen.frame)
            let local = DisplayGeometry.rectInScreenSpace(globalRect: intersection, screen: screen)
            let source = DisplayGeometry.sourceRectForCapture(
                screenLocalBottomLeft: local,
                displayHeight: screen.frame.height
            )
            let scale = screen.backingScaleFactor
            let filter = await ScreenCaptureService.shared.displayFilter(for: display, content: content)
            let config = SCStreamConfiguration()
            config.sourceRect = source
            config.width = Int(intersection.width * scale)
            config.height = Int(intersection.height * scale)
            config.showsCursor = AppSettings.shared.recordShowCursor
            config.ignoreShadowsDisplay = !AppSettings.shared.captureWindowWithShadow
            config.captureResolution = .best
            try await beginRecording(filter: filter, configuration: config, kind: kind)
        } catch {
            showError(error)
        }
    }

    private func beginRecording(filter: SCContentFilter, configuration: SCStreamConfiguration, kind: RecordingKind) async throws {
        if kind == .gif {
            try startGIFCapture()
            return
        }

        let url = temporaryMovieURL()
        outputURL = url
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureError.captureFailed("Cannot add video input") }
        writer.add(input)

        let output = RecorderStreamOutput(writer: writer, input: input)
        streamOutput = output

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try await stream.startCapture()

        self.stream = stream
        self.assetWriter = writer
        self.videoInput = input
        writer.startWriting()

        isRecording = true
        notifyRecordingChanged()
        stopPanel = RecordingStopPanelController.shared
        stopPanel?.show(captureAnchor: captureAnchor, onStop: { [weak self] in self?.stop() })
    }

    private func startGIFCapture() throws {
        gifFrames = []
        let fps = AppSettings.shared.gifFPS
        gifTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.captureGIFFrame() }
        }
        isRecording = true
        notifyRecordingChanged()
        stopPanel = RecordingStopPanelController.shared
        stopPanel?.show(captureAnchor: captureAnchor, onStop: { [weak self] in self?.stop() })
        Task { await captureGIFFrame() }
    }

    private func captureGIFFrame() async {
        guard let region = captureRegion else {
            await captureFullscreenGIFFrame()
            return
        }
        guard let image = try? await ScreenCaptureService.shared.captureRegion(
            globalRect: region,
            showsCursor: AppSettings.shared.recordShowCursor
        ) else { return }
        gifFrames.append(image)
    }

    private func captureFullscreenGIFFrame() async {
        guard let content = try? await ScreenCaptureService.shared.shareableContent(),
              let display = content.displays.first(where: { $0.displayID == gifDisplayID }),
              let image = try? await ScreenCaptureService.shared.captureFullscreen(
                  display: display,
                  showsCursor: AppSettings.shared.recordShowCursor
              )
        else { return }
        gifFrames.append(image)
    }

    private func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        stopPanel?.hide()
        stopPanel = nil
        notifyRecordingChanged()

        if kind == .gif {
            gifTimer?.invalidate()
            gifTimer = nil
            finishGIF()
            return
        }

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        videoInput?.markAsFinished()
        if let writer = assetWriter, let url = outputURL {
            await writer.finishWriting()
            if writer.status == .completed {
                CaptureCoordinator.shared.presentCapturedMovie(at: url, captureAnchor: captureAnchor)
            }
        }
        assetWriter = nil
        videoInput = nil
        streamOutput = nil
        outputURL = nil
    }

    private func finishGIF() {
        guard !gifFrames.isEmpty else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Octoshot-\(UUID().uuidString).gif")
        do {
            try GIFExporter.writeGIF(
                frames: gifFrames,
                fps: AppSettings.shared.gifFPS,
                maxWidth: AppSettings.shared.gifMaxWidth,
                to: url
            )
            if let preview = gifFrames.first {
                CaptureCoordinator.shared.presentCapturedGIF(at: url, preview: preview, captureAnchor: captureAnchor)
            }
        } catch {
            showError(error)
        }
        gifFrames = []
    }

    private func temporaryMovieURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Octoshot-\(UUID().uuidString).mp4")
    }

    private func notifyRecordingChanged() {
        NotificationCenter.default.post(name: .octoshotRecordingStateDidChange, object: nil)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

private final class RecorderStreamOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "com.neardws.octoshot.recorder")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput

    init(writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.input = input
    }

    private var sessionStarted = false

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, input.isReadyForMoreMediaData else { return }
        if !sessionStarted {
            sessionStarted = true
            let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: start)
        }
        input.append(sampleBuffer)
    }
}

private final class RecordingStopTarget: NSObject {
    var onStop: (() -> Void)?
    @objc func stopPressed() { onStop?() }
}

@MainActor
final class RecordingStopPanelController {
    static let shared = RecordingStopPanelController()
    private var panel: NSPanel?
    private let stopTarget = RecordingStopTarget()

    func show(captureAnchor: CGPoint, onStop: @escaping () -> Void) {
        stopTarget.onStop = onStop
        let button = NSButton(title: "Stop Recording", target: stopTarget, action: #selector(RecordingStopTarget.stopPressed))
        button.bezelStyle = .rounded
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 44))
        button.frame = NSRect(x: 16, y: 8, width: 128, height: 28)
        view.addSubview(button)

        if panel == nil {
            let panel = NSPanel(contentRect: view.bounds, styleMask: [.nonactivatingPanel, .titled], backing: .buffered, defer: false)
            panel.title = "Recording"
            FullScreenOverlaySupport.configureFloatingOverlayPanel(panel)
            self.panel = panel
        }
        panel?.contentView = view
        panel?.setFrameOrigin(CGPoint(x: captureAnchor.x - 80, y: captureAnchor.y - 22))
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
        stopTarget.onStop = nil
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 0 }
        return CGDirectDisplayID(number.uint32Value)
    }
}
