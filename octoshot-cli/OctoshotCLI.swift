import AppKit
import Foundation
import OctoshotCore

@main
struct OctoshotCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--version" || args.first == "version" {
            print(OctoshotVersion.semanticVersion())
            return
        }
        UserDefaults.standard.addSuite(named: "com.neardws.Octoshot")
        _ = NSApplication.shared
        if args.isEmpty || args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }
        guard let command = args.first else {
            printUsage()
            exit(1)
        }
        let rest = Array(args.dropFirst())
        do {
            switch command {
            case "capture":
                try await runCapture(rest)
            case "list-windows":
                try await runListWindows()
            case "list-displays":
                try await runListDisplays()
            case "ocr":
                try await runOCR(rest)
            case "redact", "auto-redact":
                try await runRedact(rest)
            case "ask-ai":
                try await runAskAI(rest)
            case "to-latex":
                try await runLaTeX(rest)
            case "extract-table":
                try await runExtractTable(rest)
            case "annotate":
                try await runAnnotate(rest)
            case "record":
                try runRecord(rest)
            case "mcp":
                await MCPServer.run()
            case "help", "--help", "-h":
                printUsage()
            default:
                fputs("Unknown command: \(command)\n", stderr)
                printUsage()
                exit(1)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func printUsage() {
        print("""
        octoshot — Octoshot agent CLI (local-only)

        Commands:
          version, --version   Print the semantic version
          capture --mode <fullscreen|display|window|region> [--display-id N] [--window-id N] [--rect x,y,w,h] [--output PATH] [--base64]
          list-windows
          list-displays
          ocr --input PATH
          auto-redact --input PATH [--output PATH]
          ask-ai --input PATH --prompt TEXT
          to-latex --input PATH [--output PATH]
          extract-table --input PATH [--save-clip]
          annotate --input PATH --spec PATH.json [--output PATH]
          record start [--mode fullscreen|region] [--format video|gif] [--rect x,y,w,h]
          record stop
          mcp   Start Model Context Protocol server on stdio

        Capture output uses the configured PNG/JPEG format. Extensionless paths get
        .png/.jpg; explicit extensions are preserved, but encoding uses the configured format.
        Automatically named captures never overwrite existing files.
        record start (CLI/MCP/URL) asks for consent by default in Octoshot.
        """)
    }

    private static func runRecord(_ args: [String]) throws {
        guard let sub = args.first else {
            throw CaptureError.captureFailed("record requires start or stop")
        }
        switch sub {
        case "stop":
            let url = AgentAppLauncher.recordURL(action: "stop")
            try AgentAppLauncher.openOctoshotURL(url)
            printJSON(["status": "stop_requested", "url": url.absoluteString])
        case "start":
            var mode = "fullscreen"
            var format = "video"
            var rect: String?
            var i = 1
            while i < args.count {
                if ["--mode", "--format", "--rect"].contains(args[i]), i + 1 >= args.count {
                    throw CaptureError.captureFailed("Missing value for \(args[i])")
                }
                switch args[i] {
                case "--mode":
                    i += 1
                    mode = args[i]
                case "--format":
                    i += 1
                    format = args[i]
                case "--rect":
                    i += 1
                    rect = args[i]
                default:
                    break
                }
                i += 1
            }
            guard ["fullscreen", "region", "area"].contains(mode), ["video", "gif"].contains(format) else {
                throw CaptureError.captureFailed("Invalid recording mode or format")
            }
            let url = AgentAppLauncher.recordURL(action: "start", mode: mode, format: format, rect: rect)
            try AgentAppLauncher.openOctoshotURL(url)
            printJSON(["status": "start_requested", "url": url.absoluteString])
        default:
            throw CaptureError.captureFailed("record requires start or stop")
        }
    }

    private static func runCapture(_ args: [String]) async throws {
        let options = try CaptureArgumentParser.parse(args)
        let result = try await AgentCaptureEngine.capture(options: options)
        printJSON(result)
    }

    private static func runListWindows() async throws {
        let windows = try await AgentCaptureEngine.listWindows()
        printJSON(windows)
    }

    private static func runListDisplays() async throws {
        let displays = try await AgentCaptureEngine.listDisplays()
        printJSON(displays)
    }

    private static func runOCR(_ args: [String]) async throws {
        let path = try requireInputPath(args)
        let image = try AgentCaptureEngine.loadImage(path: path)
        let result = try await OCRService.recognizeText(in: image)
        printJSON(result)
    }

    private static func runRedact(_ args: [String]) async throws {
        let path = try requireInputPath(args)
        var outputPath: URL?
        for (idx, arg) in args.enumerated() where arg == "--output" && idx + 1 < args.count {
            outputPath = URL(fileURLWithPath: args[idx + 1])
        }
        let image = try AgentCaptureEngine.loadImage(path: path)
        let redacted = try await AgentProcessing.autoRedact(image: image)
        if let outputPath {
            try ImageFormats.writePNG(image: redacted, to: outputPath)
            printJSON(["path": outputPath.path])
        } else {
            let url = AgentConfiguration.saveDirectory.appendingPathComponent("redacted-\(UUID().uuidString).png")
            try ImageFormats.writePNG(image: redacted, to: url)
            printJSON(["path": url.path])
        }
    }

    private static func runAskAI(_ args: [String]) async throws {
        let path = try requireInputPath(args)
        guard let prompt = value(for: "--prompt", in: args) else {
            throw CaptureError.captureFailed("--prompt required")
        }
        let image = try AgentCaptureEngine.loadImage(path: path)
        let text = try await AgentProcessing.askAI(image: image, prompt: prompt)
        print(text)
    }

    private static func runLaTeX(_ args: [String]) async throws {
        let path = try requireInputPath(args)
        let image = try AgentCaptureEngine.loadImage(path: path)
        let latex = try await AgentProcessing.toLaTeX(image: image)
        if let out = value(for: "--output", in: args) {
            try latex.write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
            printJSON(["path": out, "latex": latex])
        } else {
            print(latex)
        }
    }

    private static func runExtractTable(_ args: [String]) async throws {
        let path = try requireInputPath(args)
        let image = try AgentCaptureEngine.loadImage(path: path)
        if args.contains("--save-clip") {
            let folder = try await AgentProcessing.extractTableAndSaveClip(image: image)
            printJSON(["clipFolder": folder.path])
        } else {
            let md = try await AgentProcessing.extractTable(image: image)
            print(md)
        }
    }

    private static func runAnnotate(_ args: [String]) async throws {
        let path = try requireInputPath(args)
        guard let specPath = value(for: "--spec", in: args) else {
            throw CaptureError.captureFailed("--spec PATH.json required")
        }
        let specData = try Data(contentsOf: URL(fileURLWithPath: specPath))
        let spec = try JSONDecoder().decode(AgentAnnotationSpec.self, from: specData)
        let image = try AgentCaptureEngine.loadImage(path: path)
        let annotated = AnnotationRenderer.apply(spec: spec, to: image)
        let out = value(for: "--output", in: args)
            ?? AgentConfiguration.saveDirectory.appendingPathComponent("annotated-\(UUID().uuidString).png").path
        try ImageFormats.writePNG(image: annotated, to: URL(fileURLWithPath: out))
        printJSON(["path": out])
    }

    private static func requireInputPath(_ args: [String]) throws -> String {
        guard let path = value(for: "--input", in: args) else {
            throw CaptureError.captureFailed("--input PATH required")
        }
        return path
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
