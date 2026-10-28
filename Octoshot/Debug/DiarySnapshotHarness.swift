#if DEBUG
import AppKit
import SwiftUI
import OctoshotCore

@MainActor
enum DiarySnapshotHarness {
    static func runIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OCTOSHOT_QA_SNAPSHOT_DIARY"] == "1",
              let directory = environment["OCTOSHOT_QA_SNAPSHOT_DIR"] else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        do {
            let destination = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))!
            let apps = ["Cursor", "Safari", "Cursor", "Safari", "Cursor", "Cursor", "Terminal", "Notes"]
            let titles = ["示例项目 · 日报布局", "示例文档 · 焦点切换", "示例项目 · 日报布局", "示例文档 · Markdown",
                          "示例项目 · 骨架聚合", "示例项目 · 日报收尾", "示例测试 · 聚合边界", "示例待办 · 验收记录"]
            let snippets = ["聚合日报；焦点切换", "相邻 App 切换；同窗条目合并", "日报布局；文字优先",
                            "Markdown 标题；转义字符", "窗口标题去重；骨架文字分组", "空日报；导出预览",
                            "跨日窗口测试；固定时钟", "核对预览；待确认空状态"]
            var windows: [DiaryWindowSkeleton] = []
            for index in apps.indices {
                let start = day.addingTimeInterval(9 * 3600 + Double(index) * 600)
                let aggregator = DiaryWindowAggregator(clock: { start.addingTimeInterval(600) })
                _ = try aggregator.append(DiaryActivitySample(timestamp: start, appBundleID: "example." + apps[index],
                    appName: apps[index], windowTitle: titles[index], focusedText: snippets[index],
                    urlHost: apps[index] == "Safari" ? "docs.example.com" : nil))
                windows += try aggregator.observe(nil, at: start.addingTimeInterval(600))
            }
            let builder = DiaryReportBuilder(calendar: calendar, clock: { day.addingTimeInterval(22 * 3600) })
            var chatIndex = 0
            let client = DiaryOllamaClient(transport: { request in
                let payload: [String: Any]
                switch request.url!.lastPathComponent {
                case "version": payload = ["version": "0.40.5"]
                case "tags": payload = ["models": [["name": DiaryOllamaConfiguration.defaultModel]]]
                default:
                    let window = windows[chatIndex]
                    let ending = DiaryRoastQualityGate.endings[chatIndex % DiaryRoastQualityGate.endings.count]
                    chatIndex += 1
                    payload = ["message": ["content": "<think>离线示例</think>「\(window.entries[0].windowTitle.prefix(14))」，\(ending)。"]]
                }
                return (try JSONSerialization.data(withJSONObject: payload),
                        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            let service = DiaryOllamaRoastService(defaults: SettingsSnapshotDefaults()) { client }
            let roast = await service.prepare(windows: windows)
            try render(DiaryReportView(report: builder.build(windows: windows, day: day, roastProvider: roast)),
                       size: NSSize(width: 900, height: 2400), to: destination.appendingPathComponent("diary-report-full.png"))
            try render(DiaryReportView(report: builder.build(windows: [], day: day, roastProvider: roast)),
                       size: NSSize(width: 900, height: 900), to: destination.appendingPathComponent("diary-report-empty.png"))
            let model = DiaryReportCoordinator(defaults: SettingsSnapshotDefaults())
            let statuses: [(String, DiaryOllamaStatus)] = [("not-running", .notRunning),
                ("version-too-old", .versionTooOld(found: "0.39.0")), ("model-missing", .modelMissing), ("ready", .ready)]
            for (name, status) in statuses {
                try render(SettingsDiaryPane(model: model, preview: .init(status: status)), size: NSSize(width: 820, height: 1100),
                           to: destination.appendingPathComponent("settings-ollama-\(name).png"))
            }
            let failedClient = DiaryOllamaClient(transport: { _ in throw URLError(.cannotConnectToHost) })
            let failedService = DiaryOllamaRoastService(defaults: SettingsSnapshotDefaults()) { failedClient }
            let fallback = await failedService.prepare(windows: windows)
            try render(DiaryReportView(report: builder.build(windows: windows, day: day, roastProvider: fallback)),
                       size: NSSize(width: 900, height: 2400), to: destination.appendingPathComponent("diary-report-fallback.png"))
            try render(SettingsDiaryPane(model: model, preview: .init(status: .notRunning,
                failureReason: failedService.disabledReason)), size: NSSize(width: 820, height: 1100),
                       to: destination.appendingPathComponent("settings-ollama-disabled.png"))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Diary snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func render<Content: View>(_ content: Content, size: NSSize, to url: URL) throws {
        let view = content.environment(\.locale, OctoshotL10n.snapshotLocale).environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        window.contentView = nil
        window.close()
    }
}
#endif
