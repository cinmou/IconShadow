import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: make-dmg-background.swift output.png version\n", stderr)
    exit(1)
}
// Match MicaGo: 660 × 420 points, with an explicit 2× Retina bitmap.
let width = 660, height = 420
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2,
    pixelsHigh: height * 2, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
// NSGraphicsContext already maps rep.size points to the 2× bitmap pixels.
NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.98, blue: 0.99, alpha: 1),
           ending: NSColor(srgbRed: 0.88, green: 0.93, blue: 0.97, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)
func centered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let size = string.size()
    string.draw(at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: y))
}
let ink = NSColor(srgbRed: 0.20, green: 0.29, blue: 0.38, alpha: 1)
centered("Icon Shadow", y: 350, font: .systemFont(ofSize: 28, weight: .semibold), color: ink)
centered("\(CommandLine.arguments[2]) · Drag to Applications · 拖移至应用程序", y: 319, font: .systemFont(ofSize: 13), color: ink.withAlphaComponent(0.65))
let arrow = NSBezierPath()
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 286, y: 204)); arrow.line(to: NSPoint(x: 374, y: 204))
arrow.move(to: NSPoint(x: 358, y: 219)); arrow.line(to: NSPoint(x: 374, y: 204)); arrow.line(to: NSPoint(x: 358, y: 189))
ink.withAlphaComponent(0.45).setStroke(); arrow.stroke()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
