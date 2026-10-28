import AppKit
import Foundation
import OctoshotCore

enum MCPServer {
    static func run() async {
        let server = MCPStdioServer()
        await server.serve()
    }
}

actor MCPStdioServer {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func serve() async {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let request = try? decoder.decode(JSONRPCRequest.self, from: data) else { continue }
            let response = await handle(request)
            if let out = try? encoder.encode(response), let str = String(data: out, encoding: .utf8) {
                print(str)
                fflush(stdout)
            }
        }
    }

    private func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return JSONRPCResponse(
                id: request.id,
                result: MCPInitialization.result()
            )
        case "tools/list":
            return JSONRPCResponse(id: request.id, result: MCPJSONValue.object(["tools": .array(toolDefinitions)]))
        case "tools/call":
            return await handleToolCall(request)
        case "notifications/initialized", "initialized":
            return JSONRPCResponse(id: request.id, result: nil)
        default:
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    private var toolDefinitions: [MCPJSONValue] {
        [
            tool("capture_screen", "Capture fullscreen or display", ["mode": "fullscreen|display", "display_id": "number", "output": "path", "base64": "bool"]),
            tool("capture_window", "Capture a window by ID", ["window_id": "number", "output": "path", "base64": "bool"]),
            tool("list_windows", "List on-screen windows", [:]),
            tool("list_displays", "List displays", [:]),
            tool("ocr", "OCR text from image path", ["path": "string"]),
            tool("auto_redact", "Redact sensitive regions", ["path": "string", "output": "path"]),
            tool("ask_ai", "Vision chat via local OpenAI-compatible API", ["path": "string", "prompt": "string"]),
            tool("to_latex", "Formula to LaTeX", ["path": "string"]),
            tool("extract_table", "Table to Markdown", ["path": "string", "save_clip": "bool"]),
            tool("annotate", "Apply JSON annotations", ["path": "string", "spec": "object", "output": "path"]),
            tool("record_start", "Start screen recording in Octoshot app (opens URL)", ["mode": "fullscreen|region", "format": "video|gif", "rect": "x,y,w,h"]),
            tool("record_stop", "Stop active Octoshot screen recording", [:])
        ] + DiaryMCPTools.definitions
    }

    private func tool(_ name: String, _ description: String, _ props: [String: String]) -> MCPJSONValue {
        var properties: [String: MCPJSONValue] = [:]
        for (key, type) in props {
            properties[key] = .object(["type": .string(type == "number" ? "number" : type == "bool" ? "boolean" : type == "object" ? "object" : "string")])
        }
        return .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties)
            ])
        ])
    }

    private func handleToolCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let params = request.params,
              case .object(let dict) = params,
              case .string(let name)? = dict["name"] else {
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32602, message: "Invalid tool call"))
        }
        do {
            let args = dict["arguments"] ?? .object([:])
            let text = try await invokeTool(name: name, arguments: args)
            return JSONRPCResponse(
                id: request.id,
                result: MCPJSONValue.object([
                    "content": .array([
                        .object(["type": .string("text"), "text": .string(text)])
                    ])
                ])
            )
        } catch {
            if DiaryMCPTools.names.contains(name),
               let text = try? DiaryAgentJSON.text(DiaryAgentError(error.localizedDescription)) {
                return JSONRPCResponse(id: request.id, result: .object([
                    "isError": .bool(true),
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])])
                ]))
            }
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32000, message: error.localizedDescription))
        }
    }

    private func invokeTool(name: String, arguments: MCPJSONValue) async throws -> String {
        if DiaryMCPTools.names.contains(name) {
            let request = try DiaryMCPTools.request(name: name, arguments: arguments)
            return try await DiaryAgentClient.send(request).jsonText()
        }
        guard case .object(let args) = arguments else { throw CaptureError.captureFailed("arguments must be object") }
        func str(_ key: String) -> String? {
            guard case .string(let v)? = args[key] else { return nil }
            return v
        }
        func int(_ key: String) throws -> UInt32? {
            guard let argument = args[key] else { return nil }
            guard case .number(let value) = argument, value.isFinite,
                  value >= 0, value <= Double(UInt32.max), value.rounded() == value else {
                throw CaptureError.captureFailed("Invalid \(key): expected an unsigned 32-bit integer")
            }
            return UInt32(value)
        }
        func bool(_ key: String) -> Bool {
            guard case .bool(let v)? = args[key] else { return false }
            return v
        }

        switch name {
        case "list_windows":
            let windows = try await AgentCaptureEngine.listWindows()
            return String(data: try JSONEncoder().encode(windows), encoding: .utf8) ?? "[]"
        case "list_displays":
            let displays = try await AgentCaptureEngine.listDisplays()
            return String(data: try JSONEncoder().encode(displays), encoding: .utf8) ?? "[]"
        case "capture_screen":
            guard let mode = AgentCaptureMode(rawValue: str("mode") ?? "fullscreen"),
                  mode == .fullscreen || mode == .display else {
                throw CaptureError.captureFailed("Invalid mode: expected fullscreen or display")
            }
            let result = try await AgentCaptureEngine.capture(options: .init(
                mode: mode,
                displayID: try int("display_id"),
                outputPath: str("output").map { URL(fileURLWithPath: $0) },
                includeBase64: bool("base64")
            ))
            return String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? "{}"
        case "capture_window":
            guard let wid = try int("window_id") else { throw CaptureError.captureFailed("window_id required") }
            let result = try await AgentCaptureEngine.capture(options: .init(
                mode: .window,
                windowID: wid,
                outputPath: str("output").map { URL(fileURLWithPath: $0) },
                includeBase64: bool("base64")
            ))
            return String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? "{}"
        case "ocr":
            guard let path = str("path") else { throw CaptureError.captureFailed("path required") }
            let image = try AgentCaptureEngine.loadImage(path: path)
            let ocr = try await OCRService.recognizeText(in: image)
            return String(data: try JSONEncoder().encode(ocr), encoding: .utf8) ?? ""
        case "auto_redact":
            guard let path = str("path") else { throw CaptureError.captureFailed("path required") }
            let image = try AgentCaptureEngine.loadImage(path: path)
            let out = try await AgentProcessing.autoRedact(image: image)
            let url = str("output").map { URL(fileURLWithPath: $0) }
                ?? AgentConfiguration.saveDirectory.appendingPathComponent("redacted-\(UUID().uuidString).png")
            try ImageFormats.writePNG(image: out, to: url)
            return try encodeMCPFileResult(["path": url.path])
        case "ask_ai":
            guard let path = str("path"), let prompt = str("prompt") else { throw CaptureError.captureFailed("path and prompt required") }
            let image = try AgentCaptureEngine.loadImage(path: path)
            return try await AgentProcessing.askAI(image: image, prompt: prompt)
        case "to_latex":
            guard let path = str("path") else { throw CaptureError.captureFailed("path required") }
            let image = try AgentCaptureEngine.loadImage(path: path)
            return try await AgentProcessing.toLaTeX(image: image)
        case "extract_table":
            guard let path = str("path") else { throw CaptureError.captureFailed("path required") }
            let image = try AgentCaptureEngine.loadImage(path: path)
            if bool("save_clip") {
                let folder = try await AgentProcessing.extractTableAndSaveClip(image: image)
                return try encodeMCPFileResult(["clipFolder": folder.path])
            }
            return try await AgentProcessing.extractTable(image: image)
        case "annotate":
            guard let path = str("path"), let specValue = args["spec"] else { throw CaptureError.captureFailed("path and spec required") }
            let specData = try JSONSerialization.data(withJSONObject: specValue.toJSONObject())
            let spec = try JSONDecoder().decode(AgentAnnotationSpec.self, from: specData)
            let image = try AgentCaptureEngine.loadImage(path: path)
            let annotated = try AnnotationRenderer.apply(spec: spec, to: image)
            let out = str("output").map { URL(fileURLWithPath: $0) }
                ?? AgentConfiguration.saveDirectory.appendingPathComponent("annotated-\(UUID().uuidString).png")
            try ImageFormats.writePNG(image: annotated, to: out)
            return try encodeMCPFileResult(["path": out.path])
        case "record_start":
            let mode = str("mode") ?? "fullscreen"
            let format = str("format") ?? "video"
            let url = AgentAppLauncher.recordURL(action: "start", mode: mode, format: format, rect: str("rect"))
            try AgentAppLauncher.openOctoshotURL(url)
            return "{\"status\":\"start_requested\",\"url\":\"\(url.absoluteString)\"}"
        case "record_stop":
            let url = AgentAppLauncher.recordURL(action: "stop")
            try AgentAppLauncher.openOctoshotURL(url)
            return "{\"status\":\"stop_requested\",\"url\":\"\(url.absoluteString)\"}"
        default:
            throw CaptureError.captureFailed("Unknown tool \(name)")
        }
    }
}

// MARK: - Minimal JSON-RPC + MCPJSONValue

struct JSONRPCRequest: Decodable {
    let jsonrpc: String?
    let id: JSONValue?
    let method: String
    let params: MCPJSONValue?
}

struct JSONRPCResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONValue?
    let result: MCPJSONValue?
    let error: JSONRPCError?

    init(id: JSONValue?, result: MCPJSONValue?) {
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONValue?, error: JSONRPCError) {
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct JSONRPCError: Encodable {
    let code: Int
    let message: String
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case int(Int)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let i = try? container.decode(Int.self) { self = .int(i) }
        else if let d = try? container.decode(Double.self) { self = .number(d) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let d): try container.encode(d)
        case .int(let i): try container.encode(i)
        case .null: try container.encodeNil()
        }
    }
}
