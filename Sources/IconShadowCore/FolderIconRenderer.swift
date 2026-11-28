import Foundation
import AppKit
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers

public enum FolderStyle: String, CaseIterable, Sendable {
    case appLogo
    case embossed
}

public struct FolderRGB: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }
}

public enum FolderColorPreset: String, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case skyBlue
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case graphite
    case custom

    public var id: String { rawValue }

    /// Calibrated sRGB front-pocket midtone aligned with macOS Appearance folder palette.
    public var targetRGB: FolderRGB? {
        switch self {
        case .systemDefault, .custom: nil
        case .skyBlue: FolderRGB(red: 0.37, green: 0.76, blue: 0.95)   // Classic Sky Blue (#5EC2F2)
        case .blue: FolderRGB(red: 0.22, green: 0.56, blue: 0.96)      // System Blue (#388FF5)
        case .purple: FolderRGB(red: 0.72, green: 0.45, blue: 0.90)    // System Purple (#B873E6)
        case .pink: FolderRGB(red: 0.96, green: 0.42, blue: 0.62)      // System Pink (#F56B9E)
        case .red: FolderRGB(red: 0.95, green: 0.39, blue: 0.36)       // System Red (#F2635C)
        case .orange: FolderRGB(red: 0.97, green: 0.64, blue: 0.27)    // System Orange (#F7A345)
        case .yellow: FolderRGB(red: 0.97, green: 0.82, blue: 0.27)    // System Yellow (#F7D145)
        case .green: FolderRGB(red: 0.36, green: 0.80, blue: 0.45)     // System Green (#5CCC73)
        case .graphite: FolderRGB(red: 0.64, green: 0.65, blue: 0.67)  // System Graphite (#A3A6AB)
        }
    }
}

public struct FolderSettings: Equatable, Sendable {
    public var style: FolderStyle = .appLogo
    public var colorPreset: FolderColorPreset = .systemDefault
    public var customColor = FolderRGB(red: 0.16, green: 0.75, blue: 0.72)
    /// Show the white paper sheet peeking out from behind the front pocket (macOS non-empty folder style).
    public var hasFiles: Bool = false
    /// Percentage of the 1024 canvas occupied by the artwork's longest edge.
    public var scale: Double = 38
    public var horizontal: Double = 0
    /// Positive values move artwork down in screen coordinates relative to the folder's front-pocket optical center.
    public var vertical: Double = 0
    /// Embossed cavity & bevel intensity (0...1.5, 1.0 matches native macOS folders).
    public var embossDepth: Double = 1.0
    /// Embossed silhouette extraction / shadow-trim threshold (0...1, default 0.40).
    /// Higher values cut away more background gradient, texture, or exterior drop shadows.
    public var embossThreshold: Double = 0.40
    /// Contact shadow opacity for App Logo mode (0...0.6).
    public var badgeShadowOpacity: Double = 0.20
    /// Clip full-bleed square artwork to macOS continuous corners in App Logo mode.
    public var roundLogoCorners: Bool = false
    public var trimTransparentEdges: Bool = true

    public init() {}

    public func resolvedTargetRGB() -> FolderRGB? {
        switch colorPreset {
        case .systemDefault: nil
        case .custom: customColor
        default: colorPreset.targetRGB
        }
    }
}

public struct FolderSymbolPreset: Identifiable, Hashable, Sendable {
    public let name: String
    public let keywords: String
    public var id: String { name }

    public init(_ name: String, _ keywords: String) {
        self.name = name
        self.keywords = keywords
    }
}

public struct FolderBaseMetrics: Sendable {
    /// Native 1024x1024 folder RGBA pixels (premultipliedLast, sRGB) in top-left row order.
    let pixels: [UInt8]
    public let baseImage: CGImage
    /// Opaque body mask covering the entire folder (back flap + front pocket) for clipping internal layers.
    let folderBodyMask: CGImage
    /// Front-pocket alpha mask (opaque only within the front pocket below pocketTopY).
    let frontPocketMask: CGImage
    /// Horizontal opaque bounds of the folder body in 1024 coordinates (e.g. 42...981).
    let bodyMinX: Double
    let bodyMaxX: Double
    /// Top crease Y of the front pocket in top-left 1024 coordinates (e.g. ~270 on macOS 26/27, ~258 on macOS 14/15).
    public let pocketTopY: Double
    /// Bottom edge Y of the front pocket in top-left 1024 coordinates (e.g. ~888 on macOS 26/27, ~882 on macOS 14/15).
    public let pocketBottomY: Double
    /// Optical vertical center for folder emblems in top-left 1024 coordinates (~580 on macOS 26/27, ~551 on macOS 14/15).
    public let opticalCenterY: Double
    /// Reference front-pocket perceived luminance used for luminance-preserving recoloring.
    let referenceLuminance: Double
}

public enum FolderIconRenderer {
    public static let curatedSymbols: [FolderSymbolPreset] = [
        // Development & Tools
        FolderSymbolPreset("hammer.fill", "dev developer build tools 开发 工具 构建"),
        FolderSymbolPreset("terminal.fill", "code cli shell script 终端 代码 脚本"),
        FolderSymbolPreset("chevron.left.forwardslash.chevron.right", "code source programming 源码 编程"),
        FolderSymbolPreset("cpu.fill", "hardware chip system ai 硬件 芯片 系统"),
        FolderSymbolPreset("gearshape.fill", "settings config system 设置 配置"),
        FolderSymbolPreset("wrench.and.screwdriver.fill", "utilities fix repair 实用 维护"),
        FolderSymbolPreset("shippingbox.fill", "package build release bundle 打包 发布"),
        FolderSymbolPreset("swift", "swift apple xcode ios macos"),
        // Work & Documents
        FolderSymbolPreset("doc.text.fill", "documents notes text files 文档 笔记"),
        FolderSymbolPreset("tray.full.fill", "inbox archive mail 收件箱 归档"),
        FolderSymbolPreset("archivebox.fill", "archive backup zip 归档 备份"),
        FolderSymbolPreset("briefcase.fill", "work business project 工作 项目"),
        FolderSymbolPreset("book.closed.fill", "books reading library 书籍 阅读"),
        FolderSymbolPreset("graduationcap.fill", "study school learning 学习 课程"),
        FolderSymbolPreset("calendar", "schedule date plan 日历 计划"),
        FolderSymbolPreset("checkmark.seal.fill", "done approved verified 完成 审核"),
        // Creative & Media
        FolderSymbolPreset("paintbrush.pointed.fill", "design art creative 设计 绘画"),
        FolderSymbolPreset("photo.fill.on.rectangle.fill", "photos images pictures 照片 图片 素材"),
        FolderSymbolPreset("camera.fill", "photography raw shoot 摄影 相机"),
        FolderSymbolPreset("film.fill", "video movies cinema 视频 电影 剪辑"),
        FolderSymbolPreset("music.note", "audio songs sound 音乐 音频"),
        FolderSymbolPreset("headphones", "podcast audio music 播客 耳机"),
        FolderSymbolPreset("sparkles", "ai magic favorite 精选 灵感"),
        FolderSymbolPreset("wand.and.stars", "effects edit retouch 特效 修图"),
        // Apps, Games & Lifestyle
        FolderSymbolPreset("square.grid.2x2.fill", "apps applications 软件 应用"),
        FolderSymbolPreset("gamecontroller.fill", "games gaming play 游戏 娱乐"),
        FolderSymbolPreset("cube.fill", "3d model blender assets 模型 立体"),
        FolderSymbolPreset("globe", "web internet network 网页 网络"),
        FolderSymbolPreset("cloud.fill", "icloud sync drive 云盘 同步"),
        FolderSymbolPreset("arrow.down.circle.fill", "downloads transfer 下载 传输"),
        FolderSymbolPreset("externaldrive.fill", "disk storage drive 硬盘 存储"),
        FolderSymbolPreset("lock.fill", "private secret vault 隐私 加密"),
        // Personal & Misc
        FolderSymbolPreset("star.fill", "favorites starred 收藏 星标"),
        FolderSymbolPreset("heart.fill", "personal love likes 喜欢 个人"),
        FolderSymbolPreset("bookmark.fill", "bookmarks reading 书签"),
        FolderSymbolPreset("tag.fill", "tags labels category 标签 分类"),
        FolderSymbolPreset("house.fill", "home personal 家庭 个人"),
        FolderSymbolPreset("airplane", "travel trip flight 旅行 照片"),
        FolderSymbolPreset("cart.fill", "shopping receipts 购物 账单"),
        FolderSymbolPreset("creditcard.fill", "finance bills money 财务 账单"),
    ]

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedBase: FolderBaseMetrics?
    private nonisolated(unsafe) static var tintedBaseCache: [FolderRGB: CGImage] = [:]

    /// Rasterizes the host system's native folder icon at 1024x1024 in Aqua appearance.
    /// Must be called on MainActor the first time; subsequent calls reuse the cached metrics.
    @MainActor
    public static func prepareSystemFolderBase() throws -> FolderBaseMetrics {
        cacheLock.lock()
        if let existing = cachedBase {
            cacheLock.unlock()
            return existing
        }
        cacheLock.unlock()

        let folderImage = NSWorkspace.shared.icon(for: .folder)
        var pixels = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let image: CGImage = try pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: 1024,
                height: 1024,
                bitsPerComponent: 8,
                bytesPerRow: 1024 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { throw IconError.renderingFailed }
            ctx.interpolationQuality = .high
            let draw = {
                NSGraphicsContext.saveGraphicsState()
                let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
                gc.imageInterpolation = .high
                NSGraphicsContext.current = gc
                folderImage.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
                NSGraphicsContext.restoreGraphicsState()
            }
            if let aqua = NSAppearance(named: .aqua) {
                aqua.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            guard let cg = ctx.makeImage() else { throw IconError.renderingFailed }
            return cg
        }

        let metrics = try buildMetrics(from: pixels, image: image)
        cacheLock.lock()
        cachedBase = metrics
        cacheLock.unlock()
        return metrics
    }

    /// Loads any system SF Symbol cleanly rasterized at 1024px longest edge.
    @MainActor
    public static func loadSymbol(_ symbolName: String, weight: NSFont.Weight = .medium) throws -> IconSource {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let base = NSImage(systemSymbolName: trimmed, accessibilityDescription: nil)
        else { throw IconError.invalidImage }
        let config = NSImage.SymbolConfiguration(pointSize: 512, weight: weight)
            .applying(.init(hierarchicalColor: .black))
        let symbol = base.withSymbolConfiguration(config) ?? base
        let natural = symbol.size
        guard natural.width.isFinite, natural.height.isFinite, natural.width > 0, natural.height > 0 else {
            throw IconError.invalidImage
        }
        let factor = 1024 / max(natural.width, natural.height)
        let width = max(1, Int((natural.width * factor).rounded()))
        let height = max(1, Int((natural.height * factor).rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { throw IconError.renderingFailed }
        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        gc.imageInterpolation = .high
        NSGraphicsContext.current = gc
        symbol.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { throw IconError.renderingFailed }
        return try IconSource(image: cg)
    }

    @MainActor
    public static func isValidSymbol(_ symbolName: String) -> Bool {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
    }

    /// Builds geometric measurements & front-pocket clipping mask from the rasterized native folder.
    static func buildMetrics(from pixels: [UInt8], image: CGImage) throws -> FolderBaseMetrics {
        var firstOpaqueY = 200
        var lastOpaqueY = 888
        var foundFirst = false
        for y in 120..<960 {
            let a = pixels[(y * 1024 + 512) * 4 + 3]
            if a > 180 {
                if !foundFirst { firstOpaqueY = y; foundFirst = true }
                lastOpaqueY = y
            }
        }

        // Detect the front-pocket top crease at x=512:
        // - macOS 26/27 (Liquid Glass): back interior is darker than the front top glass rim (sharp positive luminance jump around y=268).
        // - macOS 14/15 (Big Sur-Sequoia): back flap is lighter than front face (sharp negative luminance drop around y=258).
        var bestJumpY = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 270 : 258
        var bestJumpScore = 0.0
        let scanStart = max(firstOpaqueY + 18, 225)
        let scanEnd = min(lastOpaqueY - 200, 320)
        if scanStart < scanEnd {
            for y in scanStart..<scanEnd {
                let lPrev = luminance(pixels, x: 512, y: y - 3)
                let lCurr = luminance(pixels, x: 512, y: y + 3)
                let score = abs(lCurr - lPrev)
                if score > bestJumpScore {
                    bestJumpScore = score
                    bestJumpY = y
                }
            }
        }
        let pocketTopY = Double(bestJumpScore > 0.05 ? bestJumpY : (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 270 : 258))
        let pocketBottomY = Double(lastOpaqueY)

        // Calibrated optical centers measured against native Apple folders:
        // macOS 26/27: pocket 270..888 -> optical center 580 (midpoint 579 + 1)
        // macOS 14/15: pocket 258..882 -> optical center 551 (slightly above geometric midpoint 570)
        let opticalCenterY: Double
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            opticalCenterY = (pocketTopY + pocketBottomY) / 2.0 + 1.0
        } else {
            opticalCenterY = (pocketTopY + pocketBottomY) / 2.0 - 19.0
        }

        // Sample front-pocket reference luminance across the central interior (safe from rim & shadows).
        var lumSum = 0.0
        var lumCount = 0
        let sampleTop = Int(pocketTopY) + 90
        let sampleBottom = Int(pocketBottomY) - 90
        if sampleTop < sampleBottom {
            for y in stride(from: sampleTop, to: sampleBottom, by: 16) {
                for x in stride(from: 220, to: 804, by: 16) {
                    let i = (y * 1024 + x) * 4
                    if pixels[i + 3] > 250 {
                        lumSum += luminance(pixels, x: x, y: y)
                        lumCount += 1
                    }
                }
            }
        }
        let refLum = lumCount > 0 ? lumSum / Double(lumCount) : 0.68

        // Measure horizontal body bounds around mid-pocket height.
        var bodyMinX = 42
        var bodyMaxX = 981
        let midRow = Int((pocketTopY + pocketBottomY) / 2.0)
        for x in 0..<1024 where pixels[(midRow * 1024 + x) * 4 + 3] > 180 {
            bodyMinX = x; break
        }
        for x in stride(from: 1023, through: 0, by: -1) where pixels[(midRow * 1024 + x) * 4 + 3] > 180 {
            bodyMaxX = x; break
        }

        // Build full folder body mask & front-pocket clipping mask.
        var bodyMaskPixels = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        var maskPixels = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let clipStart = Int(pocketTopY) + 8
        for y in 0..<1024 {
            let verticalFactor: Double
            if y < clipStart {
                verticalFactor = 0
            } else if y < clipStart + 8 {
                verticalFactor = Double(y - clipStart) / 8.0
            } else {
                verticalFactor = 1
            }
            for x in 0..<1024 {
                let i = (y * 1024 + x) * 4
                let a = pixels[i + 3]
                if a > 200 {
                    let edgeAlpha = min(1.0, Double(a - 200) / 55.0)
                    let bm = UInt8((edgeAlpha * 255.0).rounded())
                    bodyMaskPixels[i] = bm
                    bodyMaskPixels[i + 1] = bm
                    bodyMaskPixels[i + 2] = bm
                    bodyMaskPixels[i + 3] = bm
                    if verticalFactor > 0 {
                        let m = UInt8((verticalFactor * edgeAlpha * 255.0).rounded())
                        maskPixels[i] = m
                        maskPixels[i + 1] = m
                        maskPixels[i + 2] = m
                        maskPixels[i + 3] = m
                    }
                }
            }
        }
        let bodyMask: CGImage = try bodyMaskPixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: 1024,
                height: 1024,
                bitsPerComponent: 8,
                bytesPerRow: 1024 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ), let cg = ctx.makeImage() else { throw IconError.renderingFailed }
            return cg
        }
        let frontMask: CGImage = try maskPixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: 1024,
                height: 1024,
                bitsPerComponent: 8,
                bytesPerRow: 1024 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ), let cg = ctx.makeImage() else { throw IconError.renderingFailed }
            return cg
        }

        return FolderBaseMetrics(
            pixels: pixels,
            baseImage: image,
            folderBodyMask: bodyMask,
            frontPocketMask: frontMask,
            bodyMinX: Double(bodyMinX),
            bodyMaxX: Double(bodyMaxX),
            pocketTopY: pocketTopY,
            pocketBottomY: pocketBottomY,
            opticalCenterY: opticalCenterY,
            referenceLuminance: refLum
        )
    }

    private static func luminance(_ pixels: [UInt8], x: Int, y: Int) -> Double {
        let i = (y * 1024 + x) * 4
        let a = Double(pixels[i + 3]) / 255.0
        guard a > 0.001 else { return 0 }
        let r = min(1.0, Double(pixels[i]) / 255.0 / a)
        let g = min(1.0, Double(pixels[i + 1]) / 255.0 / a)
        let b = min(1.0, Double(pixels[i + 2]) / 255.0 / a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Recolors the cached native folder base using its measured luminance & specular structure,
    /// leaving neutral exterior shadows untouched and preserving glass top-rim highlights.
    public static func tintedFolderBase(metrics: FolderBaseMetrics, target: FolderRGB?) throws -> CGImage {
        guard let target else { return metrics.baseImage }

        cacheLock.lock()
        if let cached = tintedBaseCache[target] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let src = metrics.pixels
        var dst = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let refLum = max(metrics.referenceLuminance, 0.25)
        let tr = target.red
        let tg = target.green
        let tb = target.blue
        let targetMax = max(tr, max(tg, tb))
        let targetMin = min(tr, min(tg, tb))
        let targetSat = targetMax > 0 ? (targetMax - targetMin) / targetMax : 0

        for idx in stride(from: 0, to: src.count, by: 4) {
            let aByte = src[idx + 3]
            if aByte == 0 { continue }
            let a = Double(aByte) / 255.0
            let r = min(1.0, Double(src[idx]) / 255.0 / a)
            let g = min(1.0, Double(src[idx + 1]) / 255.0 / a)
            let b = min(1.0, Double(src[idx + 2]) / 255.0 / a)

            // Preserve pure dark exterior drop shadows completely untouched.
            let maxC = max(r, max(g, b))
            if maxC < 0.06 {
                dst[idx] = src[idx]
                dst[idx + 1] = src[idx + 1]
                dst[idx + 2] = src[idx + 2]
                dst[idx + 3] = aByte
                continue
            }

            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let relL = lum / refLum

            // Smooth blend so semi-transparent shadow borders transition cleanly into colored folder edges.
            let bodyWeight = min(1.0, max(0.0, (maxC - 0.06) / 0.14))

            var outR: Double
            var outG: Double
            var outB: Double

            if relL <= 1.0 {
                // Darker regions (back flap interior, bottom depth, pocket lip shadow):
                // Deepen smoothly while slightly enriching saturation for colored glass realism.
                let shade = pow(max(0.0, relL), 1.32)
                if targetSat > 0.08 && relL < 0.96 {
                    let depth = min(1.0, (0.96 - relL) * 2.0)
                    let mean = (tr + tg + tb) / 3.0
                    let boost = 1.0 + 0.22 * depth
                    let sr = min(1.0, max(0.0, mean + (tr - mean) * boost))
                    let sg = min(1.0, max(0.0, mean + (tg - mean) * boost))
                    let sb = min(1.0, max(0.0, mean + (tb - mean) * boost))
                    outR = sr * shade
                    outG = sg * shade
                    outB = sb * shade
                } else {
                    outR = tr * shade
                    outG = tg * shade
                    outB = tb * shade
                }
            } else {
                // Brighter regions (glass top rim highlight around y=270, soft upper sheen):
                // Blend gracefully toward crisp white specular highlight.
                let spec = min(0.88, (relL - 1.0) * 1.95)
                outR = tr + (1.0 - tr) * spec
                outG = tg + (1.0 - tg) * spec
                outB = tb + (1.0 - tb) * spec
            }

            let finalR = r * (1.0 - bodyWeight) + outR * bodyWeight
            let finalG = g * (1.0 - bodyWeight) + outG * bodyWeight
            let finalB = b * (1.0 - bodyWeight) + outB * bodyWeight

            dst[idx] = UInt8(min(255.0, max(0.0, (finalR * a * 255.0).rounded())))
            dst[idx + 1] = UInt8(min(255.0, max(0.0, (finalG * a * 255.0).rounded())))
            dst[idx + 2] = UInt8(min(255.0, max(0.0, (finalB * a * 255.0).rounded())))
            dst[idx + 3] = aByte
        }

        let tinted: CGImage = try dst.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: 1024,
                height: 1024,
                bitsPerComponent: 8,
                bytesPerRow: 1024 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ), let cg = ctx.makeImage() else { throw IconError.renderingFailed }
            return cg
        }

        cacheLock.lock()
        if tintedBaseCache.count > 24 { tintedBaseCache.removeAll() }
        tintedBaseCache[target] = tinted
        cacheLock.unlock()
        return tinted
    }

    /// Renders a custom folder icon (either empty tinted folder, App Logo badge, or native 3-layer Embossed glyph).
    public static func render(
        source: IconSource?,
        base: FolderBaseMetrics,
        settings: FolderSettings,
        size: Int = 1024
    ) throws -> CGImage {
        guard size > 0, size <= 4096 else { throw IconError.renderingFailed }
        let folderImage = try tintedFolderBase(metrics: base, target: settings.resolvedTargetRGB())
        let ctx = try IconRenderer.context(size)
        let ratio = Double(size) / 1024.0
        ctx.scaleBy(x: ratio, y: ratio)
        let fullRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        ctx.draw(folderImage, in: fullRect)

        if settings.hasFiles {
            try drawPaperSheet(base: base, folderImage: folderImage, size: size, ratio: ratio, into: ctx)
        }

        guard let source else {
            guard let result = ctx.makeImage() else { throw IconError.renderingFailed }
            return result
        }

        // Convert optical center Y from top-left screen coordinates to Core Graphics bottom-left coordinates.
        let centerX = 512.0 + settings.horizontal
        let centerY = (1024.0 - base.opticalCenterY) - settings.vertical

        let bounds = settings.trimTransparentEdges
            ? source.artworkBounds
            : CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let targetEdge = 1024.0 * settings.scale / 100.0
        let factor = targetEdge / max(bounds.width, bounds.height)
        let contentW = bounds.width * factor
        let contentH = bounds.height * factor
        let contentRect = CGRect(
            x: centerX - contentW / 2.0,
            y: centerY - contentH / 2.0,
            width: contentW,
            height: contentH
        )
        let artworkRect = CGRect(
            x: contentRect.minX - bounds.minX * factor,
            y: contentRect.minY - bounds.minY * factor,
            width: Double(source.width) * factor,
            height: Double(source.height) * factor
        )

        switch settings.style {
        case .appLogo:
            try drawAppLogo(
                source: source,
                contentRect: contentRect,
                artworkRect: artworkRect,
                settings: settings,
                size: size,
                ratio: ratio,
                into: ctx
            )
        case .embossed:
            try drawEmbossed(
                source: source,
                base: base,
                centerX: centerX,
                centerY: centerY,
                targetEdge: targetEdge,
                settings: settings,
                size: size,
                ratio: ratio,
                into: ctx
            )
        }

        guard let result = ctx.makeImage() else { throw IconError.renderingFailed }
        return result
    }

    /// Draws the crisp white paper sheet tucked behind the front pocket (calibrated from Apple's
    /// FolderComponent_PaperSheet: inset 31 px from folder sides, peeking 37 px above the front pocket,
    /// 30 px continuous top corners, tucked seamlessly behind the 64 px continuous front-flap shoulders).
    private static func drawPaperSheet(
        base: FolderBaseMetrics,
        folderImage: CGImage,
        size: Int,
        ratio: Double,
        into ctx: CGContext
    ) throws {
        let fullRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let inset = 31.0
        let paperMinX = base.bodyMinX + inset
        let paperWidth = max(100.0, (base.bodyMaxX - base.bodyMinX + 1.0) - inset * 2.0)
        // Measured native PaperSheet peeks 37 px above the front pocket top crease (y = 232 vs 269).
        let peekHeight = 37.0
        let paperTopYTopLeft = max(base.pocketTopY - peekHeight, 160.0)
        let paperHeight = peekHeight + 90.0
        // Convert top-left rect to Core Graphics bottom-left rect.
        let paperRectCG = CGRect(
            x: paperMinX,
            y: 1024.0 - (paperTopYTopLeft + paperHeight),
            width: paperWidth,
            height: paperHeight
        )
        let paperCornerFraction = 30.0 / paperWidth
        let paperMask = try IconRenderer.maskImage(in: paperRectCG, size: size, cornerRadiusFraction: paperCornerFraction)

        // Render the paper layer (soft top shadow onto back flap + crisp white sheet with subtle pocket-lip shading).
        let paperCtx = try IconRenderer.context(size)
        paperCtx.scaleBy(x: ratio, y: ratio)

        // Subtle shadow cast by the paper onto the dark back flap interior.
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let shadowCI = CIImage(cgImage: paperMask)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.14),
            ])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5.0 * ratio])
            .transformed(by: CGAffineTransform(translationX: 0, y: 1.5 * ratio))
        if let shadowCG = IconRenderer.ciContext.createCGImage(shadowCI, from: CGRect(x: 0, y: 0, width: size, height: size)) {
            paperCtx.draw(shadowCG, in: fullRect)
        }

        // Crisp white paper body with very gentle top-to-crease shading so it looks tactile, not flat.
        paperCtx.saveGState()
        paperCtx.clip(to: fullRect, mask: paperMask)
        let colors = [
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
            CGColor(red: 0.965, green: 0.972, blue: 0.982, alpha: 1.0),
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0.0, 1.0]
        ) {
            let topCG = 1024.0 - paperTopYTopLeft
            let creaseCG = 1024.0 - base.pocketTopY
            paperCtx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 512, y: topCG),
                end: CGPoint(x: 512, y: creaseCG),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        } else {
            paperCtx.setFillColor(CGColor(gray: 1, alpha: 1))
            paperCtx.fill(paperRectCG)
        }
        paperCtx.restoreGState()

        guard let paperImage = paperCtx.makeImage() else { throw IconError.renderingFailed }

        // Build exact FrontFlap continuous-rounded-rect mask (x = bodyMinX..bodyMaxX, y = pocketTopY..pocketBottomY, r = 64 px)
        // so Apple's real FrontFlap (including its glossy glass rim & 64 px rounded shoulders) sits cleanly ON TOP of the paper.
        let frontWidth = base.bodyMaxX - base.bodyMinX + 1.0
        let frontHeight = base.pocketBottomY - base.pocketTopY + 1.0
        let frontRectCG = CGRect(
            x: base.bodyMinX,
            y: 1024.0 - base.pocketBottomY - 1.0,
            width: frontWidth,
            height: frontHeight
        )
        let frontFlapMask = try IconRenderer.maskImage(
            in: frontRectCG,
            size: size,
            cornerRadiusFraction: 64.0 / max(frontWidth, 1.0)
        )

        // Composite: clip paper strictly inside folder silhouette, then re-draw the real FrontFlap over the lower portion.
        ctx.saveGState()
        ctx.clip(to: fullRect, mask: base.folderBodyMask)
        ctx.draw(paperImage, in: fullRect)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: fullRect, mask: frontFlapMask)
        ctx.draw(folderImage, in: fullRect)
        ctx.restoreGState()
    }

    private static func drawAppLogo(
        source: IconSource,
        contentRect: CGRect,
        artworkRect: CGRect,
        settings: FolderSettings,
        size: Int,
        ratio: Double,
        into ctx: CGContext
    ) throws {
        let fullRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let layerCtx = try IconRenderer.context(size)
        layerCtx.scaleBy(x: ratio, y: ratio)
        if settings.roundLogoCorners {
            let side = max(contentRect.width, contentRect.height)
            let tile = CGRect(
                x: contentRect.midX - side / 2.0,
                y: contentRect.midY - side / 2.0,
                width: side,
                height: side
            )
            let mask = try IconRenderer.maskImage(in: tile, size: size)
            layerCtx.clip(to: fullRect, mask: mask)
        }
        layerCtx.draw(source.image, in: artworkRect)
        guard let logoLayer = layerCtx.makeImage() else { throw IconError.renderingFailed }

        if settings.badgeShadowOpacity > 0 {
            let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
            var shadow = CIImage(cgImage: logoLayer).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: settings.badgeShadowOpacity),
            ])
            shadow = shadow.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8.0 * ratio])
            shadow = shadow.transformed(by: CGAffineTransform(translationX: 0, y: -4.0 * ratio))
            guard let shadowCG = IconRenderer.ciContext.createCGImage(
                shadow,
                from: CGRect(x: 0, y: 0, width: size, height: size)
            ) else { throw IconError.renderingFailed }
            ctx.draw(shadowCG, in: fullRect)
        }
        ctx.draw(logoLayer, in: fullRect)
    }

    /// Calibrated 3-layer native macOS folder emboss shader:
    /// 1. Interior cavity multiply fill (~15% black * depth) preserving underlying folder gradient & tint
    /// 2. Top inner shadow (1.5 px downward, 1.5 px blur, ~8% black * depth, clipped inside glyph)
    /// 3. Bottom rim bevel highlight (2.0 px downward, 2.0 px blur, ~25% white * depth, clipped outside glyph)
    /// All layers are strictly clipped to the folder's front-pocket silhouette.
    private static func drawEmbossed(
        source: IconSource,
        base: FolderBaseMetrics,
        centerX: Double,
        centerY: Double,
        targetEdge: Double,
        settings: FolderSettings,
        size: Int,
        ratio: Double,
        into ctx: CGContext
    ) throws {
        guard settings.embossDepth > 0 else { return }
        let fullRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let extent = CGRect(x: 0, y: 0, width: size, height: size)

        // Extract clean silhouette mask with exterior shadow removal and per-row background keying for opaque tiles.
        let maskSource = try embossSilhouette(from: source, threshold: settings.embossThreshold)

        // Re-measure extracted silhouette bounds when trimming is enabled so inner glyphs extracted from
        // padded .app plates fill the folder front pocket cleanly at the chosen scale.
        let effectiveBounds: CGRect
        if settings.trimTransparentEdges,
           let extracted = try? IconRenderer.alphaBounds(maskSource, threshold: 48) {
            effectiveBounds = extracted
        } else if settings.trimTransparentEdges {
            effectiveBounds = source.artworkBounds
        } else {
            effectiveBounds = CGRect(x: 0, y: 0, width: maskSource.width, height: maskSource.height)
        }
        let factor = targetEdge / max(effectiveBounds.width, effectiveBounds.height)
        let contentW = effectiveBounds.width * factor
        let contentH = effectiveBounds.height * factor
        let contentRect = CGRect(
            x: centerX - contentW / 2.0,
            y: centerY - contentH / 2.0,
            width: contentW,
            height: contentH
        )
        let artworkRect = CGRect(
            x: contentRect.minX - effectiveBounds.minX * factor,
            y: contentRect.minY - effectiveBounds.minY * factor,
            width: Double(maskSource.width) * factor,
            height: Double(maskSource.height) * factor
        )

        let glyphCtx = try IconRenderer.context(size)
        glyphCtx.scaleBy(x: ratio, y: ratio)
        glyphCtx.draw(maskSource, in: artworkRect)
        guard let glyphMask = glyphCtx.makeImage() else { throw IconError.renderingFailed }

        let glyphCI = CIImage(cgImage: glyphMask)
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let one = CIVector(x: 1, y: 1, z: 1, w: 0)
        let depth = settings.embossDepth

        // Clip all embossed effects cleanly inside the folder's front pocket.
        ctx.saveGState()
        ctx.clip(to: fullRect, mask: base.frontPocketMask)

        // Layer 1: Interior cavity darkening (measured native ratio = 0.85 -> 15% black multiply).
        let cavityAlpha = min(0.55, 0.15 * depth)
        let cavityCI = glyphCI.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: cavityAlpha),
        ])
        if let cavityCG = IconRenderer.ciContext.createCGImage(cavityCI, from: extent) {
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.draw(cavityCG, in: fullRect)
            ctx.restoreGState()
        }

        // Layer 2: Top inner shadow (inverted alpha shifted downward 1.5 px, blurred 1.5 px, clipped inside glyph).
        let invertedAlpha = glyphCI.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: -1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
        let innerBlur = invertedAlpha
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5 * ratio])
            .transformed(by: CGAffineTransform(translationX: 0, y: -1.5 * ratio))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: min(0.45, 0.12 * depth)),
            ])
            .cropped(to: extent)
        if let innerCG = IconRenderer.ciContext.createCGImage(innerBlur, from: extent) {
            ctx.saveGState()
            ctx.clip(to: fullRect, mask: glyphMask)
            ctx.setBlendMode(.multiply)
            ctx.draw(innerCG, in: fullRect)
            ctx.restoreGState()
        }

        // Layer 3: Bottom outer bevel highlight (glyph alpha shifted downward 2.0 px, blurred 2.0 px,
        // punched out by original glyph so it illuminates ONLY the bottom outer rim).
        let shiftedWhite = glyphCI
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0 * ratio])
            .transformed(by: CGAffineTransform(translationX: 0, y: -2.0 * ratio))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: min(0.60, 0.28 * depth)),
                "inputBiasVector": one,
            ])
            .cropped(to: extent)
        let rimHighlight = shiftedWhite.applyingFilter("CISourceOutCompositing", parameters: [
            kCIInputBackgroundImageKey: glyphCI,
        ]).cropped(to: extent)
        if let rimCG = IconRenderer.ciContext.createCGImage(rimHighlight, from: extent) {
            ctx.draw(rimCG, in: fullRect)
        }

        ctx.restoreGState()
    }

    /// Returns a clean alpha silhouette for embossing controlled by `threshold` (0...1).
    /// - Transparent artwork / SVGs / SF Symbols: strips faint exterior shadows using a smooth alpha threshold.
    /// - Opaque tiles (such as `.app` icons or solid-background images): insets inside the rounded plate border
    ///   to physically discard exterior drop shadows and glass rims, then samples each row's side background
    ///   to neutralize vertical plate gradients before applying the contrast threshold.
    static func embossSilhouette(from source: IconSource, threshold: Double = 0.40) throws -> CGImage {
        let clampedThreshold = min(max(threshold, 0.0), 1.0)
        let w = source.width
        let h = source.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            ctx.draw(source.image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { throw IconError.renderingFailed }

        // Convert bottom-left artworkBounds into top-left bitmap coordinates.
        let b = source.artworkBounds
        let minX = max(0, Int(b.minX))
        let maxX = min(w - 1, Int(b.maxX) - 1)
        let minY = max(0, h - Int(b.maxY))
        let maxY = min(h - 1, h - 1 - Int(b.minY))
        guard maxX >= minX, maxY >= minY else { return source.image }

        // Measure opacity density inside artworkBounds to detect opaque tiles (.app / flat JPGs).
        var total = 0
        var opaque = 0
        let step = max(1, min(maxX - minX, maxY - minY) / 48)
        for y in stride(from: minY, through: maxY, by: step) {
            for x in stride(from: minX, through: maxX, by: step) {
                total += 1
                if pixels[(y * w + x) * 4 + 3] > 220 { opaque += 1 }
            }
        }
        let opaqueRatio = total > 0 ? Double(opaque) / Double(total) : 0

        // Transparent logos, SVGs, and SF Symbols — OR user set threshold to 0% to keep full silhouette:
        // strip exterior low-alpha drop shadows while keeping crisp anti-aliased edges.
        if opaqueRatio < 0.86 || clampedThreshold <= 0.01 {
            let alphaLow = clampedThreshold <= 0.01 ? 0.35 : (0.12 + clampedThreshold * 0.70)
            let alphaHigh = min(0.99, alphaLow + 0.16)
            var maskOut = [UInt8](repeating: 0, count: w * h * 4)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let a = Double(pixels[i + 3]) / 255.0
                if a <= alphaLow { continue }
                let s = min(1.0, (a - alphaLow) / max(0.02, alphaHigh - alphaLow))
                maskOut[i + 3] = UInt8((s * 255.0).rounded())
            }
            return try makeAlphaMask(from: &maskOut, width: w, height: h)
        }

        // Opaque tile (.app / solid-background image):
        // 1. Define a concentric continuous-squircle inset window (~7.5% inside artworkBounds)
        //    so exterior shadows, rounded-square rims, and edge bezels are 100% excluded.
        let bw = Double(maxX - minX + 1)
        let bh = Double(maxY - minY + 1)
        let cx = Double(minX) + bw / 2.0
        let cy = Double(minY) + bh / 2.0
        let insetFraction = 0.075
        let halfW = max(1.0, bw * (0.5 - insetFraction))
        let halfH = max(1.0, bh * (0.5 - insetFraction))

        // 2. Sample per-row background color from the left and right inner edges of the inset plate.
        //    This cancels vertical linear gradients cleanly across the entire tile.
        let sampleInsetX = max(2, Int(bw * 0.12))
        let sampleBand = max(2, Int(bw * 0.04))
        let sampleMinY = min(maxY, minY + max(2, Int(bh * 0.12)))
        let sampleMaxY = max(minY, maxY - max(2, Int(bh * 0.12)))

        var rowBG = [(r: Double, g: Double, b: Double, valid: Bool)](repeating: (0, 0, 0, false), count: h)
        var fallbackR = 0.0, fallbackG = 0.0, fallbackB = 0.0
        var fallbackCount = 0

        for y in sampleMinY...sampleMaxY {
            var sr = 0.0, sg = 0.0, sb = 0.0
            var sc = 0
            let leftStart = min(maxX, minX + sampleInsetX)
            let leftEnd = min(maxX, leftStart + sampleBand)
            let rightEnd = max(minX, maxX - sampleInsetX)
            let rightStart = max(minX, rightEnd - sampleBand)
            for x in leftStart...leftEnd {
                let i = (y * w + x) * 4
                let a = Double(pixels[i + 3]) / 255.0
                if a > 0.92 {
                    sr += min(1.0, Double(pixels[i]) / 255.0 / a)
                    sg += min(1.0, Double(pixels[i + 1]) / 255.0 / a)
                    sb += min(1.0, Double(pixels[i + 2]) / 255.0 / a)
                    sc += 1
                }
            }
            for x in rightStart...rightEnd {
                let i = (y * w + x) * 4
                let a = Double(pixels[i + 3]) / 255.0
                if a > 0.92 {
                    sr += min(1.0, Double(pixels[i]) / 255.0 / a)
                    sg += min(1.0, Double(pixels[i + 1]) / 255.0 / a)
                    sb += min(1.0, Double(pixels[i + 2]) / 255.0 / a)
                    sc += 1
                }
            }
            if sc > 0 {
                let rr = sr / Double(sc), rg = sg / Double(sc), rb = sb / Double(sc)
                rowBG[y] = (rr, rg, rb, true)
                fallbackR += rr; fallbackG += rg; fallbackB += rb; fallbackCount += 1
            }
        }

        guard fallbackCount > 0 else { return source.image }
        fallbackR /= Double(fallbackCount)
        fallbackG /= Double(fallbackCount)
        fallbackB /= Double(fallbackCount)

        // Fill top/bottom cap rows from the nearest valid sampled row.
        var firstValidY = sampleMinY
        while firstValidY <= sampleMaxY && !rowBG[firstValidY].valid { firstValidY += 1 }
        var lastValidY = sampleMaxY
        while lastValidY >= sampleMinY && !rowBG[lastValidY].valid { lastValidY -= 1 }
        let topBG = firstValidY <= sampleMaxY ? rowBG[firstValidY] : (fallbackR, fallbackG, fallbackB, true)
        let botBG = lastValidY >= sampleMinY ? rowBG[lastValidY] : (fallbackR, fallbackG, fallbackB, true)
        for y in 0..<h where !rowBG[y].valid {
            rowBG[y] = y < firstValidY ? topBG : (y > lastValidY ? botBG : (fallbackR, fallbackG, fallbackB, true))
        }

        // Check whether the interior actually has meaningful contrast against the plate background.
        var maxDist = 0.0
        for y in stride(from: minY, through: maxY, by: step) {
            let bg = rowBG[y]
            for x in stride(from: minX, through: maxX, by: step) {
                let nx = abs(Double(x) - cx) / halfW
                let ny = abs(Double(y) - cy) / halfH
                if pow(nx, 4.6) + pow(ny, 4.6) > 1.0 { continue }
                let i = (y * w + x) * 4
                let a = Double(pixels[i + 3]) / 255.0
                if a < 0.85 { continue }
                let dr = min(1.0, Double(pixels[i]) / 255.0 / a) - bg.r
                let dg = min(1.0, Double(pixels[i + 1]) / 255.0 / a) - bg.g
                let db = min(1.0, Double(pixels[i + 2]) / 255.0 / a) - bg.b
                maxDist = max(maxDist, sqrt(dr * dr + dg * dg + db * db))
            }
        }
        guard maxDist > 0.16 else {
            // Pure flat-color tile with no inner emblem: return clean shadow-free plate silhouette.
            var maskOut = [UInt8](repeating: 0, count: w * h * 4)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let a = Double(pixels[i + 3]) / 255.0
                if a > 0.55 { maskOut[i + 3] = UInt8((min(1.0, (a - 0.55) / 0.25) * 255.0).rounded()) }
            }
            return try makeAlphaMask(from: &maskOut, width: w, height: h)
        }

        // Map user threshold (0...1) cleanly into color distance space.
        let low = 0.05 + clampedThreshold * 0.45
        let high = min(1.4, low + 0.14)
        var maskOut = [UInt8](repeating: 0, count: w * h * 4)

        for y in minY...maxY {
            let bg = rowBG[y]
            let ny = abs(Double(y) - cy) / halfH
            let nyPow = pow(ny, 4.6)
            if nyPow > 1.08 { continue }
            for x in minX...maxX {
                let nx = abs(Double(x) - cx) / halfW
                let superellipse = pow(nx, 4.6) + nyPow
                if superellipse >= 1.02 { continue }
                let edgeFade = superellipse <= 0.94 ? 1.0 : max(0.0, (1.02 - superellipse) / 0.08)

                let i = (y * w + x) * 4
                let a = Double(pixels[i + 3]) / 255.0
                if a < 0.70 { continue }

                let dr = min(1.0, Double(pixels[i]) / 255.0 / a) - bg.r
                let dg = min(1.0, Double(pixels[i + 1]) / 255.0 / a) - bg.g
                let db = min(1.0, Double(pixels[i + 2]) / 255.0 / a) - bg.b
                let dist = sqrt(dr * dr + dg * dg + db * db)
                if dist <= low { continue }
                let strength = min(1.0, (dist - low) / max(0.04, high - low))
                maskOut[i + 3] = UInt8((strength * edgeFade * 255.0).rounded())
            }
        }

        return try makeAlphaMask(from: &maskOut, width: w, height: h)
    }

    private static func makeAlphaMask(from bufferData: inout [UInt8], width: Int, height: Int) throws -> CGImage {
        try bufferData.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ), let cg = ctx.makeImage() else { throw IconError.renderingFailed }
            return cg
        }
    }
}
