import Foundation
import OctoshotCore

extension AppSettings {
    var embeddedAIUseOnDeviceVLM: Bool {
        get {
            AppSettings.defaults.object(forKey: EmbeddedAISettings.userDefaultsKeys.useEmbeddedVision) as? Bool ?? true
        }
        set {
            AppSettings.defaults.set(newValue, forKey: EmbeddedAISettings.userDefaultsKeys.useEmbeddedVision)
        }
    }

    var embeddedAIOllamaFallbackEnabled: Bool {
        get {
            AppSettings.defaults.object(forKey: EmbeddedAISettings.userDefaultsKeys.ollamaFallbackEnabled) as? Bool ?? false
        }
        set {
            AppSettings.defaults.set(newValue, forKey: EmbeddedAISettings.userDefaultsKeys.ollamaFallbackEnabled)
        }
    }
}
