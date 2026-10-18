// Renders the Pulsar logo (1024px) and the DMG background. Usage: swift make_assets.swift <outdir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let pink = CGColor(red: 1.0, green: 0.18, blue: 0.53, alpha: 1)
let violet = CGColor(red: 0.48, green: 0.18, blue: 0.97, alpha: 1)
let cyan = CGColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func render(_ w: Int, _ h: Int, _ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

/// Pointer arrow with its tip at the origin, pointing up-left (y-up coordinates).
func cursorPath(scale s: CGFloat, at tip: CGPoint) -> CGPath {
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, -0.36), (0.085, -0.275), (0.145, -0.41), (0.205, -0.385),
                                     (0.145, -0.255), (0.26, -0.255)]
    let p = CGMutablePath()
    p.addLines(between: pts.map { CGPoint(x: tip.x + $0.0 * s, y: tip.y + $0.1 * s) })
    p.closeSubpath()
    return p
}

func drawLogo(_ c: CGContext, size S: CGFloat) {
    // macOS icon grid: 824px body inside 1024 canvas.
    let inset = S * 0.098
    let body = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let squircle = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)

    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -S * 0.01), blur: S * 0.03, color: CGColor(gray: 0, alpha: 0.5))
    c.addPath(squircle); c.setFillColor(CGColor(gray: 0.05, alpha: 1)); c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(squircle); c.clip()
    c.drawLinearGradient(gradient([CGColor(red: 0.13, green: 0.05, blue: 0.24, alpha: 1), CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)]),
                         start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    let center = CGPoint(x: S * 0.44, y: S * 0.56)
    c.drawRadialGradient(gradient([pink.copy(alpha: 0.55)!, violet.copy(alpha: 0.18)!, violet.copy(alpha: 0)!]),
                         startCenter: center, startRadius: 0, endCenter: center, endRadius: S * 0.42, options: [])

    // Pulse rings: gradient-stroked arcs that fade outward.
    for (i, r) in [0.13, 0.23, 0.33].enumerated() {
        let ring = CGMutablePath()
        ring.addArc(center: center, radius: S * r, startAngle: .pi * 0.62, endAngle: .pi * 2.12, clockwise: false)
        c.saveGState()
        c.setLineWidth(S * (0.034 - Double(i) * 0.007))
        c.setLineCap(.round)
        c.addPath(ring); c.replacePathWithStrokedPath(); c.clip()
        c.setAlpha(1 - Double(i) * 0.28)
        c.drawLinearGradient(gradient([pink, violet, cyan]), start: CGPoint(x: body.minX, y: body.maxY),
                             end: CGPoint(x: body.maxX, y: body.minY), options: [])
        c.restoreGState()
    }

    // Cursor with neon glow.
    let arrow = cursorPath(scale: S * 0.62, at: center)
    c.saveGState()
    c.setShadow(offset: .zero, blur: S * 0.05, color: pink)
    c.addPath(arrow); c.setFillColor(.white); c.fillPath()
    c.restoreGState()
    c.addPath(arrow); c.setStrokeColor(CGColor(gray: 0.08, alpha: 1)); c.setLineWidth(S * 0.012); c.setLineJoin(.round); c.strokePath()

    // Glass highlight.
    c.drawLinearGradient(gradient([CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)]),
                         start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    c.restoreGState()

    c.addPath(squircle); c.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); c.setLineWidth(S * 0.004); c.strokePath()
}

render(1024, 1024, "icon_1024.png") { drawLogo($0, size: 1024) }

// DMG background (rendered @2x: 1320x800 for a 660x400 window).
render(1320, 800, "dmg_bg.png") { c in
    c.scaleBy(x: 2, y: 2)
    c.drawLinearGradient(gradient([CGColor(red: 0.09, green: 0.04, blue: 0.17, alpha: 1), CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)]),
                         start: CGPoint(x: 0, y: 400), end: CGPoint(x: 0, y: 0), options: [])
    c.drawRadialGradient(gradient([pink.copy(alpha: 0.25)!, violet.copy(alpha: 0)!]), startCenter: CGPoint(x: 330, y: 200),
                         startRadius: 0, endCenter: CGPoint(x: 330, y: 200), endRadius: 330, options: [])
    // Arrow from app slot (x 170) to Applications slot (x 490); Finder icon centers are at y=190 from top.
    let y: CGFloat = 400 - 190
    let shaft = CGMutablePath()
    shaft.move(to: CGPoint(x: 265, y: y)); shaft.addLine(to: CGPoint(x: 385, y: y))
    shaft.move(to: CGPoint(x: 365, y: y + 16)); shaft.addLine(to: CGPoint(x: 387, y: y)); shaft.addLine(to: CGPoint(x: 365, y: y - 16))
    c.saveGState()
    c.setLineWidth(6); c.setLineCap(.round); c.setLineJoin(.round)
    c.addPath(shaft); c.replacePathWithStrokedPath(); c.clip()
    c.drawLinearGradient(gradient([pink, violet, cyan]), start: CGPoint(x: 265, y: 0), end: CGPoint(x: 390, y: 0), options: [])
    c.restoreGState()

    let title = NSAttributedString(string: "Drag Pulsar into Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor(white: 1, alpha: 0.75),
    ])
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    title.draw(at: NSPoint(x: 330 - title.size().width / 2, y: 70))
}
