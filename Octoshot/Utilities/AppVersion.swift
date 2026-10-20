import Foundation
import OctoshotCore

enum AppVersion {
    static var short: String {
        OctoshotVersion.semanticVersion()
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var display: String {
        AppVersionFormatter.display(
            short: short,
            build: build,
            gitCommit: Bundle.main.object(forInfoDictionaryKey: "OctoshotGitCommit") as? String
        )
    }
}
