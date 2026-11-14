// Draws four app icon style concepts into design/icon/concepts.png.
// Usage: swift design/icon/concepts.swift
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: bottom, ending: top)!.draw(in: path, angle: 90)
}

func withShadow(_ color: NSColor, blur: CGFloat, dy: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = color; sh.shadowBlurRadius = blur; sh.shadowOffset = NSSize(width: 0, height: dy)
    sh.set(); draw()
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ s: String, font: NSFont, color: NSColor, center: NSPoint) {
    let t = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let ink = t.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
    t.draw(at: NSPoint(x: center.x - ink.midX, y: center.y - ink.midY))
}

func rounded(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return f.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? f
}

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

/// Draws the rounded-square body with the standard soft drop shadow, then the concept inside it (1024 space).
func icon(size: CGFloat, top: NSColor, bottom: NSColor, _ content: () -> Void) -> NSBitmapImageRep {
    let rep = bitmap(Int(size), Int(size))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)
    withShadow(.black.withAlphaComponent(0.28), blur: 24, dy: -10) { rgb(0x000000).setFill(); bodyPath.fill() }
    gradient(bodyPath, top, bottom)
    NSGraphicsContext.saveGraphicsState(); bodyPath.addClip(); content(); NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let mint = rgb(0x3CCB9A), mintLight = rgb(0x7BF0C4)

// 1. Terminal: dark window, traffic lights, mint "$" prompt with a block cursor.
func terminal(_ size: CGFloat) -> NSBitmapImageRep {
    icon(size: size, top: rgb(0x343A44), bottom: rgb(0x15171C)) {
        rgb(0xFFFFFF, 0.06).setFill(); NSRect(x: 100, y: 770, width: 824, height: 154).fill()
        for (i, c) in [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: 190 + CGFloat(i) * 70, y: 822, width: 44, height: 44)).fill()
        }
        withShadow(mint.withAlphaComponent(0.6), blur: 40, dy: 0) {
            text("$", font: .monospacedSystemFont(ofSize: 380, weight: .heavy), color: mint, center: NSPoint(x: 350, y: 430))
            mint.setFill(); NSBezierPath(roundedRect: NSRect(x: 560, y: 285, width: 190, height: 52), xRadius: 14, yRadius: 14).fill()
        }
    }
}

// 2. Coin: shiny gold coin with an embossed "$", on mint.
func coin(_ size: CGFloat) -> NSBitmapImageRep {
    icon(size: size, top: rgb(0x6FE6BA), bottom: rgb(0x1FAE7E)) {
        let c = NSRect(x: 512 - 285, y: 500 - 285, width: 570, height: 570)
        withShadow(.black.withAlphaComponent(0.3), blur: 30, dy: -18) { rgb(0xE59A12).setFill(); NSBezierPath(ovalIn: c).fill() }
        NSGradient(colors: [rgb(0xFFE89A), rgb(0xFFC93C), rgb(0xF0A21C)])!.draw(in: NSBezierPath(ovalIn: c), angle: -60)
        let ring = NSBezierPath(ovalIn: c.insetBy(dx: 52, dy: 52)); ring.lineWidth = 16; rgb(0xD98A0E, 0.55).setStroke(); ring.stroke()
        text("$", font: rounded(380, weight: .black), color: rgb(0xFFF4C7, 0.9), center: NSPoint(x: 506, y: 506))
        text("$", font: rounded(380, weight: .black), color: rgb(0xD58508), center: NSPoint(x: 512, y: 500))
    }
}

// 3. Chart: three rising mint bars on navy, a small gold coin above the tallest.
func chart(_ size: CGFloat) -> NSBitmapImageRep {
    icon(size: size, top: rgb(0x2C3757), bottom: rgb(0x111726)) {
        let heights: [CGFloat] = [230, 360, 500], w: CGFloat = 138, gap: CGFloat = 48, x0: CGFloat = 512 - (3 * w + 2 * gap) / 2
        for (i, h) in heights.enumerated() {
            let r = NSRect(x: x0 + CGFloat(i) * (w + gap), y: 210, width: w, height: h)
            let p = NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34)
            withShadow(mint.withAlphaComponent(0.45), blur: 30, dy: 0) { mint.setFill(); p.fill() }
            NSGradient(starting: mint.withAlphaComponent(i == 2 ? 1 : 0.75), ending: mintLight)!.draw(in: p, angle: 90)
        }
        let cx = x0 + 2 * (w + gap) + w / 2
        let cr = NSRect(x: cx - 62, y: 210 + 500 + 34, width: 124, height: 124)
        NSGradient(colors: [rgb(0xFFE89A), rgb(0xF5B32A)])!.draw(in: NSBezierPath(ovalIn: cr), angle: -60)
        text("$", font: rounded(84, weight: .black), color: rgb(0xC97A0A), center: NSPoint(x: cr.midX, y: cr.midY))
    }
}

// 4. Receipt: tilted white receipt with zigzag bottom, gray lines and a mint "$" total.
func receipt(_ size: CGFloat) -> NSBitmapImageRep {
    icon(size: size, top: rgb(0x6FE6BA), bottom: rgb(0x1FAE7E)) {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState(); ctx.translateBy(x: 512, y: 512); ctx.rotate(by: -0.10); ctx.translateBy(x: -512, y: -512)
        let left: CGFloat = 300, right: CGFloat = 724, top: CGFloat = 830, bottom: CGFloat = 200, teeth = 7
        let p = NSBezierPath()
        p.move(to: NSPoint(x: left, y: bottom)); p.line(to: NSPoint(x: left, y: top - 30))
        p.appendArc(withCenter: NSPoint(x: left + 30, y: top - 30), radius: 30, startAngle: 180, endAngle: 90, clockwise: true)
        p.line(to: NSPoint(x: right - 30, y: top))
        p.appendArc(withCenter: NSPoint(x: right - 30, y: top - 30), radius: 30, startAngle: 90, endAngle: 0, clockwise: true)
        p.line(to: NSPoint(x: right, y: bottom))
        let tw = (right - left) / CGFloat(teeth)
        for i in 0..<teeth {
            let x = right - CGFloat(i) * tw
            p.line(to: NSPoint(x: x - tw / 2, y: bottom + 36)); p.line(to: NSPoint(x: x - tw, y: bottom))
        }
        p.close()
        withShadow(.black.withAlphaComponent(0.25), blur: 30, dy: -16) { NSColor.white.setFill(); p.fill() }
        rgb(0xD5DBE3).setFill()
        for (i, w) in [260, 200, 240, 170].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: left + 50, y: top - 110 - CGFloat(i) * 70, width: CGFloat(w), height: 26), xRadius: 13, yRadius: 13).fill()
        }
        rgb(0xE6EAF0).setFill(); NSRect(x: left + 50, y: 395, width: right - left - 100, height: 8).fill()
        text("$", font: rounded(230, weight: .black), color: mint, center: NSPoint(x: right - 130, y: 300))
        rgb(0xD5DBE3).setFill(); NSBezierPath(roundedRect: NSRect(x: left + 50, y: 290, width: 140, height: 26), xRadius: 13, yRadius: 13).fill()
        ctx.restoreGState()
    }
}

let concepts: [(String, (CGFloat) -> NSBitmapImageRep)] = [
    ("1. Terminal", terminal), ("2. Coin", coin), ("3. Chart", chart), ("4. Receipt", receipt),
]

// Sheet: each concept at 300px with 64px and 32px versions under it, on light and dark halves.
let cell: CGFloat = 360, sheetW = Int(cell) * concepts.count, sheetH = 2 * 470
let sheet = bitmap(sheetW, sheetH)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
for (row, bg) in [rgb(0xF5F5F7), rgb(0x1E1E20)].enumerated() {
    let y0 = CGFloat(sheetH) - CGFloat(row + 1) * 470
    bg.setFill(); NSRect(x: 0, y: y0, width: CGFloat(sheetW), height: 470).fill()
    for (i, (label, draw)) in concepts.enumerated() {
        let x = CGFloat(i) * cell
        for (sz, rect) in [(CGFloat(300), NSRect(x: x + 30, y: y0 + 140, width: 300, height: 300)),
                           (64, NSRect(x: x + 30, y: y0 + 50, width: 64, height: 64)),
                           (32, NSRect(x: x + 114, y: y0 + 66, width: 32, height: 32))] {
            let img = NSImage(size: rect.size); img.addRepresentation(draw(sz * 2)); img.draw(in: rect)
        }
        if row == 0 {
            NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.darkGray])
                .draw(at: NSPoint(x: x + 170, y: y0 + 70))
        }
    }
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: here.appendingPathComponent("concepts.png"))
print("Wrote design/icon/concepts.png")
