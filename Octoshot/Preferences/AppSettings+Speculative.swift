import Foundation

extension AppSettings {
    private enum SpeculativeKeys {
        static let enabled = "speculativePostProcessingEnabled"
        static let confidenceThreshold = "speculativeConfidenceThreshold"
    }

    var speculativePostProcessingEnabled: Bool {
        get { AppSettings.defaults.object(forKey: SpeculativeKeys.enabled) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: SpeculativeKeys.enabled) }
    }

    /// Minimum normalized confidence (0…1) to run background post-processing.
    var speculativeConfidenceThreshold: Double {
        get {
            let v = AppSettings.defaults.double(forKey: SpeculativeKeys.confidenceThreshold)
            return v > 0 ? v : 0.45
        }
        set { AppSettings.defaults.set(newValue, forKey: SpeculativeKeys.confidenceThreshold) }
    }
}
