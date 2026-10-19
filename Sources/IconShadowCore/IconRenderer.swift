import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import QuartzCore
import CoreImage

public enum IconError: LocalizedError {
    case invalidImage, emptyImage, oversizedImage, renderingFailed, exportFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidImage: String(localized: "Choose a supported image or macOS application.")
        case .emptyImage: String(localized: "This image is fully transparent.")
        case .oversizedImage: String(localized: "Use an image no larger than 8192 × 8192 pixels.")
        case .renderingFailed: String(localized: "Could not create the icon canvas.")
        case .exportFailed(let message): String(format: String(localized: "Export failed: %@"), message)
        }
    }
}

public struct IconSettings: Equatable, Sendable {
    /// Percentage of the 1024 canvas occupied by the longest artwork edge.
    public var scale: Double = 80.46875 // 824 / 1024
    public var horizontal: Double = 0
    /// Positive values move artwork down in screen coordinates.
    public var vertical: Double = 0
    public var shadowOpacity: Double = 0.25
    public var shadowBlur: Double = 15
    public var shadowOffset: Double = 8
    public var fitToMask = true
    public var trimTransparentEdges = true
    public init() {}
}

public struct IconSource: Sendable {
    public let image: CGImage
    /// Core Graphics coordinates, with origin at the bottom left.
    public let contentBounds: CGRect
    /// Main artwork at alpha > 50%; excludes faint exterior shadows when fitting.
    /// Fully translucent artwork falls back to the visible-alpha bounds.
    public let artworkBounds: CGRect
    public var width: Int { image.width }
    public var height: Int { image.height }
    public init(image: CGImage) throws {
        guard image.width <= 8192, image.height <= 8192 else { throw IconError.oversizedImage }
        self.image = image
        self.contentBounds = try IconRenderer.alphaBounds(image)
        do {
            self.artworkBounds = try IconRenderer.alphaBounds(image, threshold: 128)
        } catch IconError.emptyImage {
            self.artworkBounds = self.contentBounds
        }
    }
}

public enum IconRenderer {
    public static let canvasSize = 1024
    public static var supportedImageTypes: [UTType] {
        (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).compactMap { UTType($0) }
    }

    public static func load(_ url: URL) throws -> IconSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
            let type = CGImageSourceGetType(source) as String? else { throw IconError.invalidImage }
        // ICNS contains multiple representations. Explicitly select the largest.
        let count = CGImageSourceGetCount(source)
        var bestIndex = 0, bestArea = 0
        // Only icon containers and multipage TIFF use largest-representation selection.
        // Animated GIF/WebP/APNG/HEIF inputs use their first frame.
        let candidates = ["com.apple.icns", "com.microsoft.ico", "public.tiff"].contains(type) ? count : min(count, 1)
        guard candidates > 0 else { throw IconError.invalidImage }
        for index in 0..<candidates {
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
            guard w <= 8192, h <= 8192 else { throw IconError.oversizedImage }
            if w * h > bestArea { bestIndex = index; bestArea = w * h }
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 8192]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, bestIndex, options as CFDictionary)
        else { throw IconError.invalidImage }
        return try IconSource(image: image)
    }

    static func context(_ size: Int) throws -> CGContext {
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw IconError.renderingFailed }
        context.interpolationQuality = .high
        return context
    }

    public static func alphaBounds(_ image: CGImage, threshold: UInt8 = 2) throws -> CGRect {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let bounds: CGRect? = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var minX = w, minY = h, maxX = -1, maxY = -1
            for y in 0..<h { for x in 0..<w where bytes[(y * w + x) * 4 + 3] > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }}
            guard maxX >= minX else { return .null }
            // Bitmap rows run top to bottom; the renderer uses bottom-left coordinates.
            return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        guard let bounds else { throw IconError.renderingFailed }
        guard !bounds.isNull else { throw IconError.emptyImage }
        return bounds
    }

    /// Native continuous corners; the radius is a measured approximation of the system mask.
    public static func maskImage(in rect: CGRect, size: Int = 1024, cornerRadiusFraction: Double = 54.0 / 208) throws -> CGImage {
        let ctx = try context(size)
        let ratio = Double(size) / 1024
        ctx.scaleBy(x: ratio, y: ratio)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: rect.size)
        layer.backgroundColor = CGColor(gray: 1, alpha: 1)
        layer.cornerRadius = rect.width * cornerRadiusFraction
        layer.cornerCurve = .continuous
        layer.render(in: ctx)
        guard let image = ctx.makeImage() else { throw IconError.renderingFailed }
        return image
    }

    // CIContext is thread-safe and reused across preview/export jobs.
    private static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    public static func render(_ source: IconSource, settings: IconSettings, size: Int = 1024) throws -> CGImage {
        guard size > 0, size <= 4096 else { throw IconError.renderingFailed }
        let ctx = try context(size)
        let ratio = Double(size) / 1024
        ctx.scaleBy(x: ratio, y: ratio)
        let bounds = settings.trimTransparentEdges ? source.artworkBounds :
            CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let edge = 1024 * settings.scale / 100
        let factor = edge / max(bounds.width, bounds.height)
        let content = CGRect(x: 512 + settings.horizontal - bounds.width * factor / 2,
                             y: 512 - settings.vertical - bounds.height * factor / 2,
                             width: bounds.width * factor, height: bounds.height * factor)
        let artwork = CGRect(x: content.minX - bounds.minX * factor,
                             y: content.minY - bounds.minY * factor,
                             width: Double(source.width) * factor, height: Double(source.height) * factor)
        // Clip only the artwork, then cast a shadow from its final alpha (including holes).
        let layerContext = try context(size)
        layerContext.scaleBy(x: ratio, y: ratio)
        if settings.fitToMask {
            let tile = CGRect(x: 512 + settings.horizontal - edge / 2,
                              y: 512 - settings.vertical - edge / 2, width: edge, height: edge)
            let nativeMask = try maskImage(in: tile, size: size)
            layerContext.clip(to: CGRect(x: 0, y: 0, width: 1024, height: 1024), mask: nativeMask)
        }
        layerContext.draw(source.image, in: artwork)
        guard let layer = layerContext.makeImage() else { throw IconError.renderingFailed }
        if settings.shadowOpacity > 0 {
            let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
            var shadow = CIImage(cgImage: layer).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: settings.shadowOpacity)])
            if settings.shadowBlur > 0 {
                shadow = shadow.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: settings.shadowBlur * ratio])
            }
            shadow = shadow.transformed(by: CGAffineTransform(translationX: 0, y: -settings.shadowOffset * ratio))
            guard let shadowImage = ciContext.createCGImage(shadow, from: CGRect(x: 0, y: 0, width: size, height: size))
            else { throw IconError.renderingFailed }
            ctx.draw(shadowImage, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        ctx.draw(layer, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        guard let result = ctx.makeImage() else { throw IconError.renderingFailed }
        return result
    }

    public static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw IconError.exportFailed(String(localized: "Could not encode PNG.")) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw IconError.exportFailed(String(localized: "PNG encoding failed.")) }
        return data as Data
    }

    public static func resized(_ image: CGImage, to size: Int) throws -> CGImage {
        let ctx = try context(size)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let result = ctx.makeImage() else { throw IconError.renderingFailed }
        return result
    }
}
