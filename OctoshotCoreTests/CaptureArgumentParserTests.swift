import Foundation
import XCTest
@testable import OctoshotCore

final class CaptureArgumentParserTests: XCTestCase {
    func testMissingValuesThrowForEveryValueOption() {
        for option in ["--output", "--mode", "--display-id", "--window-id", "--rect"] {
            for prefix in [[], ["--base64", "--mode", "window"]] {
                XCTAssertThrowsError(try CaptureArgumentParser.parse(prefix + [option]), option) { error in
                    XCTAssertEqual(error.localizedDescription, "Missing value for \(option)")
                }
            }
        }
    }

    func testInvalidIdentifiersThrow() {
        for option in ["--display-id", "--window-id"] {
            for value in ["abc", "1.5", "-1", "4294967296", ""] {
                XCTAssertThrowsError(try CaptureArgumentParser.parse([option, value]), "\(option) \(value)") { error in
                    XCTAssertEqual(
                        error.localizedDescription,
                        "Invalid value for \(option): expected an unsigned 32-bit integer"
                    )
                }
            }
        }
    }

    func testInvalidRectanglesThrow() {
        for value in ["", "1,2,3", "1,2,3,4,5", "1,2,no,4", "1,,2,3,4", "1,2,3,4,", "no,1,2,3,4", "nan,2,3,4", "1,2,inf,4"] {
            XCTAssertThrowsError(try CaptureArgumentParser.parse(["--rect", value]), value) { error in
                XCTAssertEqual(error.localizedDescription, "Invalid value for --rect: expected four finite numbers: x,y,w,h")
            }
        }
    }

    func testCompleteValidInvocation() throws {
        let options = try CaptureArgumentParser.parse([
            "--mode", "region", "--display-id", "42", "--window-id", "123",
            "--rect", "-10.5,20,300,200.5", "--output", "/tmp/capture with spaces.png", "--base64"
        ])
        XCTAssertEqual(options.mode, .region)
        XCTAssertEqual(options.displayID, 42)
        XCTAssertEqual(options.windowID, 123)
        XCTAssertEqual(options.region, CGRect(x: -10.5, y: 20, width: 300, height: 200.5))
        XCTAssertEqual(options.outputPath, URL(fileURLWithPath: "/tmp/capture with spaces.png"))
        XCTAssertTrue(options.includeBase64)
    }

    func testBase64Alone() throws {
        let options = try CaptureArgumentParser.parse(["--base64"])
        XCTAssertTrue(options.includeBase64)
        XCTAssertEqual(options.mode, .fullscreen)
        XCTAssertNil(options.displayID)
        XCTAssertNil(options.windowID)
        XCTAssertNil(options.region)
        XCTAssertNil(options.outputPath)
    }

    func testDefaults() throws {
        let options = try CaptureArgumentParser.parse([])
        XCTAssertEqual(options.mode, .fullscreen)
        XCTAssertNil(options.displayID)
        XCTAssertNil(options.windowID)
        XCTAssertNil(options.region)
        XCTAssertNil(options.outputPath)
        XCTAssertFalse(options.includeBase64)
    }

    func testRecognizedModes() throws {
        for mode in [AgentCaptureMode.fullscreen, .display, .window, .region] {
            XCTAssertEqual(try CaptureArgumentParser.parse(["--mode", mode.rawValue]).mode, mode)
        }
    }

    func testUnknownModeFallsBackToFullscreen() throws {
        let options = try CaptureArgumentParser.parse(["--mode", "window", "--mode", "unknown"])
        XCTAssertEqual(options.mode, .fullscreen)
    }

    func testUnknownArgumentsAreIgnored() throws {
        let options = try CaptureArgumentParser.parse(["--unknown", "value", "--base64", "extra"])
        XCTAssertEqual(options.mode, .fullscreen)
        XCTAssertTrue(options.includeBase64)
    }

    func testRepeatedOptionsUseLastValueAndAcceptIdentifierBounds() throws {
        let options = try CaptureArgumentParser.parse([
            "--display-id", "42", "--display-id", "0", "--window-id", "4294967295",
            "--output", "first.png", "--output", "last.png"
        ])
        XCTAssertEqual(options.displayID, 0)
        XCTAssertEqual(options.windowID, UInt32.max)
        XCTAssertEqual(options.outputPath, URL(fileURLWithPath: "last.png"))
    }
}
