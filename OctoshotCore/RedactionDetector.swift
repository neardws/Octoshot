import AppKit
import Vision

public enum RedactionDetector {
    public static func detect(
        in image: NSImage,
        settings: RedactionSettingsSnapshot? = nil
    ) async throws -> [RedactionCandidate] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.captureFailed("Unable to decode image for redaction detection")
        }
        let settings = settings ?? AgentConfiguration.redactionSettings()
        var candidates: [RedactionCandidate] = []

        let textCandidates = try await detectSensitiveText(in: cgImage, imageSize: image.size, settings: settings)
        candidates.append(contentsOf: textCandidates)

        if settings.redactFaces {
            let faces = try await detectFaces(in: cgImage, imageSize: image.size)
            candidates.append(contentsOf: faces)
        }
        return mergeOverlapping(candidates)
    }

    private static func detectSensitiveText(
        in cgImage: CGImage,
        imageSize: NSSize,
        settings: RedactionSettingsSnapshot
    ) async throws -> [RedactionCandidate] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        var found: [RedactionCandidate] = []
        for observation in observations {
            guard let top = observation.topCandidates(1).first else { continue }
            let matches = SensitivePatternMatcher.matches(in: top.string, settings: settings)
            for match in matches {
                let visionBox: CGRect
                if let observation = try? top.boundingBox(for: match.range) {
                    visionBox = observation.boundingBox
                } else {
                    visionBox = observation.boundingBox
                }
                let rect = visionRectToImage(visionBox, imageSize: imageSize)
                found.append(RedactionCandidate(
                    rect: rect.insetBy(dx: -4, dy: -4),
                    kind: match.kind,
                    detail: match.value
                ))
            }
        }
        return found
    }

    private static func detectFaces(in cgImage: CGImage, imageSize: NSSize) async throws -> [RedactionCandidate] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.map { face in
            RedactionCandidate(
                rect: visionRectToImage(face.boundingBox, imageSize: imageSize).insetBy(dx: -8, dy: -8),
                kind: .face,
                detail: "Face"
            )
        }
    }

    /// Vision bounding boxes are normalized with origin bottom-left.
    private static func visionRectToImage(_ box: CGRect, imageSize: NSSize) -> CGRect {
        let w = imageSize.width * box.width
        let h = imageSize.height * box.height
        let x = imageSize.width * box.origin.x
        let y = imageSize.height * (1 - box.origin.y - box.height)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func mergeOverlapping(_ items: [RedactionCandidate]) -> [RedactionCandidate] {
        var merged = items
        var index = 0
        while index < merged.count {
            var j = index + 1
            while j < merged.count {
                if merged[index].rect.intersects(merged[j].rect) {
                    merged[index].rect = merged[index].rect.union(merged[j].rect)
                    merged.remove(at: j)
                } else {
                    j += 1
                }
            }
            index += 1
        }
        return merged
    }
}
