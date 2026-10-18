import Foundation

/// How Octoshot treats `octoshot://` requests from other apps and web pages.
public enum URLSchemeAutomationPolicy: String, CaseIterable, Identifiable, Sendable {
    /// Confirm each request that would capture or record without further input.
    case ask
    /// Run every request without confirmation.
    case allow
    /// Ignore requests, except stopping a recording.
    case off

    public var id: String { rawValue }
}

/// Decides whether an `octoshot://` request may run. Any app or web page can open these URLs,
/// so requests that capture without the user taking part need their consent.
public enum URLSchemeGate {
    public enum RequestKind: Equatable, Sendable {
        /// Opens area or window selection; nothing is captured until the user selects.
        case interactive
        /// Takes a screenshot or starts a recording with no further input.
        case silentCapture
        /// Ends a recording. Always allowed, so a recording can never get stuck on.
        case stopRecording
        case unsupported
    }

    public enum Decision: Equatable, Sendable {
        case run
        case ask
        case refuse
    }

    public static func classify(_ url: URL) -> RequestKind {
        guard url.scheme?.lowercased() == "octoshot" else { return .unsupported }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.lowercased()
        }

        switch url.host?.lowercased() {
        case "capture":
            switch value("mode") ?? "fullscreen" {
            case "area", "region", "window": return .interactive
            case "fullscreen", "display": return .silentCapture
            default: return .unsupported
            }
        case "record":
            switch value("action") ?? "start" {
            case "stop":
                return .stopRecording
            case "start":
                if value("rect") != nil { return .silentCapture }
                switch value("mode") ?? "fullscreen" {
                case "area", "region": return .interactive
                case "fullscreen": return .silentCapture
                default: return .unsupported
                }
            default:
                return .unsupported
            }
        default:
            return .unsupported
        }
    }

    /// - Parameter callerIsTrusted: the user chose "Always allow" for the app that opened the URL.
    public static func decision(
        for kind: RequestKind,
        policy: URLSchemeAutomationPolicy,
        callerIsTrusted: Bool
    ) -> Decision {
        switch kind {
        case .unsupported:
            return .refuse
        case .stopRecording:
            return .run
        case .interactive:
            return policy == .off ? .refuse : .run
        case .silentCapture:
            switch policy {
            case .off: return .refuse
            case .allow: return .run
            case .ask: return callerIsTrusted ? .run : .ask
            }
        }
    }
}
