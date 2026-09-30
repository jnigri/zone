import AppKit

/// The logo is a white silhouette on transparency (Resources/Logo.png, copied into
/// the app bundle by scripts/build-app.sh). Its alpha is used as a mask everywhere:
/// template image in the menu bar, accent-tinted in the header and app icon.
enum Logo {
    /// Logo cropped to its visible pixels, or nil when running outside the app bundle.
    static let cgImage: CGImage? = {
        guard let url = Bundle.main.url(forResource: "Logo", withExtension: "png") else { return nil }
        return load(url)
    }()

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

    // MARK: App icon

    /// Renders the macOS iconset: accent-colored logo on a dark rounded tile,
    /// using the theme's dark background and accent.
    static func renderIconSet(logo: URL, to directory: URL) throws {
        guard let image = load(logo) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try appIconPNG(logo: image, pixels: base * scale).write(to: directory.appending(path: name))
            }
        }
    }

    private static func appIconPNG(logo: CGImage, pixels: Int) throws -> Data {
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
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil))
        ctx.setFillColor(CGColor(srgbRed: 0x14 / 255, green: 0x15 / 255, blue: 0x16 / 255, alpha: 1))
        ctx.fillPath()

        let area = tile.insetBy(dx: tile.width * 0.14, dy: tile.width * 0.14)
        let scale = min(area.width / CGFloat(logo.width), area.height / CGFloat(logo.height))
        let drawn = CGSize(width: CGFloat(logo.width) * scale, height: CGFloat(logo.height) * scale)
        let target = CGRect(x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2, width: drawn.width, height: drawn.height)

        // Tint: draw the silhouette, then keep only its alpha filled with the accent.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.draw(logo, in: target)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0x5A / 255, blue: 0, alpha: 1))
        ctx.fill(target)
        ctx.endTransparencyLayer()
        ctx.flush()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    // MARK: Loading

    private static func load(_ url: URL) -> CGImage? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return cgImage.cropping(to: opaqueBounds(of: cgImage)) ?? cgImage
    }

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
