// Draws the Wave app icon (blue-violet rounded square, white waving hand) into an .icns.
// Usage: swift scripts/make-icon.swift <out.icns>   (build.sh runs it)
import AppKit

let out = CommandLine.arguments[1]
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Wave.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: an 824 square centred in 1024, leaving room for the shadow.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.33, green: 0.68, blue: 1.0, alpha: 1), NSColor(red: 0.6, green: 0.4, blue: 0.98, alpha: 1)])!
        .draw(in: path, angle: -50)
    // Soft top sheen, like light on glass.
    NSGradient(colors: [.white.withAlphaComponent(0.22), .white.withAlphaComponent(0)])!.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 430 * s, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let glyph = NSImage(systemSymbolName: "hand.wave.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let g = glyph.size
    glyph.draw(in: NSRect(x: tile.midX - g.width / 2, y: tile.midY - g.height / 2, width: g.width, height: g.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! png(base * scale).write(to: set.appending(path: name))
    }
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out]
try! p.run()
p.waitUntilExit()
exit(p.terminationStatus)
