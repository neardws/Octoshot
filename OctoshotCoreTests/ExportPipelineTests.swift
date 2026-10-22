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

    // MARK: - Redaction boxes past the image edge

    /// Renderer stub that returns solid black at the requested pixel size, so tests need no GPU.
    private func blackRenderer(extents: RenderExtents? = nil) -> RedactionRenderer {
        RedactionRenderer(render: { _, extent in
            extents?.append(extent)
            let context = CGContext(data: nil, width: Int(extent.width), height: Int(extent.height),
                                    bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context?.fill(extent.offsetBy(dx: -extent.minX, dy: -extent.minY))
            return context?.makeImage()
        })
    }

    private final class RenderExtents: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [CGRect] = []
        var all: [CGRect] { lock.lock(); defer { lock.unlock() }; return values }
        func append(_ value: CGRect) { lock.lock(); values.append(value); lock.unlock() }
    }

    /// White 40×24 pt image at 2× (80×48 px).
    private func whiteImage() throws -> NSImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 48, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 48))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 40, height: 24))
    }

    private func brightness(_ image: CGImage, x: Int, yFromTop: Int) throws -> CGFloat {
        let offset = try XCTUnwrap((0..<image.width).contains(x) && (0..<image.height).contains(yFromTop)
            ? (yFromTop * image.width + x) * 4 : nil, "Sample must be within the actual pixel bounds")
        let bytes = try rgba(image)
        return CGFloat(max(bytes[offset], bytes[offset + 1], bytes[offset + 2])) / 255
    }

    func testClippedRegionKeepsOnlyThePartOnTheCanvas() {
        let canvas = CGSize(width: 40, height: 24)
        XCTAssertEqual(RedactionRenderer.clippedRegion(CGRect(x: 30, y: 10, width: 20, height: 20), canvasSize: canvas),
                       CGRect(x: 30, y: 10, width: 10, height: 14))
        XCTAssertEqual(RedactionRenderer.clippedRegion(CGRect(x: -5, y: -5, width: 10, height: 10), canvasSize: canvas),
                       CGRect(x: 0, y: 0, width: 5, height: 5))
        XCTAssertEqual(RedactionRenderer.clippedRegion(CGRect(x: 10, y: 10, width: -4, height: -4), canvasSize: canvas),
                       CGRect(x: 6, y: 6, width: 4, height: 4), "boxes dragged up and left are normalized")
        XCTAssertNil(RedactionRenderer.clippedRegion(CGRect(x: 50, y: 0, width: 10, height: 10), canvasSize: canvas))
        XCTAssertNil(RedactionRenderer.clippedRegion(CGRect(x: 40, y: 0, width: 10, height: 10), canvasSize: canvas),
                     "touching the edge from outside covers nothing")
        XCTAssertNil(RedactionRenderer.clippedRegion(CGRect(x: 5, y: 5, width: 0, height: 0), canvasSize: canvas))
        XCTAssertNil(RedactionRenderer.clippedRegion(CGRect(x: CGFloat.nan, y: 0, width: 5, height: 5), canvasSize: canvas))
        XCTAssertNil(RedactionRenderer.clippedRegion(CGRect(x: 0, y: 0, width: 5, height: 5), canvasSize: .zero))
    }

    func testPatchPastTheEdgeCoversTheVisiblePart() throws {
        let extents = RenderExtents()
        let renderer = blackRenderer(extents: extents)
        let source = try XCTUnwrap(whiteImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let canvas = CGSize(width: 40, height: 24)
        for topLeft in [true, false] {
            let patch = try renderer.patch(source: source, region: CGRect(x: 30, y: 10, width: 20, height: 20),
                                           canvasSize: canvas, kind: .blur, topLeftOrigin: topLeft, useCache: false)
            XCTAssertEqual(patch.width, 20)
            XCTAssertEqual(patch.height, 28)
        }
        // Fractional edges that round one pixel past the image still render.
        let edge = try renderer.patch(source: source, region: CGRect(x: 0.3, y: 0.3, width: 39.9, height: 23.9),
                                      canvasSize: canvas, kind: .pixelate, topLeftOrigin: true, useCache: false)
        XCTAssertEqual(edge.width, 80)
        XCTAssertEqual(edge.height, 48)
        for extent in extents.all {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 80, height: 48).contains(extent))
        }
    }

    func testPatchEntirelyOffTheImageStillThrows() throws {
        let renderer = blackRenderer()
        let source = try XCTUnwrap(whiteImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        for region in [CGRect(x: 41, y: 0, width: 10, height: 10), CGRect(x: -20, y: -20, width: 10, height: 10),
                       CGRect(x: 5, y: 5, width: 0, height: 8)] {
            XCTAssertThrowsError(try renderer.patch(source: source, region: region,
                                                    canvasSize: CGSize(width: 40, height: 24),
                                                    kind: .blur, topLeftOrigin: true)) {
                XCTAssertEqual($0 as? RedactionError, .invalidRegion)
            }
        }
    }

    func testAgentBlurPastTheEdgeRedactsInsteadOfBlockingExport() throws {
        // AppKit points with a bottom-left origin: covers x 30–40, y 10–24 of a 40×24 image (its top-right corner).
        let specification = try JSONDecoder().decode(AgentAnnotationSpec.self, from: Data(
            "{\"annotations\":[{\"type\":\"blur\",\"from\":[30,10],\"to\":[60,40]}]}".utf8))

        let output = try AnnotationRenderer.apply(spec: specification, to: whiteImage(), renderer: blackRenderer())
        let rendered = try XCTUnwrap(output.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(try brightness(rendered, x: rendered.width * 7 / 8, yFromTop: rendered.height / 12),
                       0, accuracy: 0.01, "visible part is redacted")
        XCTAssertEqual(try brightness(rendered, x: rendered.width * 7 / 8, yFromTop: rendered.height * 5 / 6),
                       1, accuracy: 0.01, "below the box is untouched")
        XCTAssertEqual(try brightness(rendered, x: rendered.width / 8, yFromTop: rendered.height / 12),
                       1, accuracy: 0.01, "left of the box is untouched")
    }

    func testAgentBlurEntirelyOffTheImageBlocksExport() throws {
        let specification = try JSONDecoder().decode(AgentAnnotationSpec.self, from: Data(
            "{\"annotations\":[{\"type\":\"blur\",\"from\":[50,0],\"to\":[60,10]}]}".utf8))
        XCTAssertThrowsError(try AnnotationRenderer.apply(spec: specification, to: whiteImage(),
                                                          renderer: blackRenderer())) {
            XCTAssertTrue($0 is RedactionError)
        }
    }
}
