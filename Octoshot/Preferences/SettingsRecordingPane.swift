import SwiftUI

struct SettingsRecordingPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(
                title: OctoshotL10n.text("Recording"),
                subtitle: OctoshotL10n.text("Area capture modes, GIF export, scroll capture, and screen recording defaults"),
                systemImage: "record.circle"
            )

            Section {
                Toggle(OctoshotL10n.text("Remember last area capture mode"), isOn: $settings.rememberAreaCaptureMode)
                Text(OctoshotL10n.text("While dragging a region, press S screenshot, R scroll, V video, G GIF, L LaTeX, or T figure/table on the mode bar."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(OctoshotL10n.text("Area selection"), systemImage: "viewfinder")
            }

            Section {
                Toggle(OctoshotL10n.text("Show pointer in recordings"), isOn: $settings.recordShowCursor)
                Toggle(OctoshotL10n.text("Highlight clicks (planned)"), isOn: $settings.recordShowClicks)
                    .disabled(true)
                Toggle(OctoshotL10n.text("Capture system audio (planned)"), isOn: $settings.recordSystemAudio)
                    .disabled(true)
                Toggle(OctoshotL10n.text("Capture microphone (planned)"), isOn: $settings.recordMicrophone)
                    .disabled(true)
                Text(OctoshotL10n.text("Video uses ScreenCaptureKit (H.264 MP4). Audio tracks will land in a follow-up release."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(OctoshotL10n.text("Screen recording"), systemImage: "video")
            }

            Section {
                HStack {
                    Text(OctoshotL10n.text("GIF frame rate"))
                    Slider(value: $settings.gifFPS, in: 5...20, step: 1)
                    Text("\(Int(settings.gifFPS)) fps")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                Stepper(value: $settings.gifMaxWidth, in: 320...1920, step: 80) {
                    Text(OctoshotL10n.format("Max GIF width: %d px", settings.gifMaxWidth))
                }
            } header: {
                Label(OctoshotL10n.text("GIF export"), systemImage: "photo.stack")
            }

            Section {
                Toggle(OctoshotL10n.text("Auto-scroll while capturing"), isOn: $settings.scrollCaptureAutoScroll)
                Text(OctoshotL10n.text("Requires Accessibility permission to post scroll wheel events. You can always scroll manually during capture."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(OctoshotL10n.text("Scrolling capture"), systemImage: "arrow.up.and.down.text.horizontal")
            }
        }
    }
}
