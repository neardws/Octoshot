import AppKit
import CoreImage
import OctoshotCore

enum AnnotationDrawing {
    static func draw(stroke: AnnotationStroke, in canvas: NSRect, sourceImage: NSImage?, renderer: RedactionRenderer = .shared, sourceCGImage: CGImage? = nil) throws {
        switch stroke.tool {
        case .arrow:
            stroke.color.setStroke()
            let path = NSBezierPath()
            path.move(to: stroke.start)
            path.line(to: stroke.end)
            path.lineWidth = stroke.lineWidth
            path.stroke()
            addArrowHead(to: path, at: stroke.end, from: stroke.start, width: stroke.lineWidth)
        case .line:
            stroke.color.setStroke()
            let path = NSBezierPath()
            path.move(to: stroke.start)
            path.line(to: stroke.end)
            path.lineWidth = stroke.lineWidth
            path.stroke()
        case .rectangle:
            stroke.color.setStroke()
            let box = rect(from: stroke.start, to: stroke.end)
            let path = NSBezierPath(rect: box)
            path.lineWidth = stroke.lineWidth
            path.stroke()
        case .ellipse:
            stroke.color.setStroke()
            let path = NSBezierPath(ovalIn: rect(from: stroke.start, to: stroke.end))
            path.lineWidth = stroke.lineWidth
            path.stroke()
        case .pen:
            guard !stroke.points.isEmpty else { return }
            stroke.color.setStroke()
            let path = NSBezierPath()
            path.move(to: stroke.points[0])
            for point in stroke.points.dropFirst() {
                path.line(to: point)
            }
            path.lineWidth = stroke.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .highlighter:
            guard !stroke.points.isEmpty else { return }
            stroke.color.withAlphaComponent(0.35).setStroke()
            let path = NSBezierPath()
            path.move(to: stroke.points[0])
            for point in stroke.points.dropFirst() {
                path.line(to: point)
            }
            path.lineWidth = max(stroke.lineWidth * 3, 12)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .text:
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(16, stroke.lineWidth * 4)),
                .foregroundColor: stroke.color
            ]
            (stroke.text as NSString).draw(at: stroke.start, withAttributes: attributes)
        case .counter:
            let value = stroke.counterValue ?? 1
            let diameter = max(28, stroke.lineWidth * 8)
            let center = stroke.start
            let circle = NSBezierPath(ovalIn: CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            ))
            stroke.color.setFill()
            circle.fill()
            NSColor.white.setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            let label = "\(value)" as NSString
            let font = NSFont.boldSystemFont(ofSize: diameter * 0.45)
            let size = label.size(withAttributes: [.font: font])
            let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
            label.draw(at: origin, withAttributes: [.font: font, .foregroundColor: NSColor.white])
        case .pixelate:
            try pixelate(from: stroke.start, to: stroke.end, in: canvas, sourceImage: sourceImage, renderer: renderer, sourceCGImage: sourceCGImage)
        case .blur:
            try blur(from: stroke.start, to: stroke.end, in: canvas, sourceImage: sourceImage, renderer: renderer, sourceCGImage: sourceCGImage)
        case .crop, .measure:
            break
        }
    }

    static func rect(from start: CGPoint, to end: CGPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    static func addArrowHead(to path: NSBezierPath, at tip: CGPoint, from tail: CGPoint, width: CGFloat) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let head = width * 3
        let p1 = CGPoint(
            x: tip.x - head * cos(angle - .pi / 6),
            y: tip.y - head * sin(angle - .pi / 6)
        )
        let p2 = CGPoint(
            x: tip.x - head * cos(angle + .pi / 6),
            y: tip.y - head * sin(angle + .pi / 6)
        )
        path.move(to: tip)
        path.line(to: p1)
        path.move(to: tip)
        path.line(to: p2)
        path.lineWidth = width
        path.stroke()
    }

    /// Draws a filtered patch upright; `region` is top-left based, matching the flipped composite.
    private static func drawPatch(_ patch: CGImage, in region: NSRect) {
        NSImage(cgImage: patch, size: region.size).draw(
            in: region,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    /// `start`/`end` are in the source image's points with a top-left origin.
    static func pixelate(from start: CGPoint, to end: CGPoint, in canvas: NSRect, sourceImage: NSImage?, renderer: RedactionRenderer = .shared, sourceCGImage: CGImage? = nil) throws {
        try redact(from: start, to: end, in: canvas, sourceImage: sourceImage,
                   renderer: renderer, sourceCGImage: sourceCGImage, kind: .pixelate)
    }

    static func blur(from start: CGPoint, to end: CGPoint, in canvas: NSRect, sourceImage: NSImage?,
                     renderer: RedactionRenderer = .shared, sourceCGImage: CGImage? = nil) throws {
        try redact(from: start, to: end, in: canvas, sourceImage: sourceImage,
                   renderer: renderer, sourceCGImage: sourceCGImage, kind: .blur)
    }

    private static func redact(from start: CGPoint, to end: CGPoint, in canvas: NSRect,
                               sourceImage: NSImage?, renderer: RedactionRenderer,
                               sourceCGImage: CGImage?, kind: RedactionRenderer.Kind) throws {
        guard let source = sourceCGImage ?? sourceImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw RedactionError.unavailableSource
        }
        let region = rect(from: start, to: end)
        let patch = try renderer.patch(source: source, region: region, canvasSize: canvas.size,
                                       kind: kind, topLeftOrigin: true)
        drawPatch(patch, in: region)
    }
}
