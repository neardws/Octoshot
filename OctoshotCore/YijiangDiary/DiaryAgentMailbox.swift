import Foundation

public struct DiaryAgentMailbox {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Octoshot/DiaryIPC", isDirectory: true)
    }
    public let directory: URL

    public init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    public func prepare(_ request: DiaryAgentRequest) throws -> String {
        try DiaryStore.prepareDirectory(directory, fileManager: .default)
        let identifier = UUID().uuidString
        let folder = directory.appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            try JSONEncoder().encode(request).write(to: folder.appendingPathComponent("request.json"), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                ofItemAtPath: folder.appendingPathComponent("request.json").path)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return identifier
    }

    public func url(for identifier: String) -> URL {
        var components = URLComponents()
        components.scheme = "octoshot"
        components.host = "diary"
        components.queryItems = [URLQueryItem(name: "request", value: identifier)]
        return components.url!
    }

    public func serve(_ url: URL, using service: DiaryAgentService) throws {
        guard url.scheme == "octoshot", url.host == "diary",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 1, items[0].name == "request", let identifier = items[0].value else {
            throw DiaryAgentError("Invalid diary IPC URL")
        }
        let folder = try validatedFolder(identifier)
        let input = folder.appendingPathComponent("request.json")
        let attributes = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let modified = attributes.contentModificationDate, abs(modified.timeIntervalSinceNow) < 120 else {
            throw DiaryAgentError("Expired or unsafe diary request")
        }
        let data = try Data(contentsOf: input)
        try FileManager.default.removeItem(at: input)
        let response: DiaryAgentResponse
        do { response = service.handle(try JSONDecoder().decode(DiaryAgentRequest.self, from: data)) }
        catch { response = DiaryAgentResponse(error: error.localizedDescription) }
        let output = folder.appendingPathComponent("reply.json")
        guard !FileManager.default.fileExists(atPath: output.path) else { throw DiaryAgentError("Diary reply already exists") }
        try JSONEncoder().encode(response).write(to: output, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
    }

    public func response(for identifier: String) throws -> DiaryAgentResponse? {
        let output = try validatedFolder(identifier).appendingPathComponent("reply.json")
        guard FileManager.default.fileExists(atPath: output.path) else { return nil }
        let attributes = try output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
            throw DiaryAgentError("Unsafe diary reply")
        }
        return try JSONDecoder().decode(DiaryAgentResponse.self, from: Data(contentsOf: output))
    }

    public func remove(_ identifier: String) {
        guard let folder = try? validatedFolder(identifier) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    private func validatedFolder(_ identifier: String) throws -> URL {
        guard UUID(uuidString: identifier)?.uuidString == identifier else { throw DiaryAgentError("Invalid diary request ID") }
        let folder = directory.appendingPathComponent(identifier, isDirectory: true)
        for path in [directory, folder] {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  path.resolvingSymlinksInPath().standardizedFileURL == path.standardizedFileURL else {
                throw DiaryAgentError("Unsafe diary IPC directory")
            }
        }
        return folder
    }
}
