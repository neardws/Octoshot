import Foundation
import Combine
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
final class ModelDownloadService: ObservableObject {
    static let shared = ModelDownloadService()

    @Published private(set) var active: EmbeddedModelID?
    @Published private(set) var latestProgress: ModelDownloadProgress?

    func download(_ model: EmbeddedModelID) async throws {
        guard active == nil else {
            throw EmbeddedAIError.downloadFailed(OctoshotL10n.text("Another download is already in progress."))
        }
        active = model
        defer { active = nil }

        if model == .miniCPMV46_4bit {
            do { try await downloadDiaryModel() }
            catch {
                postProgress(model, fraction: 0, status: error.localizedDescription)
                throw error
            }
            return
        }

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
        guard active != model else {
            throw EmbeddedAIError.downloadFailed("请等待下载完成后再删除。")
        }
        let dir = EmbeddedAIModelPaths.directory(for: model)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        postProgress(model, fraction: 0, status: OctoshotL10n.text("Removed"))
    }

    private func postProgress(_ model: EmbeddedModelID, fraction: Double, status: String) {
        let payload = ModelDownloadProgress(model: model, fraction: fraction, status: status)
        latestProgress = payload
        NotificationCenter.default.post(name: .octoshotModelDownloadProgress, object: payload)
    }

    private func downloadDiaryModel() async throws {
        let model = EmbeddedModelID.miniCPMV46_4bit
        postProgress(model, fraction: 0, status: "读取 MiniCPM 文件列表…")
        try await DiaryModelDownload.install(in: EmbeddedAIModelPaths.directory(for: model), listing: {
            var next: URL? = URL(string: "https://huggingface.co/api/models/\(model.huggingFaceRepo)/tree/main?recursive=true&limit=1000")!
            var objects: [[String: Any]] = []
            var visited: Set<URL> = []
            while let url = next {
                guard url.scheme == "https", url.host == "huggingface.co",
                      url.path == "/api/models/\(model.huggingFaceRepo)/tree/main",
                      visited.insert(url).inserted, visited.count <= 20 else {
                    throw DiaryModelDownloadError.invalidListing
                }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let page = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    throw EmbeddedAIError.downloadFailed("无法读取 MiniCPM 文件列表。")
                }
                objects += page
                next = nil
                for link in (http.value(forHTTPHeaderField: "Link") ?? "").components(separatedBy: ",") {
                    if link.contains("rel=\"next\""), let start = link.firstIndex(of: "<"), let end = link.firstIndex(of: ">") {
                        next = URL(string: String(link[link.index(after: start)..<end]))
                    }
                }
            }
            return try DiaryModelDownload.parseListing(JSONSerialization.data(withJSONObject: objects))
        }, fetch: { file, destination in
            let encoded = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
            let url = URL(string: "https://huggingface.co/\(model.huggingFaceRepo)/resolve/main/\(encoded)")!
            let delegate = DiaryDownloadProgressDelegate { written, total in
                guard self.active == model else { return }
                self.postProgress(model, fraction: total > 0 ? Double(written) / Double(total) : 0,
                                  status: "下载 \(file.path)：\(written / 1_000_000) / \(max(total, 0) / 1_000_000) MB（当前文件）")
            }
            let (temporary, response) = try await URLSession.shared.download(from: url, delegate: delegate)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw EmbeddedAIError.downloadFailed("下载失败：\(file.path)")
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        }, progress: { fraction, status in
            self.postProgress(model, fraction: fraction, status: status)
        })
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

private final class DiaryDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @MainActor (Int64, Int64) -> Void

    init(progress: @escaping @MainActor (Int64, Int64) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in progress(totalBytesWritten, totalBytesExpectedToWrite) }
    }
}
