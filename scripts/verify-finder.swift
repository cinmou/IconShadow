import AppKit
import Foundation

// Operates only on a disposable app in build/validation, never an installed app.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let exported = root.appendingPathComponent(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/validation/flat-icon.icns")
let fixture = root.appendingPathComponent("build/validation/Icon Acceptance.app")
let fm = FileManager.default
if !fm.fileExists(atPath: fixture.path) {
    try fm.createDirectory(at: fixture.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleName": "Icon Acceptance", "CFBundleIdentifier": "dev.cinmou.IconShadow.Acceptance", "CFBundlePackageType": "APPL", "CFBundleExecutable": "Acceptance"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: fixture.appendingPathComponent("Contents/Info.plist"))
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: fixture.appendingPathComponent("Contents/MacOS/Acceptance"))
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.appendingPathComponent("Contents/MacOS/Acceptance").path)
}
guard let image = NSImage(contentsOf: exported) else { fatalError("AppKit could not decode ICNS") }
guard NSWorkspace.shared.setIcon(image, forFile: fixture.path, options: []) else { fatalError("Finder custom icon assignment failed") }
// URLResourceValues.customIcon may be nil even when Finder stores an Icon\r resource.
let fork = fixture.appendingPathComponent("Icon\r/..namedfork/rsrc")
let persisted = try Data(contentsOf: fork)
guard !persisted.isEmpty else { fatalError("Custom icon resource was not persisted") }
let native = NSWorkspace.shared.icon(forFile: fixture.path)
var rect = CGRect(x: 0, y: 0, width: 256, height: 256)
guard let cg = native.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { fatalError("Icon services cannot render the result") }
let rep = NSBitmapImageRep(cgImage: cg)
try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("build/validation/finder-custom-icon.png"))
print("PASS: AppKit decoded the UI export; NSWorkspace applied it to the disposable app; a custom icon resource persisted; Icon Services rendered it.")
