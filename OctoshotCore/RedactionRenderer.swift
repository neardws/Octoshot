import AppKit
import CoreImage

public enum RedactionError: LocalizedError {
    case unavailableSource
    case invalidRegion
    case filterFailed

    public var errorDescription: String? {
        switch self {
        case .unavailableSource: return "Redaction failed: source pixels are unavailable. Export was blocked."
        case .invalidRegion: return "Redaction failed: the region is outside the source image. Export was blocked."
        case .filterFailed: return "Redaction rendering failed. Export was blocked to protect unredacted content."
        }
    }
}

public final class RedactionRenderer: @unchecked Sendable {
    public enum Kind: String { case blur, pixelate }

    private final class Patch {
        let image: CGImage

        init(image: CGImage) {
            self.image = image
        }
    }

    public static let shared = RedactionRenderer()
    private let context: CIContext
    private let cache = NSCache<NSString, Patch>()
    private let cacheLock = NSLock()
    private var cachedSource: CGImage?
    private let render: (@Sendable (CIImage, CGRect) -> CGImage?)?

    public init(context: CIContext = CIContext(), render: (@Sendable (CIImage, CGRect) -> CGImage?)? = nil) {
        self.context = context
        self.render = render
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 256
    }

    public func invalidate() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeAllObjects()
        cachedSource = nil
    }

    /// The part of `region` that lies on the canvas, or nil when none of it does.
    /// Callers draw the patch into this rectangle, so a box dragged past the edge still redacts what it covers.
    public static func clippedRegion(_ region: CGRect, canvasSize: CGSize) -> CGRect? {
        guard canvasSize.width.isFinite, canvasSize.height.isFinite,
              canvasSize.width > 0, canvasSize.height > 0,
              region.origin.x.isFinite, region.origin.y.isFinite,
              region.width.isFinite, region.height.isFinite else { return nil }
        let clipped = region.standardized.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }

    /// Filters the source pixels under `region`, clipped to the canvas.
    /// Throws when nothing of the region is on the canvas, so export is blocked rather than left unredacted.
    public func patch(source: CGImage, region: CGRect, canvasSize: CGSize,
                      kind: Kind, topLeftOrigin: Bool, useCache: Bool = true) throws -> CGImage {
        guard let region = Self.clippedRegion(region, canvasSize: canvasSize) else {
            throw RedactionError.invalidRegion
        }
        let scaleX = CGFloat(source.width) / canvasSize.width
        let scaleY = CGFloat(source.height) / canvasSize.height
        // `integral` rounds outward, which can step one pixel past the edge; clip again in pixels.
        let crop = CGRect(x: region.minX * scaleX,
                          y: topLeftOrigin ? region.minY * scaleY : CGFloat(source.height) - region.maxY * scaleY,
                          width: region.width * scaleX, height: region.height * scaleY).integral
            .intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard !crop.isNull, crop.width >= 1, crop.height >= 1 else {
            throw RedactionError.invalidRegion
        }
        let parameter = kind == .blur ? 14 : 12
        let key = "\(ObjectIdentifier(source))-\(crop)-\(kind.rawValue)-\(parameter)-\(scaleX)-\(scaleY)" as NSString
        if useCache {
            cacheLock.lock()
            if cachedSource !== source {
                cache.removeAllObjects()
                cachedSource = source
            }
            let cached = cache.object(forKey: key)
            cacheLock.unlock()
            if let cached { return cached.image }
        }
        guard let cropped = source.cropping(to: crop) else { throw RedactionError.invalidRegion }
        let input = CIImage(cgImage: cropped)
        guard let filter = CIFilter(name: kind == .blur ? "CIGaussianBlur" : "CIPixellate") else {
            throw RedactionError.filterFailed
        }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(parameter, forKey: kind == .blur ? kCIInputRadiusKey : kCIInputScaleKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { throw RedactionError.filterFailed }
        let result: CGImage?
        if let render {
            result = render(output, input.extent)
        } else {
            let outputSpace = source.colorSpace?.model == .rgb
                ? source.colorSpace : CGColorSpace(name: CGColorSpace.sRGB)
            result = context.createCGImage(output, from: input.extent, format: .RGBA8,
                                           colorSpace: outputSpace, deferred: false)
        }
        guard let result else { throw RedactionError.filterFailed }
        if useCache {
            cacheLock.lock()
            if cachedSource === source {
                cache.setObject(Patch(image: result), forKey: key,
                                cost: result.bytesPerRow * result.height)
            }
            cacheLock.unlock()
        }
        return result
    }
}
