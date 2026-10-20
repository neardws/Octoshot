import Foundation

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case shortcuts
    case capture
    case recording
    case annotation
    case ai
    case developer
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return OctoshotL10n.text("General")
        case .shortcuts: return OctoshotL10n.text("Shortcuts")
        case .capture: return OctoshotL10n.text("Capture")
        case .recording: return OctoshotL10n.text("Recording")
        case .annotation: return OctoshotL10n.text("Annotation")
        case .ai: return OctoshotL10n.text("AI")
        case .developer: return OctoshotL10n.text("Developer")
        case .about: return OctoshotL10n.text("About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "command"
        case .capture: return "camera.viewfinder"
        case .recording: return "record.circle"
        case .annotation: return "pencil.and.outline"
        case .ai: return "brain"
        case .developer: return "hammer"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return OctoshotL10n.text("Startup, menu bar, and after capture")
        case .shortcuts: return OctoshotL10n.text("Global hotkeys and macOS screenshots")
        case .capture: return OctoshotL10n.text("Save folder, format, and quick access")
        case .recording: return OctoshotL10n.text("Video, GIF, scroll capture, and mode bar")
        case .annotation: return OctoshotL10n.text("Redaction and annotate defaults")
        case .ai: return OctoshotL10n.text("Embedded SmolVLM2, pix2tex, optional Ollama")
        case .developer: return OctoshotL10n.text("Dev tools and Agent CLI")
        case .about: return OctoshotL10n.text("Version and license")
        }
    }
}
