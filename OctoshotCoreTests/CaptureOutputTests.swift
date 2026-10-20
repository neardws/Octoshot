import AppKit
import XCTest
@testable import OctoshotCore

final class CaptureOutputTests: XCTestCase {
    func testUniqueWritesPreserveExistingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let proposed = directory.appendingPathComponent("Screenshot.png")
        let first = try CaptureOutput.writeUnique(Data([1]), to: proposed)
        let second = try CaptureOutput.writeUnique(Data([2]), to: proposed)
        let third = try CaptureOutput.writeUnique(Data([3]), to: proposed)
        XCTAssertEqual(first, proposed)
        XCTAssertEqual(second.lastPathComponent, "Screenshot (2).png")
        XCTAssertEqual(third.lastPathComponent, "Screenshot (3).png")
        XCTAssertEqual(try Data(contentsOf: first), Data([1]))
        XCTAssertEqual(try Data(contentsOf: second), Data([2]))
    }

    func testConcurrentWritersNeverOverwrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let proposed = directory.appendingPathComponent("Screenshot.jpg")
        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for index in 0..<20 {
                group.addTask { try CaptureOutput.writeUnique(Data([UInt8(index)]), to: proposed) }
            }
            var results: [URL] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(Set(urls).count, 20)
        XCTAssertEqual(Set(try urls.map { try Data(contentsOf: $0) }).count, 20)
    }

    func testFormatExtensionAndExplicitPathPolicy() {
        XCTAssertEqual(CaptureOutput.filename("Screenshot.png", format: .jpeg), "Screenshot.jpg")
        XCTAssertEqual(CaptureOutput.filename("Screenshot.jpeg", format: .png), "Screenshot.png")
        XCTAssertEqual(CaptureOutput.explicitURL(URL(fileURLWithPath: "/tmp/test"), format: .jpeg).path, "/tmp/test.jpg")
        XCTAssertEqual(CaptureOutput.explicitURL(URL(fileURLWithPath: "/tmp/test.png"), format: .jpeg).path, "/tmp/test.png")
    }

    func testJPEGWriteHasJPEGBytesAndJPGGeneratedName() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 4, height: 4))
        let proposed = directory.appendingPathComponent(CaptureOutput.filename("test.png", format: .jpeg))
        let actual = try ImageFormats.writeUnique(image: image, to: proposed, format: .jpeg, jpegQuality: 0.9)
        XCTAssertEqual(actual.pathExtension, "jpg")
        XCTAssertEqual(Array(try Data(contentsOf: actual).prefix(2)), [0xff, 0xd8])
    }

    func testUnknownDisplayFailsWithAvailableIdentifiers() throws {
        XCTAssertNoThrow(try CaptureDisplaySelection.validate(nil, available: [2, 1]))
        XCTAssertNoThrow(try CaptureDisplaySelection.validate(2, available: [2, 1]))
        XCTAssertThrowsError(try CaptureDisplaySelection.validate(999999, available: [2, 1])) {
            XCTAssertTrue($0.localizedDescription.contains("Available display ids: 1, 2"))
        }
        XCTAssertThrowsError(try CaptureDisplaySelection.validate(1, available: []))
    }

    func testCSVQuotesDelimitersQuotesAndNewlines() {
        XCTAssertEqual(CSVEncoder.encode([["a,b", "say \"hi\"", "line\rbreak", "line\nbreak", ""], ["plain", "2"]]),
                       "\"a,b\",\"say \"\"hi\"\"\",\"line\rbreak\",\"line\nbreak\",\r\nplain,2")
    }

    func testMarkdownTableExportKeepsEmptyColumnsAndEscapes() {
        XCTAssertEqual(AgentProcessing.convertMarkdownTableToCSV("| Name | Note | Empty |\n| --- | --- | --- |\n| Doe, Jane | Say \"hello\" | |"),
                       "Name,Note,Empty\r\n\"Doe, Jane\",\"Say \"\"hello\"\"\","
        )
    }
}
