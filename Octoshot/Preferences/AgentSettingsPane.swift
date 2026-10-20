import AppKit
import SwiftUI
import OctoshotCore

struct AgentSettingsPane: View {
    @State private var installStatus = ""
    @State private var isInstalled = CommandLineToolInstaller.isInstalledCorrectly()
    @State private var urlSchemePolicy = AppSettings.shared.urlSchemePolicy
    @State private var trustedCallerCount = AppSettings.shared.urlSchemeTrustedCallers.count

    var body: some View {
        Group {
            Section {
                Text("Install the `octoshot` CLI for Terminal, Claude Code, and Cursor MCP. The installer symlinks to the copy embedded in this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Install path")
                    Spacer()
                    Text(CommandLineToolInstaller.installPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isInstalled ? .green : .secondary)
                    Text(isInstalled ? "Command line tool is installed" : "Not installed at /usr/local/bin/octoshot")
                    Spacer()
                    Button("Install Command Line Tool") {
                        installCLI()
                    }
                }

                if !installStatus.isEmpty {
                    Text(installStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Agent / CLI", systemImage: "terminal")
            }

            Section {
                Text(CommandLineToolInstaller.mcpConfigSnippet())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Copy MCP JSON") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CommandLineToolInstaller.mcpConfigSnippet(), forType: .string)
                }
            } header: {
                Label("MCP configuration", systemImage: "curlybraces")
            }

            Section {
                Picker(OctoshotL10n.urlSchemePolicyLabel, selection: $urlSchemePolicy) {
                    ForEach(URLSchemeAutomationPolicy.allCases) { policy in
                        Text(OctoshotL10n.urlSchemePolicyName(policy)).tag(policy)
                    }
                }
                .onChange(of: urlSchemePolicy) { _, policy in
                    AppSettings.shared.urlSchemePolicy = policy
                }
                Text(OctoshotL10n.urlSchemeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if trustedCallerCount > 0 {
                    Button(OctoshotL10n.urlSchemeForgetTrusted(count: trustedCallerCount)) {
                        AppSettings.shared.urlSchemeTrustedCallers = []
                        trustedCallerCount = 0
                    }
                }
            } header: {
                Label(OctoshotL10n.urlSchemeSectionTitle, systemImage: "link")
            }
        }
        .onAppear {
            isInstalled = CommandLineToolInstaller.isInstalledCorrectly()
            urlSchemePolicy = AppSettings.shared.urlSchemePolicy
            trustedCallerCount = AppSettings.shared.urlSchemeTrustedCallers.count
        }
    }

    private func installCLI() {
        do {
            let url = try CommandLineToolInstaller.install()
            isInstalled = true
            installStatus = "Installed at \(url.path)"
        } catch {
            isInstalled = CommandLineToolInstaller.isInstalledCorrectly()
            installStatus = error.localizedDescription
            let alert = NSAlert()
            alert.messageText = "Could not install octoshot"
            alert.informativeText = """
            \(error.localizedDescription)

            You may need to run once with administrator privileges, for example:
            sudo ln -sf "\(CommandLineToolInstaller.bundledToolURL()?.path ?? "…/Octoshot.app/Contents/Helpers/octoshot")" /usr/local/bin/octoshot
            """
            alert.runModal()
        }
    }
}
