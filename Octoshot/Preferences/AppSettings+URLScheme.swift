import Foundation
import OctoshotCore

extension AppSettings {
    enum URLSchemeKeys {
        static let policy = "urlSchemeAutomationPolicy"
        static let trustedCallers = "urlSchemeTrustedCallers"
    }

    /// How `octoshot://` requests from other apps are handled. Defaults to asking.
    var urlSchemePolicy: URLSchemeAutomationPolicy {
        get {
            let policy = AppSettings.defaults.string(forKey: URLSchemeKeys.policy)
                .flatMap(URLSchemeAutomationPolicy.init(rawValue:)) ?? .ask
            return policy == .allow ? .ask : policy
        }
        set { AppSettings.defaults.set(newValue.rawValue, forKey: URLSchemeKeys.policy) }
    }

    /// Signed requirements for remembered callers. Legacy string-only entries are never trusted.
    var urlSchemeTrustedCallers: [String: String] {
        get { AppSettings.defaults.dictionary(forKey: "urlSchemeSignedCallers") as? [String: String] ?? [:] }
        set { AppSettings.defaults.set(newValue, forKey: "urlSchemeSignedCallers") }
    }
}
