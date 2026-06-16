import AppKit

enum Exporter {
    /// Renders the base capture with markups (arrows/rectangles) and numbered
    /// pins drawn on top, at full image resolution. Markups are drawn first so
    /// numbered pins stay legible above them.
    static func annotatedImage(base: NSImage, pins: [Pin], shapes: [Markup], style: PinStyle) -> NSImage {
        let size = base.size
        let result = NSImage(size: size)
        result.lockFocus()

        base.draw(in: NSRect(origin: .zero, size: size),
                  from: .zero, operation: .copy, fraction: 1.0)

        let lineWidth = max(3, size.width * 0.004)
        for shape in shapes {
            drawMarkup(shape, in: size, lineWidth: lineWidth)
        }

        let radius = max(16, size.width * 0.014)
        for pin in pins {
            // Pin position is the marked point (top-left origin); NSImage
            // drawing is bottom-left, so flip y.
            let anchor = CGPoint(
                x: pin.position.x * size.width,
                y: (1 - pin.position.y) * size.height
            )
            drawMarker(number: pin.number, anchor: anchor, radius: radius, style: style)
        }

        result.unlockFocus()
        return result
    }

    private static func drawMarkup(_ shape: Markup, in size: CGSize, lineWidth: CGFloat) {
        NSColor.pinpointVermillon.setStroke()

        // Normalized (top-left origin) → image space (bottom-left origin).
        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
        }

        switch shape.kind {
        case .rectangle:
            let r = shape.rect
            let rect = NSRect(
                x: r.minX * size.width,
                y: (1 - r.maxY) * size.height,
                width: r.width * size.width,
                height: r.height * size.height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: lineWidth, yRadius: lineWidth)
            path.lineWidth = lineWidth
            path.stroke()

        case .arrow:
            let start = px(shape.start)
            let end = px(shape.end)
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: start)
            path.line(to: end)

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(14, size.width * 0.018)
            let spread = CGFloat.pi / 6.5

            let leftAngle = angle - spread
            let rightAngle = angle + spread
            let left = CGPoint(x: end.x - headLength * cos(leftAngle),
                               y: end.y - headLength * sin(leftAngle))
            let right = CGPoint(x: end.x - headLength * cos(rightAngle),
                                y: end.y - headLength * sin(rightAngle))
            path.move(to: end)
            path.line(to: left)
            path.move(to: end)
            path.line(to: right)
            path.stroke()
        }
    }

    /// Draws a numbered marker at `anchor` (image space) in the chosen style.
    /// `anchor` is the marker centre for disc/outline and the tip for pointer —
    /// matching the on-screen `PinMarker` so the export looks identical.
    private static func drawMarker(number: Int, anchor: CGPoint, radius: CGFloat, style: PinStyle) {
        let vermillon = NSColor.pinpointVermillon
        let ringWidth = max(2, radius * 0.16)

        switch style {
        case .disc:
            let rect = NSRect(x: anchor.x - radius, y: anchor.y - radius, width: radius * 2, height: radius * 2)
            vermillon.setFill()
            let circle = NSBezierPath(ovalIn: rect)
            circle.fill()
            NSColor.white.setStroke()
            circle.lineWidth = ringWidth
            circle.stroke()
            drawNumber(number, center: anchor, radius: radius, color: .white)

        case .outline:
            let rect = NSRect(x: anchor.x - radius, y: anchor.y - radius, width: radius * 2, height: radius * 2)
            let collar = NSBezierPath(ovalIn: rect)
            NSColor.white.setStroke()
            collar.lineWidth = ringWidth * 1.7
            collar.stroke()
            let ring = NSBezierPath(ovalIn: rect)
            vermillon.setStroke()
            ring.lineWidth = ringWidth
            ring.stroke()
            drawNumber(number, center: anchor, radius: radius, color: vermillon)

        case .pointer:
            // Tip at the anchor; head above it (image space y grows upward).
            let headCenter = CGPoint(x: anchor.x, y: anchor.y + radius * 2.0)
            let baseY = headCenter.y - radius * 0.55
            let halfWidth = radius * 0.7

            let stem = NSBezierPath()
            stem.move(to: CGPoint(x: headCenter.x - halfWidth, y: baseY))
            stem.line(to: anchor)
            stem.line(to: CGPoint(x: headCenter.x + halfWidth, y: baseY))
            stem.close()
            vermillon.setFill()
            stem.fill()

            let headRect = NSRect(x: headCenter.x - radius, y: headCenter.y - radius, width: radius * 2, height: radius * 2)
            let head = NSBezierPath(ovalIn: headRect)
            vermillon.setFill()
            head.fill()
            NSColor.white.setStroke()
            head.lineWidth = ringWidth
            head.stroke()
            drawNumber(number, center: headCenter, radius: radius, color: .white)
        }
    }

    private static func drawNumber(_ number: Int, center: CGPoint, radius: CGFloat, color: NSColor) {
        let label = "\(number)" as NSString
        let font = NSFont.systemFont(ofSize: radius * 1.05, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = label.size(withAttributes: attrs)
        let textRect = NSRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        label.draw(in: textRect, withAttributes: attrs)
    }

    /// Builds the agent-ready text block referencing each numbered pin.
    ///
    /// Markdown-structured so an AI agent can parse it: image dimensions, each
    /// marker with its description and approximate position (percentage of the
    /// image, top-left origin) so the agent can locate it even without reading
    /// the pixels, then the user's instructions in their own section.
    static func buildText(pins: [Pin], context: String, imageSize: CGSize) -> String {
        let width = Int(imageSize.width.rounded())
        let height = Int(imageSize.height.rounded())

        var lines: [String] = []
        lines.append("# Capture annotée — \(width)×\(height) px")
        lines.append("")

        if pins.isEmpty {
            lines.append("Une image est jointe (aucun repère posé).")
        } else {
            lines.append("Une image est jointe. Des pastilles numérotées (cerclées) pointent des éléments précis.")
            lines.append("Repères (position en % de l’image, origine haut-gauche) :")
            lines.append("")
            for pin in pins.sorted(by: { $0.number < $1.number }) {
                let note = pin.note.trimmingCharacters(in: .whitespacesAndNewlines)
                let description = note.isEmpty ? "(sans description)" : note
                let xPct = Int((pin.position.x * 100).rounded())
                let yPct = Int((pin.position.y * 100).rounded())
                lines.append("\(pin.number). \(description) · ~\(xPct) % × \(yPct) %")
            }
        }

        let ctx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty {
            lines.append("")
            lines.append("## Instructions")
            lines.append(ctx)
        }
        return lines.joined(separator: "\n")
    }

    /// Puts the annotated PNG and the instruction text on the general pasteboard.
    static func copyToPasteboard(base: NSImage, pins: [Pin], shapes: [Markup], context: String, style: PinStyle) {
        let annotated = annotatedImage(base: base, pins: pins, shapes: shapes, style: style)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let tiff = annotated.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }

        pasteboard.setString(buildText(pins: pins, context: context, imageSize: base.size), forType: .string)
    }
}
