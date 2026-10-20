import Foundation

extension AppSettings {
    private enum RecordingKeys {
        static let rememberAreaCaptureMode = "rememberAreaCaptureMode"
        static let lastAreaCaptureMode = "lastAreaCaptureMode"
        static let gifFPS = "gifFPS"
        static let gifMaxWidth = "gifMaxWidth"
        static let recordSystemAudio = "recordSystemAudio"
        static let recordMicrophone = "recordMicrophone"
        static let recordShowClicks = "recordShowClicks"
        static let recordShowCursor = "recordShowCursor"
        static let scrollAutoScroll = "scrollAutoScroll"
        static let recordStopHotkeyEnabled = "recordStopHotkeyEnabled"
    }

    var rememberAreaCaptureMode: Bool {
        get { AppSettings.defaults.object(forKey: RecordingKeys.rememberAreaCaptureMode) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: RecordingKeys.rememberAreaCaptureMode) }
    }

    var lastAreaCaptureMode: AreaCaptureMode {
        get {
            let raw = AppSettings.defaults.string(forKey: RecordingKeys.lastAreaCaptureMode) ?? AreaCaptureMode.screenshot.rawValue
            return AreaCaptureMode(rawValue: raw) ?? .screenshot
        }
        set { AppSettings.defaults.set(newValue.rawValue, forKey: RecordingKeys.lastAreaCaptureMode) }
    }

    var gifFPS: Double {
        get {
            let v = AppSettings.defaults.double(forKey: RecordingKeys.gifFPS)
            return v > 0 ? v : 10
        }
        set { AppSettings.defaults.set(newValue, forKey: RecordingKeys.gifFPS) }
    }

    var gifMaxWidth: Int {
        get {
            let v = AppSettings.defaults.integer(forKey: RecordingKeys.gifMaxWidth)
            return v > 0 ? v : 800
        }
        set { AppSettings.defaults.set(newValue, forKey: RecordingKeys.gifMaxWidth) }
    }

    var recordSystemAudio: Bool {
        get { AppSettings.defaults.object(forKey: RecordingKeys.recordSystemAudio) as? Bool ?? false }
        set { AppSettings.defaults.set(newValue, forKey: RecordingKeys.recordSystemAudio) }
    }

    var recordMicrophone: Bool {
        get { AppSettings.defaults.object(forKey: RecordingKeys.recordMicrophone) as? Bool ?? false }
        set { AppSettings.defaults.set(newValue, forKey: RecordingKeys.recordMicrophone) }
    }

    var recordShowClicks: Bool {
        get { AppSettings.defaults.object(forKey: RecordingKeys.recordShowClicks) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: RecordingKeys.recordShowClicks) }
    }

    var recordShowCursor: Bool {
        get { AppSettings.defaults.object(forKey: RecordingKeys.recordShowCursor) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: RecordingKeys.recordShowCursor) }
    }

    var scrollCaptureAutoScroll: Bool {
        get { AppSettings.defaults.object(forKey: RecordingKeys.scrollAutoScroll) as? Bool ?? false }
        set { AppSettings.defaults.set(newValue, forKey: RecordingKeys.scrollAutoScroll) }
    }
}
