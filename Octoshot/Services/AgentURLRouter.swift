import AppKit
import Foundation
import OctoshotCore
import Security

/// The app that opened an `octoshot://` URL, when macOS tells us.
struct URLSchemeCaller {
    /// Bundle ID, or executable path for command-line tools; used to remember "Always allow".
    let identifier: String
    let displayName: String
    let code: SecCode
    let requirement: String
    let isBrowser: Bool

    var canAlwaysAllow: Bool {
        URLSchemeGate.canAlwaysAllow(identity: identifier, requirement: requirement, isBrowser: isBrowser)
    }

    func matches(_ stored: String?) -> Bool {
        guard let stored else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(stored as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

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
        var code: SecCode?
        var attributes: [String: Any] = [kSecGuestAttributePid as String: NSNumber(value: pid)]
        if let token = event.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data {
            attributes[kSecGuestAttributeAudit as String] = token
        }
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code) == errSecSuccess,
              let code, SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var designated: SecRequirement?
        var staticCode: SecStaticCode?
        var requirement: CFString?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &designated) == errSecSuccess,
              let designated,
              SecRequirementCopyString(designated, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        let handlerGroups = ["http", "https"].map {
            NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "\($0)://example.com")!)
        }
        let isBrowser = URLSchemeGate.isBrowser(identifier: identifier, isRegisteredWebHandler:
            handlerGroups.contains(where: \.isEmpty)
                || handlerGroups.joined().contains { $0.standardizedFileURL == app.bundleURL?.standardizedFileURL })
        return URLSchemeCaller(identifier: identifier, displayName: name, code: code,
                               requirement: requirement as String, isBrowser: isBrowser)
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
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var displayID = ScreenCaptureService.displayID(at: NSEvent.mouseLocation)
        if url.host?.lowercased() == "record", kind != .stopRecording,
           let parameter = query.first(where: { $0.name == "rect" }) {
            guard let rect = parseRect(parameter.value) else {
                NSLog("Octoshot: invalid recording rectangle")
                return
            }
            displayID = ScreenCaptureService.displayID(at: CGPoint(x: rect.midX, y: rect.midY))
        }
        if kind != .stopRecording, let parameter = query.first(where: { $0.name == "display_id" }) {
            guard let raw = parameter.value, let requested = UInt32(raw) else {
                NSLog("Octoshot: invalid display_id")
                return
            }
            do { try CaptureDisplaySelection.validateActive(requested) } catch {
                NSLog("Octoshot: %@", error.localizedDescription)
                return
            }
            displayID = requested
        }
        let settings = AppSettings.shared
        let trusted = caller.map {
            URLSchemeGate.isTrusted(identity: $0.identifier, requirement: $0.requirement, isBrowser: $0.isBrowser,
                                    storedRequirement: settings.urlSchemeTrustedCallers[$0.identifier],
                                    signatureMatches: $0.matches(settings.urlSchemeTrustedCallers[$0.identifier]))
        } ?? false

        switch URLSchemeGate.decision(for: kind, policy: settings.urlSchemePolicy, callerIsTrusted: trusted) {
        case .refuse:
            NSLog("Octoshot: ignored URL request %@ (%@)", url.absoluteString, caller?.identifier ?? "unknown caller")
            return
        case .ask:
            guard confirm(url: url, caller: caller) else { return }
        case .run:
            break
        }

        switch url.host?.lowercased() {
        case "capture":
            handleCapture(query: query, displayID: displayID)
        case "record":
            handleRecord(query: query, displayID: displayID)
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
        if let caller, caller.canAlwaysAllow {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = OctoshotL10n.urlSchemeAlwaysAllow(appName: caller.displayName)
        }

        alert.layout()
        let panel = ConsentPanel(contentRect: alert.window.contentView!.bounds,
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = alert.window.contentView
        FullScreenOverlaySupport.configureCaptureOverlayPanel(panel)
        panel.center()
        var response: NSApplication.ModalResponse = .cancel
        let actions = ConsentActions { result in response = result; NSApp.stopModal(withCode: result) }
        for (index, button) in alert.buttons.enumerated() {
            button.tag = index
            button.target = actions
            button.action = #selector(ConsentActions.respond(_:))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        withExtendedLifetime(actions) { NSApp.runModal(for: panel) }
        panel.orderOut(nil)
        let allowed = response == .alertSecondButtonReturn
        if allowed, let caller, caller.canAlwaysAllow, caller.matches(caller.requirement), alert.suppressionButton?.state == .on {
            AppSettings.shared.urlSchemeTrustedCallers[caller.identifier] = caller.requirement
        }
        return allowed
    }

    private static func handleCapture(query: [URLQueryItem], displayID: UInt32?) {
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }

        let mode = value("mode")?.lowercased() ?? "fullscreen"
        switch mode {
        case "area", "region":
            CaptureCoordinator.shared.startAreaCapture(displayID: displayID)
        case "window":
            CaptureCoordinator.shared.startWindowCapture(displayID: displayID)
        case "fullscreen", "display":
            // Always saves to the configured save folder; callers cannot choose the path.
            Task {
                do {
                    _ = try await AgentCaptureEngine.capture(options: .init(
                        mode: mode == "display" ? .display : .fullscreen,
                        displayID: displayID
                    ))
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        default:
            break
        }
    }

    private static func handleRecord(query: [URLQueryItem], displayID: UInt32?) {
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
                ScreenCaptureRecorder.shared.startRegion(rect, kind: kind, displayID: displayID)
                return
            }
            let mode = value("mode") ?? "fullscreen"
            switch mode.lowercased() {
            case "area", "region":
                CaptureCoordinator.shared.startAreaCapture(displayID: displayID, mode: kind == .video ? .recordVideo : .recordGIF)
            case "fullscreen":
                CaptureCoordinator.shared.startFullscreenRecording(video: kind == .video, displayID: displayID)
            default:
                break
            }
        default:
            break
        }
    }

    private static func parseRect(_ raw: String?) -> CGRect? {
        guard let raw else { return nil }
        do {
            let options = try CaptureArgumentParser.parse(["--mode", "region", "--rect", raw])
            try options.validate()
            return options.region
        } catch { return nil }
    }
}

private final class ConsentActions: NSObject {
    let completion: (NSApplication.ModalResponse) -> Void

    init(completion: @escaping (NSApplication.ModalResponse) -> Void) { self.completion = completion }

    @objc func respond(_ button: NSButton) {
        completion(button.tag == 1 ? .alertSecondButtonReturn : .alertFirstButtonReturn)
    }
}

private final class ConsentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
