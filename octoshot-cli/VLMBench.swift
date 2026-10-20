#if DEBUG
import AppKit
import Darwin
import Foundation
import OctoshotCore
import OctoshotEmbeddedMLX

extension OctoshotCLI {
    @MainActor
    static func runVLMBench(_ args: [String]) async throws {
        var options: [String: String] = [:]
        var developer = false
        var index = 0
        let flags: Set<String> = ["--image", "--prompt", "--max-tokens", "--repeat", "--timeout"]
        while index < args.count {
            let flag = args[index]
            if flag == "--developer" {
                developer = true
                index += 1
            } else if flags.contains(flag), index + 1 < args.count, options[flag] == nil {
                options[flag] = args[index + 1]
                index += 2
            } else {
                throw CaptureError.captureFailed("Invalid vlm-bench argument: \(flag)")
            }
        }
        guard developer, let path = options["--image"], let prompt = options["--prompt"],
              let maxTokens = Int(options["--max-tokens"] ?? "256"), maxTokens > 0,
              let repetitions = Int(options["--repeat"] ?? "1"), repetitions > 0,
              let timeout = Double(options["--timeout"] ?? "120"), timeout.isFinite,
              timeout > 0, timeout <= 86400 else {
            throw CaptureError.captureFailed("vlm-bench requires --developer, --image, --prompt and positive numeric limits")
        }
        guard let image = NSImage(contentsOfFile: path) else {
            throw CaptureError.captureFailed("Cannot load image: \(path)")
        }
        let backend = LocalVLMService.shared
        EmbeddedAIProvider.vision = backend
        defer {
            EmbeddedAIProvider.vision = nil
            MLXVLMLoader.shared.unload()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for iteration in 1...repetitions {
            let start = ContinuousClock.now
            let output = try await backend.complete(prompt: prompt, image: image, maxTokens: maxTokens, timeout: timeout)
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

    private static func physicalFootprint() -> (current: UInt64?, peak: UInt64?) {
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
}

private struct VLMBenchResult: Encodable {
    let call: Int
    let elapsedSeconds: Double
    let outputChars: Int
    let physicalFootprintBytes: UInt64?
    let processLifetimePeakFootprintBytes: UInt64?
    let maxTokens: Int
}
#endif
