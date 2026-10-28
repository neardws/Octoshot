import AppKit
import Foundation
import OctoshotCore

enum DiaryAgentClient {
    @MainActor
    static func send(_ request: DiaryAgentRequest) async throws -> DiaryAgentResponse {
        let mailbox = DiaryAgentMailbox()
        let identifier = try mailbox.prepare(request)
        defer { mailbox.remove(identifier) }
        try await AgentAppLauncher.openRunningDiaryURL(mailbox.url(for: identifier))
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while ContinuousClock.now < deadline {
            if let response = try mailbox.response(for: identifier) {
                if let error = response.error { throw DiaryAgentError(error) }
                return response
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DiaryAgentError("Timed out waiting for the running Octoshot app (30 seconds)")
    }
}
