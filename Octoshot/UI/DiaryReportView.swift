import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OctoshotCore

struct DiaryReportView: View {
    let report: DiaryDailyReport
    var onClose: () -> Void = {}
    @State private var exportError = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text("一酱日记").font(.largeTitle.bold())
                    Text(DiaryReportText.date(report.day, calendar: report.calendar, format: "yyyy年M月d日"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("八只手 · 一本账").font(.callout).foregroundStyle(.secondary)
            }.padding(28)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("我是东太平洋红章鱼一酱 · Octopus rubescens")
                        .font(.callout).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("今天在干嘛").font(.title2.bold())
                        Text(report.overviewLine).textSelection(.enabled)
                        Text(report.focusPattern.summaryLine).font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    if report.timeline.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("今天还没有记录").font(.title3.bold())
                            Text("没有记录，不代表什么都没做。\n一酱先把八只手收好，等有记录再开工。")
                                .foregroundStyle(.secondary)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if !report.appInsights.isEmpty {
                        Text("各 App 都干了啥").font(.title2.bold())
                        ForEach(report.appInsights, id: \.appBundleID) { insight in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(insight.appName).font(.title3.bold())
                                    Spacer()
                                    Text("记录用时 " + DiaryReportText.duration(insight.totalDuration))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(Array(insight.bullets.enumerated()), id: \.offset) { _, bullet in
                                    Text("• " + bullet).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("时间线").font(.title2.bold())
                    }
                    ForEach(Array(report.timeline.enumerated()), id: \.offset) { _, segment in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(time(segment.skeleton.start) + " — " + time(segment.skeleton.end))
                                .font(.system(.callout, design: .monospaced).bold()).foregroundStyle(.secondary)
                            ForEach(Array(segment.skeleton.entries.enumerated()), id: \.offset) { _, entry in
                                Text(DiaryReportText.facts(entry)).font(.body).textSelection(.enabled)
                            }
                            if let roast = segment.roast { callout(roast) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    Text("一酱总结").font(.title2.bold())
                    if let roast = report.closingRoast { callout(roast) }
                }.padding(28)
            }
            Divider()
            HStack {
                Text("仅在本机 · 导出为明文").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("复制 Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DiaryMarkdownExporter().render(report), forType: .string)
                }
                Button("导出…") { export() }
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
            }.padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("导出失败", isPresented: $exportError) { Button("好", role: .cancel) {} }
    }

    private func time(_ date: Date) -> String {
        DiaryReportText.date(date, calendar: report.calendar, format: "HH:mm")
    }

    private func callout(_ text: String) -> some View {
        Text("一酱：" + text).italic().foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.16))
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "一酱日记-" + DiaryReportText.date(report.day, calendar: report.calendar, format: "yyyy-MM-dd") + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try DiaryMarkdownExporter().render(report).write(to: url, atomically: true, encoding: .utf8) }
        catch { exportError = true }
    }
}

@MainActor
final class DiaryReportWindowController: NSWindowController, NSWindowDelegate {
    init(report: DiaryDailyReport) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 850),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "一酱日记"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 500)
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: DiaryReportView(report: report, onClose: { [weak self] in self?.close() }))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        if SettingsWindowController.shared.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
    }
}
