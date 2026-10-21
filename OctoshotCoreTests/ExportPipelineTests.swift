import AppKit
import CoreImage
import ImageIO
import XCTest
@testable import OctoshotCore

final class ExportPipelineTests: XCTestCase {
    private final class RenderCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }

    private func pixels(space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 48, bitsPerComponent: 8,
            bytesPerRow: 320, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 24))
        context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 24, width: 80, height: 24))
        return try XCTUnwrap(context.makeImage())
    }

    private func spec(_ kind: String = "blur") throws -> AgentAnnotationSpec {
        try JSONDecoder().decode(AgentAnnotationSpec.self,
            from: Data("{\"annotations\":[{\"type\":\"\(kind)\",\"from\":[2,2],\"to\":[18,18]}]}".utf8))
    }

    private func rgba(_ image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
    }

    func testRenderFailureThrowsForBothCoreFilters() throws {
        let renderer = RedactionRenderer(render: { _, _ in nil })
        let source = NSImage(cgImage: try pixels(), size: NSSize(width: 40, height: 24))
        for kind in ["blur", "pixelate"] {
            XCTAssertThrowsError(try AnnotationRenderer.apply(spec: spec(kind), to: source, renderer: renderer)) {
                XCTAssertTrue($0 is RedactionError)
            }
        }
    }

    func testMalformedCoreRedactionThrows() throws {
        let specification = try JSONDecoder().decode(AgentAnnotationSpec.self,
            from: Data("{\"annotations\":[{\"type\":\"blur\"}]}".utf8))
        XCTAssertThrowsError(try AnnotationRenderer.apply(spec: specification,
            to: NSImage(cgImage: pixels(), size: NSSize(width: 40, height: 24))))
    }

    func testCacheMatchesUncachedPixelsAndKeysSourceRectKindScale() throws {
        let source = try pixels()
        let replacement = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 16, height: 16)))
        let counter = RenderCounter()
        let renderer = RedactionRenderer(render: { _, _ in
            counter.increment()
            return replacement
        })
        let region = CGRect(x: 2, y: 2, width: 16, height: 16)
        func patch(_ source: CGImage, _ region: CGRect, _ kind: RedactionRenderer.Kind = .blur,
                   _ size: CGSize = CGSize(width: 80, height: 48), cache: Bool = true) throws -> CGImage {
            try renderer.patch(source: source, region: region, canvasSize: size,
                               kind: kind, topLeftOrigin: true, useCache: cache)
        }
        let first = try patch(source, region)
        XCTAssertEqual(try rgba(first), try rgba(patch(source, region)))
        XCTAssertEqual(counter.calls, 1)
        XCTAssertEqual(try rgba(first), try rgba(patch(source, region, cache: false)))
        XCTAssertEqual(counter.calls, 2)
        _ = try patch(pixels(), region)
        _ = try patch(source, region.offsetBy(dx: 1, dy: 0))
        _ = try patch(source, region, .pixelate)
        _ = try patch(source, region, .blur, CGSize(width: 40, height: 24))
        XCTAssertEqual(counter.calls, 6)
        renderer.invalidate()
        _ = try patch(source, region)
        XCTAssertEqual(counter.calls, 7)
        XCTAssertThrowsError(try patch(source, region.offsetBy(dx: 100, dy: 0)))
    }

    func testRealGPUCachedAndUncachedPixels() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OCTOSHOT_TEST_GPU"] == "1",
                          "Opt-in GPU test: OCTOSHOT_TEST_GPU=1 outside the sandbox")
        let renderer = RedactionRenderer()
        let source = try pixels()
        for kind in [RedactionRenderer.Kind.blur, .pixelate] {
            let region = CGRect(x: 2, y: 2, width: 32, height: 32)
            let cached = try renderer.patch(source: source, region: region, canvasSize: CGSize(width: 80, height: 48),
                                            kind: kind, topLeftOrigin: true)
            let uncached = try renderer.patch(source: source, region: region, canvasSize: CGSize(width: 80, height: 48),
                                              kind: kind, topLeftOrigin: true, useCache: false)
            XCTAssertEqual(try rgba(cached), try rgba(uncached))
            XCTAssertEqual(cached.bitsPerComponent, 8)
            XCTAssertEqual(uncached.bitsPerComponent, 8)
            XCTAssertEqual(cached.colorSpace?.copyICCData(), source.colorSpace?.copyICCData())
        }
    }

    func testConcurrentRequestsCompleteWithInjectedRenderer() throws {
        let first = try pixels()
        let second = try pixels(space: XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)))
        let completed = RenderCounter()
        let renderer = RedactionRenderer(render: { _, _ in first })
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            do {
                let result = try renderer.patch(source: index.isMultiple(of: 2) ? first : second,
                    region: CGRect(x: 2, y: 2, width: 16, height: 16), canvasSize: CGSize(width: 80, height: 48),
                    kind: index.isMultiple(of: 3) ? .blur : .pixelate, topLeftOrigin: true)
                XCTAssertEqual(result.width, first.width)
                completed.increment()
            } catch {
                XCTFail("Concurrent redaction failed: \(error)")
            }
        }
        XCTAssertEqual(completed.calls, 40)
    }

    func testDirectEncodingPreservesSizeAlphaProfileOrientationAndDPI() throws {
        for spaceName in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let source = try pixels(space: XCTUnwrap(CGColorSpace(name: spaceName)))
            let image = NSImage(cgImage: source, size: NSSize(width: 40, height: 24))
            let legacy = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            for format in [ScreenshotFormat.png, .jpeg] {
                let encoded = try XCTUnwrap(ImageFormats.data(for: image, format: format, jpegQuality: 0.85))
                let decoder = try XCTUnwrap(CGImageSourceCreateWithData(encoded as CFData, nil))
                let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
                XCTAssertEqual(decoded.bitsPerComponent, 8)
                XCTAssertEqual(decoded.width, legacy.pixelsWide)
                XCTAssertEqual(decoded.height, legacy.pixelsHigh)
                XCTAssertEqual(decoded.colorSpace?.model, source.colorSpace?.model)
                XCTAssertEqual(decoded.colorSpace?.name, source.colorSpace?.name)
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoder, 0, nil) as? [CFString: Any])
                XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0, 144, accuracy: 1)
                XCTAssertEqual((properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 0, 144, accuracy: 1)
                XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1, 1)
                let legacyData = try XCTUnwrap(legacy.representation(using: format == .png ? .png : .jpeg,
                    properties: format == .png ? [:] : [.compressionFactor: 0.85]))
                let legacyDecoder = try XCTUnwrap(CGImageSourceCreateWithData(legacyData as CFData, nil))
                let legacyPixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(legacyDecoder, 0, nil))
                XCTAssertEqual(decoded.colorSpace?.name, legacyPixels.colorSpace?.name)
                if format == .png {
                    XCTAssertTrue(try XCTUnwrap(NSBitmapImageRep(data: encoded)).hasAlpha)
                    XCTAssertEqual(try rgba(decoded), try rgba(source))
                    XCTAssertEqual(try rgba(decoded), try rgba(legacyPixels))
                } else {
                    XCTAssertFalse(try XCTUnwrap(NSBitmapImageRep(data: encoded)).hasAlpha)
                    let actual = try rgba(decoded)
                    let expected = try rgba(legacyPixels)
                    let meanError = zip(actual, expected).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(actual.count)
                    XCTAssertLessThan(meanError, 8)
                }
            }
        }
    }

    @MainActor
    func testAsyncWriteRoundTripsAndReportsWriteFailure() async throws {
        let snapshot = ImageFormats.Snapshot(image: try pixels(), pointSize: CGSize(width: 40, height: 24))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for format in [ScreenshotFormat.png, .jpeg] {
            let url = directory.appendingPathComponent("roundtrip.\(format.fileExtension)")
            let actual = try await ImageFormats.writeAsync(snapshot, to: url, format: format, jpegQuality: 0.85)
            XCTAssertEqual(actual, url)
            let data = try Data(contentsOf: actual)
            let decoder = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceCreateImageAtIndex(decoder, 0, nil)?.width, 80)
            XCTAssertTrue(Thread.isMainThread)
        }
        let file = directory.appendingPathComponent("roundtrip.png")
        do {
            _ = try await ImageFormats.writeAsync(snapshot, to: file.appendingPathComponent("invalid.png"), format: .png, jpegQuality: 1)
            XCTFail("Expected a failed disk write")
        } catch { }
    }

    func testLoadedOrientationMatchesLegacyEncoding() throws {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try pixels(), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let image = try XCTUnwrap(NSImage(data: data as Data))
        let legacyRep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let legacyData = try XCTUnwrap(legacyRep.representation(using: .png, properties: [:]))
        let newData = try XCTUnwrap(ImageFormats.pngData(from: image))
        func decode(_ data: Data) throws -> CGImage {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        let before = try decode(legacyData)
        let after = try decode(newData)
        XCTAssertEqual(after.width, before.width)
        XCTAssertEqual(after.height, before.height)
        XCTAssertEqual(try rgba(after), try rgba(before))
    }
}
