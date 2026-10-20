import Foundation
import XCTest
@testable import OctoshotCore

final class OctoshotVersionTests: XCTestCase {
    func testBundleVersionOverridesLegacyFallback() throws {
        try withBundle(version: "7.8.9") { bundle in
            XCTAssertEqual(OctoshotVersion.semanticVersion(bundle: bundle), "7.8.9")
            XCTAssertNotEqual(OctoshotVersion.semanticVersion(bundle: bundle), "0.1.0")
        }
    }

    func testMissingOrEmptyVersionUsesUnknownSemanticVersion() throws {
        let versions: [String?] = [nil, "", "  "]
        for version in versions {
            try withBundle(version: version) { bundle in
                XCTAssertEqual(OctoshotVersion.semanticVersion(bundle: bundle), "0.0.0")
            }
        }
    }

    func testInitializeResultEncodesBundleSemanticVersionWithoutCommit() throws {
        try withBundle(version: "7.8.9") { bundle in
            let data = try JSONEncoder().encode(MCPInitialization.result(bundle: bundle))
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: String])
            XCTAssertEqual(serverInfo, ["name": "octoshot", "version": "7.8.9"])
            XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
            let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
            XCTAssertNotNil(capabilities["tools"] as? [String: Any])
        }
    }

    private func withBundle(version: String?, body: (Bundle) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = directory.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info = ["CFBundleIdentifier": "com.neardws.version-tests.\(UUID().uuidString)",
                    "CFBundlePackageType": "BNDL", "OctoshotGitCommit": "abcdef0-dirty"]
        info["CFBundleShortVersionString"] = version
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try body(XCTUnwrap(Bundle(url: directory)))
    }
}
