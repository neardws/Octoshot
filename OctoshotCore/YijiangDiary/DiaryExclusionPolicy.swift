import Foundation

public struct DiaryExclusionPolicy {
    public static let defaultExcludedBundleIDs: Set<String> = [
        "com.agilebits.onepassword7", "com.1password.1password", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.apple.systempreferences",
        "com.apple.SystemSettings", "com.apple.Settings", "com.lastpass.LastPass",
        "com.lastpass.LastPassMac", "com.dashlane.Dashlane", "com.dashlane.DashlaneDesktop",
        "org.keepassxc.keepassxc", "com.neardws.Octoshot"
    ]
    public var userExcludedBundleIDs: Set<String>
    public var focusedTextLimit: Int

    public init(userExcludedBundleIDs: Set<String> = [], focusedTextLimit: Int = 2_000) {
        self.userExcludedBundleIDs = userExcludedBundleIDs
        self.focusedTextLimit = max(0, focusedTextLimit)
    }

    public func allows(bundleID: String) -> Bool {
        let lowered = bundleID.lowercased()
        return !Self.defaultExcludedBundleIDs.union(userExcludedBundleIDs).contains { $0.lowercased() == lowered }
            && !["com.agilebits.", "com.1password.", "com.lastpass.", "com.dashlane."].contains { lowered.hasPrefix($0) }
    }

    public func sanitize(_ sample: DiaryActivitySample) -> DiaryActivitySample? {
        guard allows(bundleID: sample.appBundleID), !sample.isPrivateBrowsing, !sample.isSecureInput else { return nil }
        return DiaryActivitySample(timestamp: sample.timestamp, appBundleID: sample.appBundleID,
                                   appName: Self.mask(sample.appName), windowTitle: Self.mask(sample.windowTitle),
                                   focusedText: sample.focusedText.map { String(Self.mask($0).prefix(max(0, focusedTextLimit))) },
                                   urlHost: sample.urlHost, keyframeURL: sample.keyframeURL)
    }

    public static func mask(_ text: String) -> String {
        let settings = RedactionSettingsSnapshot(redactPhones: true, redactEmails: true,
                                                redactNationalIDs: true, redactCreditCards: true,
                                                redactAPIKeys: true, redactIPAddresses: true, redactFaces: false)
        let ranges = SensitivePatternMatcher.matches(in: text, settings: settings)
            .map(\.range).sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in ranges {
            if let previous = merged.last, range.lowerBound <= previous.upperBound {
                merged[merged.count - 1] = previous.lowerBound..<max(previous.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var result = text
        for range in merged.reversed() { result.replaceSubrange(range, with: "•••") }
        return result
    }
}
