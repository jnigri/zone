import AppKit

/// The logo is a white silhouette on transparency (Resources/Logo.png, copied into
/// the app bundle by scripts/build-app.sh). Its alpha is used as a mask everywhere:
/// template image in the menu bar, accent-tinted in the header, charcoal on the app icon.
enum Logo {
    /// Silhouette and sunglasses mask, both cropped to the visible pixels, or nil when running
    /// outside the app bundle.
    private static let parts: (logo: CGImage, lenses: CGImage)? = {
        guard let url = Bundle.main.url(forResource: "Logo", withExtension: "png"),
              let original = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let bounds = opaqueBounds(of: original)
        guard let logo = original.cropping(to: bounds), let lenses = lenses(in: original)?.cropping(to: bounds)
        else { return nil }
        return (logo, lenses)
    }()

    static var cgImage: CGImage? { parts?.logo }

    /// Template image for the menu bar (and the header, tinted); macOS colors it to fit.
    static let templateImage: NSImage = {
        guard let cgImage else {
            return NSImage(systemSymbolName: "headphones", accessibilityDescription: "Zone")!
        }
        let height: CGFloat = 16
        let size = NSSize(width: height * CGFloat(cgImage.width) / CGFloat(cgImage.height), height: height)
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }()

    /// Menu bar image for Beast Mode: the same face with orange lenses. A colored image can't
    /// be a template, so it draws itself white or black to match the menu bar it lands in.
    static let beastImage: NSImage = {
        guard let parts else { return templateImage }
        return NSImage(size: templateImage.size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ctx.interpolationQuality = .high
            drawTinted(parts.lenses, in: rect, color: orange, ctx: ctx)
            drawTinted(parts.logo, in: rect, color: CGColor(gray: dark ? 1 : 0, alpha: dark ? 1 : 0.85), ctx: ctx)
            return true
        }
    }()

    // MARK: App icon

    /// Renders the macOS iconset in an Asiimov-inspired style from the light palette:
    /// light tile, orange diagonal wedge with a charcoal stripe, charcoal logo with orange lenses.
    static func renderIconSet(logo: URL, to directory: URL) throws {
        guard let original = NSImage(contentsOf: logo)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let lensMask = lenses(in: original)
        else { throw CocoaError(.fileReadCorruptFile) }
        let bounds = opaqueBounds(of: original)
        guard let image = original.cropping(to: bounds), let lenses = lensMask.cropping(to: bounds)
        else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try appIconPNG(logo: image, lenses: lenses, pixels: base * scale)
                    .write(to: directory.appending(path: name))
            }
        }
    }

    private static let charcoal = CGColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255, alpha: 1)
    private static let orange = CGColor(srgbRed: 1, green: 0x5A / 255, blue: 0, alpha: 1)

    private static func appIconPNG(logo: CGImage, lenses: CGImage, pixels: Int) throws -> Data {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { throw CocoaError(.fileWriteUnknown) }

        let ctx = context.cgContext
        ctx.interpolationQuality = .high
        let size = CGFloat(pixels)

        // macOS icon grid: ~10% margin around a rounded square.
        let tile = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.1, dy: size * 0.1)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)

        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()

        // Light tile, a touch darker toward the bottom (light palette background → panel).
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            CGColor(srgbRed: 0xF7 / 255, green: 0xF8 / 255, blue: 0xF8 / 255, alpha: 1),
            CGColor(srgbRed: 0xDD / 255, green: 0xE1 / 255, blue: 0xE4 / 255, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])

        // Diagonal bands in the bottom-right corner, clear of the logo: charcoal stripe, then orange wedge.
        func band(from a: CGFloat, to b: CGFloat, color: CGColor) {
            let points = [(a, 0.0), (b, 0.0), (b + 2, 2.0), (a + 2, 2.0)].map {
                CGPoint(x: tile.minX + $0.0 * tile.width, y: tile.minY + $0.1 * tile.height)
            }
            ctx.addLines(between: points)
            ctx.closePath()
            ctx.setFillColor(color)
            ctx.fillPath()
        }
        band(from: 0.56, to: 0.61, color: charcoal)
        band(from: 0.66, to: 3, color: orange)
        ctx.restoreGState()

        // Hairline edge so the light tile holds up on light backgrounds.
        ctx.addPath(tilePath)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
        ctx.setLineWidth(max(1, size / 512))
        ctx.strokePath()

        let area = tile.insetBy(dx: tile.width * 0.14, dy: tile.width * 0.14)
        let scale = min(area.width / CGFloat(logo.width), area.height / CGFloat(logo.height))
        let drawn = CGSize(width: CGFloat(logo.width) * scale, height: CGFloat(logo.height) * scale)
        let target = CGRect(x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2, width: drawn.width, height: drawn.height)

        drawTinted(lenses, in: target, color: orange, ctx: ctx)
        drawTinted(logo, in: target, color: charcoal, ctx: ctx)
        ctx.flush()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    /// Draws `mask`'s alpha filled with `color`.
    private static func drawTinted(_ mask: CGImage, in rect: CGRect, color: CGColor, ctx: CGContext) {
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.draw(mask, in: rect)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color)
        ctx.fill(rect)
        ctx.endTransparencyLayer()
    }

    /// Head circle in Logo.png's 1536×1024 pixel grid (measured from the image).
    private static let headCenter = CGPoint(x: 764, y: 544)
    private static let headRadius: CGFloat = 364

    /// The sunglasses: transparent pixels inside the head circle (the cutout isn't fully
    /// enclosed, it opens into the gap under the headband, so a flood fill can't find it).
    /// Includes the antialiased rim, which the silhouette then covers.
    private static func lenses(in image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let source = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: space, bitmapInfo: info)
        else { return nil }
        source.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Scale the measured circle in case the logo is re-exported at another size.
        let scale = CGFloat(width) / 1536
        let cx = headCenter.x * scale, cy = headCenter.y * scale, r = (headRadius - 4) * scale
        var mask = [UInt8](repeating: 0, count: width * height * 4)
        // Memory rows run top-down, like the pixel coordinates measured in the image.
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] < 250 {
                let dx = CGFloat(x) - cx, dy = CGFloat(y) - cy
                guard dx * dx + dy * dy < r * r else { continue }
                let i = (y * width + x) * 4
                mask[i] = 255; mask[i + 1] = 255; mask[i + 2] = 255; mask[i + 3] = 255
            }
        }
        return mask.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space, bitmapInfo: info)?.makeImage()
        }
    }

    // MARK: Measuring

    /// Bounding box of pixels that aren't (nearly) transparent, in CGImage coordinates (top-left origin).
    private static func opaqueBounds(of image: CGImage) -> CGRect {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return CGRect(x: 0, y: 0, width: width, height: height) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return CGRect(x: 0, y: 0, width: width, height: height) }
        // Bitmap context memory rows run top-down, matching CGImage cropping coordinates.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
