import Foundation

/// How Octoshot treats `octoshot://` requests from other apps and web pages.
public enum URLSchemeAutomationPolicy: String, CaseIterable, Identifiable, Sendable {
    /// Confirm each request that would capture or record without further input.
    case ask
    /// Legacy value; unverified callers still require confirmation.
    case allow
    /// Ignore requests, except stopping a recording.
    case off

    public var id: String { rawValue }
}

/// Decides whether an `octoshot://` request may run. Any app or web page can open these URLs,
/// so requests that capture without the user taking part need their consent.
public enum URLSchemeGate {
    public static func isBrowser(identifier: String, isRegisteredWebHandler: Bool) -> Bool {
        let prefixes = ["com.apple.safari", "com.google.chrome", "org.chromium.chromium",
                        "org.mozilla.firefox", "org.mozilla.nightly", "com.microsoft.edgemac",
                        "company.thebrowser.browser", "com.brave.browser", "com.operasoftware.opera",
                        "com.vivaldi.vivaldi", "com.kagi.kagimacos"]
        return isRegisteredWebHandler || prefixes.contains { identifier.lowercased().hasPrefix($0) }
    }

    public static func canAlwaysAllow(identity: String?, requirement: String?, isBrowser: Bool) -> Bool {
        guard let identity, !identity.isEmpty, let requirement, !requirement.isEmpty else { return false }
        return !isBrowser
    }

    public static func isTrusted(identity: String?, requirement: String?, isBrowser: Bool,
                                 storedRequirement: String?, signatureMatches: Bool) -> Bool {
        canAlwaysAllow(identity: identity, requirement: requirement, isBrowser: isBrowser)
            && storedRequirement != nil && signatureMatches
    }
    public enum RequestKind: Equatable, Sendable {
        /// Opens area or window selection; nothing is captured until the user selects.
        case interactive
        /// Takes a screenshot or starts a recording with no further input.
        case silentCapture
        /// Ends a recording. Always allowed, so a recording can never get stuck on.
        case stopRecording
        case diary
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
        case "diary":
            return .diary
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
                switch value("mode") ?? "fullscreen" {
                case "area", "region", "fullscreen": return .silentCapture
                default: return .unsupported
                }
            default:
                return .unsupported
            }
        default:
            return .unsupported
        }
    }

    /// - Parameter callerIsTrusted: a non-browser sender validated against its remembered signing requirement.
    public static func decision(
        for kind: RequestKind,
        policy: URLSchemeAutomationPolicy,
        callerIsTrusted: Bool
    ) -> Decision {
        switch kind {
        case .unsupported:
            return .refuse
        case .stopRecording, .diary:
            return .run
        case .interactive:
            return policy == .off ? .refuse : .run
        case .silentCapture:
            switch policy {
            case .off: return .refuse
            case .allow, .ask: return callerIsTrusted ? .run : .ask
            }
        }
    }
}
