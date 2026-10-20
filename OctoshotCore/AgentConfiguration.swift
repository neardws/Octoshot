import Foundation

/// UserDefaults-backed settings shared by the GUI app, CLI, and MCP server.
public enum AgentConfiguration {
    public static var captureShowCursor: Bool {
        UserDefaults.standard.object(forKey: "captureShowCursor") as? Bool ?? false
    }

    public static var captureWindowWithShadow: Bool {
        UserDefaults.standard.object(forKey: "captureWindowWithShadow") as? Bool ?? true
    }
    private enum Keys {
        static let aiBaseURL = "aiBaseURL"
        static let aiVisionModel = "aiVisionModel"
        static let aiAPIKey = "aiAPIKey"
        static let clipsLibraryDirectory = "clipsLibraryDirectory"
        static let saveDirectory = "saveDirectory"
        static let format = "screenshotFormat"
        static let jpegQuality = "jpegQuality"
        static let redactPhones = "redactPhones"
        static let redactEmails = "redactEmails"
        static let redactNationalIDs = "redactNationalIDs"
        static let redactCreditCards = "redactCreditCards"
        static let redactAPIKeys = "redactAPIKeys"
        static let redactIPAddresses = "redactIPAddresses"
        static let redactFaces = "redactFaces"
    }

    public static var aiBaseURL: URL {
        if let raw = UserDefaults.standard.string(forKey: Keys.aiBaseURL),
           let url = URL(string: raw) { return url }
        return URL(string: "http://localhost:11434/v1")!
    }

    public static var aiVisionModel: String {
        UserDefaults.standard.string(forKey: Keys.aiVisionModel) ?? "qwen2.5vl:latest"
    }

    public static var aiAPIKey: String {
        UserDefaults.standard.string(forKey: Keys.aiAPIKey) ?? ""
    }

    public static var clipsLibraryDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: Keys.clipsLibraryDirectory) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/Octoshot Clips", isDirectory: true)
    }

    public static var saveDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: Keys.saveDirectory) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    public static var screenshotFormat: String {
        UserDefaults.standard.string(forKey: Keys.format) ?? "png"
    }

    public static var jpegQuality: Double {
        let q = UserDefaults.standard.double(forKey: Keys.jpegQuality)
        return q > 0 ? q : 0.85
    }

    public static func redactionSettings() -> RedactionSettingsSnapshot {
        RedactionSettingsSnapshot(
            redactPhones: UserDefaults.standard.object(forKey: Keys.redactPhones) as? Bool ?? true,
            redactEmails: UserDefaults.standard.object(forKey: Keys.redactEmails) as? Bool ?? true,
            redactNationalIDs: UserDefaults.standard.object(forKey: Keys.redactNationalIDs) as? Bool ?? true,
            redactCreditCards: UserDefaults.standard.object(forKey: Keys.redactCreditCards) as? Bool ?? true,
            redactAPIKeys: UserDefaults.standard.object(forKey: Keys.redactAPIKeys) as? Bool ?? true,
            redactIPAddresses: UserDefaults.standard.object(forKey: Keys.redactIPAddresses) as? Bool ?? true,
            redactFaces: UserDefaults.standard.object(forKey: Keys.redactFaces) as? Bool ?? true
        )
    }

    public static func openAIClient() -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            baseURL: aiBaseURL,
            model: aiVisionModel,
            apiKey: aiAPIKey.isEmpty ? nil : aiAPIKey
        )
    }
}
