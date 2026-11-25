import Foundation
import CoreGraphics

public enum IconExporter {
    private static let icnsSlots: [(type: String, points: Int, scale: Int)] = [
        ("icp4", 16, 1),
        ("ic11", 16, 2),
        ("icp5", 32, 1),
        ("ic12", 32, 2),
        ("ic07", 128, 1),
        ("ic13", 128, 2),
        ("ic08", 256, 1),
        ("ic14", 256, 2),
        ("ic09", 512, 1),
        ("ic10", 512, 2),
    ]

    public static func exportPNG(_ image: CGImage, to url: URL) throws {
        try write(IconRenderer.pngData(image), to: url)
    }

    public static func icnsData(_ image: CGImage) throws -> Data {
        var resizedByPixels: [Int: CGImage] = [:]
        if image.width == 1024, image.height == 1024 {
            resizedByPixels[1024] = image
        }
        var body = Data()
        for slot in icnsSlots {
            let pixels = slot.points * slot.scale
            let sized: CGImage
            if let cached = resizedByPixels[pixels] {
                sized = cached
            } else {
                sized = try IconRenderer.resized(image, to: pixels)
                resizedByPixels[pixels] = sized
            }
            let png = try IconRenderer.pngData(sized, dpi: slot.scale == 2 ? 144 : 72)
            var chunkLength = UInt32(8 + png.count).bigEndian
            body.append(contentsOf: slot.type.utf8)
            withUnsafeBytes(of: &chunkLength) { body.append(contentsOf: $0) }
            body.append(png)
        }
        var output = Data("icns".utf8)
        var totalLength = UInt32(8 + body.count).bigEndian
        withUnsafeBytes(of: &totalLength) { output.append(contentsOf: $0) }
        output.append(body)
        return output
    }

    public static func exportICNS(_ image: CGImage, to url: URL) throws {
        try write(icnsData(image), to: url)
    }

    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // In App Sandbox, NSSavePanel authorizes the target file URL itself;
            // volumes without /.TemporaryItems reject sibling atomic temp files.
            try data.write(to: url)
        }
    }
}
