// Renders the MonitorHop app icon into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)

    // Background squircle on the macOS icon grid (≈ 824/1024 content).
    let inset = s * 0.098
    let bg = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bgPath = NSBezierPath(roundedRect: bg, xRadius: bg.width * 0.225, yRadius: bg.width * 0.225)
    NSGradient(
        starting: NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.47, green: 0.25, blue: 0.88, alpha: 1)
    )!.draw(in: bgPath, angle: -65)

    func monitor(_ rect: NSRect, alpha: CGFloat) {
        let white = NSColor.white.withAlphaComponent(alpha)
        white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.07, yRadius: rect.width * 0.07).fill()
        let inner = rect.insetBy(dx: rect.width * 0.07, dy: rect.width * 0.07)
        NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.50, alpha: 0.85 * alpha).setFill()
        NSBezierPath(roundedRect: inner, xRadius: inner.width * 0.035, yRadius: inner.width * 0.035).fill()
        white.setFill()
        NSRect(x: rect.midX - rect.width * 0.07, y: rect.minY - rect.height * 0.16,
               width: rect.width * 0.14, height: rect.height * 0.16).fill()
        let base = NSRect(x: rect.midX - rect.width * 0.22, y: rect.minY - rect.height * 0.23,
                          width: rect.width * 0.44, height: rect.height * 0.08)
        NSBezierPath(roundedRect: base, xRadius: base.height / 2, yRadius: base.height / 2).fill()
    }
    let mw = s * 0.34, mh = s * 0.235
    monitor(NSRect(x: s * 0.125, y: s * 0.36, width: mw, height: mh), alpha: 0.72)
    monitor(NSRect(x: s * 0.535, y: s * 0.36, width: mw, height: mh), alpha: 1.0)

    // "Hop" arc from the left monitor to the right one.
    let start = NSPoint(x: s * 0.30, y: s * 0.64)
    let end = NSPoint(x: s * 0.69, y: s * 0.645)
    let c1 = NSPoint(x: s * 0.36, y: s * 0.83)
    let c2 = NSPoint(x: s * 0.62, y: s * 0.83)
    let arc = NSBezierPath()
    arc.move(to: start)
    arc.curve(to: end, controlPoint1: c1, controlPoint2: c2)
    arc.lineWidth = s * 0.038
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()

    // Arrow head along the tangent at the end of the arc.
    var dx = end.x - c2.x, dy = end.y - c2.y
    let length = max(sqrt(dx * dx + dy * dy), 0.0001)
    dx /= length; dy /= length
    let nx = -dy, ny = dx
    let head = s * 0.075
    let tip = NSPoint(x: end.x + dx * head * 0.55, y: end.y + dy * head * 0.55)
    let back = NSPoint(x: end.x - dx * head * 0.6, y: end.y - dy * head * 0.6)
    let arrow = NSBezierPath()
    arrow.move(to: tip)
    arrow.line(to: NSPoint(x: back.x + nx * head * 0.7, y: back.y + ny * head * 0.7))
    arrow.line(to: NSPoint(x: back.x - nx * head * 0.7, y: back.y - ny * head * 0.7))
    arrow.close()
    NSColor.white.setFill()
    arrow.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in variants {
    try render(pixels).write(to: output.appendingPathComponent(name))
}
print("wrote \(variants.count) images to \(output.path)")
