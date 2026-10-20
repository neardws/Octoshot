import Darwin
import Foundation

#if EMBEDDED_MLX
import AppKit
import OctoshotCore
import OctoshotEmbeddedMLX

private enum VLMBenchError: LocalizedError {
    case invalidArgument(String)
    case invalidOptions
    case imageUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let flag):
            return "Invalid vlm-bench argument: \(flag)"
        case .invalidOptions:
            return "vlm-bench requires --developer, --image, --prompt and positive numeric limits"
        case .imageUnavailable(let path):
            return "Cannot load image: \(path)"
        }
    }
}

@MainActor
private func runVLMBench(_ args: [String]) async throws {
    var options: [String: String] = [:]
    var developer = false
    var index = 0
    let flags: Set<String> = ["--image", "--prompt", "--max-tokens", "--repeat", "--timeout", "--model-dir"]
    while index < args.count {
        let flag = args[index]
        if flag == "--developer" {
            developer = true
            index += 1
        } else if flags.contains(flag), index + 1 < args.count, options[flag] == nil {
            options[flag] = args[index + 1]
            index += 2
        } else {
            throw VLMBenchError.invalidArgument(flag)
        }
    }
    guard developer, let path = options["--image"], let prompt = options["--prompt"],
          let maxTokens = Int(options["--max-tokens"] ?? "256"), maxTokens > 0,
          let repetitions = Int(options["--repeat"] ?? "1"), repetitions > 0,
          let timeout = Double(options["--timeout"] ?? "120"), timeout.isFinite,
          timeout > 0, timeout <= 86400 else {
        throw VLMBenchError.invalidOptions
    }
    guard let image = NSImage(contentsOfFile: path) else {
        throw VLMBenchError.imageUnavailable(path)
    }
    let modelDirectory = options["--model-dir"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? EmbeddedAIModelPaths.directory(for: .smolVLM2_500M_4bit)
    defer { MLXVLMLoader.shared.unload() }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    for iteration in 1...repetitions {
        let start = ContinuousClock.now
        let output = try await MLXVLMLoader.shared.respond(
            prompt: prompt, image: image, modelDirectory: modelDirectory,
            maxTokens: maxTokens, timeout: timeout)
        let elapsed = start.duration(to: .now).components
        let footprint = physicalFootprint()
        let result = VLMBenchResult(
            call: iteration,
            elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
            outputChars: output.count,
            physicalFootprintBytes: footprint.current,
            processLifetimePeakFootprintBytes: footprint.peak,
            maxTokens: maxTokens)
        print(String(decoding: try encoder.encode(result), as: UTF8.self))
        fflush(stdout)
    }
}

private func physicalFootprint() -> (current: UInt64?, peak: UInt64?) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { return (nil, nil) }
    return (info.phys_footprint, UInt64(max(0, info.ledger_phys_footprint_peak)))
}

private struct VLMBenchResult: Encodable {
    let call: Int
    let elapsedSeconds: Double
    let outputChars: Int
    let physicalFootprintBytes: UInt64?
    let processLifetimePeakFootprintBytes: UInt64?
    let maxTokens: Int
}

do {
    try await runVLMBench(Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
#else
fputs("vlm-bench requires EMBEDDED_MLX build\n", stderr)
exit(2)
#endif
