// Draws the app icon and writes every size macOS needs into the asset catalog.
// Run: swift Tools/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let set = root.appendingPathComponent("NotchPrompter/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024   // design at 1024 units

    // macOS icon grid: 824 square with ~185 radius, centred, leaving room for the shadow.
    let tile = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * u, yRadius: 185 * u)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 20 * u
    shadow.shadowOffset = NSSize(width: 0, height: -8 * u)
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    // Screen wallpaper: warm to cool gradient.
    NSGradient(colors: [NSColor(calibratedRed: 0.99, green: 0.46, blue: 0.33, alpha: 1),
                        NSColor(calibratedRed: 0.62, green: 0.25, blue: 0.85, alpha: 1),
                        NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.86, alpha: 1)])!
        .draw(in: tile, angle: -60)

    // The prompter hanging from the top edge, with rounded bottom corners.
    let pw: CGFloat = 600 * u, ph: CGFloat = 470 * u
    let prompter = NSRect(x: 512 * u - pw / 2, y: tile.maxY - ph, width: pw, height: ph + 60 * u)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: prompter, xRadius: 90 * u, yRadius: 90 * u).fill()

    // Camera dot.
    NSColor(white: 0.22, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 512 * u - 16 * u, y: tile.maxY - 58 * u, width: 32 * u, height: 32 * u)).fill()

    // Script lines: the first ones already said (dim), the next ones bright.
    let lines: [(CGFloat, CGFloat)] = [(380, 0.32), (440, 1), (320, 1)]
    for (i, line) in lines.enumerated() {
        let w = line.0 * u, h = 44 * u
        let y = tile.maxY - 150 * u - CGFloat(i) * 82 * u - h
        NSColor(white: 1, alpha: line.1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 512 * u - w / 2, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
    }

    // Red microphone badge, bottom right.
    let badge = NSRect(x: 636 * u, y: 156 * u, width: 220 * u, height: 220 * u)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badge.insetBy(dx: -14 * u, dy: -14 * u)).fill()
    NSColor(calibratedRed: 0.98, green: 0.23, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(ovalIn: badge).fill()
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 120 * u, weight: .bold)) {
        let tinted = NSImage(size: mic.size, flipped: false) { r in
            mic.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let m = tinted.size
        tinted.draw(in: NSRect(x: badge.midX - m.width / 2, y: badge.midY - m.height / 2, width: m.width, height: m.height))
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try draw(points * scale).write(to: set.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appendingPathComponent("Contents.json"))
try draw(1024).write(to: root.appendingPathComponent("AppStore/icon-1024.png"))
print("Wrote icons to \(set.path)")
