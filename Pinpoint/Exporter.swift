import AppKit

enum Exporter {
    /// Renders the base capture with numbered markers drawn on top, at full
    /// image resolution.
    static func annotatedImage(base: NSImage, pins: [Pin]) -> NSImage {
        let size = base.size
        let result = NSImage(size: size)
        result.lockFocus()

        base.draw(in: NSRect(origin: .zero, size: size),
                  from: .zero, operation: .copy, fraction: 1.0)

        let radius = max(16, size.width * 0.014)
        for pin in pins {
            // Pin position is top-left origin; NSImage drawing is bottom-left.
            let center = CGPoint(
                x: pin.position.x * size.width,
                y: (1 - pin.position.y) * size.height
            )
            drawMarker(number: pin.number, at: center, radius: radius)
        }

        result.unlockFocus()
        return result
    }

    private static func drawMarker(number: Int, at center: CGPoint, radius: CGFloat) {
        let rect = NSRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)

        let accent = NSColor.controlAccentColor
        accent.setFill()
        let circle = NSBezierPath(ovalIn: rect)
        circle.fill()

        NSColor.white.setStroke()
        circle.lineWidth = max(2, radius * 0.14)
        circle.stroke()

        let label = "\(number)" as NSString
        let font = NSFont.systemFont(ofSize: radius * 1.05, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
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
    static func copyToPasteboard(base: NSImage, pins: [Pin], context: String) {
        let annotated = annotatedImage(base: base, pins: pins)
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
