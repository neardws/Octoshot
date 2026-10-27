import XCTest
@testable import OctoshotCore

final class EmbeddedAIModelCatalogTests: XCTestCase {
    func testModelsRootUnderApplicationSupport() {
        let root = EmbeddedAIModelPaths.modelsRoot()
        XCTAssertTrue(root.path.contains("Octoshot/Models"))
    }

    func testSmolVLMManifest() {
        XCTAssertEqual(EmbeddedModelID.smolVLM2_500M_4bit.approximateSizeMB, 292)
        XCTAssertFalse(EmbeddedModelID.smolVLM2_500M_4bit.huggingFaceRepo.isEmpty)
        XCTAssertTrue(EmbeddedModelID.smolVLM2_500M_4bit.legacyGGUFFileNames.isEmpty)
    }

    func testPix2TexManifest() {
        XCTAssertEqual(EmbeddedModelID.pix2texMFR_Q4.primaryGGUFFileName, "pix2tex-mfr-q4_k.gguf")
        XCTAssertEqual(EmbeddedModelID.pix2texMFR_Q4.legacyGGUFFileNames, ["pix2tex-mfr-Q4_K.gguf"])
    }

    func testPix2TexInstallationAcceptsCanonicalAndLegacyFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(EmbeddedAIModelPaths.isInstalled(.pix2texMFR_Q4, in: directory))
        for fileName in ["pix2tex-mfr-Q4_K.gguf", "pix2tex-mfr-q4_k.gguf"] {
            let file = directory.appendingPathComponent(fileName)
            try Data().write(to: file)
            XCTAssertTrue(EmbeddedAIModelPaths.isInstalled(.pix2texMFR_Q4, in: directory))
            try FileManager.default.removeItem(at: file)
        }
        XCTAssertFalse(EmbeddedAIModelPaths.isInstalled(.pix2texMFR_Q4, in: directory))
    }

    func testPix2TexResolverUsesExistingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = EmbeddedModelID.pix2texMFR_Q4

        XCTAssertNil(model.resolvedLocalGGUFURL(in: directory))
        for fileName in ["pix2tex-mfr-Q4_K.gguf", "pix2tex-mfr-q4_k.gguf"] {
            let file = directory.appendingPathComponent(fileName)
            try Data().write(to: file)
            XCTAssertEqual(model.resolvedLocalGGUFURL(in: directory), file)
            try FileManager.default.removeItem(at: file)
        }
        XCTAssertNil(model.resolvedLocalGGUFURL(in: directory))
    }

    func testPix2TexResolverPrefersCanonicalWhenBothExist() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let canonical = directory.appendingPathComponent("pix2tex-mfr-q4_k.gguf")
        let legacy = directory.appendingPathComponent("pix2tex-mfr-Q4_K.gguf")
        try Data().write(to: legacy)
        try Data().write(to: canonical)
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard fileNames.contains(canonical.lastPathComponent), fileNames.contains(legacy.lastPathComponent) else {
            throw XCTSkip("Both filename variants require a case-sensitive filesystem")
        }

        XCTAssertEqual(EmbeddedModelID.pix2texMFR_Q4.resolvedLocalGGUFURL(in: directory), canonical)
        XCTAssertTrue(EmbeddedAIModelPaths.isInstalled(.pix2texMFR_Q4, in: directory))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
