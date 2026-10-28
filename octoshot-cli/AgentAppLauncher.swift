import AppKit
import Foundation
import OctoshotCore

enum AgentAppLauncher {
    private static let bundleID = "com.neardws.Octoshot"

    @MainActor
    static func openRunningDiaryURL(_ url: URL) async throws {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let appURL = running.bundleURL else {
            throw DiaryAgentError("Octoshot must already be running with diary enabled")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }

    static func openOctoshotURL(_ url: URL) throws {
        let workspace = NSWorkspace.shared
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            throw NSError(domain: "Octoshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Octoshot app is not installed"])
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        workspace.open([url], withApplicationAt: appURL, configuration: configuration, completionHandler: nil)
    }

    static func recordURL(action: String, mode: String = "fullscreen", format: String = "video", rect: String? = nil) -> URL {
        var items = [
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "mode", value: mode),
            URLQueryItem(name: "format", value: format)
        ]
        if let rect {
            items.append(URLQueryItem(name: "rect", value: rect))
        }
        var components = URLComponents()
        components.scheme = "octoshot"
        components.host = "record"
        components.queryItems = items
        return components.url ?? URL(string: "octoshot://record?action=\(action)")!
    }
}
