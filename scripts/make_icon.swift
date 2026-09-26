// Renders the mAhgic app icon into an .iconset folder.
// usage: swift scripts/make_icon.swift <out.iconset> [preview.png]
//
// Motif: a chocolate-chip cookie with a bite taken out, sitting inside a green
// battery-charge ring, with a lightning bolt in the middle.
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Deterministic pseudo-random numbers so every size renders the same icon.
struct RNG {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

let center = CGPoint(x: 512, y: 500)
let cookieRadius: CGFloat = 238

/// Slightly wobbly circle so the cookie looks baked, not drawn with a compass.
func blob(center c: CGPoint, radius r: CGFloat, wobble: CGFloat, seed: UInt64, points n: Int = 48) -> NSBezierPath {
    var rng = RNG(state: seed)
    let offsets = (0..<n).map { _ in (rng.next() - 0.5) * 2 * wobble }
    let pts = (0..<n).map { i -> CGPoint in
        let a = CGFloat(i) / CGFloat(n) * 2 * .pi
        let rr = r + offsets[i]
        return CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
    }
    let path = NSBezierPath()
    for i in 0..<n {
        let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
        if i == 0 { path.move(to: p1) }
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
    }
    path.close()
    return path
}

func circle(_ c: CGPoint, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

// Bite: three overlapping circles on the upper right edge of the cookie.
let biteAngle: CGFloat = 38 * .pi / 180
let biteCenters: [(CGFloat, CGFloat)] = [(-13, 64), (0, 70), (13, 64)]   // (degrees offset, radius)
func biteCircles() -> [(CGPoint, CGFloat)] {
    biteCenters.map { off, r in
        let a = biteAngle + off * .pi / 180
        let d = cookieRadius + 10
        return (CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d), r)
    }
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
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    rgb(0x1B2336).setFill()
    bg.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0x121826), rgb(0x2A3552)])!.draw(in: bg, angle: 90)
    // Soft glow behind the cookie
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    NSGradient(colors: [rgb(0x57D68A, 0.22), rgb(0x57D68A, 0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: 400, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // --- Charge ring (80 %) --------------------------------------------------
    let ringRadius: CGFloat = 318
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: ringRadius, startAngle: 0, endAngle: 360)
    track.lineWidth = 40
    rgb(0xFFFFFF, 0.10).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: ringRadius, startAngle: 90, endAngle: 90 - 0.8 * 360, clockwise: true)
    arc.lineWidth = 40
    arc.lineCapStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let ringGlow = NSShadow()
    ringGlow.shadowColor = rgb(0x4CD37E, 0.55)
    ringGlow.shadowBlurRadius = 18
    ringGlow.set()
    rgb(0x49C874).setStroke()
    arc.stroke()
    NSGraphicsContext.restoreGraphicsState()
    // highlight gradient along the ring
    NSGraphicsContext.saveGraphicsState()
    let arcOutline = NSBezierPath(cgPath: arc.cgPath.copy(strokingWithWidth: 40, lineCap: .round, lineJoin: .round, miterLimit: 10))
    arcOutline.addClip()
    NSGradient(colors: [rgb(0x8AF0A8), rgb(0x2FAE5E)])!.draw(in: arcOutline, angle: -60)
    NSGraphicsContext.restoreGraphicsState()

    // --- Cookie ---------------------------------------------------------------
    let cookie = blob(center: center, radius: cookieRadius, wobble: 5, seed: 7, points: 22)
    // The cookie is drawn into its own transparency layer so the bite can be erased
    // (destination-out) without touching the background; the drop shadow is applied
    // to the finished, bitten cookie.
    NSGraphicsContext.saveGraphicsState()
    let cookieShadow = NSShadow()
    cookieShadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    cookieShadow.shadowBlurRadius = 26
    cookieShadow.shadowOffset = NSSize(width: 0, height: -12)
    cookieShadow.set()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    rgb(0xC98A3E).setFill()
    cookie.fill()

    NSGraphicsContext.saveGraphicsState()
    cookie.addClip()
    // baked body: light top-left, darker rim
    NSGradient(colors: [rgb(0xF2C27A), rgb(0xDDA05A), rgb(0xB8762F)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!
        .draw(fromCenter: CGPoint(x: center.x - 60, y: center.y + 70), radius: 0,
              toCenter: center, radius: cookieRadius + 10, options: [])
    // crumbs / texture
    var rng = RNG(state: 42)
    for _ in 0..<140 {
        let a = rng.next() * 2 * .pi, d = sqrt(rng.next()) * (cookieRadius - 10)
        let p = CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d)
        let r = 3 + rng.next() * 6
        (rng.next() > 0.5 ? rgb(0xFFE0A8, 0.35) : rgb(0x9A5E22, 0.30)).setFill()
        circle(p, r).fill()
    }
    // rim darkening
    let rim = blob(center: center, radius: cookieRadius - 4, wobble: 5, seed: 7, points: 22)
    rim.lineWidth = 14
    rgb(0x9C6127, 0.45).setStroke()
    rim.stroke()

    // chocolate chips (keep the middle free for the bolt)
    let chips: [(CGFloat, CGFloat, CGFloat)] = [   // (angle°, distance, size)
        (150, 160, 32), (205, 178, 30), (245, 150, 34), (290, 190, 27),
        (330, 150, 30), (112, 190, 26), (0, 185, 22), (175, 205, 18),
    ]
    for (i, chip) in chips.enumerated() {
        let a = chip.0 * .pi / 180
        let p = CGPoint(x: center.x + cos(a) * chip.1, y: center.y + sin(a) * chip.1)
        let shape = blob(center: p, radius: chip.2, wobble: chip.2 * 0.22, seed: UInt64(100 + i), points: 9)
        NSGraphicsContext.saveGraphicsState()
        let chipShadow = NSShadow()
        chipShadow.shadowColor = rgb(0x6B3A12, 0.6)
        chipShadow.shadowBlurRadius = 4
        chipShadow.shadowOffset = NSSize(width: 0, height: -3)
        chipShadow.set()
        rgb(0x3B2012).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        // glossy highlight
        rgb(0x8A5A3A, 0.8).setFill()
        circle(CGPoint(x: p.x - chip.2 * 0.3, y: p.y + chip.2 * 0.3), chip.2 * 0.22).fill()
    }
    NSGraphicsContext.restoreGraphicsState()   // cookie clip

    // bite edge: darker baked crumb line around the bite
    for (c, r) in biteCircles() {
        NSGraphicsContext.saveGraphicsState()
        cookie.addClip()
        let edge = circle(c, r + 3)
        edge.lineWidth = 10
        rgb(0xA8692A, 0.9).setStroke()
        edge.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
    ctx.setBlendMode(.destinationOut)
    NSColor.black.setFill()
    for (c, r) in biteCircles() { circle(c, r).fill() }
    ctx.setBlendMode(.normal)
    ctx.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()   // cookie shadow

    // --- Lightning bolt -------------------------------------------------------
    let bolt = NSBezierPath()
    let o = CGPoint(x: center.x, y: center.y)
    bolt.move(to: CGPoint(x: o.x + 38, y: o.y + 150))
    bolt.line(to: CGPoint(x: o.x - 92, y: o.y - 12))
    bolt.line(to: CGPoint(x: o.x - 6, y: o.y - 12))
    bolt.line(to: CGPoint(x: o.x - 40, y: o.y - 150))
    bolt.line(to: CGPoint(x: o.x + 94, y: o.y + 28))
    bolt.line(to: CGPoint(x: o.x + 10, y: o.y + 28))
    bolt.close()
    bolt.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let boltShadow = NSShadow()
    boltShadow.shadowColor = rgb(0x3B2012, 0.7)
    boltShadow.shadowBlurRadius = 12
    boltShadow.shadowOffset = NSSize(width: 0, height: -5)
    boltShadow.set()
    rgb(0xFFFFFF).setFill()
    bolt.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    bolt.addClip()
    NSGradient(colors: [rgb(0xFFFFFF), rgb(0xFFF1C9)])!.draw(in: bolt, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    bolt.lineWidth = 9
    rgb(0x5A3316, 0.85).setStroke()
    bolt.stroke()

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
