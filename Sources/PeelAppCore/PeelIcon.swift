import AppKit

/// peel's menu-bar icon: a corkscrew twist of citrus peel, like a cocktail garnish.
/// Drawn in code as a template image so it follows the menu bar's light/dark appearance.
public enum PeelIcon {
    public static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawTwist(in: rect.insetBy(dx: 1, dy: 0.5))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A ribbon spiralling down a slightly tilted axis; the back of each turn is thinner and
    /// fainter so the twist reads as three-dimensional.
    static func drawTwist(in rect: NSRect, color: NSColor = .black, weight: Double = 1) {
        let turns = 2.5
        let steps = 240
        let top = rect.maxY - rect.height * 0.10
        let bottom = rect.minY + rect.height * 0.03
        let radius = rect.width * 0.30
        func taper(_ t: Double) -> Double { 0.55 + 0.45 * sin(.pi * t) }
        func point(_ t: Double) -> (NSPoint, depth: Double) {
            let angle = t * turns * 2 * .pi
            let x = rect.midX + radius * taper(t) * sin(angle) + rect.width * 0.12 * (t - 0.5)
            return (NSPoint(x: x, y: top - (top - bottom) * t), cos(angle))
        }
        for frontPass in [false, true] {
            for step in 0..<steps {
                let t0 = Double(step) / Double(steps)
                let (start, depth) = point(t0)
                let (end, _) = point(Double(step + 1) / Double(steps))
                guard (depth > 0) == frontPass else { continue }
                let width = rect.width * (frontPass ? 0.06 + 0.035 * depth : 0.045) * taper(t0) * weight
                color.withAlphaComponent(frontPass ? 1 : 0.55).setStroke()
                let segment = NSBezierPath()
                segment.move(to: start)
                segment.line(to: end)
                segment.lineWidth = width
                segment.lineCapStyle = .round
                segment.stroke()
            }
        }
    }

    /// The app icon (Finder, System Settings, the About panel): the same twist in white on an orange
    /// tile, on the macOS icon grid — an 824/1024 rounded square, centred, with room for its shadow.
    public static func appIconPNG(pixels px: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(px) / 1024
        let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.shadowBlurRadius = 24 * s
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Tangerine, lighter at the top.
        NSGradient(starting: NSColor(srgbRed: 1.00, green: 0.66, blue: 0.22, alpha: 1),
                   ending: NSColor(srgbRed: 0.96, green: 0.43, blue: 0.07, alpha: 1))!
            .draw(in: shape, angle: -90)
        drawTwist(in: tile.insetBy(dx: tile.width * 0.21, dy: tile.height * 0.15), color: .white, weight: 1.6)

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// Writes the .iconset folder `iconutil -c icns` turns into the app's icon: each size at 1x and 2x.
    public static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            try appIconPNG(pixels: size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
            try appIconPNG(pixels: size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }
    }

    /// Fraction of a 36×36 rendering covered by ink (used by tests to catch a blank/garbled icon).
    static func inkCoverage() -> Double {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        menuBarImage().draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        NSGraphicsContext.restoreGraphicsState()
        var inked = 0
        for x in 0..<36 {
            for y in 0..<36 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { inked += 1 }
        }
        return Double(inked) / Double(36 * 36)
    }
}
