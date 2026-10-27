import AppKit
import SwiftUI
import UserNotifications
import OctoshotCore

struct DiarySystemNotifications: DiaryReportNotificationScheduling {
    static let identifier = "yijiang-diary.daily-report"

    func replaceReportNotification(fireDate: Date?, calendar: Calendar) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard let fireDate else { return }
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "一酱写好今天的日记了"
        content.body = "八只手的流水账，点开看看。没有记录也可以来坐坐。"
        content.userInfo = ["diaryDate": "deliveryDate"]
        let components = calendar.dateComponents([.hour, .minute], from: fireDate)
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
    }
}

@MainActor
final class DiaryReportCoordinator: ObservableObject {
    static let shared = DiaryReportCoordinator()
    @Published private(set) var settings: DiarySettings
    @Published private(set) var error: String?
    var roastFailureReason: String? { DiaryMiniCPMRuntime.service.disabledReason }
    @Published private(set) var buildingReport = false
    @Published var roastEnabled: Bool {
        didSet { defaults.set(roastEnabled, forKey: "diary.minicpm.enabled") }
    }
    private let defaults: UserDefaults
    private var scheduling: Task<Void, Never>?
    private var reportWindow: DiaryReportWindowController?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        roastEnabled = defaults.bool(forKey: "diary.minicpm.enabled")
        do { settings = try DiarySettings.load(from: defaults) }
        catch { settings = DiarySettings(); self.error = OctoshotL10n.text("Could not load diary settings.") }
    }

    func update(_ newSettings: DiarySettings) {
        let requestPermission = !settings.enabled && newSettings.enabled
        do {
            try newSettings.save(to: defaults)
            settings = newSettings
            error = nil
            reschedule(requestPermission: requestPermission)
        } catch { self.error = OctoshotL10n.text("Could not save diary settings.") }
    }

    func reschedule(requestPermission: Bool = false) {
        let previous = scheduling
        scheduling = Task {
            await previous?.value
            do {
                if requestPermission && settings.enabled {
                    let center = UNUserNotificationCenter.current()
                    if await center.notificationSettings().authorizationStatus == .notDetermined {
                        _ = try await center.requestAuthorization(options: [.alert, .sound])
                    }
                }
                try await DiaryReportScheduler().reschedule(settings: settings, using: DiarySystemNotifications())
            } catch { self.error = OctoshotL10n.text("Report notifications are unavailable. You can still open the diary from the menu.") }
        }
    }

    func open(day: Date) {
        guard !buildingReport else { return }
        buildingReport = true
        Task { @MainActor in
            defer { buildingReport = false }
            do {
                let database = DiaryStore.defaultDirectory.appendingPathComponent("diary.sqlite")
                let windows = FileManager.default.fileExists(atPath: database.path) ? try DiaryStore().fetch(day: day) : []
                let roasts = roastEnabled
                    ? await DiaryMiniCPMRuntime.service.prepare(windows: windows, keyFrame: DiaryMiniCPMRuntime.keyFrameData)
                    : DiaryPreparedRoasts(lines: [])
                let report = DiaryReportBuilder().build(windows: windows, day: day, roastProvider: roasts)
                reportWindow?.close()
                reportWindow = DiaryReportWindowController(report: report)
                reportWindow?.show()
            } catch {
                let alert = NSAlert()
                alert.messageText = OctoshotL10n.text("Could not read the diary. Your records have not been changed.")
                alert.runModal()
            }
        }
    }
}
