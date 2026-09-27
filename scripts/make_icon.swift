// Renders the mAhgic app icon into an .iconset folder.
// usage: swift scripts/make_icon.swift <out.iconset> [preview.png]
//
// Motif: a battery (82 % charged) with a heartbeat line across it – "battery health" –
// plus a sparkle for the magic, on the battery-pack yellow of the website.
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let ink = rgb(0x17171B)
let cream = rgb(0xFFFDF6)

/// Four-pointed sparkle centred at `c`.
func sparkle(_ c: CGPoint, _ r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let k = r * 0.22
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.curve(to: CGPoint(x: c.x + r, y: c.y), controlPoint1: CGPoint(x: c.x + k, y: c.y + k), controlPoint2: CGPoint(x: c.x + k, y: c.y + k))
    p.curve(to: CGPoint(x: c.x, y: c.y - r), controlPoint1: CGPoint(x: c.x + k, y: c.y - k), controlPoint2: CGPoint(x: c.x + k, y: c.y - k))
    p.curve(to: CGPoint(x: c.x - r, y: c.y), controlPoint1: CGPoint(x: c.x - k, y: c.y - k), controlPoint2: CGPoint(x: c.x - k, y: c.y - k))
    p.curve(to: CGPoint(x: c.x, y: c.y + r), controlPoint1: CGPoint(x: c.x - k, y: c.y + k), controlPoint2: CGPoint(x: c.x - k, y: c.y + k))
    p.close()
    return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // --- Background squircle -------------------------------------------------
    let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    rgb(0xFFC93A).setFill()
    bg.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0xFFB020), rgb(0xFFD84A), rgb(0xFFE17A)], atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
        .draw(in: bg, angle: 90)

    // Everything in front of the background sits a little lower to balance the sparkles on top.
    ctx.translateBy(x: 0, y: -52)

    // --- Battery -------------------------------------------------------------
    let body = NSRect(x: 196, y: 348, width: 560, height: 318)
    let outline = NSBezierPath(roundedRect: body, xRadius: 70, yRadius: 70)
    NSGraphicsContext.saveGraphicsState()
    let batteryShadow = NSShadow()
    batteryShadow.shadowColor = rgb(0x8A5200, 0.35)
    batteryShadow.shadowBlurRadius = 18
    batteryShadow.shadowOffset = NSSize(width: 0, height: -12)
    batteryShadow.set()
    cream.setFill()
    outline.fill()
    NSGraphicsContext.restoreGraphicsState()
    outline.lineWidth = 40
    ink.setStroke()
    outline.stroke()
    // + terminal
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: 776, y: 440, width: 52, height: 134), xRadius: 22, yRadius: 22).fill()

    // Charge level (82 %)
    let inner = body.insetBy(dx: 46, dy: 46)
    let level = NSRect(x: inner.minX, y: inner.minY, width: inner.width * 0.82, height: inner.height)
    NSGradient(colors: [rgb(0x3FE081), rgb(0x22B45E)])!
        .draw(in: NSBezierPath(roundedRect: level, xRadius: 30, yRadius: 30), angle: -90)

    // Heartbeat line across the battery
    let midY = body.midY
    let pulse = NSBezierPath()
    pulse.move(to: CGPoint(x: inner.minX + 8, y: midY))
    pulse.line(to: CGPoint(x: 356, y: midY))
    pulse.line(to: CGPoint(x: 398, y: midY + 58))
    pulse.line(to: CGPoint(x: 452, y: midY - 104))
    pulse.line(to: CGPoint(x: 512, y: midY + 118))
    pulse.line(to: CGPoint(x: 560, y: midY - 30))
    pulse.line(to: CGPoint(x: 588, y: midY))
    pulse.line(to: CGPoint(x: inner.maxX - 8, y: midY))
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    // dark halo so the line reads on green and cream alike
    pulse.lineWidth = 46
    ink.setStroke()
    pulse.stroke()
    pulse.lineWidth = 22
    cream.setStroke()
    pulse.stroke()

    // --- Magic sparkles ------------------------------------------------------
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = rgb(0xFFFFFF, 0.9)
    glow.shadowBlurRadius = 16
    glow.set()
    cream.setFill()
    sparkle(CGPoint(x: 760, y: 766), 88).fill()
    sparkle(CGPoint(x: 648, y: 820), 38).fill()
    NSGraphicsContext.restoreGraphicsState()
    ink.setStroke()
    let big = sparkle(CGPoint(x: 760, y: 766), 88)
    big.lineWidth = 12
    big.lineJoinStyle = .round
    big.stroke()
    let small = sparkle(CGPoint(x: 648, y: 820), 38)
    small.lineWidth = 9
    small.lineJoinStyle = .round
    small.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: outDir.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: outDir.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
if CommandLine.arguments.count > 2 {
    try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
