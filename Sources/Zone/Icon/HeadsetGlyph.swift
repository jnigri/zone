import AppKit
import SwiftUI

/// Line-art trace of Resources/Logo.png (head with headset and sunglasses).
/// Used where the bitmap won't do: the monochrome menu bar icon and the in-app header.
/// The app icon itself is rendered from the PNG.
enum HeadsetGlyph {
    /// Glyph fitted (aspect preserved, centered) into `rect`.
    /// `weight` is the stroke width in logo pixels; the original is ~34, small sizes need more.
    static func path(in rect: CGRect, weight: CGFloat = 34) -> CGPath {
        let unit = shape(weight: weight)
        let box = unit.boundingBoxOfPath
        let scale = min(rect.width / box.width, rect.height / box.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        return unit.copy(using: &transform) ?? unit
    }

    /// Geometry in the logo's 1536×1024 pixel space, y pointing down.
    private static func shape(weight w: CGFloat) -> CGPath {
        func stroked(_ path: CGPath) -> CGPath {
            path.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
        }
        func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2), transform: nil)
        }

        // Head ring; its disk hides whatever sits behind the head.
        let head = CGPoint(x: 768, y: 565)
        let headRadius: CGFloat = 367
        let headRing = stroked(ellipse(head, headRadius, headRadius))
        let headDisk = ellipse(head, headRadius + w / 2, headRadius + w / 2)

        // Ear cups, tucked behind the head.
        let cupCenters = [CGPoint(x: 330, y: 580), CGPoint(x: 1206, y: 580)]
        let cupRX: CGFloat = 92, cupRY: CGFloat = 142
        let cupDisks = cupCenters.map { ellipse($0, cupRX + w / 2, cupRY + w / 2) }
        let cups = cupCenters
            .map { stroked(ellipse($0, cupRX, cupRY)).subtracting(headDisk) }
            .reduce(CGMutablePath() as CGPath) { $0.union($1) }

        // Headband: arc over the head whose ends disappear into the cups.
        let bandCenter = CGPoint(x: 768, y: 490)
        let bandRX: CGFloat = 425, bandRY: CGFloat = 395
        let arc = CGMutablePath()
        let steps = 64
        for i in 0...steps {
            let theta = -0.2 + (Double.pi + 0.4) * Double(i) / Double(steps)
            let point = CGPoint(x: bandCenter.x - bandRX * cos(theta), y: bandCenter.y - bandRY * sin(theta))
            i == 0 ? arc.move(to: point) : arc.addLine(to: point)
        }
        let band = cupDisks.reduce(stroked(arc).subtracting(headDisk)) { $0.subtracting($1) }

        // Sunglasses: top bar plus two lenses, each with a diagonal glint cut out.
        let bar = CGPath(roundedRect: CGRect(x: 447, y: 465, width: 642, height: 40), cornerWidth: 14, cornerHeight: 14, transform: nil)
        let leftLens = CGMutablePath()
        leftLens.move(to: CGPoint(x: 458, y: 495))
        leftLens.addLine(to: CGPoint(x: 742, y: 495))
        leftLens.addCurve(to: CGPoint(x: 610, y: 690), control1: CGPoint(x: 722, y: 610), control2: CGPoint(x: 700, y: 690))
        leftLens.addCurve(to: CGPoint(x: 458, y: 495), control1: CGPoint(x: 500, y: 690), control2: CGPoint(x: 470, y: 610))
        leftLens.closeSubpath()
        var mirror = CGAffineTransform(translationX: 1536, y: 0).scaledBy(x: -1, y: 1)
        let rightLens = leftLens.copy(using: &mirror)!

        let glint = CGMutablePath()
        glint.addLines(between: [
            CGPoint(x: 580, y: 505), CGPoint(x: 616, y: 505),
            CGPoint(x: 514, y: 612), CGPoint(x: 492, y: 588),
        ])
        glint.closeSubpath()
        var shift = CGAffineTransform(translationX: 412, y: 0)
        let rightGlint = glint.copy(using: &shift)!

        let glasses = bar.union(leftLens).union(rightLens)
            .subtracting(glint)
            .subtracting(rightGlint)

        return headRing.union(cups).union(band).union(glasses)
    }

    /// Template image for the menu bar; macOS tints it for light/dark bars.
    static let templateImage: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path(in: rect.insetBy(dx: 0.5, dy: 0.5), weight: 64))
            ctx.setFillColor(.black)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()

    // MARK: App icon

    /// Renders the macOS iconset from the logo PNG, placed on a dark rounded tile
    /// (recent macOS wraps non-tile icons in a gray plate otherwise).
    static func renderIconSet(logo: URL, to directory: URL) throws {
        guard let image = NSImage(contentsOf: logo),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        let cropped = cgImage.cropping(to: opaqueBounds(of: cgImage)) ?? cgImage

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try appIconPNG(logo: cropped, pixels: base * scale).write(to: directory.appending(path: name))
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

        let area = tile.insetBy(dx: tile.width * 0.1, dy: tile.width * 0.1)
        let scale = min(area.width / CGFloat(logo.width), area.height / CGFloat(logo.height))
        let drawn = CGSize(width: CGFloat(logo.width) * scale, height: CGFloat(logo.height) * scale)
        ctx.draw(logo, in: CGRect(x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
        ctx.flush()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
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

struct HeadsetShape: Shape {
    var weight: CGFloat = 34

    func path(in rect: CGRect) -> Path {
        Path(HeadsetGlyph.path(in: rect, weight: weight))
    }
}
