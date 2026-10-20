import AppKit
import OctoshotCore

struct ScreenColorInfo: Equatable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int

    var hexRGB: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var rgbText: String {
        "rgb(\(red), \(green), \(blue))"
    }

    var pasteboardText: String { hexRGB }
}

enum ScreenColorSampler {
    /// Reads the pixel at an AppKit global point (bottom-left origin) from a still image of
    /// the display whose frame is `screenFrame`.
    static func sample(at cocoaGlobal: NSPoint, screenFrame: CGRect, in image: CGImage) -> ScreenColorInfo? {
        guard screenFrame.contains(cocoaGlobal) else { return nil }
        let pixel = DisplayGeometry.pixelRect(
            cocoaGlobal: CGRect(origin: cocoaGlobal, size: .zero),
            screenFrame: screenFrame,
            imagePixelSize: CGSize(width: image.width, height: image.height)
        )
        let x = min(max(Int(pixel.minX), 0), image.width - 1)
        let y = min(max(Int(pixel.minY), 0), image.height - 1)
        guard let cgPixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgPixel)
        guard let color = rep.colorAt(x: 0, y: 0) else { return nil }
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return ScreenColorInfo(
            red: Int(round(r * 255)),
            green: Int(round(g * 255)),
            blue: Int(round(b * 255)),
            alpha: Int(round(a * 255))
        )
    }
}
