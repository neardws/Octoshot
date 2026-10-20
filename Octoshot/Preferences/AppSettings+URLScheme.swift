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
            let policy = UserDefaults.standard.string(forKey: URLSchemeKeys.policy)
                .flatMap(URLSchemeAutomationPolicy.init(rawValue:)) ?? .ask
            return policy == .allow ? .ask : policy
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: URLSchemeKeys.policy) }
    }

    /// Signed requirements for remembered callers. Legacy string-only entries are never trusted.
    var urlSchemeTrustedCallers: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "urlSchemeSignedCallers") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "urlSchemeSignedCallers") }
    }
}
