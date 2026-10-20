import AppKit
import Foundation
import OctoshotCore

/// The app that opened an `octoshot://` URL, when macOS tells us.
struct URLSchemeCaller {
    /// Bundle ID, or executable path for command-line tools; used to remember "Always allow".
    let identifier: String
    let displayName: String

    /// Reads the sender of the Apple event currently being handled (the open-URL event).
    @MainActor
    static func current() -> URLSchemeCaller? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
              pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid)
        else { return nil }
        guard let identifier = app.bundleIdentifier ?? app.executableURL?.path else { return nil }
        let name = app.localizedName ?? app.executableURL?.lastPathComponent ?? identifier
        return URLSchemeCaller(identifier: identifier, displayName: name)
    }
}

@MainActor
enum AgentURLRouter {
    /// Handles `octoshot://capture?mode=…&display_id=…` and
    /// `octoshot://record?action=start|stop&mode=…&format=video|gif&rect=x,y,w,h`.
    /// Requests that would capture without the user taking part follow the URL scheme policy
    /// in Settings → Developer (ask by default).
    static func handle(_ url: URL, caller: URLSchemeCaller?) {
        let kind = URLSchemeGate.classify(url)
        let settings = AppSettings.shared
        let trusted = caller.map { settings.urlSchemeTrustedCallers.contains($0.identifier) } ?? false

        switch URLSchemeGate.decision(for: kind, policy: settings.urlSchemePolicy, callerIsTrusted: trusted) {
        case .refuse:
            NSLog("Octoshot: ignored URL request %@ (%@)", url.absoluteString, caller?.identifier ?? "unknown caller")
            return
        case .ask:
            guard confirm(url: url, caller: caller) else { return }
        case .run:
            break
        }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host?.lowercased() {
        case "capture":
            handleCapture(query: query)
        case "record":
            handleRecord(query: query)
        default:
            break
        }
    }

    /// Asks the user to approve a silent capture or recording. Returns true to proceed.
    private static func confirm(url: URL, caller: URLSchemeCaller?) -> Bool {
        let isRecording = url.host?.lowercased() == "record"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = caller.map { OctoshotL10n.urlSchemeConfirmTitle(appName: $0.displayName) }
            ?? OctoshotL10n.urlSchemeConfirmTitleUnknownApp
        alert.informativeText = isRecording
            ? OctoshotL10n.urlSchemeConfirmRecordBody
            : OctoshotL10n.urlSchemeConfirmCaptureBody
        // "Don't Allow" comes first so Return declines.
        alert.addButton(withTitle: OctoshotL10n.urlSchemeDontAllow)
        alert.addButton(withTitle: OctoshotL10n.urlSchemeAllow)
        if let caller {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = OctoshotL10n.urlSchemeAlwaysAllow(appName: caller.displayName)
        }

        NSApp.activate(ignoringOtherApps: true)
        let allowed = alert.runModal() == .alertSecondButtonReturn
        if allowed, let caller, alert.suppressionButton?.state == .on {
            AppSettings.shared.urlSchemeTrustedCallers.insert(caller.identifier)
        }
        return allowed
    }

    private static func handleCapture(query: [URLQueryItem]) {
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }

        let mode = value("mode")?.lowercased() ?? "fullscreen"
        switch mode {
        case "area", "region":
            CaptureCoordinator.shared.startAreaCapture()
        case "window":
            CaptureCoordinator.shared.startWindowCapture()
        case "fullscreen", "display":
            // Always saves to the configured save folder; callers cannot choose the path.
            Task {
                do {
                    _ = try await AgentCaptureEngine.capture(options: .init(
                        mode: mode == "display" ? .display : .fullscreen,
                        displayID: value("display_id").flatMap { UInt32($0) }
                    ))
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        default:
            break
        }
    }

    private static func handleRecord(query: [URLQueryItem]) {
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }

        let action = value("action") ?? "start"
        switch action.lowercased() {
        case "stop":
            CaptureCoordinator.shared.stopRecording()
        case "start":
            let format = value("format") ?? "video"
            let kind: RecordingKind = format.lowercased() == "gif" ? .gif : .video
            if let rect = parseRect(value("rect")) {
                ScreenCaptureRecorder.shared.startRegion(rect, kind: kind)
                return
            }
            let mode = value("mode") ?? "fullscreen"
            switch mode.lowercased() {
            case "area", "region":
                CaptureCoordinator.shared.startAreaCapture()
            case "fullscreen":
                CaptureCoordinator.shared.startFullscreenRecording(video: kind == .video)
            default:
                break
            }
        default:
            break
        }
    }

    private static func parseRect(_ raw: String?) -> CGRect? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }
}
