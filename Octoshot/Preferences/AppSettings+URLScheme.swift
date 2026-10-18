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
            UserDefaults.standard.string(forKey: URLSchemeKeys.policy)
                .flatMap(URLSchemeAutomationPolicy.init(rawValue:)) ?? .ask
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: URLSchemeKeys.policy) }
    }

    /// Callers (bundle IDs, or executable paths for tools) the user chose to always allow.
    var urlSchemeTrustedCallers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: URLSchemeKeys.trustedCallers) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: URLSchemeKeys.trustedCallers) }
    }
}
