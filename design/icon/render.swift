// Renders the "{$}" app icon and builds app/Resources/AppIcon.icns.
// Usage: swift design/icon/render.swift
import AppKit

let glyph = "{$}"
let background = rgb(0x3CCB9A)  // mint
let foreground = NSColor.white

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repo = here.deletingLastPathComponent().deletingLastPathComponent()

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

/// One icon at `size` px, on Apple's macOS icon grid
/// (1024 canvas, 824 rounded-square body, ~185 corner radius, soft drop shadow).
func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = bitmap(Int(size), Int(size))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    background.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Chunky rounded type: SF Pro Rounded, black weight.
    var font = NSFont.systemFont(ofSize: 400 * s, weight: .black)
    if let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: 400 * s) ?? font }
    let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: foreground, .kern: -8 * s])
    // Fit the ink to ~72% of the body width, then center it optically on its real bounds.
    let ink = text.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
    let scale = min((824 * 0.72 * s) / ink.width, (824 * 0.62 * s) / ink.height)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: body.midX, y: body.midY)
    ctx.scaleBy(x: scale, y: scale)
    text.draw(at: NSPoint(x: -ink.midX, y: -ink.midY))
    ctx.restoreGState()

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
