import AppKit
import UniformTypeIdentifiers

/// Uses Icon Services for applications and AppKit's native vector image decoders.
/// Does not launch or modify the imported application.
@MainActor
public enum NativeIconImporter {
    public static var vectorTypes: [UTType] {
        [.svg, .pdf].filter { NSImage.imageTypes.contains($0.identifier) }
    }

    public static func handles(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app" ||
            UTType(filenameExtension: url.pathExtension.lowercased()).map { vectorTypes.contains($0) } == true
    }

    public static func load(_ url: URL) throws -> IconSource {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let image: NSImage
        let isApplication = url.pathExtension.lowercased() == "app"
        if isApplication {
            guard let bundle = Bundle(url: url),
                  bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL",
                  let executable = bundle.executableURL,
                  FileManager.default.fileExists(atPath: executable.path) else { throw IconError.invalidImage }
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            guard handles(url), let decoded = NSImage(contentsOf: url) else { throw IconError.invalidImage }
            image = decoded
        }
        let naturalSize = isApplication ? NSSize(width: 1024, height: 1024) : image.size
        guard naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.width > 0, naturalSize.height > 0 else { throw IconError.invalidImage }
        let factor = 1024 / max(naturalSize.width, naturalSize.height)
        let width = max(1, Int((naturalSize.width * factor).rounded()))
        let height = max(1, Int((naturalSize.height * factor).rounded()))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw IconError.renderingFailed }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        graphics.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                   from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        guard let cgImage = bitmap.cgImage else { throw IconError.renderingFailed }
        return try IconSource(image: cgImage)
    }
}
