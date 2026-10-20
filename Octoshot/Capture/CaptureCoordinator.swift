import AppKit
import ScreenCaptureKit
import SwiftUI
import OctoshotCore

@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private let areaSelection = AreaSelectionController()
    private let windowSelection = WindowSelectionController()
    private let quickAccess = QuickAccessPanelController()
    private let annotation = AnnotationWindowController()

    private var isCapturing = false

    private init() {
        areaSelection.onComplete = { [weak self] rect, mode in
            Task { await self?.handleAreaSelection(rect, mode: mode) }
        }
        areaSelection.onCancel = { [weak self] in self?.isCapturing = false }

        windowSelection.onComplete = { [weak self] window, anchor in
            Task { await self?.performWindowCapture(window, captureAnchor: anchor) }
        }
        windowSelection.onCancel = { [weak self] in self?.isCapturing = false }
    }

    func startAreaCapture(displayID: UInt32? = nil, mode: AreaCaptureMode? = nil) {
        Task {
            do { try CaptureDisplaySelection.validateActive(displayID) } catch { finishWithError(error); return }
            guard await beginCaptureFlow() else { return }
            areaSelection.begin(displayID: displayID, mode: mode)
        }
    }

    func startWindowCapture(displayID: UInt32? = nil) {
        Task {
            do { try CaptureDisplaySelection.validateActive(displayID) } catch { finishWithError(error); return }
            guard await beginCaptureFlow() else { return }
            do {
                let content = try await ScreenCaptureService.shared.shareableContent()
                ScreenRecordingAccessCache.shared.lastKnownGranted = true
                let appWindows = ShareableWindowFilter.pickableWindows(from: content)
                windowSelection.begin(windows: appWindows, displayID: displayID)
            } catch {
                await PermissionManager.handleCaptureFailure(error)
                finishWithError(error)
            }
        }
    }

    func startFullscreenCapture() {
        Task { await performFullscreenCapture() }
    }

    func startFullscreenRecording(video: Bool, displayID: UInt32? = nil) {
        let selectedID = displayID ?? ScreenCaptureService.displayID(at: NSEvent.mouseLocation)
        Task {
            guard await beginCaptureFlow() else { return }
            isCapturing = false
            ScreenCaptureRecorder.shared.startFullscreen(kind: video ? .video : .gif, displayID: selectedID)
        }
    }

    func stopRecording() {
        ScreenCaptureRecorder.shared.stop()
    }

    private func beginCaptureFlow() async -> Bool {
        if isCapturing { return false }
        await PermissionManager.prepareForCaptureIfNeeded()
        isCapturing = true
        return true
    }

    private func handleAreaSelection(_ rect: CGRect, mode: AreaCaptureMode) async {
        defer { isCapturing = false }
        switch mode {
        case .screenshot:
            await performRegionCapture(rect)
        case .scrolling:
            ScrollingCaptureController.shared.start(region: rect)
        case .recordVideo:
            ScreenCaptureRecorder.shared.startRegion(rect, kind: .video)
        case .recordGIF:
            ScreenCaptureRecorder.shared.startRegion(rect, kind: .gif)
        case .formulaLaTeX:
            CaptureFollowUpState.shared.areaFollowUp = .latex
            await performRegionCapture(rect)
        case .figureTable:
            CaptureFollowUpState.shared.areaFollowUp = .paperClip
            await performRegionCapture(rect)
        }
    }

    private func performRegionCapture(_ rect: CGRect) async {
        do {
            let image = try await ScreenCaptureService.shared.captureRegion(
                globalRect: rect,
                showsCursor: AppSettings.shared.captureShowCursor
            )
            ScreenRecordingAccessCache.shared.lastKnownGranted = true
            let anchor = CGPoint(x: rect.midX, y: rect.midY)
            await handleRegionCaptureResult(image, captureAnchor: anchor)
        } catch {
            await PermissionManager.handleCaptureFailure(error)
            finishWithError(error)
        }
    }

    private func handleRegionCaptureResult(_ image: NSImage, captureAnchor: CGPoint) async {
        let followUp = CaptureFollowUpState.shared.areaFollowUp
        CaptureFollowUpState.shared.areaFollowUp = .standard
        switch followUp {
        case .standard:
            presentResult(image, captureAnchor: captureAnchor)
        case .latex:
            CaptureFeedback.playCaptureSoundIfEnabled()
            FeatureCoordinator.shared.showLaTeX(with: image)
        case .paperClip:
            presentResult(image, captureAnchor: captureAnchor)
            Task {
                do {
                    let folder = try await PaperClipService.processFigure(image: image)
                    let alert = NSAlert()
                    alert.messageText = "Saved to Clips Library"
                    alert.informativeText = folder.path
                    alert.runModal()
                } catch {
                    finishWithError(error)
                }
            }
        }
    }

    private func performWindowCapture(_ window: SCWindow, captureAnchor: CGPoint) async {
        defer { isCapturing = false }
        do {
            let image = try await ScreenCaptureService.shared.captureWindow(
                window,
                includeShadow: AppSettings.shared.captureWindowWithShadow,
                showsCursor: AppSettings.shared.captureShowCursor
            )
            ScreenRecordingAccessCache.shared.lastKnownGranted = true
            presentResult(image, captureAnchor: captureAnchor)
        } catch {
            await PermissionManager.handleCaptureFailure(error)
            finishWithError(error)
        }
    }

    private func performFullscreenCapture() async {
        let mouse = NSEvent.mouseLocation
        let selectedID = ScreenCaptureService.displayID(at: mouse)
        guard await beginCaptureFlow() else { return }
        defer { isCapturing = false }
        do {
            let content = try await ScreenCaptureService.shared.shareableContent()
            guard let display = content.displays.first(where: { $0.displayID == selectedID }) else { throw CaptureError.noDisplays }
            let image = try await ScreenCaptureService.shared.captureFullscreen(
                display: display,
                showsCursor: AppSettings.shared.captureShowCursor
            )
            ScreenRecordingAccessCache.shared.lastKnownGranted = true
            let anchor = CGPoint(x: mouse.x, y: mouse.y)
            presentResult(image, captureAnchor: anchor)
        } catch {
            await PermissionManager.handleCaptureFailure(error)
            finishWithError(error)
        }
    }

    func presentCapturedImage(_ image: NSImage, captureAnchor: CGPoint? = nil) {
        presentResult(image, captureAnchor: captureAnchor ?? NSEvent.mouseLocation)
    }

    func presentCapturedMovie(at url: URL, captureAnchor: CGPoint? = nil) {
        CaptureFeedback.playCaptureSoundIfEnabled()
        let preview = NSImage(size: NSSize(width: 120, height: 68))
        preview.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 68).fill()
        let symbol = "play.rectangle.fill"
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            img.draw(in: NSRect(x: 40, y: 14, width: 40, height: 40))
        }
        preview.unlockFocus()
        presentResult(preview, savedFileURL: url, captureAnchor: captureAnchor ?? NSEvent.mouseLocation)
        RecentCapturesStore.record(url: url)
    }

    func presentCapturedGIF(at url: URL, preview: NSImage, captureAnchor: CGPoint? = nil) {
        CaptureFeedback.playCaptureSoundIfEnabled()
        presentResult(preview, savedFileURL: url, captureAnchor: captureAnchor ?? NSEvent.mouseLocation)
        RecentCapturesStore.record(url: url)
    }

    private func presentResult(_ image: NSImage, savedFileURL: URL? = nil, captureAnchor: CGPoint? = nil) {
        CaptureFeedback.playCaptureSoundIfEnabled()
        let settings = AppSettings.shared
        var savedURL: URL? = savedFileURL

        if settings.afterCaptureCopyToClipboard, savedFileURL == nil {
            ImageFormats.copyToPasteboard(image)
        }

        if settings.afterCaptureSaveToDisk, savedFileURL == nil {
            let url = settings.defaultSaveURL()
            do {
                let actualURL = try ImageFormats.writeUnique(
                    image: image,
                    to: url,
                    format: settings.format,
                    jpegQuality: settings.jpegQuality
                )
                savedURL = actualURL
                RecentCapturesStore.record(url: actualURL)
            } catch {
                finishWithError(error)
            }
        }

        guard settings.afterCaptureShowQuickAccess else { return }

        var captureURL = savedURL
        let developer = settings.developerModeEnabled
        quickAccess.show(
            image: image,
            actions: QuickAccessActions(
            onCopy: {
                if let file = savedFileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                } else {
                    ImageFormats.copyToPasteboard(image)
                }
            },
            onSave: {
                if let file = savedFileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    return
                }
                let url = AppSettings.shared.defaultSaveURL()
                do {
                    let actualURL = try ImageFormats.writeUnique(
                        image: image,
                        to: url,
                        format: AppSettings.shared.format,
                        jpegQuality: AppSettings.shared.jpegQuality
                    )
                    captureURL = actualURL
                    RecentCapturesStore.record(url: actualURL)
                } catch {
                    self.finishWithError(error)
                }
            },
            onAnnotate: { self.annotation.open(with: image) },
            onPin: { PinnedScreenshotManager.shared.pin(image: image) },
            onOCR: { FeatureCoordinator.shared.showOCR(with: image) },
            onAskAI: { self.showAI(for: image) },
            onCopyMarkdown: developer ? {
                do {
                    captureURL = try DeveloperClipboard.copyMarkdownSnippet(for: image, existingURL: captureURL)
                } catch {
                    self.finishWithError(error)
                }
            } : nil,
            onCopyPath: developer ? {
                do {
                    if let file = savedFileURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(file.path, forType: .string)
                    } else {
                        captureURL = try DeveloperClipboard.copyFilePath(for: image, existingURL: captureURL)
                    }
                } catch {
                    self.finishWithError(error)
                }
            } : nil,
            onClose: {}
            ),
            captureAnchor: captureAnchor
        )
    }

    private func showAI(for image: NSImage) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Ask Local AI"
        panel.isFloatingPanel = true
        panel.contentView = NSHostingView(rootView: AIAssistantPanelView(image: image))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func finishWithError(_ error: Error) {
        isCapturing = false
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
