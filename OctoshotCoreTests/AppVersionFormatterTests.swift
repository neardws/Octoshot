import XCTest
@testable import OctoshotCore

final class AppVersionFormatterTests: XCTestCase {
    func testDisplayWithoutCommitPreservesVersion() {
        XCTAssertEqual(
            AppVersionFormatter.display(short: "0.3.2", build: "5", gitCommit: nil),
            "0.3.2 (5)"
        )
    }

    func testDisplayWithCommit() {
        XCTAssertEqual(
            AppVersionFormatter.display(short: "0.3.2", build: "5", gitCommit: "02b1a51"),
            "0.3.2 (5) · 02b1a51"
        )
    }

    func testDisplayWithDirtyCommit() {
        XCTAssertEqual(
            AppVersionFormatter.display(short: "0.3.2", build: "5", gitCommit: "02b1a51-dirty"),
            "0.3.2 (5) · 02b1a51-dirty"
        )
    }

    func testDisplayWithEmptyCommitPreservesVersion() {
        XCTAssertEqual(
            AppVersionFormatter.display(short: "0.3.2", build: "5", gitCommit: ""),
            "0.3.2 (5)"
        )
    }
}
