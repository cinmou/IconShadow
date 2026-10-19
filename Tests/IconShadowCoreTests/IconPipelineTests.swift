import XCTest
import CoreGraphics
import ImageIO
import AppKit
@testable import IconShadowCore

final class IconPipelineTests: XCTestCase {
    func fixture() throws -> IconSource {
        let ctx = try IconRenderer.context(1024)
        // An asymmetrically padded, nonsquare image with a transparent hole.
        ctx.setFillColor(CGColor(red: 0.18, green: 0.48, blue: 0.94, alpha: 1))
        ctx.fill(CGRect(x: 80, y: 300, width: 600, height: 400))
        ctx.clear(CGRect(x: 330, y: 450, width: 100, height: 100))
        return try IconSource(image: XCTUnwrap(ctx.makeImage()))
    }

    func testTrimPreservesAspectRatioAndCoordinates() throws {
        let source = try fixture()
        XCTAssertEqual(source.contentBounds, CGRect(x: 80, y: 300, width: 600, height: 400))
        var settings = IconSettings(); settings.shadowOpacity = 0; settings.fitToMask = false
        let output = try IconRenderer.render(source, settings: settings)
        let bounds = try IconRenderer.alphaBounds(output)
        XCTAssertEqual(bounds.midX, 512, accuracy: 1)
        XCTAssertEqual(bounds.midY, 512, accuracy: 1)
        XCTAssertEqual(bounds.width, 824, accuracy: 2)
        XCTAssertEqual(bounds.width / bounds.height, 1.5, accuracy: 0.01)
        settings.horizontal = 30; settings.vertical = 50
        let moved = try IconRenderer.alphaBounds(IconRenderer.render(source, settings: settings))
        XCTAssertEqual(moved.midX, 542, accuracy: 1)
        XCTAssertEqual(moved.midY, 462, accuracy: 1)
    }

    func testExistingShadowDoesNotShrinkOrShiftArtwork() throws {
        let ctx = try IconRenderer.context(1024)
        // A finished icon: 824 px body with a wider, downward-offset faint shadow.
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.2))
        ctx.fill(CGRect(x: 74, y: 66, width: 876, height: 876))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 824))
        let source = try IconSource(image: XCTUnwrap(ctx.makeImage()))
        XCTAssertEqual(source.contentBounds.width, 876)
        XCTAssertEqual(source.artworkBounds, CGRect(x: 100, y: 100, width: 824, height: 824))
        let output = try IconRenderer.render(source, settings: IconSettings())
        let body = try IconRenderer.alphaBounds(output, threshold: 128)
        XCTAssertEqual(body.width, 824, accuracy: 1)
        XCTAssertEqual(body.height, 824, accuracy: 1)
        XCTAssertEqual(body.midX, 512, accuracy: 1)
        XCTAssertEqual(body.midY, 512, accuracy: 1)
    }

    func testFullyTranslucentArtworkStillFits() throws {
        let ctx = try IconRenderer.context(1024)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.3))
        ctx.fill(CGRect(x: 200, y: 300, width: 400, height: 300))
        let source = try IconSource(image: XCTUnwrap(ctx.makeImage()))
        XCTAssertEqual(source.artworkBounds, source.contentBounds)
        var settings = IconSettings(); settings.shadowOpacity = 0; settings.fitToMask = false
        let bounds = try IconRenderer.alphaBounds(IconRenderer.render(source, settings: settings))
        XCTAssertEqual(bounds.width, 824, accuracy: 2)
    }

    func testTrimOffRetainsPadding() throws {
        var settings = IconSettings(); settings.shadowOpacity = 0; settings.fitToMask = false; settings.trimTransparentEdges = false
        let output = try IconRenderer.render(fixture(), settings: settings)
        let bounds = try IconRenderer.alphaBounds(output)
        XCTAssertEqual(bounds.width, 600 * 824 / 1024.0, accuracy: 2)
    }

    func testShadowFallsDownAndMaskClipsCorners() throws {
        let ctx = try IconRenderer.context(1024)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let source = try IconSource(image: XCTUnwrap(ctx.makeImage()))
        var settings = IconSettings(); settings.fitToMask = false; settings.shadowBlur = 0; settings.shadowOffset = 30; settings.shadowOpacity = 0.5
        let out = try IconRenderer.render(source, settings: settings)
        let bounds = try IconRenderer.alphaBounds(out)
        XCTAssertEqual(bounds.minY, 70, accuracy: 1)
        XCTAssertEqual(bounds.maxY, 924, accuracy: 1)
        settings.fitToMask = true; settings.shadowOpacity = 0
        let masked = try IconRenderer.render(source, settings: settings)
        let bytes = try XCTUnwrap(masked.dataProvider?.data) as Data
        // Top-left corner of the artwork tile must become transparent.
        XCTAssertEqual(bytes[(100 * masked.bytesPerRow) + 110 * 4 + 3], 0)
        XCTAssertEqual(bytes[(512 * masked.bytesPerRow) + 512 * 4 + 3], 255)
    }

    func testFileDropURLDecoding() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("IconShadow-drop-\(UUID().uuidString).png")
        try IconExporter.exportPNG(fixture().image, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = NSItemProvider(contentsOf: file)!
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier("public.file-url"))
        let decoded = expectation(description: "Finder file URL representation")
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            XCTAssertNil(error)
            XCTAssertEqual(url?.standardizedFileURL, file.standardizedFileURL)
            decoded.fulfill()
        }
        wait(for: [decoded], timeout: 5)
    }

    func testRejectsEmptyAndInvalidInput() throws {
        XCTAssertThrowsError(try IconSource(image: XCTUnwrap(IconRenderer.context(32).makeImage())))
        XCTAssertThrowsError(try IconRenderer.load(URL(fileURLWithPath: "/tmp/missing.png")))
        XCTAssertThrowsError(try IconRenderer.render(fixture(), settings: IconSettings(), size: 0))
    }

    func testFlatIconAndInitialShadowComparison() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/validation")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ctx = try IconRenderer.context(1024)
        let rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        ctx.clip(to: rect, mask: try IconRenderer.maskImage(in: rect))
        let colors = [CGColor(red: 0.35, green: 0.68, blue: 0.98, alpha: 1),
                      CGColor(red: 0.18, green: 0.29, blue: 0.82, alpha: 1)]
        let gradient = try XCTUnwrap(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1]))
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
        ctx.fill(CGRect(x: 260, y: 300, width: 160, height: 440))
        ctx.fill(CGRect(x: 460, y: 300, width: 300, height: 160))
        let input = try XCTUnwrap(ctx.makeImage())
        let png = root.appendingPathComponent("flat-icon.png")
        try IconExporter.exportPNG(input, to: png)
        let source = try IconRenderer.load(png)
        try IconExporter.exportPNG(IconRenderer.render(source, settings: IconSettings()), to: root.appendingPathComponent("flat-icon-default.png"))
        var initial = IconSettings()
        initial.shadowOpacity = 0.35; initial.shadowBlur = 12; initial.shadowOffset = 6
        try IconExporter.exportPNG(IconRenderer.render(source, settings: initial), to: root.appendingPathComponent("flat-icon-initial.png"))
        try IconExporter.exportICNS(IconRenderer.render(source, settings: IconSettings()), to: root.appendingPathComponent("flat-icon.icns"))
    }

    func testPNGAndICNSRoundTripWithRealSamples() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/validation")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("padded-artwork.png")
        try IconExporter.exportPNG(fixture().image, to: input)
        let decoded = try IconRenderer.load(input)
        XCTAssertEqual(decoded.contentBounds, try fixture().contentBounds)
        var report = "Host: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        let samples = [input.path,
            "/System/Applications/Calculator.app/Contents/Resources/AppIcon.icns",
            "/System/Applications/Notes.app/Contents/Resources/AppIcon.icns",
            "/System/Applications/Preview.app/Contents/Resources/AppIcon.icns"]
        for (index, path) in samples.enumerated() {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let source = try IconRenderer.load(url)
            let output = try IconRenderer.render(source, settings: IconSettings())
            let name = index == 0 ? "artwork" : url.pathComponents.dropLast(3).last!.replacingOccurrences(of: ".app", with: "")
            let png = root.appendingPathComponent("\(index)-\(name).png")
            let icns = root.appendingPathComponent("\(index)-\(name).icns")
            try IconExporter.exportPNG(output, to: png)
            try IconExporter.exportICNS(output, to: icns)
            let back = try IconRenderer.load(icns)
            XCTAssertEqual(back.width, 1024); XCTAssertEqual(back.height, 1024)
            let encoded = try XCTUnwrap(CGImageSourceCreateWithURL(icns as CFURL, nil))
            var dimensions = Set<Int>()
            for i in 0..<CGImageSourceGetCount(encoded) {
                let rep = try XCTUnwrap(CGImageSourceCreateImageAtIndex(encoded, i, nil))
                dimensions.insert(rep.width)
            }
            XCTAssertTrue(Set([16, 32, 64, 128, 256, 512, 1024]).isSubset(of: dimensions))
            let roundTripBounds = try IconRenderer.alphaBounds(back.image)
            XCTAssertEqual(roundTripBounds, try IconRenderer.alphaBounds(output))
            let props = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
            let pngRep = try XCTUnwrap(CGImageSourceCreateImageAtIndex(props, 0, nil))
            XCTAssertEqual(pngRep.width, 1024); XCTAssertEqual(pngRep.height, 1024)
            report += "\(path): input \(source.width)x\(source.height), alpha>2 \(source.contentBounds), body>128 \(try IconRenderer.alphaBounds(source.image, threshold: 128)); output \(roundTripBounds); ICNS sizes \(dimensions.sorted())\n"
        }
        try report.write(to: root.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }
}
