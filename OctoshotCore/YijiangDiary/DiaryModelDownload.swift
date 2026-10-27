import CryptoKit
import Foundation

public struct DiaryModelFile: Codable, Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let sha256: String?

    public init(path: String, size: Int64, sha256: String? = nil) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }
}

public enum DiaryModelDownloadError: LocalizedError {
    case invalidListing, insufficientSpace(required: Int64, available: Int64), invalidFile(String)

    public var errorDescription: String? {
        switch self {
        case .invalidListing: return "MiniCPM 文件列表不完整或不安全，请重试。"
        case let .insufficientSpace(required, available):
            return "空间不足：需要 \(required / 1_000_000) MB，可用 \(available / 1_000_000) MB。"
        case let .invalidFile(path): return "MiniCPM 文件校验失败：\(path)；重试会重新下载该文件。"
        }
    }
}

public enum DiaryModelDownload {
    public static let manifestName = ".verified-install.json"
    public static let reserveBytes: Int64 = 512 * 1024 * 1024

    public static func parseListing(_ data: Data) throws -> [DiaryModelFile] {
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DiaryModelDownloadError.invalidListing
        }
        let files = try objects.compactMap { object -> DiaryModelFile? in
            guard object["type"] as? String == "file" else { return nil }
            guard let path = object["path"] as? String,
                  let size = (object["size"] as? NSNumber)?.int64Value else {
                throw DiaryModelDownloadError.invalidListing
            }
            guard ["json", "safetensors", "model", "tiktoken", "txt", "jinja"].contains((path as NSString).pathExtension) else { return nil }
            let lfs = object["lfs"] as? [String: Any]
            return DiaryModelFile(path: path, size: size, sha256: lfs?["oid"] as? String)
        }
        try validateListing(files)
        return files
    }

    public static func validateListing(_ files: [DiaryModelFile]) throws {
        guard files.contains(where: { $0.path == "config.json" }),
              files.contains(where: { $0.path == "tokenizer.json" }),
              files.contains(where: { $0.path.hasSuffix(".safetensors") }),
              Set(files.map(\.path)).count == files.count,
              files.allSatisfy({ file in
                  !file.path.isEmpty && !file.path.hasPrefix("/") && !file.path.contains("\\") &&
                  !file.path.split(separator: "/").contains(where: { $0 == ".." || $0.hasPrefix(".") }) &&
                  file.size > 0 && file.size < 10_000_000_000 &&
                  (file.sha256 == nil || file.sha256!.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil)
              }) else { throw DiaryModelDownloadError.invalidListing }
    }

    public static func availableBytes(at directory: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        return (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    public static func checkSpace(remaining: Int64, available: Int64) throws {
        let required = remaining + reserveBytes
        guard available >= required else {
            throw DiaryModelDownloadError.insufficientSpace(required: required, available: available)
        }
    }

    public static func matches(_ file: DiaryModelFile, at url: URL, verifyHash: Bool = true) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == file.size else { return false }
        guard verifyHash, let expected = file.sha256 else { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var hash = SHA256()
        do {
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined() == expected.lowercased()
        } catch { return false }
    }

    public static func isInstalled(in directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(manifestName)),
              let files = try? JSONDecoder().decode([DiaryModelFile].self, from: data),
              (try? validateListing(files)) != nil else { return false }
        return files.allSatisfy {
            let url = directory.appendingPathComponent($0.path)
            return staysInside(url, directory: directory) && matches($0, at: url, verifyHash: false)
        }
    }

    public static func install(
        in directory: URL,
        listing: () async throws -> [DiaryModelFile],
        availableSpace: (URL) throws -> Int64 = availableBytes,
        fetch: (DiaryModelFile, URL) async throws -> Void,
        progress: (Double, String) -> Void = { _, _ in }
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try await listing()
        try validateListing(files)
        guard files.allSatisfy({ staysInside(directory.appendingPathComponent($0.path), directory: directory) }) else {
            throw DiaryModelDownloadError.invalidListing
        }
        let marker = directory.appendingPathComponent(manifestName)
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
        let reusable = Set(files.filter { matches($0, at: directory.appendingPathComponent($0.path)) }.map(\.path))
        let remaining = files.filter { !reusable.contains($0.path) }.reduce(Int64(0)) { $0 + $1.size }
        try checkSpace(remaining: remaining, available: availableSpace(directory))
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        var completed = total - remaining
        for file in files where !reusable.contains(file.path) {
            try Task.checkCancellation()
            try checkSpace(remaining: file.size, available: availableSpace(directory))
            progress(Double(completed) / Double(total), "下载 \(file.path)…")
            let target = directory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = target.appendingPathExtension("partial")
            guard staysInside(partial, directory: directory) else { throw DiaryModelDownloadError.invalidListing }
            if FileManager.default.fileExists(atPath: partial.path) { try FileManager.default.removeItem(at: partial) }
            defer { try? FileManager.default.removeItem(at: partial) }
            try await fetch(file, partial)
            guard matches(file, at: partial) else { throw DiaryModelDownloadError.invalidFile(file.path) }
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: partial, to: target)
            completed += file.size
            progress(Double(completed) / Double(total), "已校验 \(file.path)")
        }
        try JSONEncoder().encode(files).write(to: marker, options: .atomic)
        progress(1, "下载完成，可开启一酱吐槽")
    }

    private static func staysInside(_ url: URL, directory: URL) -> Bool {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root)
    }
}
