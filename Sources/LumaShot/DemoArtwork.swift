import AppKit

enum DemoArtwork {
    /// A generated practice image. This never captures or reads the user's screen.
    static func make() -> NSImage {
        let width = 1440, height = 960
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let background = NSColor(red: 0.974, green: 0.969, blue: 0.951, alpha: 1)
        background.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
            (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        let ink = NSColor(red: 0.18, green: 0.25, blue: 0.22, alpha: 1)
        let muted = NSColor(red: 0.49, green: 0.54, blue: 0.49, alpha: 1)
        text("MOMENT / 片刻", x: 88, y: 853, size: 22, weight: .semibold, color: ink)
        text("灵感日记     自然观察     关于片刻", x: 1000, y: 858, size: 16, color: muted)
        muted.withAlphaComponent(0.2).setFill(); NSRect(x: 88, y: 822, width: 1264, height: 1).fill()
        text("SLOW DOWN. LOOK AROUND.", x: 92, y: 719, size: 14, weight: .medium, color: muted)
        text("留一点空间，", x: 88, y: 609, size: 66, weight: .semibold, color: ink)
        text("给新的想法。", x: 88, y: 521, size: 66, weight: .semibold, color: ink)
        text("不必追赶每一个瞬间。", x: 93, y: 455, size: 21, color: muted)
        text("有些美好，值得停下来，看一看。", x: 93, y: 416, size: 21, color: muted)
        ink.setFill(); NSBezierPath(roundedRect: NSRect(x: 91, y: 322, width: 166, height: 52), xRadius: 26, yRadius: 26).fill()
        text("探索这一刻  ↗", x: 118, y: 337, size: 17, weight: .medium, color: .white)
        let picture = NSRect(x: 740, y: 298, width: 607, height: 457)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: picture, xRadius: 28, yRadius: 28).addClip()
        NSGradient(starting: NSColor(red: 0.79, green: 0.85, blue: 0.78, alpha: 1), ending: NSColor(red: 0.90, green: 0.90, blue: 0.76, alpha: 1))!.draw(in: picture, angle: 70)
        NSColor(red: 0.98, green: 0.94, blue: 0.77, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1092, y: 549, width: 102, height: 102)).fill()
        for (offset, color) in [(CGFloat(0), NSColor(red: 0.47, green: 0.62, blue: 0.50, alpha: 1)), (CGFloat(-100), NSColor(red: 0.29, green: 0.46, blue: 0.36, alpha: 1)), (CGFloat(-190), NSColor(red: 0.19, green: 0.35, blue: 0.29, alpha: 1))] {
            let hill = NSBezierPath(); hill.move(to: NSPoint(x: 700, y: 260)); hill.line(to: NSPoint(x: 700, y: 450 + offset))
            hill.curve(to: NSPoint(x: 1380, y: 480 + offset), controlPoint1: NSPoint(x: 900, y: 760 + offset), controlPoint2: NSPoint(x: 1020, y: 290 + offset))
            hill.line(to: NSPoint(x: 1380, y: 250)); hill.close(); color.setFill(); hill.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        text("01 / 山野之间", x: 754, y: 260, size: 14, color: muted)
        muted.withAlphaComponent(0.2).setFill(); NSRect(x: 88, y: 202, width: 1264, height: 1).fill()
        text("收集日常里的微小确幸", x: 90, y: 143, size: 18, weight: .medium, color: ink)
        text("一张截图，一份灵感，一个值得留下的片刻。", x: 90, y: 106, size: 15, color: muted)
        text("LUMASHOT  /  标注练习画布", x: 1084, y: 112, size: 11, color: muted)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height)); image.addRepresentation(bitmap)
        return image
    }
}
