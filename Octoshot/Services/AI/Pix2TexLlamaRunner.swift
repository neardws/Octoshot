import AppKit
import Foundation
import OctoshotCore

enum Pix2TexLlamaRunner {
    static func bundledCLI() -> URL? {
        if let url = Bundle.main.url(forResource: "llama-mtmd-cli", withExtension: nil, subdirectory: "Helpers"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama-mtmd-cli")
        if FileManager.default.isExecutableFile(atPath: helpers.path) {
            return helpers
        }
        return nil
    }

    static func llamaMtmdCLI() -> URL? {
        if let bundled = bundledCLI() { return bundled }
        let appSupport = EmbeddedAIModelPaths.latexEngineCLI
        if FileManager.default.isExecutableFile(atPath: appSupport.path) {
            return appSupport
        }
        return nil
    }

    static func run(image: NSImage, modelPath: URL) async throws -> String {
        let cli = try await resolveCLI()
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("octoshot-pix2tex-\(UUID().uuidString).png")
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw EmbeddedAIError.specialistFailed("Could not encode image")
        }
        try png.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let output = try await runProcess(
            executable: cli,
            arguments: [
                "-m", modelPath.path,
                "--image", imageURL.path,
                "-p", "latex",
                "-n", "256",
                "--temp", "0.1"
            ],
            workingDirectory: cli.deletingLastPathComponent()
        )
        return output
    }

    private static func resolveCLI() async throws -> URL {
        if let cli = llamaMtmdCLI() { return cli }
        return try await LaTeXEngineInstaller.shared.ensureCLI()
    }

    private static func runProcess(executable: URL, arguments: [String], workingDirectory: URL) async throws -> String {
        var env = ProcessInfo.processInfo.environment
        env["DYLD_LIBRARY_PATH"] = workingDirectory.path
        let result = try await SubprocessRunner.run(
            executable: executable, arguments: arguments,
            currentDirectory: workingDirectory, environment: env, timeout: 300)
        guard result.terminationStatus == 0 else {
            throw EmbeddedAIError.specialistFailed(
                result.text.isEmpty ? "llama-mtmd exited \(result.terminationStatus)" : result.text)
        }
        return result.text
    }
}
