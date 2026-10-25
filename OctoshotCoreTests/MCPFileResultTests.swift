import Foundation
import XCTest

final class MCPFileResultTests: XCTestCase {
    private struct Response: Codable {
        let jsonrpc: String
        let id: Int
        let result: Result

        struct Result: Codable {
            let content: [Content]
        }

        struct Content: Codable {
            let type: String
            let text: String
        }
    }

    private func assertRoundTrip(_ path: String, file: StaticString = #filePath, line: UInt = #line) throws {
        for key in ["path", "clipFolder"] {
            let text = try encodeMCPFileResult([key: path])
            let response = Response(jsonrpc: "2.0", id: 106, result: .init(content: [.init(type: "text", text: text)]))
            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            XCTAssertEqual(decoded.jsonrpc, "2.0", file: file, line: line)
            XCTAssertEqual(decoded.id, 106, file: file, line: line)
            XCTAssertEqual(decoded.result.content.count, 1, file: file, line: line)
            let content = try XCTUnwrap(decoded.result.content.first, file: file, line: line)
            XCTAssertEqual(content.type, "text", file: file, line: line)
            XCTAssertEqual(content.text, text, file: file, line: line)
            let result = try JSONDecoder().decode([String: String].self, from: Data(content.text.utf8))
            XCTAssertEqual(result, [key: path], file: file, line: line)
            let actualPath = try XCTUnwrap(result[key], file: file, line: line)
            XCTAssertEqual(Array(actualPath.unicodeScalars), Array(path.unicodeScalars), file: file, line: line)
        }
    }

    func testOrdinaryPath() throws {
        try assertRoundTrip("/tmp/screenshot.png")
    }

    func testDoubleQuoteInPath() throws {
        try assertRoundTrip("/tmp/say \"hello\".png")
    }

    func testBackslashInPath() throws {
        try assertRoundTrip("/tmp/literal\\n\\t\\u0041.png")
    }

    func testNewlineInPath() throws {
        try assertRoundTrip("/tmp/line\nbreak.png")
    }

    func testTabInPath() throws {
        try assertRoundTrip("/tmp/tab\there.png")
    }

    func testSpacesInPath() throws {
        try assertRoundTrip("/tmp/my screenshots/image 1.png")
    }

    func testChineseInPath() throws {
        try assertRoundTrip("/tmp/截图/表格.png")
    }

    func testCombinedSpecialCharactersInPath() throws {
        try assertRoundTrip("/tmp/中文 \"quoted\"\\literal\n\t\r/e\u{301}.png")
    }
}
