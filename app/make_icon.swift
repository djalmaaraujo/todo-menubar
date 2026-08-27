import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func drawGlyph(size: CGFloat, color: NSColor, lineScale: CGFloat = 0.052) {
    let s = size / 100.0
    color.setStroke()
    let lw = size * lineScale
    let rows: [CGFloat] = [72, 50, 28] // centers, bottom-up

    for (i, cy) in rows.enumerated() {
        // check mark (rows 0,1) or empty circle (row 2)
        if i < 2 {
            let check = NSBezierPath()
            check.lineWidth = lw
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: 16 * s, y: cy * s))
            check.line(to: NSPoint(x: 23 * s, y: (cy - 7) * s))
            check.line(to: NSPoint(x: 34 * s, y: (cy + 9) * s))
            check.stroke()
        } else {
            let diameter = 16 * s
            let box = NSBezierPath(ovalIn: NSRect(x: 17 * s, y: (cy - 8) * s,
                                                  width: diameter, height: diameter))
            box.lineWidth = lw
            box.stroke()
        }

        // the list line to the right
        let line = NSBezierPath()
        line.lineWidth = lw
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 46 * s, y: cy * s))
        line.line(to: NSPoint(x: 86 * s, y: cy * s))
        line.stroke()
    }
}

// ---- menubar template mark (black on transparent) ----
func makeMenubarMark(size: CGFloat = 150) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    drawGlyph(size: size, color: .black, lineScale: 0.06)
    img.unlockFocus()
    img.isTemplate = true
    return img
}

// ---- app icon tile (gradient rounded rect + light glyph) ----
func makeIconTile(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.2237
    let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    clip.addClip()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0x63 / 255, green: 0x66 / 255, blue: 0xf1 / 255, alpha: 1), // indigo #6366f1
        NSColor(srgbRed: 0x22 / 255, green: 0xd3 / 255, blue: 0xee / 255, alpha: 1)  // cyan #22d3ee
    ])!
    gradient.draw(in: rect, angle: -45)

    // center the glyph inside ~64% of the tile
    let inset = size * 0.18
    let g = size - inset * 2
    let ctx = NSGraphicsContext.current
    ctx?.saveGraphicsState()
    let transform = AffineTransform(translationByX: inset, byY: inset)
    (transform as NSAffineTransform).concat()
    drawGlyph(size: g, color: NSColor(srgbRed: 0xe2 / 255, green: 0xe8 / 255, blue: 0xf0 / 255, alpha: 1),
              lineScale: 0.058)
    ctx?.restoreGraphicsState()

    img.unlockFocus()
    return img
}

func writePNG(_ image: NSImage, to path: String, pixelSize: CGFloat) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixelSize), pixelsHigh: Int(pixelSize),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// menubar mark
writePNG(makeMenubarMark(), to: "\(outDir)/menubar-mark.png", pixelSize: 150)
print("wrote menubar-mark.png")

// app icon set
let iconset = "\(outDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let specs: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                           (256, 1), (256, 2), (512, 1), (512, 2)]
for (base, scale) in specs {
    let px = CGFloat(base * scale)
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    writePNG(makeIconTile(size: px), to: "\(iconset)/\(name)", pixelSize: px)
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
task.launch()
task.waitUntilExit()
if task.terminationStatus == 0 {
    try? FileManager.default.removeItem(atPath: iconset)
    print("wrote AppIcon.icns")
} else {
    writePNG(makeIconTile(size: 1024), to: "\(outDir)/AppIcon.png", pixelSize: 1024)
    print("iconutil missing — wrote AppIcon.png (1024) instead")
}
