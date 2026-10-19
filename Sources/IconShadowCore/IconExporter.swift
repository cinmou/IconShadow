import Foundation
import CoreGraphics

public enum IconExporter {
    public static func exportPNG(_ image: CGImage, to url: URL) throws {
        try IconRenderer.pngData(image).write(to: url, options: .atomic)
    }

    public static func exportICNS(_ image: CGImage, to url: URL) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("IconShadow-\(UUID().uuidString)")
        let iconset = root.appendingPathComponent("Icon.iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                let sized = try IconRenderer.resized(image, to: points * scale)
                try exportPNG(sized, to: iconset.appendingPathComponent(name))
            }
        }
        let output = root.appendingPathComponent("Icon.icns")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        let error = Pipe()
        process.standardError = error
        try process.run()
        let diagnostic = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw IconError.exportFailed(String(data: diagnostic, encoding: .utf8) ?? String(localized: "iconutil failed."))
        }
        try Data(contentsOf: output).write(to: url, options: .atomic)
    }
}
