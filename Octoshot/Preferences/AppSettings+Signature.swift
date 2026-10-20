import Foundation
import OctoshotCore

extension AppSettings {
    private enum SignatureKeys {
        static let aiBaseURL = "aiBaseURL"
        static let aiVisionModel = "aiVisionModel"
        static let aiAPIKey = "aiAPIKey"
        static let aiLatexPrompt = "aiLatexPrompt"
        static let clipsLibraryDirectory = "clipsLibraryDirectory"
        static let autoRedactOnAnnotate = "autoRedactOnAnnotate"
        static let redactPhones = "redactPhones"
        static let redactEmails = "redactEmails"
        static let redactNationalIDs = "redactNationalIDs"
        static let redactCreditCards = "redactCreditCards"
        static let redactAPIKeys = "redactAPIKeys"
        static let redactIPAddresses = "redactIPAddresses"
        static let redactFaces = "redactFaces"
    }

    var aiBaseURL: URL {
        get {
            if let raw = AppSettings.defaults.string(forKey: SignatureKeys.aiBaseURL),
               let url = URL(string: raw) { return url }
            return URL(string: "http://localhost:11434/v1")!
        }
        set { AppSettings.defaults.set(newValue.absoluteString, forKey: SignatureKeys.aiBaseURL) }
    }

    var aiVisionModel: String {
        get { AppSettings.defaults.string(forKey: SignatureKeys.aiVisionModel) ?? "qwen2.5vl:latest" }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.aiVisionModel) }
    }

    var aiAPIKey: String {
        get { AppSettings.defaults.string(forKey: SignatureKeys.aiAPIKey) ?? "" }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.aiAPIKey) }
    }

    var aiLatexPrompt: String {
        get { AppSettings.defaults.string(forKey: SignatureKeys.aiLatexPrompt) ?? AIPrompts.latex }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.aiLatexPrompt) }
    }

    var clipsLibraryDirectory: URL {
        get {
            if let path = AppSettings.defaults.string(forKey: SignatureKeys.clipsLibraryDirectory) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            let pictures = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/Octoshot Clips", isDirectory: true)
            return pictures
        }
        set { AppSettings.defaults.set(newValue.path, forKey: SignatureKeys.clipsLibraryDirectory) }
    }

    var autoRedactOnAnnotate: Bool {
        get { AppSettings.defaults.object(forKey: SignatureKeys.autoRedactOnAnnotate) as? Bool ?? false }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.autoRedactOnAnnotate) }
    }

    var redactPhones: Bool {
        get { AppSettings.defaults.object(forKey: SignatureKeys.redactPhones) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.redactPhones) }
    }

    var redactEmails: Bool {
        get { AppSettings.defaults.object(forKey: SignatureKeys.redactEmails) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.redactEmails) }
    }

    var redactNationalIDs: Bool {
        get { AppSettings.defaults.object(forKey: SignatureKeys.redactNationalIDs) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.redactNationalIDs) }
    }

    var redactCreditCards: Bool {
        get { AppSettings.defaults.object(forKey: SignatureKeys.redactCreditCards) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.redactCreditCards) }
    }

    var redactAPIKeys: Bool {
        get { AppSettings.defaults.object(forKey: SignatureKeys.redactAPIKeys) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.redactAPIKeys) }
    }

    var redactIPAddresses: Bool {
        get { AppSettings.defaults.object(forKey: SignatureKeys.redactIPAddresses) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.redactIPAddresses) }
    }

    var redactFaces: Bool {
        get { AppSettings.defaults.object(forKey: SignatureKeys.redactFaces) as? Bool ?? true }
        set { AppSettings.defaults.set(newValue, forKey: SignatureKeys.redactFaces) }
    }
}
