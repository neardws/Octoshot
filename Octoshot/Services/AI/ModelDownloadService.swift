import Foundation
import OctoshotCore

extension Notification.Name {
    static let octoshotModelDownloadProgress = Notification.Name("OctoshotModelDownloadProgress")
}

struct ModelDownloadProgress: Sendable {
    let model: EmbeddedModelID
    let fraction: Double
    let status: String
}

@MainActor
final class ModelDownloadService {
    static let shared = ModelDownloadService()

    private var active: EmbeddedModelID?

    func download(_ model: EmbeddedModelID) async throws {
        guard active == nil else {
            throw EmbeddedAIError.downloadFailed(OctoshotL10n.text("Another download is already in progress."))
        }
        active = model
        defer { active = nil }

        let destination = EmbeddedAIModelPaths.directory(for: model)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        postProgress(model, fraction: 0, status: OctoshotL10n.text("Listing files…"))
        let files = try await listRemoteFiles(repo: model.huggingFaceRepo, model: model)
        guard !files.isEmpty else {
            throw EmbeddedAIError.downloadFailed(OctoshotL10n.format("No files found for %@", model.huggingFaceRepo))
        }

        var completedBytes: Int64 = 0
        let totalBytes = max(files.compactMap(\.size).reduce(0, +), 1)

        for entry in files {
            let localURL = destination.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: localURL.path) {
                completedBytes += entry.size ?? 0
                continue
            }
            postProgress(model, fraction: Double(completedBytes) / Double(totalBytes), status: OctoshotL10n.format("Downloading %@…", entry.path))
            try await downloadFile(repo: model.huggingFaceRepo, path: entry.path, to: localURL) { chunk in
                completedBytes += chunk
                postProgress(
                    model,
                    fraction: min(1, Double(completedBytes) / Double(totalBytes)),
                    status: OctoshotL10n.format("Downloading %@…", entry.path)
                )
            }
        }

        postProgress(model, fraction: 1, status: OctoshotL10n.text("Download complete"))
        if model == .smolVLM2_500M_4bit {
            EmbeddedAISettings.markEmbeddedVLMInstalled()
        }
    }

    func delete(_ model: EmbeddedModelID) throws {
        let dir = EmbeddedAIModelPaths.directory(for: model)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        postProgress(model, fraction: 0, status: OctoshotL10n.text("Removed"))
    }

    private func postProgress(_ model: EmbeddedModelID, fraction: Double, status: String) {
        let payload = ModelDownloadProgress(model: model, fraction: fraction, status: status)
        NotificationCenter.default.post(name: .octoshotModelDownloadProgress, object: payload)
    }

    private struct RemoteFile {
        let path: String
        let size: Int64?
    }

    private func listRemoteFiles(repo: String, model: EmbeddedModelID) async throws -> [RemoteFile] {
        if let gguf = model.primaryGGUFFileName {
            return [RemoteFile(path: gguf, size: Int64(model.approximateSizeMB) * 1_024 * 1_024)]
        }
        let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main?recursive=1")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmbeddedAIError.downloadFailed(OctoshotL10n.format("Could not list %@", repo))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json.compactMap { item in
            guard let path = item["path"] as? String else { return nil }
            if path.hasSuffix(".md") && path != "README.md" { return nil }
            if path.contains(".git") { return nil }
            let size = (item["size"] as? NSNumber)?.int64Value
            return RemoteFile(path: path, size: size)
        }
    }

    private func downloadFile(
        repo: String,
        path: String,
        to localURL: URL,
        onBytes: (Int64) -> Void
    ) async throws {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(encoded)")!
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmbeddedAIError.downloadFailed(OctoshotL10n.format("HTTP error for %@", path))
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        onBytes(size)
    }
}
