import AppKit
import ImageIO
import XCTest
@testable import OctoshotCore

final class QuickAccessDragPayloadTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".derivedData/DragTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func snapshot() throws -> ImageFormats.Snapshot {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8,
                                            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        return ImageFormats.Snapshot(image: try XCTUnwrap(context.makeImage()), pointSize: CGSize(width: 4, height: 3))
    }

    private func makeDirectory(_ url: URL, age: TimeInterval) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: url.appendingPathComponent("sentinel"))
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    func testPayloadOffersFilePNGAndTIFF() async throws {
        let date = now
        let payload = try await QuickAccessDragPayload.prepare(snapshot(), temporaryDirectory: temporaryDirectory, now: { date })
        XCTAssertEqual(QuickAccessDragPayload.pasteboardTypes.map(\.rawValue), ["public.file-url", "public.png", "public.tiff"])
        let writer = QuickAccessDragPasteboardWriter(payload: payload)
        XCTAssertEqual(writer.pasteboardPropertyList(forType: .fileURL) as? String, payload.fileURL.absoluteString)
        XCTAssertEqual(writer.pasteboardPropertyList(forType: .png) as? Data, payload.pngData)
        XCTAssertEqual(writer.pasteboardPropertyList(forType: .tiff) as? Data, payload.tiffData)
        XCTAssertNil(writer.pasteboardPropertyList(forType: .string))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(payload.tiffData as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.tiff")
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testPreparationWritesDecodablePNGOffMain() async throws {
        let date = now
        let payload = try await QuickAccessDragPayload.prepare(snapshot(), temporaryDirectory: temporaryDirectory, now: {
            XCTAssertFalse(Thread.isMainThread)
            return date
        })
        let data = try Data(contentsOf: payload.fileURL)
        XCTAssertEqual(data, payload.pngData)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 8)
        XCTAssertEqual(image.height, 6)
        XCTAssertEqual(payload.fileURL.deletingLastPathComponent().deletingLastPathComponent(),
                       temporaryDirectory.appendingPathComponent("Octoshot-Drag", isDirectory: true))
        XCTAssertNotNil(UUID(uuidString: payload.fileURL.deletingLastPathComponent().lastPathComponent))
        XCTAssertEqual(payload.preparedAt, now)
    }

    func testFilenameIsStableAndFilesystemSafe() {
        let name = QuickAccessDragPayload.filename(at: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(name, "Screenshot 2023-11-14 at 22.13.20.png")
        XCTAssertNil(name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)))
    }

    func testCleanupRemovesOnlyStaleOwnedDirectories() throws {
        let root = temporaryDirectory.appendingPathComponent("Octoshot-Drag")
        let stale = root.appendingPathComponent(UUID().uuidString)
        let fresh = root.appendingPathComponent(UUID().uuidString)
        let boundary = root.appendingPathComponent(UUID().uuidString)
        let unrelated = root.appendingPathComponent("unrelated")
        let outside = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for directory in [stale, unrelated, outside] { try makeDirectory(directory, age: 7200) }
        try makeDirectory(fresh, age: 60)
        try makeDirectory(boundary, age: 3600)
        let link = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let file = root.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: file.path)

        try QuickAccessDragPayload.cleanup(temporaryDirectory: temporaryDirectory, now: now)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        for directory in [fresh, boundary, unrelated, outside, link] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sentinel").path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanupRejectsSymlinkRoot() throws {
        let outside = temporaryDirectory.appendingPathComponent("outside")
        let stale = outside.appendingPathComponent(UUID().uuidString)
        try makeDirectory(stale, age: 7200)
        try FileManager.default.createSymbolicLink(at: temporaryDirectory.appendingPathComponent("Octoshot-Drag"),
                                                  withDestinationURL: outside)
        XCTAssertThrowsError(try QuickAccessDragPayload.cleanup(temporaryDirectory: temporaryDirectory, now: now))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale.appendingPathComponent("sentinel").path))
    }

    func testPreparationCleansStaleFilesAndUsesUniqueDirectories() async throws {
        let stale = temporaryDirectory.appendingPathComponent("Octoshot-Drag/\(UUID().uuidString)")
        try makeDirectory(stale, age: 7200)
        let date = now
        let first = try await QuickAccessDragPayload.prepare(snapshot(), temporaryDirectory: temporaryDirectory, now: { date })
        let second = try await QuickAccessDragPayload.prepare(snapshot(), temporaryDirectory: temporaryDirectory, now: { date })
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertNotEqual(first.fileURL, second.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.fileURL.path))
    }
}
