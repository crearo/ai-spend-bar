// Renders the app icon (a dark terminal window with a mint "$_" prompt) and builds
// app/Resources/AppIcon.icns. Other styles we tried live in concepts.swift.
// Usage: swift design/icon/render.swift
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let mint = rgb(0x3CCB9A)
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repo = here.deletingLastPathComponent().deletingLastPathComponent()

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func withShadow(_ color: NSColor, blur: CGFloat, dy: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = color; sh.shadowBlurRadius = blur; sh.shadowOffset = NSSize(width: 0, height: dy)
    sh.set(); draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// The icon at `size` px. Drawn in a 1024 space on Apple's macOS icon grid
/// (824 rounded-square body, ~185 corner radius, soft drop shadow).
func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = bitmap(Int(size), Int(size))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: size / 1024, y: size / 1024)

    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    withShadow(.black.withAlphaComponent(0.28), blur: 24, dy: -10) { NSColor.black.setFill(); body.fill() }
    NSGradient(starting: rgb(0x15171C), ending: rgb(0x343A44))!.draw(in: body, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    // Title bar with the three window buttons.
    rgb(0xFFFFFF, 0.06).setFill(); NSRect(x: 100, y: 770, width: 824, height: 154).fill()
    for (i, c) in [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)].enumerated() {
        c.setFill(); NSBezierPath(ovalIn: NSRect(x: 190 + CGFloat(i) * 70, y: 822, width: 44, height: 44)).fill()
    }
    // Prompt "$" and a cursor, with a soft glow.
    withShadow(mint.withAlphaComponent(0.6), blur: 40, dy: 0) {
        let dollar = NSAttributedString(string: "$", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 380, weight: .heavy), .foregroundColor: mint])
        let ink = dollar.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
        dollar.draw(at: NSPoint(x: 350 - ink.midX, y: 430 - ink.midY))
        mint.setFill()
        NSBezierPath(roundedRect: NSRect(x: 560, y: 285, width: 190, height: 52), xRadius: 14, yRadius: 14).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// 1. Full-size preview.
write(renderIcon(size: 1024), here.appendingPathComponent("icon.png"))

// 2. Iconset -> app/Resources/AppIcon.icns (each size drawn natively, not downscaled).
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    write(renderIcon(size: CGFloat(pt)), iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    write(renderIcon(size: CGFloat(pt * 2)), iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let resources = repo.appendingPathComponent("app/Resources")
try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
precondition(p.terminationStatus == 0, "iconutil failed")

// 3. Size sheet: 256, 64, 32, 16 px on light and dark.
let sizes: [CGFloat] = [256, 64, 32, 16]
let colW: CGFloat = 660, rowH: CGFloat = 300, pad: CGFloat = 22
let sheet = bitmap(Int(colW * 2), Int(rowH))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
for (col, bg) in [rgb(0xF5F5F7), rgb(0x1E1E20)].enumerated() {
    bg.setFill(); NSRect(x: CGFloat(col) * colW, y: 0, width: colW, height: rowH).fill()
    var x = CGFloat(col) * colW + pad
    for sz in sizes {
        let img = NSImage(size: NSSize(width: sz, height: sz)); img.addRepresentation(renderIcon(size: sz * 2))
        img.draw(in: NSRect(x: x, y: (rowH - sz) / 2, width: sz, height: sz))
        x += sz + pad
    }
}
NSGraphicsContext.restoreGraphicsState()
write(sheet, here.appendingPathComponent("sizes.png"))
print("Wrote design/icon/icon.png, design/icon/sizes.png, app/Resources/AppIcon.icns")
