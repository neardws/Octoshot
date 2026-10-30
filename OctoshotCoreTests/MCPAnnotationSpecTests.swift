import Foundation
import OctoshotCore
import XCTest

final class MCPAnnotationSpecTests: XCTestCase {
    func testNonObjectSpecsThrowParameterError() {
        let cases: [(String, MCPJSONValue)] = [
            ("number", .number(7)),
            ("bool", .bool(true)),
            ("string", .string("x")),
            ("null", .null),
            ("array", .array([.object(["annotations": .array([])])]))
        ]

        for (name, value) in cases {
            XCTAssertThrowsError(try decodeAgentAnnotationSpec(from: value), name) { error in
                guard case CaptureError.captureFailed(let reason) = error else {
                    return XCTFail("Expected parameter error for \(name), got \(error)")
                }
                XCTAssertEqual(reason, "spec must be an object", name)
            }
        }
    }

    func testMissingAnnotationsThrowsDecodingError() {
        XCTAssertThrowsError(try decodeAgentAnnotationSpec(from: .object([:]))) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("Expected missing annotations key, got \(error)")
            }
            XCTAssertEqual(key.stringValue, "annotations")
        }
    }

    func testEmptyAnnotationsDecode() throws {
        let spec = try decodeAgentAnnotationSpec(from: .object(["annotations": .array([])]))
        XCTAssertTrue(spec.annotations.isEmpty)
    }

    func testTextAnnotationDecodes() throws {
        let spec = try decodeAgentAnnotationSpec(from: .object([
            "annotations": .array([
                .object([
                    "type": .string("text"),
                    "at": .array([.number(10), .number(20)]),
                    "text": .string("Hello")
                ])
            ])
        ]))
        XCTAssertEqual(spec.annotations.count, 1)
        let annotation = try XCTUnwrap(spec.annotations.first)
        XCTAssertEqual(annotation.type, .text)
        XCTAssertEqual(annotation.at, [10, 20])
        XCTAssertEqual(annotation.text, "Hello")
    }
}
