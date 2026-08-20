import AppKit

enum Exporter {
    /// Renders the base capture with markups (redactions, arrows, rectangles)
    /// and numbered pins drawn on top, at full image resolution. Markups are
    /// drawn first so numbered pins stay legible above them, and redactions
    /// first among those — `inDrawOrder`, the same order the editor previews.
    static func annotatedImage(base: NSImage, pins: [Pin], shapes: [Markup], style: PinStyle) -> NSImage {
        let size = base.size
        let result = NSImage(size: size)
        result.lockFocus()

        base.draw(in: NSRect(origin: .zero, size: size),
                  from: .zero, operation: .copy, fraction: 1.0)

        // Drawn at 1:1 into the image's own pixel grid, so the metrics need
        // no scaling here. `EditorView` builds the same metrics with the
        // canvas' scale factor, which is what makes the preview WYSIWYG.
        let metrics = MarkupMetrics(imageWidth: size.width)
        for shape in shapes.inDrawOrder {
            drawMarkup(shape, in: size, metrics: metrics)
        }

        for pin in pins {
            // Pin position is the marked point (top-left origin); NSImage
            // drawing is bottom-left, so flip y.
            let anchor = CGPoint(
                x: pin.position.x * size.width,
                y: (1 - pin.position.y) * size.height
            )
            // Keep the badge fully inside the image when the point is near an
            // edge; the exact point is still carried by the % in the text.
            let drawAnchor = clampedMarkerAnchor(anchor, metrics: metrics, style: style, in: size)
            drawMarker(number: pin.number, anchor: drawAnchor, metrics: metrics, style: style)
        }

        result.unlockFocus()
        return result
    }

    private static func drawMarkup(_ shape: Markup, in size: CGSize, metrics: MarkupMetrics) {
        NSColor.pinpointVermillon.setStroke()
        let lineWidth = metrics.lineWidth

        // Normalized (top-left origin) → image space (bottom-left origin).
        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
        }

        switch shape.kind {
        case .rectangle:
            let rect = imageRect(shape.rect, in: size)
            let path = NSBezierPath(roundedRect: rect,
                                    xRadius: metrics.cornerRadius, yRadius: metrics.cornerRadius)
            path.lineWidth = lineWidth
            path.stroke()

        case .redaction:
            drawRedaction(imageRect(shape.rect, in: size), lineWidth: lineWidth)

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
            let headLength = metrics.arrowHeadLength
            let spread = MarkupMetrics.arrowHeadSpread

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

    /// A normalized rect (top-left origin) in the image's own drawing space
    /// (bottom-left origin).
    private static func imageRect(_ rect: CGRect, in size: CGSize) -> NSRect {
        NSRect(
            x: rect.minX * size.width,
            y: (1 - rect.maxY) * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }

    /// Paints out a redacted region: an opaque bar, then a vermillon border
    /// drawn *inside* it so the annotation reads as one of Pinpoint's own
    /// without ever narrowing what it covers.
    ///
    /// Three details carry the guarantee, and none of them is cosmetic:
    ///
    /// - `.copy` rather than the default source-over, so the pixels underneath
    ///   are **replaced** and not blended with. A colour that ever picked up an
    ///   alpha below 1 would otherwise turn the bar into a tint.
    /// - `integral`, which rounds the rect *outwards* to whole units. A bar on
    ///   fractional bounds leaves a partially covered row of pixels along each
    ///   edge — a sliver of the original image, and a sliver of a character is
    ///   sometimes a whole character.
    /// - antialiasing off while filling, for the same reason: a smoothed edge
    ///   is a blended edge.
    ///
    /// Square corners, not the rounded ones a rectangle markup gets: a rounded
    /// corner would leave the four corners of the region the user dragged
    /// showing.
    private static func drawRedaction(_ rect: NSRect, lineWidth: CGFloat) {
        guard rect.width > 0, rect.height > 0 else { return }
        let context = NSGraphicsContext.current
        let wasAntialiasing = context?.shouldAntialias ?? true
        context?.shouldAntialias = false
        NSColor.pinpointRedaction.setFill()
        rect.integral.fill(using: .copy)
        context?.shouldAntialias = wasAntialiasing

        // Inset by half the stroke width so the whole border sits inside the
        // bar; a centred stroke would spill outside the area the user drew.
        // Skipped on a bar too thin to hold one, where it would invert.
        let inset = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        guard inset.width > 0, inset.height > 0 else { return }
        NSColor.pinpointVermillon.setStroke()
        let border = NSBezierPath(rect: inset)
        border.lineWidth = lineWidth
        border.stroke()
    }

    /// Shifts `anchor` so the marker's badge stays fully within `size` (image
    /// space, y up). For the pointer the tip is at the anchor and the head sits
    /// above it (+y); disc/outline are centred on the anchor. Mirrors the
    /// clamping done on screen in `EditorView` so export and editor agree.
    private static func clampedMarkerAnchor(_ anchor: CGPoint, metrics: MarkupMetrics, style: PinStyle, in size: CGSize) -> CGPoint {
        let side = metrics.badgeHalfSide  // half-width incl. ring
        let x = clamp(anchor.x, side, size.width - side)
        switch style {
        case .disc, .outline:
            return CGPoint(x: x, y: clamp(anchor.y, side, size.height - side))
        case .pointer:
            // The head reaches anchor.y + pointerHeight upward; the tip is the low point.
            return CGPoint(x: x, y: clamp(anchor.y, 0, size.height - metrics.pointerHeight))
        }
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        max(lo, min(v, max(lo, hi)))
    }

    /// Draws a numbered marker at `anchor` (image space) in the chosen style.
    /// `anchor` is the marker centre for disc/outline and the tip for pointer —
    /// matching the on-screen `PinMarker` so the export looks identical.
    private static func drawMarker(number: Int, anchor: CGPoint, metrics: MarkupMetrics, style: PinStyle) {
        let vermillon = NSColor.pinpointVermillon
        let radius = metrics.pinRadius
        let ringWidth = metrics.ringWidth

        switch style {
        case .disc:
            let rect = NSRect(x: anchor.x - radius, y: anchor.y - radius, width: radius * 2, height: radius * 2)
            vermillon.setFill()
            let circle = NSBezierPath(ovalIn: rect)
            circle.fill()
            NSColor.white.setStroke()
            circle.lineWidth = ringWidth
            circle.stroke()
            drawNumber(number, center: anchor, fontSize: metrics.numberFontSize, color: .white)

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
            drawNumber(number, center: anchor, fontSize: metrics.numberFontSize, color: vermillon)

        case .pointer:
            // Tip at the anchor; head above it (image space y grows upward).
            let headCenter = CGPoint(x: anchor.x, y: anchor.y + metrics.pointerHeadOffset)
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
            drawNumber(number, center: headCenter, fontSize: metrics.numberFontSize, color: .white)
        }
    }

    private static func drawNumber(_ number: Int, center: CGPoint, fontSize: CGFloat, color: NSColor) {
        let label = "\(number)" as NSString
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
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

    /// Builds the agent-ready text block referencing each annotation.
    ///
    /// Markdown-structured so an AI agent can parse it: image dimensions, then
    /// one line per numbered marker and one per shape (arrow/rectangle), each
    /// with a stable ID and its position both in pixels and in percent of the
    /// image (top-left origin), so the agent can locate every annotation
    /// without reading the pixels — then the user's instructions in their own
    /// section.
    static func buildText(pins: [Pin], shapes: [Markup] = [], context: String, imageSize: CGSize,
                          accessibility: AXSnapshot? = nil) -> String {
        let width = Int(imageSize.width.rounded())
        let height = Int(imageSize.height.rounded())
        let orderedPins = pins.sorted { $0.number < $1.number }

        var lines: [String] = []
        // POSIX locale so the dimensions stay raw digits: the user's locale would
        // group them ("2 560×1 440"), which is noise for the agent reading this.
        lines.append(String(localized: "export.header",
                            defaultValue: "# Annotated capture — \(width)×\(height) px",
                            locale: Locale(identifier: "en_US_POSIX")))
        lines.append("")

        if orderedPins.isEmpty {
            lines.append(String(localized: "An image is attached (no markers placed)."))
        } else {
            lines.append(String(localized: "An image is attached. Numbered (ringed) badges point to specific elements."))
        }
        if !orderedPins.isEmpty || !shapes.isEmpty {
            lines.append(String(localized: "export.coordinates", defaultValue: "Positions are given in pixels from the top-left corner (0, 0), then as a percentage of the image size."))
        }

        // What the user painted over (#50). Every accessibility lookup below
        // goes through it: the bar hides the pixels, and this hides the text
        // that describes the very same pixels — the leak this feature would
        // otherwise open, since a marker dropped on a hidden token would carry
        // the token's label and value into this file.
        let mask = RedactionMask(shapes)

        // Kept only when at least one marker actually resolves to an element:
        // an empty snapshot must not print a legend promising details that never
        // come, and must leave the text byte-identical to what it was before.
        let snapshot = accessibility.flatMap { candidate in
            orderedPins.contains {
                candidate.element(atNormalized: $0.position, hiddenBy: mask) != nil
            } ? candidate : nil
        }

        if !orderedPins.isEmpty {
            lines.append("")
            lines.append("## " + String(localized: "Markers"))
            lines.append(String(localized: "export.markers.legend", defaultValue: "M1, M2… are the numbers drawn on the image; the code in brackets is a stable ID for that marker."))
            if snapshot != nil {
                lines.append(String(localized: "export.markers.accessibility.legend", defaultValue: "“UI” lines name the interface element found under the marker in the macOS accessibility tree at capture time — its role, its label, the app owning it, and its box in this image. “Path” is the chain of containers around it."))
            }
            lines.append("")
            for pin in orderedPins {
                let note = pin.note.trimmingCharacters(in: .whitespacesAndNewlines)
                let description = note.isEmpty ? String(localized: "(no description)") : note
                lines.append("- M\(pin.number) [\(pin.id.shortToken)] · \(description) — "
                             + "\(pixels(pin.position, in: imageSize)) px · \(percent(pin.position))")
                // The interface element the marker landed on, read from the
                // accessibility tree while the capture was taken (#55). Indented
                // under its marker so the association is positional and can't be
                // misread, and left out entirely when there's nothing to say.
                lines.append(contentsOf: accessibilityLines(for: pin.position, snapshot: snapshot,
                                                            mask: mask, imageSize: imageSize))
            }
        }

        if !shapes.isEmpty {
            lines.append("")
            lines.append("## " + String(localized: "export.shapes.heading", defaultValue: "Shapes"))
            lines.append(String(localized: "export.shapes.legend", defaultValue: "Unnumbered outlines drawn on the image: rectangles are listed top-left → bottom-right, arrows tail → tip, followed by the size of their bounding box."))
            // Only when there is one, so a capture without redactions keeps the
            // text it had before. Says what a hidden area *is* — never what it
            // held — because an agent that doesn't know a region was painted
            // out would read the bar as part of the interface.
            if !mask.isEmpty {
                lines.append(String(localized: "export.shapes.redaction.legend", defaultValue: "A hidden area is a region the user painted over before sharing: its pixels are not in the image, and nothing was collected about what sat under it. Ask the user rather than guessing."))
            }
            lines.append("")
            for (index, shape) in shapes.enumerated() {
                let box = shape.rect
                let from: CGPoint, to: CGPoint
                switch shape.kind {
                case .rectangle, .redaction:
                    from = CGPoint(x: box.minX, y: box.minY)
                    to = CGPoint(x: box.maxX, y: box.maxY)
                case .arrow:
                    from = shape.start
                    to = shape.end
                }
                let boxWidth = Int((box.width * imageSize.width).rounded())
                let boxHeight = Int((box.height * imageSize.height).rounded())
                lines.append("- S\(index + 1) [\(shape.id.shortToken)] · \(shape.label) — "
                             + "\(pixels(from, in: imageSize)) → \(pixels(to, in: imageSize)) px · "
                             + "\(percent(from)) → \(percent(to)) · \(boxWidth)×\(boxHeight) px")
            }
        }

        let ctx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty {
            lines.append("")
            lines.append("## " + String(localized: "Instructions"))
            lines.append(ctx)
        }
        return lines.joined(separator: "\n")
    }

    /// The two-or-three indented lines describing what sits under a marker, or
    /// nothing at all when the snapshot has no element there.
    ///
    /// Written for both readers at once: a human scanning the file sees a
    /// sentence, an agent sees `key: value` fields it can lift verbatim. The
    /// role stays in its raw accessibility spelling (`AXButton`) because that is
    /// the vocabulary shared with every inspector, and with the code that
    /// created the element in the first place.
    private static func accessibilityLines(for position: CGPoint, snapshot: AXSnapshot?,
                                           mask: RedactionMask, imageSize: CGSize) -> [String] {
        guard let snapshot,
              let resolved = snapshot.element(atNormalized: position, hiddenBy: mask) else { return [] }
        let element = resolved.element

        var facts: [String] = [element.summary]
        if let identifier = element.identifier, identifier != element.name {
            facts.append("id=\(identifier)")
        }
        if let subrole = element.subrole { facts.append("subrole=\(subrole)") }
        if let bundle = resolved.application.bundleIdentifier ?? resolved.application.name {
            facts.append(bundle)
        }
        facts.append(box(element.frame, snapshot: snapshot, imageSize: imageSize))
        if element.enabled == false { facts.append(String(localized: "export.ax.disabled", defaultValue: "disabled")) }

        // `UI:`, `Value:` and `Path:` stay in English like `M1` and `px`: they
        // are field names in a machine-read file, not prose. Only the sentences
        // a human might read are localized.
        var lines = ["  - UI: " + facts.joined(separator: " · ")]
        if let value = element.value {
            lines.append("  - Value: “\(value)”")
        } else if let redaction = element.redaction {
            lines.append("  - Value: " + redactionNote(redaction))
        }
        lines.append("  - Path: " + resolved.path)
        return lines
    }

    /// An element's screen frame restated in the image's own pixel grid, so it
    /// lines up with every other coordinate in this file. Not clamped: a box
    /// reaching past the edges is an element that sticks out of the capture,
    /// which is worth knowing rather than hiding.
    private static func box(_ frame: CGRect, snapshot: AXSnapshot, imageSize: CGSize) -> String {
        let rect = snapshot.normalizedRect(for: frame)
        let x = Int((rect.minX * imageSize.width).rounded())
        let y = Int((rect.minY * imageSize.height).rounded())
        let width = Int((rect.width * imageSize.width).rounded())
        let height = Int((rect.height * imageSize.height).rounded())
        return "box (\(x), \(y)) \(width)×\(height) px"
    }

    /// Says plainly that a value exists and was withheld, rather than leaving a
    /// silent gap an agent might read as "the field was empty".
    private static func redactionNote(_ redaction: AXSnapshot.Redaction) -> String {
        switch redaction {
        case .secureField:
            return String(localized: "export.ax.value.secure",
                          defaultValue: "withheld (secure field — Pinpoint never reads it)")
        case .textFieldPolicy:
            return String(localized: "export.ax.value.policy",
                          defaultValue: "withheld (text field — enable “Include what is typed in fields” in Pinpoint’s settings)")
        case .userRedaction:
            return String(localized: "export.ax.value.redacted",
                          defaultValue: "withheld (the user painted over this element — its name and its contents were left out)")
        }
    }

    /// `(1075, 259)` — a normalized point in the image's pixel grid, top-left origin.
    private static func pixels(_ point: CGPoint, in size: CGSize) -> String {
        "(\(Int((point.x * size.width).rounded())), \(Int((point.y * size.height).rounded())))"
    }

    /// `(42 %, 18 %)` — the same point as a share of the image's width and height.
    private static func percent(_ point: CGPoint) -> String {
        "(\(Int((point.x * 100).rounded())) %, \(Int((point.y * 100).rounded())) %)"
    }

    /// The image to share with an agent: the annotated capture, optionally with
    /// a legend strip below it (numbered pin descriptions + instructions) so a
    /// single paste carries everything — most chat UIs paste only the image and
    /// drop the clipboard text.
    static func exportImage(base: NSImage, pins: [Pin], shapes: [Markup], context: String,
                            style: PinStyle, includeLegend: Bool) -> NSImage {
        let annotated = annotatedImage(base: base, pins: pins, shapes: shapes, style: style)
        guard includeLegend, let legend = legendString(pins: pins, context: context, width: annotated.size.width) else {
            return annotated
        }

        let width = annotated.size.width
        let pad = max(18, width * 0.022)
        let textWidth = width - pad * 2
        let textHeight = ceil(legend.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        let panelHeight = textHeight + pad * 2
        let totalHeight = annotated.size.height + panelHeight

        let result = NSImage(size: NSSize(width: width, height: totalHeight))
        result.lockFocus()
        // Capture on top (image space is bottom-left origin, so the panel sits
        // at the bottom and the capture above it).
        annotated.draw(in: NSRect(x: 0, y: panelHeight, width: width, height: annotated.size.height))
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: panelHeight).fill()
        NSColor.black.withAlphaComponent(0.10).setFill()
        NSRect(x: 0, y: panelHeight - 1, width: width, height: 1).fill()
        // .usesLineFragmentOrigin fills from the top edge of the rect downwards.
        legend.draw(with: NSRect(x: pad, y: pad, width: textWidth, height: textHeight),
                    options: [.usesLineFragmentOrigin])
        result.unlockFocus()
        return result
    }

    /// The legend rendered into the exported image, or nil if there's nothing to
    /// show (no pins and no instructions).
    private static func legendString(pins: [Pin], context: String, width: CGFloat) -> NSAttributedString? {
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderedPins = pins.sorted { $0.number < $1.number }
        guard !orderedPins.isEmpty || !trimmedContext.isEmpty else { return nil }

        let bodySize = max(15, width * 0.016)
        let body = NSFont.systemFont(ofSize: bodySize)
        let number = NSFont.systemFont(ofSize: bodySize, weight: .bold)
        let heading = NSFont.systemFont(ofSize: bodySize * 0.8, weight: .bold)
        let dark = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
        let secondary = NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodySize * 0.22
        paragraph.paragraphSpacing = bodySize * 0.35

        let result = NSMutableAttributedString()
        func add(_ text: String, _ font: NSFont, _ color: NSColor) {
            result.append(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ]))
        }

        if !orderedPins.isEmpty {
            add(String(localized: "legend.markers", defaultValue: "MARKERS") + "\n", heading, secondary)
            for pin in orderedPins {
                let note = pin.note.trimmingCharacters(in: .whitespacesAndNewlines)
                add("\(pin.number)", number, .pinpointVermillon)
                add("   \(note.isEmpty ? String(localized: "(no description)") : note)\n", body, dark)
            }
        }
        if !trimmedContext.isEmpty {
            if !orderedPins.isEmpty { add("\n", body, dark) }
            add(String(localized: "legend.instructions", defaultValue: "INSTRUCTIONS") + "\n", heading, secondary)
            add(trimmedContext, body, dark)
        }
        return result
    }

    /// Longest-edge cap (pixels) for the image placed on the pasteboard. Captures
    /// are stored at native Retina resolution, which makes the full-size PNG too
    /// large to paste into some targets (Claude, GitHub). The agent doesn't need
    /// that detail — the text carries each marker's position — so the clipboard
    /// image is downscaled to fit, while "Save image…" keeps full resolution.
    static let clipboardMaxDimension: CGFloat = 2000

    /// PNG data for the annotated image (with legend when `includeLegend`),
    /// optionally downscaled so its longest edge is at most `maxDimension` pixels.
    /// Pass `nil` for full native resolution.
    static func pngData(base: NSImage, pins: [Pin], shapes: [Markup], context: String,
                        style: PinStyle, includeLegend: Bool, maxDimension: CGFloat?) -> Data? {
        let image = exportImage(base: base, pins: pins, shapes: shapes, context: context,
                                style: style, includeLegend: includeLegend)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let output = maxDimension.flatMap { downscaled(rep, maxDimension: $0) } ?? rep
        return output.representation(using: .png, properties: [:])
    }

    /// Returns `rep` shrunk so its longest pixel edge is `maxDimension`, or `rep`
    /// itself when it already fits. Works in pixels so the cap is exact regardless
    /// of the drawing context's scale.
    private static func downscaled(_ rep: NSBitmapImageRep, maxDimension: CGFloat) -> NSBitmapImageRep? {
        let longest = CGFloat(max(rep.pixelsWide, rep.pixelsHigh))
        guard longest > maxDimension else { return rep }
        let factor = maxDimension / longest
        let width = Int((CGFloat(rep.pixelsWide) * factor).rounded())
        let height = Int((CGFloat(rep.pixelsHigh) * factor).rounded())
        guard let dst = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return rep }
        dst.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: dst)
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return dst
    }

    /// Puts the (optionally legend-bearing) annotated PNG on the general
    /// pasteboard, downscaled to `clipboardMaxDimension` so it stays pasteable.
    ///
    /// When the legend is baked into the image the PNG is self-contained, so we
    /// deliberately leave the plain instruction text off the pasteboard: a
    /// terminal (e.g. Claude Code) pastes text and silently drops the image when
    /// both share a pasteboard item, so the bare string would hide the capture.
    /// Only when the legend is *not* embedded do we add the text, since then it
    /// is the sole carrier of the marker descriptions and instructions.
    /// Returns `false` when nothing reached the pasteboard — rendering failed or
    /// every write was rejected — so callers don't report a copy that never
    /// happened.
    @discardableResult
    static func copyToPasteboard(base: NSImage, pins: [Pin], shapes: [Markup], context: String,
                                 style: PinStyle, includeLegend: Bool,
                                 accessibility: AXSnapshot? = nil) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wrote = false
        if let png = pngData(base: base, pins: pins, shapes: shapes, context: context,
                             style: style, includeLegend: includeLegend, maxDimension: clipboardMaxDimension) {
            wrote = pasteboard.setData(png, forType: .png)
        }

        if !includeLegend {
            let text = buildText(pins: pins, shapes: shapes, context: context, imageSize: base.size,
                                 accessibility: accessibility)
            wrote = pasteboard.setString(text, forType: .string) || wrote
        }

        return wrote
    }
}
