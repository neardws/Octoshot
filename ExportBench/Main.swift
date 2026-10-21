#if DEBUG
import AppKit
import CoreImage
import OctoshotCore

struct Summary: Codable {
    let medianMS: Double
    let p95MS: Double
    let samplesMS: [Double]

    init(_ samples: [Double]) {
        samplesMS = samples
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        medianMS = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        p95MS = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
    }
}

enum BenchError: Error { case invalidArguments, image, missingRedaction(String, Int) }

@main
struct ExportBench {
    @MainActor
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 5, arguments[1] == "--developer",
                  ["export", "bench"].contains(arguments[2]),
                  let outIndex = arguments.firstIndex(of: "--out"), outIndex + 1 < arguments.count else {
                throw BenchError.invalidArguments
            }
            let destination = URL(fileURLWithPath: arguments[outIndex + 1], isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let iterationIndex = arguments.firstIndex(of: "--iterations")
            let iterations = iterationIndex.flatMap { $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil } ?? 20
            guard iterations > 0 else { throw BenchError.invalidArguments }
            var measurements: [String: Summary] = [:]
            for (name, width, height) in [("1080p", 1920, 1080), ("5K", 5120, 2880)] {
                let source = try synthetic(width: width, height: height)
                let strokes = fixture(size: source.size)
                let specification = try spec(strokes, height: source.size.height)
                let canvas = AnnotationCanvasView(frame: NSRect(origin: .zero, size: source.size))
                canvas.baseImage = source
                guard let reference = try canvas.currentImage() else { throw BenchError.image }
                canvas.strokes = strokes
                for path in ["editor", "core"] {
                    func render() throws -> NSImage {
                        if path == "core" { return try AnnotationRenderer.apply(spec: specification, to: source) }
                        canvas.rebuildComposite()
                        guard let image = try canvas.currentImage() else { throw BenchError.image }
                        return image
                    }
                    let annotated = try render()
                    try validate(annotated, reference: reference, strokes: strokes, path: path)
                    if arguments[2] == "export" {
                        for format in [ScreenshotFormat.png, .jpeg] {
                            _ = try await ImageFormats.writeAsync(ImageFormats.snapshot(annotated), to: destination.appendingPathComponent("\(path)-\(name).\(format == .png ? "png" : "jpg")"), format: format, jpegQuality: 0.85)
                        }
                    } else {
                        var samples: [Double] = []
                        for _ in 0..<iterations {
                            let start = CFAbsoluteTimeGetCurrent()
                            try autoreleasepool { _ = try render() }
                            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                        }
                        measurements["\(path)-annotate-export-\(name)-warm"] = Summary(samples)
                        for format in [ScreenshotFormat.png, .jpeg] {
                            var saveSamples: [Double] = []
                            var snapshotSamples: [Double] = []
                            let url = destination.appendingPathComponent("scratch-\(path)-\(name).\(format == .png ? "png" : "jpg")")
                            for _ in 0..<iterations {
                                let start = CFAbsoluteTimeGetCurrent()
                                let snapshot = try ImageFormats.snapshot(annotated)
                                snapshotSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                                _ = try await ImageFormats.writeAsync(snapshot, to: url, format: format, jpegQuality: 0.85)
                                saveSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                            }
                            try FileManager.default.removeItem(at: url)
                            let key = "\(path)-save-\(format.rawValue)-\(name)"
                            measurements[key] = Summary(saveSamples)
                            measurements[key + "-main-snapshot"] = Summary(snapshotSamples)
                        }
                    }
                }
            }
            if arguments[2] == "bench" {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(measurements)
                try data.write(to: destination.appendingPathComponent("bench.json"))
                print(String(decoding: data, as: UTF8.self))
            }
        } catch {
            fputs("Export benchmark failed (no capture APIs used): \(error)\n", stderr)
            exit(1)
        }
    }

    static func synthetic(width: Int, height: Int) throws -> NSImage {
        var seed: UInt64 = 0x0C705407
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                seed = seed &* 6364136223846793005 &+ 1
                let checker = ((column / 5 + row / 5) % 2) * 90
                let glyph = row % 24 < 12 && column % 11 < 3 ? 40 : 0
                let offset = (row * width + column) * 4
                pixels[offset] = UInt8(30 + column * 80 / width + checker + glyph)
                pixels[offset + 1] = UInt8(20 + row * 80 / height + checker)
                pixels[offset + 2] = UInt8(40 + Int(seed >> 60) + checker)
            }
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw BenchError.image }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    static func fixture(size: NSSize) -> [AnnotationStroke] {
        (0..<50).map { index in
            let tool: AnnotationTool = index < 10 ? .blur : index < 20 ? .pixelate : [.arrow, .rectangle, .text, .highlighter, .ellipse, .line][(index - 20) % 6]
            let start = CGPoint(x: (0.03 + Double(index % 10) * 0.095) * size.width,
                                y: (0.04 + Double(index / 10) * 0.18) * size.height)
            let end = CGPoint(x: start.x + size.width * 0.06, y: start.y + size.height * 0.08)
            return AnnotationStroke(tool: tool, start: start, end: end, text: "Test \(index)",
                color: NSColor(srgbRed: 0.9, green: 0.2, blue: 0.1, alpha: 1), lineWidth: 4,
                points: [start, end])
        }
    }

    static func spec(_ strokes: [AnnotationStroke], height: CGFloat) throws -> AgentAnnotationSpec {
        let items: [[String: Any]] = strokes.map {
            ["type": $0.tool.rawValue, "from": [$0.start.x, height - $0.start.y],
             "to": [$0.end.x, height - $0.end.y], "at": [$0.start.x, height - $0.start.y],
             "text": $0.text, "color": "#E6331A", "lineWidth": 4,
             "points": [$0.start.x, height - $0.start.y, $0.end.x, height - $0.end.y]]
        }
        return try JSONDecoder().decode(AgentAnnotationSpec.self, from: JSONSerialization.data(withJSONObject: ["annotations": items]))
    }

    static func bytes(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let valid = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard valid else { throw BenchError.image }
        return pixels
    }

    static func validate(_ result: NSImage, reference: NSImage, strokes: [AnnotationStroke], path: String) throws {
        guard let actual = result.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let original = reference.cgImage(forProposedRect: nil, context: nil, hints: nil),
              actual.width == original.width, actual.height == original.height else { throw BenchError.image }
        for (index, stroke) in strokes.prefix(20).enumerated() {
            let scaleX = CGFloat(actual.width) / result.size.width
            let scaleY = CGFloat(actual.height) / result.size.height
            let region = AnnotationDrawing.rect(from: stroke.start, to: stroke.end)
            let crop = CGRect(x: region.minX * scaleX, y: region.minY * scaleY,
                              width: region.width * scaleX, height: region.height * scaleY).insetBy(dx: 4, dy: 4).integral
            guard let before = original.cropping(to: crop), let after = actual.cropping(to: crop) else { throw BenchError.image }
            let first = try bytes(before)
            let second = try bytes(after)
            let changed = zip(first, second).filter { abs(Int($0) - Int($1)) > 8 }.count
            guard changed > first.count / 10 else {
                let probe = CIImage(cgImage: before).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14])
                if CIContext().createCGImage(probe, from: probe.extent) == nil {
                    fputs("CIContext.createCGImage returned nil; GPU may be unavailable in this sandbox. Run outside the sandbox.\n", stderr)
                }
                throw BenchError.missingRedaction(path, index)
            }
        }
    }
}
#endif
