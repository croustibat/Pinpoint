#!/usr/bin/env swift
// Generates the Pinpoint app icon at every required size, matching the design
// system (§01): a graphite squircle with a faint targeting reticle and a
// vermillon teardrop pin carrying a white "1".
//
// Usage: swift generate_icon.swift <output-dir>

import AppKit

// MARK: - Palette (design system)
let vermillon = NSColor(srgbRed: 255/255, green: 77/255, blue: 46/255, alpha: 1)
let vermillonLight = NSColor(srgbRed: 255/255, green: 106/255, blue: 69/255, alpha: 1)
let vermillonDark = NSColor(srgbRed: 232/255, green: 53/255, blue: 15/255, alpha: 1)
let graphiteTop = NSColor(srgbRed: 0.235, green: 0.235, blue: 0.255, alpha: 1)
let graphiteBottom = NSColor(srgbRed: 0.105, green: 0.105, blue: 0.118, alpha: 1)

func draw(_ ctx: CGContext, _ n: CGFloat) {
    let rgb = CGColorSpaceCreateDeviceRGB()

    // Squircle background (inset to leave the standard transparent margin).
    let margin = n * 0.092
    let rect = CGRect(x: margin, y: margin, width: n - 2 * margin, height: n - 2 * margin)
    let squircle = CGPath(roundedRect: rect,
                          cornerWidth: rect.width * 0.2237,
                          cornerHeight: rect.height * 0.2237,
                          transform: nil)

    // Drop shadow + solid base (casts the shadow).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -n * 0.015),
                  blur: n * 0.04,
                  color: NSColor.black.withAlphaComponent(0.40).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(graphiteBottom.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Graphite gradient, clipped to the squircle.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let graphite = CGGradient(colorsSpace: rgb,
                              colors: [graphiteTop.cgColor, graphiteBottom.cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(graphite,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY),
                           options: [])

    drawReticle(ctx, rect, n)
    drawPin(ctx, rect, n, rgb)
    ctx.restoreGState()
}

func drawReticle(_ ctx: CGContext, _ rect: CGRect, _ n: CGFloat) {
    let c = CGPoint(x: rect.midX, y: rect.midY)
    ctx.saveGState()
    ctx.setLineWidth(max(1, rect.width * 0.006))

    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.09).cgColor)
    for fraction in [0.20, 0.32, 0.44] {
        let r = rect.width * CGFloat(fraction)
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    ctx.strokePath()

    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.13).cgColor)
    let inner = rect.width * 0.40, outer = rect.width * 0.47
    for deg in stride(from: 0.0, to: 360.0, by: 90.0) {
        let a = CGFloat(deg) * .pi / 180
        ctx.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
    }
    ctx.strokePath()
    ctx.restoreGState()
}

func drawPin(_ ctx: CGContext, _ rect: CGRect, _ n: CGFloat, _ rgb: CGColorSpace) {
    let r = rect.width * 0.205
    let c = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.085)
    let tip = CGPoint(x: c.x, y: c.y - r * 2.35)
    let baseY = c.y - r * 0.55
    let baseLeft = CGPoint(x: c.x - r * 0.72, y: baseY)
    let baseRight = CGPoint(x: c.x + r * 0.72, y: baseY)

    let pin = CGMutablePath()
    pin.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    pin.move(to: baseLeft)
    pin.addLine(to: tip)
    pin.addLine(to: baseRight)
    pin.closeSubpath()

    // Shadow + base fill.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -n * 0.012),
                  blur: n * 0.03,
                  color: NSColor.black.withAlphaComponent(0.40).cgColor)
    ctx.addPath(pin)
    ctx.setFillColor(vermillon.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Vermillon gradient, clipped to the pin.
    ctx.saveGState()
    ctx.addPath(pin)
    ctx.clip()
    let grad = CGGradient(colorsSpace: rgb,
                          colors: [vermillonLight.cgColor, vermillonDark.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: c.x, y: c.y + r),
                           end: CGPoint(x: c.x, y: tip.y),
                           options: [])
    ctx.restoreGState()

    // White "1" centred in the bulb.
    let label = "1" as NSString
    let font = NSFont.systemFont(ofSize: r * 1.45, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let size = label.size(withAttributes: attrs)
    label.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2), withAttributes: attrs)
}

func makeIcon(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    draw(gc.cgContext, CGFloat(pixels))
    gc.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Main
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: generate_icon.swift <output-dir>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = CommandLine.arguments[1]
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let url = URL(fileURLWithPath: "\(outDir)/icon_\(pixels).png")
    try! makeIcon(pixels).write(to: url)
    print("wrote \(url.lastPathComponent)")
}
