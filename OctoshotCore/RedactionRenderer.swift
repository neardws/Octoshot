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

    public func patch(source: CGImage, region: CGRect, canvasSize: CGSize,
                      kind: Kind, topLeftOrigin: Bool, useCache: Bool = true) throws -> CGImage {
        guard canvasSize.width.isFinite, canvasSize.height.isFinite,
              canvasSize.width > 0, canvasSize.height > 0,
              region.origin.x.isFinite, region.origin.y.isFinite,
              region.width.isFinite, region.height.isFinite,
              region.width > 0, region.height > 0 else { throw RedactionError.invalidRegion }
        let scaleX = CGFloat(source.width) / canvasSize.width
        let scaleY = CGFloat(source.height) / canvasSize.height
        let crop = CGRect(x: region.minX * scaleX,
                          y: topLeftOrigin ? region.minY * scaleY : CGFloat(source.height) - region.maxY * scaleY,
                          width: region.width * scaleX, height: region.height * scaleY).integral
        guard CGRect(x: 0, y: 0, width: source.width, height: source.height).contains(crop) else {
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
            result = context.createCGImage(output, from: input.extent)
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
