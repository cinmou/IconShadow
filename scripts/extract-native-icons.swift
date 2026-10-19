import AppKit
import ImageIO
import UniformTypeIdentifiers
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/validation")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for name in ["Calculator", "Notes", "Preview", "App Store"] {
let image = NSWorkspace.shared.icon(forFile: "/System/Applications/\(name).app")
image.size = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("native-\(name).png"))

}
