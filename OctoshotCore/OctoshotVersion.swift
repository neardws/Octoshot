import Foundation

public enum OctoshotVersion {
    public static func semanticVersion(bundle: Bundle = .main) -> String {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "0.0.0"
        }
        return version
    }
}
