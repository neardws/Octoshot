import Foundation
import OctoshotCore

struct OllamaModel: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

enum OllamaService {
    static let defaultHost = URL(string: "http://127.0.0.1:11434")!

    static func hostURL(from settingsBase: URL) -> URL {
        guard var components = URLComponents(url: settingsBase, resolvingAgainstBaseURL: false) else {
            return defaultHost
        }
        if components.path.hasSuffix("/v1") {
            components.path = String(components.path.dropLast(2))
        }
        if components.path == "/" || components.path.isEmpty {
            components.path = ""
        }
        return components.url ?? defaultHost
    }

    static func isReachable(baseURL: URL = AgentConfiguration.aiBaseURL) async -> Bool {
        await listModels(baseURL: baseURL) != nil
    }

    static func listModels(baseURL: URL = AgentConfiguration.aiBaseURL) async -> [OllamaModel]? {
        let host = hostURL(from: baseURL)
        let endpoint = host.appendingPathComponent("api/tags")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { $0["name"] as? String }.map { OllamaModel(name: $0) }
        } catch {
            return nil
        }
    }

    static func pullModel(
        _ name: String,
        baseURL: URL = AgentConfiguration.aiBaseURL,
        onStatus: @escaping (String) -> Void
    ) async throws {
        let host = hostURL(from: baseURL)
        let endpoint = host.appendingPathComponent("api/pull")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.pullFailed
        }
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let status = json["status"] as? String {
                onStatus(status)
            }
            if json["error"] != nil {
                throw OllamaError.pullFailed
            }
        }
    }

    static func friendlyAIError(_ error: Error, model: String) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return """
                Could not reach Ollama at \(AgentConfiguration.aiBaseURL.absoluteString).
                Install Ollama from https://ollama.com, run `ollama serve`, then pull a vision model (e.g. `ollama pull qwen2.5vl`).
                """
            default:
                break
            }
        }
        if let ai = error as? AIClientError {
            switch ai {
            case .server(let message) where message.contains("404"):
                return "Model “\(model)” was not found. In Settings → AI, pull `qwen2.5vl` or choose an installed model."
            case .server(let message):
                return message
            default:
                return ai.localizedDescription
            }
        }
        return error.localizedDescription
    }

    enum OllamaError: LocalizedError {
        case pullFailed

        var errorDescription: String? {
            switch self {
            case .pullFailed:
                return OctoshotL10n.text("Ollama could not pull the model. Ensure Ollama is running and try `ollama pull qwen2.5vl` in Terminal.")
            }
        }
    }
}
