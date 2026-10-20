import AppKit
import CoreImage
import OctoshotCore

final class AnnotationCanvasView: NSView {
    var baseImage: NSImage? {
        didSet { rebuildComposite(); needsDisplay = true }
    }

    var strokes: [AnnotationStroke] = [] {
        didSet { rebuildComposite(); needsDisplay = true }
    }

    var redactionRegions: [CGRect] = [] {
        didSet { rebuildComposite(); needsDisplay = true }
    }

    var previewRedactions: [RedactionCandidate] = [] {
        didSet { needsDisplay = true }
    }

    var activeTool: AnnotationTool = .arrow {
        didSet {
            if activeTool != .measure {
                measureStart = nil
                measureEnd = nil
            }
            if !activeTool.usesFreehand {
                freehandPoints = []
            }
            needsDisplay = true
        }
    }
    var strokeColor: NSColor = .systemRed
    var lineWidth: CGFloat = 4

    private var dragStart: CGPoint?
    private var inProgress: AnnotationStroke?
    private var freehandPoints: [CGPoint] = []
    private var measureStart: CGPoint?
    private var measureEnd: CGPoint?
    private var renderedImage: NSImage?
    private var redoStrokes: [AnnotationStroke] = []
    private var cropUndoStack: [(image: NSImage, strokes: [AnnotationStroke], redactions: [CGRect])] = []
    private var cropRedoStack: [(image: NSImage, strokes: [AnnotationStroke], redactions: [CGRect])] = []
    private var nextCounterValue = 1

    var onStrokesChanged: (() -> Void)?
    var canRedo: Bool { !redoStrokes.isEmpty || !cropRedoStack.isEmpty }
    var canUndo: Bool { !strokes.isEmpty || !cropUndoStack.isEmpty }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if let renderedImage {
            renderedImage.draw(in: bounds)
        } else if let baseImage {
            baseImage.draw(in: bounds)
        }
        if let inProgress, activeTool != .crop {
            drawStrokePreview(inProgress)
        }
        if activeTool.usesFreehand, !freehandPoints.isEmpty {
            let preview = AnnotationStroke(
                tool: activeTool,
                start: .zero,
                end: .zero,
                text: "",
                color: strokeColor,
                lineWidth: lineWidth,
                points: freehandPoints
            )
            drawStrokePreview(preview)
        }
        for candidate in previewRedactions where candidate.isEnabled {
            let path = NSBezierPath(rect: mapImageRectToView(candidate.rect))
            NSColor.systemRed.withAlphaComponent(0.25).setFill()
            path.fill()
            NSColor.systemRed.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        if activeTool == .crop, let start = dragStart, let end = inProgress?.end {
            drawCropOverlay(from: start, to: end)
        }
        if let start = measureStart, let end = measureEnd {
            drawMeasureOverlay(from: start, to: end)
        }
    }

    func applyRedactions(from candidates: [RedactionCandidate]) {
        redactionRegions = candidates.filter(\.isEnabled).map(\.rect)
        previewRedactions = []
        rebuildComposite()
        needsDisplay = true
    }

    private func mapImageRectToView(_ rect: CGRect) -> CGRect {
        guard let baseImage else { return rect }
        let sx = bounds.width / max(baseImage.size.width, 1)
        let sy = bounds.height / max(baseImage.size.height, 1)
        return CGRect(x: rect.origin.x * sx, y: rect.origin.y * sy, width: rect.width * sx, height: rect.height * sy)
    }

    private func mapViewPointToImage(_ point: CGPoint) -> CGPoint {
        guard let baseImage else { return point }
        let sx = max(baseImage.size.width, 1) / bounds.width
        let sy = max(baseImage.size.height, 1) / bounds.height
        return CGPoint(x: point.x * sx, y: point.y * sy)
    }

    private func mapImagePointToView(_ point: CGPoint) -> CGPoint {
        guard let baseImage else { return point }
        let sx = bounds.width / max(baseImage.size.width, 1)
        let sy = bounds.height / max(baseImage.size.height, 1)
        return CGPoint(x: point.x * sx, y: point.y * sy)
    }

    private func imagePixelScale() -> CGFloat {
        guard let baseImage,
              let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
        return CGFloat(cg.width) / max(baseImage.size.width, 1)
    }

    private func drawStrokePreview(_ stroke: AnnotationStroke) {
        if stroke.tool.usesFreehand {
            var viewStroke = stroke
            viewStroke.points = stroke.points
            AnnotationDrawing.draw(stroke: viewStroke, in: bounds, sourceImage: baseImage)
            return
        }
        var viewStroke = stroke
        viewStroke.start = mapImagePointToView(stroke.start)
        viewStroke.end = mapImagePointToView(stroke.end)
        AnnotationDrawing.draw(stroke: viewStroke, in: bounds, sourceImage: nil)
    }

    private func drawCropOverlay(from start: CGPoint, to end: CGPoint) {
        let full = bounds
        let crop = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        NSColor.black.withAlphaComponent(0.45).setFill()
        if crop.minY > full.minY {
            NSRect(x: full.minX, y: full.minY, width: full.width, height: crop.minY - full.minY).fill()
        }
        if crop.maxY < full.maxY {
            NSRect(x: full.minX, y: crop.maxY, width: full.width, height: full.maxY - crop.maxY).fill()
        }
        if crop.minX > full.minX {
            NSRect(x: full.minX, y: crop.minY, width: crop.minX - full.minX, height: crop.height).fill()
        }
        if crop.maxX < full.maxX {
            NSRect(x: crop.maxX, y: crop.minY, width: full.maxX - crop.maxX, height: crop.height).fill()
        }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: crop)
        border.lineWidth = 1.5
        border.stroke()
    }

    private func drawMeasureOverlay(from start: CGPoint, to end: CGPoint) {
        let box = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        NSColor.systemTeal.setStroke()
        let path = NSBezierPath(rect: box)
        path.lineWidth = 1.5
        path.stroke()

        let startImage = mapViewPointToImage(start)
        let endImage = mapViewPointToImage(end)
        let widthPt = abs(endImage.x - startImage.x)
        let heightPt = abs(endImage.y - startImage.y)
        let scale = imagePixelScale()
        let widthPx = widthPt * scale
        let heightPx = heightPt * scale
        let diagonalPt = hypot(widthPt, heightPt)
        let diagonalPx = diagonalPt * scale

        let lines = [
            String(format: "%.0f × %.0f px  (%.1f × %.1f pt)", widthPx, heightPx, widthPt, heightPt),
            String(format: "↳ %.1f px diagonal", diagonalPx)
        ]
        let text = lines.joined(separator: "\n")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: box.minX + 4, y: min(box.maxY + 6, bounds.height - size.height - 12))
        let bg = NSBezierPath(roundedRect: CGRect(origin: origin, size: CGSize(width: size.width + 10, height: size.height + 8)), xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        bg.fill()
        (text as NSString).draw(in: CGRect(origin: origin, size: size).insetBy(dx: 5, dy: 4), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if activeTool == .measure {
            measureStart = point
            measureEnd = point
            needsDisplay = true
            return
        }
        if activeTool == .counter {
            commitCounter(at: point)
            return
        }
        if activeTool.usesFreehand {
            freehandPoints = [point]
            needsDisplay = true
            return
        }
        dragStart = point
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        if activeTool == .measure {
            measureEnd = current
            needsDisplay = true
            return
        }
        if activeTool.usesFreehand {
            freehandPoints.append(current)
            needsDisplay = true
            return
        }
        guard let start = dragStart else { return }
        inProgress = AnnotationStroke(
            tool: activeTool,
            start: mapViewPointToImage(start),
            end: mapViewPointToImage(current),
            text: "",
            color: strokeColor,
            lineWidth: lineWidth
        )
        if activeTool == .crop {
            inProgress?.start = start
            inProgress?.end = current
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let end = convert(event.locationInWindow, from: nil)
        if activeTool == .measure {
            measureEnd = end
            needsDisplay = true
            return
        }
        if activeTool.usesFreehand {
            guard freehandPoints.count > 1 else {
                freehandPoints = []
                needsDisplay = true
                return
            }
            let imagePoints = freehandPoints.map { mapViewPointToImage($0) }
            freehandPoints = []
            appendStroke(AnnotationStroke(
                tool: activeTool,
                start: imagePoints[0],
                end: imagePoints.last ?? imagePoints[0],
                text: "",
                color: strokeColor,
                lineWidth: lineWidth,
                points: imagePoints
            ))
            return
        }
        guard let start = dragStart else { return }
        dragStart = nil
        inProgress = nil
        if activeTool == .crop {
            applyCrop(from: start, to: end)
            return
        }
        commitStroke(from: start, to: end)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, measureStart != nil {
            measureStart = nil
            measureEnd = nil
            needsDisplay = true
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased() == "z" {
                if flags.contains(.shift) {
                    redo()
                } else {
                    undo()
                }
                return
            }
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    func undo() {
        if !strokes.isEmpty {
            let removed = strokes.removeLast()
            redoStrokes.append(removed)
            cropRedoStack = []
            rebuildComposite()
            needsDisplay = true
            onStrokesChanged?()
            return
        }
        guard let snapshot = cropUndoStack.popLast() else { return }
        cropRedoStack.append(currentCropSnapshot())
        baseImage = snapshot.image
        strokes = snapshot.strokes
        redactionRegions = snapshot.redactions
        rebuildComposite()
        needsDisplay = true
        onStrokesChanged?()
    }

    func redo() {
        if let stroke = redoStrokes.popLast() {
            strokes.append(stroke)
            rebuildComposite()
            needsDisplay = true
            onStrokesChanged?()
            return
        }
        guard let snapshot = cropRedoStack.popLast() else { return }
        cropUndoStack.append(currentCropSnapshot())
        baseImage = snapshot.image
        strokes = snapshot.strokes
        redactionRegions = snapshot.redactions
        rebuildComposite()
        needsDisplay = true
        onStrokesChanged?()
    }

    func resetHistory() {
        redoStrokes = []
        cropUndoStack = []
        cropRedoStack = []
        nextCounterValue = 1
    }

    func currentImage() -> NSImage? {
        rebuildComposite()
        return renderedImage ?? baseImage
    }

    private func appendStroke(_ stroke: AnnotationStroke) {
        redoStrokes = []
        cropRedoStack = []
        strokes.append(stroke)
        rebuildComposite()
        needsDisplay = true
        onStrokesChanged?()
    }

    private func commitCounter(at point: CGPoint) {
        let imagePoint = mapViewPointToImage(point)
        appendStroke(AnnotationStroke(
            tool: .counter,
            start: imagePoint,
            end: imagePoint,
            text: "",
            color: strokeColor,
            lineWidth: lineWidth,
            counterValue: nextCounterValue
        ))
        nextCounterValue += 1
    }

    private func commitStroke(from start: CGPoint, to end: CGPoint) {
        let imageStart = mapViewPointToImage(start)
        let imageEnd = mapViewPointToImage(end)
        if activeTool == .text {
            promptForText(at: end) { [weak self] text in
                guard let self, !text.isEmpty else { return }
                self.appendStroke(AnnotationStroke(
                    tool: .text,
                    start: self.mapViewPointToImage(end),
                    end: self.mapViewPointToImage(end),
                    text: text,
                    color: self.strokeColor,
                    lineWidth: self.lineWidth
                ))
            }
            return
        }
        appendStroke(AnnotationStroke(
            tool: activeTool,
            start: imageStart,
            end: imageEnd,
            text: "",
            color: strokeColor,
            lineWidth: lineWidth
        ))
    }

    private func applyCrop(from start: CGPoint, to end: CGPoint) {
        guard let sourceImage = baseImage else { return }
        let region = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        guard region.width > 4, region.height > 4 else { return }

        let imageRegion = NSRect(
            x: mapViewPointToImage(region.origin).x,
            y: mapViewPointToImage(region.origin).y,
            width: mapViewPointToImage(CGPoint(x: region.maxX, y: region.maxY)).x - mapViewPointToImage(region.origin).x,
            height: mapViewPointToImage(CGPoint(x: region.maxX, y: region.maxY)).y - mapViewPointToImage(region.origin).y
        ).integral

        guard let cg = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scaleX = CGFloat(cg.width) / sourceImage.size.width
        let scaleY = CGFloat(cg.height) / sourceImage.size.height
        // Both `imageRegion` and CGImage pixels use a top-left origin.
        let pixelCrop = CGRect(
            x: imageRegion.origin.x * scaleX,
            y: imageRegion.origin.y * scaleY,
            width: imageRegion.width * scaleX,
            height: imageRegion.height * scaleY
        ).integral
        guard let cropped = cg.cropping(to: pixelCrop) else { return }

        cropUndoStack.append(currentCropSnapshot())
        cropRedoStack = []
        redoStrokes = []

        let croppedImage = NSImage(cgImage: cropped, size: NSSize(
            width: imageRegion.width,
            height: imageRegion.height
        ))
        self.baseImage = croppedImage
        strokes = []
        redactionRegions = []
        previewRedactions = []
        rebuildComposite()
        needsDisplay = true
        onStrokesChanged?()
    }

    private func currentCropSnapshot() -> (image: NSImage, strokes: [AnnotationStroke], redactions: [CGRect]) {
        (image: baseImage?.copy() as? NSImage ?? baseImage ?? NSImage(), strokes: strokes, redactions: redactionRegions)
    }

    private func promptForText(at point: CGPoint, completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Add Text"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            completion(field.stringValue)
        }
    }

    func rebuildComposite() {
        guard let baseImage else {
            renderedImage = nil
            return
        }
        let size = baseImage.size
        let image = NSImage(size: size)
        // Strokes and redactions are stored with a top-left origin (the flipped view's space),
        // so composite in a flipped context too; otherwise they land vertically mirrored.
        image.lockFocusFlipped(true)
        baseImage.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        let canvas = NSRect(origin: .zero, size: size)
        for region in redactionRegions {
            AnnotationDrawing.pixelate(
                from: CGPoint(x: region.minX, y: region.minY),
                to: CGPoint(x: region.maxX, y: region.maxY),
                in: canvas,
                sourceImage: baseImage
            )
        }
        for stroke in strokes {
            AnnotationDrawing.draw(stroke: stroke, in: canvas, sourceImage: baseImage)
        }
        image.unlockFocus()
        renderedImage = image
    }
}
