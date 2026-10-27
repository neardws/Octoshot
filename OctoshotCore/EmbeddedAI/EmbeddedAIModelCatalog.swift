import Foundation

public enum EmbeddedModelID: String, CaseIterable, Codable, Sendable {
    case smolVLM2_500M_4bit
    case pix2texMFR_Q4

    public var displayName: String {
        switch self {
        case .smolVLM2_500M_4bit: return "SmolVLM2-500M (MLX 4-bit)"
        case .pix2texMFR_Q4: return "pix2tex-mfr (Q4_K)"
        }
    }

    /// Hugging Face repo id (weights downloaded on demand).
    public var huggingFaceRepo: String {
        switch self {
        case .smolVLM2_500M_4bit:
            return "mlx-community/SmolVLM2-500M-Video-Instruct-mlx-4bit"
        case .pix2texMFR_Q4:
            return "cstr/pix2tex-mfr-gguf"
        }
    }

    public var approximateSizeMB: Int {
        switch self {
        case .smolVLM2_500M_4bit: return 292
        case .pix2texMFR_Q4: return 18
        }
    }

    public var licenseNote: String {
        switch self {
        case .smolVLM2_500M_4bit:
            return "Apache-2.0 (Hugging FaceTB / mlx-community weights)"
        case .pix2texMFR_Q4:
            return "MIT (pix2tex-mfr GGUF)"
        }
    }

    /// Primary GGUF filename for pix2tex; VLM uses full repo tree.
    public var primaryGGUFFileName: String? {
        switch self {
        case .smolVLM2_500M_4bit: return nil
        case .pix2texMFR_Q4: return "pix2tex-mfr-q4_k.gguf"
        }
    }

    public var legacyGGUFFileNames: [String] {
        switch self {
        case .smolVLM2_500M_4bit: return []
        case .pix2texMFR_Q4: return ["pix2tex-mfr-Q4_K.gguf"]
        }
    }

    public func resolvedLocalGGUFURL(in directory: URL) -> URL? {
        guard let primaryGGUFFileName,
              let fileNames = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        return ([primaryGGUFFileName] + legacyGGUFFileNames)
            .first(where: { fileNames.contains($0) })
            .map { directory.appendingPathComponent($0) }
    }
}

public enum EmbeddedAIModelPaths {
    public static func modelsRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Octoshot/Models", isDirectory: true)
    }

    public static var latexEngineCLI: URL {
        modelsRoot()
            .deletingLastPathComponent()
            .appendingPathComponent("bin/llama-mtmd-cli", isDirectory: false)
    }

    public static func directory(for model: EmbeddedModelID) -> URL {
        modelsRoot().appendingPathComponent(model.rawValue, isDirectory: true)
    }

    public static func isInstalled(_ model: EmbeddedModelID) -> Bool {
        isInstalled(model, in: directory(for: model))
    }

    public static func isInstalled(_ model: EmbeddedModelID, in dir: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        if model.primaryGGUFFileName != nil {
            return model.resolvedLocalGGUFURL(in: dir) != nil
        }
        let config = dir.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: config.path)
    }

    public static func diskUsageBytes(for model: EmbeddedModelID) -> Int64 {
        let dir = directory(for: model)
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
