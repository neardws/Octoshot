import SwiftUI
import OctoshotCore

struct SettingsDiaryPane: View {
    @ObservedObject var model: DiaryReportCoordinator = .shared

    var body: some View {
        SettingsFormContainer {
            SettingsPaneHeader(title: OctoshotL10n.text("Yijiang Diary"),
                               subtitle: OctoshotL10n.text("A local diary, with eight helping hands"),
                               systemImage: "book.closed")
            Toggle(OctoshotL10n.text("Enable diary"), isOn: binding(\.enabled))
            DatePicker(OctoshotL10n.text("Daily report time"), selection: time, displayedComponents: .hourAndMinute)
            Picker(OctoshotL10n.text("Keep diary records"), selection: binding(\.retentionDays)) {
                Text(OctoshotL10n.text("7 days")).tag(Int?.some(7))
                Text(OctoshotL10n.text("30 days")).tag(Int?.some(30))
                Text(OctoshotL10n.text("90 days")).tag(Int?.some(90))
                Text(OctoshotL10n.text("Forever")).tag(Int?.none)
            }
            Button(OctoshotL10n.text("Read today's diary")) { model.open(day: Date()) }
            Text(OctoshotL10n.text("Diary stays on this Mac, encrypted and never uploaded. Markdown exports are unencrypted."))
                .font(.callout).foregroundStyle(.secondary)
            Text(OctoshotL10n.text("This milestone reads existing records only. Live recording and the roast model come later. Notifications require permission; the menu always works."))
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<DiarySettings, Value>) -> Binding<Value> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in
            var settings = model.settings
            settings[keyPath: keyPath] = value
            model.update(settings)
        })
    }

    private var time: Binding<Date> {
        Binding(get: {
            let parts = model.settings.dailyReportTime.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var settings = model.settings
            settings.dailyReportTime = String(format: "%02d:%02d", parts.hour!, parts.minute!)
            model.update(settings)
        })
    }
}
