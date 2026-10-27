import AppKit
import ApplicationServices
import Carbon
import Foundation

public struct DiaryActivitySample: Codable, Equatable {
    public var timestamp: Date
    public var appBundleID: String
    public var appName: String
    public var windowTitle: String
    public var focusedText: String?
    public private(set) var urlHost: String?
    public var isPrivateBrowsing: Bool
    public var isSecureInput: Bool
    public var keyframeURL: URL?

    public init(timestamp: Date, appBundleID: String, appName: String, windowTitle: String,
                focusedText: String? = nil, urlHost: String? = nil,
                isPrivateBrowsing: Bool = false, isSecureInput: Bool = false, keyframeURL: URL? = nil) {
        self.timestamp = timestamp
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.focusedText = focusedText
        self.urlHost = Self.hostOnly(urlHost)
        self.isPrivateBrowsing = isPrivateBrowsing
        self.isSecureInput = isSecureInput
        self.keyframeURL = keyframeURL
    }

    public static func hostOnly(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              let components = URLComponents(string: value.contains("://") ? value : "https://" + value),
              let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }) else { return nil }
        return host.lowercased()
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(timestamp: try values.decode(Date.self, forKey: .timestamp),
                  appBundleID: try values.decode(String.self, forKey: .appBundleID),
                  appName: try values.decode(String.self, forKey: .appName),
                  windowTitle: try values.decode(String.self, forKey: .windowTitle),
                  focusedText: try values.decodeIfPresent(String.self, forKey: .focusedText),
                  urlHost: try values.decodeIfPresent(String.self, forKey: .urlHost),
                  isPrivateBrowsing: try values.decodeIfPresent(Bool.self, forKey: .isPrivateBrowsing) ?? false,
                  isSecureInput: try values.decodeIfPresent(Bool.self, forKey: .isSecureInput) ?? false,
                  keyframeURL: try values.decodeIfPresent(URL.self, forKey: .keyframeURL))
    }
}

public protocol DiaryActivitySource {
    func nextSample() throws -> DiaryActivitySample?
}

public final class MockDiaryActivitySource: DiaryActivitySource {
    private let samples: [DiaryActivitySample]
    private var index = 0

    public init(samples: [DiaryActivitySample]) { self.samples = samples }

    public convenience init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try self.init(samples: decoder.decode([DiaryActivitySample].self, from: json))
    }

    public func nextSample() -> DiaryActivitySample? {
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return samples[index]
    }
}

public final class AXDiaryActivitySource: DiaryActivitySource {
    private let clock: () -> Date

    public init(clock: @escaping () -> Date = Date.init) { self.clock = clock }

    public func nextSample() -> DiaryActivitySample? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        guard !IsSecureEventInputEnabled() else {
            return DiaryActivitySample(timestamp: clock(), appBundleID: bundleID,
                                       appName: app.localizedName ?? bundleID, windowTitle: "", isSecureInput: true)
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let window = element(application, kAXFocusedWindowAttribute)
        let focused = element(application, kAXFocusedUIElementAttribute)
        let title = window.flatMap { attribute($0, kAXTitleAttribute) as? String } ?? ""
        let secure = focused.flatMap { attribute($0, kAXSubroleAttribute) as? String } == "AXSecureTextField"
        let privateBrowsing = ["private browsing", "private window", "incognito", "inprivate", "无痕", "隐私浏览"].contains {
            title.localizedCaseInsensitiveContains($0)
        }
        return DiaryActivitySample(timestamp: clock(), appBundleID: bundleID,
                                   appName: app.localizedName ?? bundleID, windowTitle: title,
                                   focusedText: secure || privateBrowsing ? nil : focused.flatMap { attribute($0, kAXValueAttribute) as? String },
                                   isPrivateBrowsing: privateBrowsing, isSecureInput: secure)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
