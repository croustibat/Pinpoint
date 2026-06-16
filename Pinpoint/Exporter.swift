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
    static func buildText(pins: [Pin], context: String) -> String {
        var lines: [String] = []
        lines.append("Capture d’écran annotée. Les repères numérotés indiquent les éléments concernés :")
        lines.append("")
        if pins.isEmpty {
            lines.append("(aucun repère posé)")
        } else {
            for pin in pins.sorted(by: { $0.number < $1.number }) {
                let note = pin.note.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("- #\(pin.number) : \(note.isEmpty ? "—" : note)")
            }
        }
        let ctx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty {
            lines.append("")
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

        pasteboard.setString(buildText(pins: pins, context: context), forType: .string)
    }
}
