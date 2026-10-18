public enum AppVersionFormatter {
    public static func display(short: String, build: String, gitCommit: String?) -> String {
        let version = "\(short) (\(build))"
        guard let gitCommit, !gitCommit.isEmpty else { return version }
        return "\(version) · \(gitCommit)"
    }
}
