import Darwin
import Foundation
import OctoshotCore

/// Ensures `llama-mtmd-cli` is available under Application Support (no Homebrew required).
@MainActor
final class LaTeXEngineInstaller {
    static let shared = LaTeXEngineInstaller()

    private static let releaseTag = "b11514"

    private init() {}

    func ensureCLI() async throws -> URL {
        if let bundled = Pix2TexLlamaRunner.bundledCLI(), FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let dest = EmbeddedAIModelPaths.latexEngineCLI
        if FileManager.default.isExecutableFile(atPath: dest.path) {
            return dest
        }
        try await downloadCLI(to: dest)
        return dest
    }

    private func downloadCLI(to dest: URL) async throws {
        let arch = ProcessInfo.processInfo.machineArchitecture
        let tarball: String
        switch arch {
        case .arm64:
            tarball = "llama-\(Self.releaseTag)-bin-macos-arm64.tar.gz"
        case .x86_64:
            tarball = "llama-\(Self.releaseTag)-bin-macos-x64.tar.gz"
        }
        let url = URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/\(Self.releaseTag)/\(tarball)")!
        let (archiveURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmbeddedAIError.specialistFailed(OctoshotL10n.text("Could not download llama.cpp runtime"))
        }

        let extractRoot = FileManager.default.temporaryDirectory.appendingPathComponent("octoshot-llama-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractRoot) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", extractRoot.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EmbeddedAIError.specialistFailed(OctoshotL10n.text("Failed to extract llama.cpp archive"))
        }

        guard let cli = findCLI(in: extractRoot) else {
            throw EmbeddedAIError.specialistFailed(OctoshotL10n.text("llama-mtmd-cli missing from archive"))
        }

        let binDir = dest.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: cli, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)

        let sourceBin = cli.deletingLastPathComponent()
        if let dylibs = try? FileManager.default.contentsOfDirectory(at: sourceBin, includingPropertiesForKeys: nil) {
            for lib in dylibs where lib.pathExtension == "dylib" {
                let target = binDir.appendingPathComponent(lib.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.removeItem(at: target)
                }
                try? FileManager.default.copyItem(at: lib, to: target)
            }
        }
        try? FileManager.default.removeItem(at: archiveURL)
    }

    private func findCLI(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let file as URL in enumerator where file.lastPathComponent == "llama-mtmd-cli" {
            return file
        }
        return nil
    }
}

private extension ProcessInfo {
    enum MachineArch {
        case arm64
        case x86_64
    }

    var machineArchitecture: MachineArch {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        if machine == "arm64" { return .arm64 }
        return .x86_64
    }
}
