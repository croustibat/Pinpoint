import AppKit
import CoreText
import Foundation

// Proves, against the real code, that the text recognizer of #49 cannot put
// something the user painted over (#50) into the files a capture is handed
// over in.
//
// The app itself is a menu-bar SwiftUI app with no test target, so this is a
// small executable compiled from the very same sources — `TextRecognizer`,
// `RedactionMask`, `Exporter`, `FileHandoff.Document` — rather than a
// reimplementation of them. What it asserts is what actually ships.
//
//   scripts/verify-ocr-redaction.sh
//
// The first case is the one that gives the others their teeth: it puts a fake
// API key on a synthetic screen with no redaction at all and *requires* the
// recognizer to read it. A harness that can't find the secret when it is in
// plain sight would pass every redaction check below while proving nothing.

@main
struct VerifyOCRRedaction {

    /// The string that must never leave. Shaped like the thing this is actually
    /// about — an API key sitting in a terminal someone is about to screenshot.
    static let secret = "sk-live-9F3KQ2ZP7X"
    /// A line with nothing sensitive in it, on the same synthetic screen. Every
    /// redaction case checks this one *survives*: a recognizer that returned
    /// nothing at all would otherwise look like a recognizer that was careful.
    static let ordinary = "Cannot find module 'react'"

    /// Where the two lines sit, normalized (0…1), top-left origin. Baselines;
    /// the boxes are measured from the rendered glyphs.
    static let ordinaryBaseline = CGPoint(x: 0.08, y: 0.32)
    static let secretBaseline = CGPoint(x: 0.08, y: 0.62)

    static var failures = 0

    static func main() async {
        // 1× and 2× renderings of the same screen. A Retina capture is stored
        // at its native pixel count, so the 2× image is twice the pixels of the
        // 1× one for the same content — every box, every reach and every
        // redaction rect below is normalized, and both have to come out the
        // same. That equality *is* the Retina check.
        for scale in [1, 2] {
            let capture = render(scale: scale)
            let size = CGSize(width: capture.image.width, height: capture.image.height)
            print("\n── \(scale)× — \(capture.image.width)×\(capture.image.height) px ──")

            // The reference read: no redaction anywhere.
            let clock = ContinuousClock()
            var elapsed = Duration.zero
            var open = TextRecognition.empty
            elapsed = await clock.measure {
                open = await TextRecognizer.recognize(in: capture.image, hiddenBy: RedactionMask([]))
            }
            print("   .accurate over the whole image: \(elapsed)")

            check("the recognizer reads the secret when nothing hides it",
                  contains(open, secret))
            check("the recognizer reads the ordinary line",
                  contains(open, ordinary))
            check("a marker on the secret resolves to it",
                  open.text(near: capture.secretAnchor, imageSize: size,
                            hiddenBy: RedactionMask([]))?.text.contains(secret) == true)
            check("a marker on the ordinary line resolves to it, not to the secret",
                  open.text(near: capture.ordinaryAnchor, imageSize: size,
                            hiddenBy: RedactionMask([]))?.text.contains("module") == true)
            check("a marker in empty space resolves to nothing",
                  open.text(near: CGPoint(x: 0.5, y: 0.93), imageSize: size,
                            hiddenBy: RedactionMask([])) == nil)

            // The redactions to try: the whole line, a bar over half of it, and
            // a bar clipping only its last few characters. All three must end
            // the same way — any overlap at all takes the whole read out.
            let full = capture.secretBox.insetBy(dx: -0.005, dy: -0.005)
            let half = CGRect(x: capture.secretBox.midX, y: capture.secretBox.minY,
                              width: capture.secretBox.width / 2, height: capture.secretBox.height)
            let tail = CGRect(x: capture.secretBox.maxX - capture.secretBox.width * 0.12,
                              y: capture.secretBox.minY,
                              width: capture.secretBox.width * 0.12, height: capture.secretBox.height)

            for (label, rect) in [("the whole line", full), ("half of it", half), ("its last characters", tail)] {
                await verify(covering: label, rect: rect, capture: capture, size: size)
            }
        }

        await verifyAccessibilityArbitration()
        await showExport()

        print(failures == 0
              ? "\n\u{2713} every check passed"
              : "\n\u{2717} \(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// The other half of "don't say it twice": a read is dropped when the
    /// accessibility tree already names the same thing (a native app), and kept
    /// when it doesn't (an Electron window, where the tree is anonymous groups
    /// and the pixels are the only place the string exists).
    static func verifyAccessibilityArbitration() async {
        print("\n── accessibility arbitration (#55) ──")
        let capture = render(scale: 2)
        let size = CGSize(width: capture.image.width, height: capture.image.height)
        let open = RedactionMask([])
        let read = await TextRecognizer.recognize(in: capture.image, hiddenBy: open)

        // A tree that already spells out the ordinary line, the way a native
        // app's `AXStaticText` would. The snapshot covers the whole capture, so
        // one screen point maps to one normalized point.
        let screen = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        func snapshot(named name: String?) -> AXSnapshot {
            AXSnapshot(
                captureRect: screen,
                applications: [.init(name: "Example", bundleIdentifier: "com.example", processIdentifier: 1)],
                elements: [AXSnapshot.Element(role: "AXStaticText", title: name, frame: screen,
                                              application: 0, windowOrder: 0, depth: 0)],
                truncated: false, capturedAt: Date(), includesFieldValues: false
            )
        }

        var native = [Pin(number: 1, position: capture.ordinaryAnchor)]
        let tree = snapshot(named: ordinary)
        native.applyRecognition(read, imageSize: size, hiddenBy: open) { text, point in
            tree.names(text, atNormalized: point, hiddenBy: open)
        }
        check("a read the tree already names is dropped", native[0].recognized == nil)
        check("and no description is pre-filled from it", native[0].note.isEmpty)

        var electron = [Pin(number: 1, position: capture.ordinaryAnchor)]
        let anonymous = snapshot(named: nil)
        electron.applyRecognition(read, imageSize: size, hiddenBy: open) { text, point in
            anonymous.names(text, atNormalized: point, hiddenBy: open)
        }
        check("a read the tree has no name for is kept",
              electron[0].recognized?.text.contains("module") == true)
        check("and pre-fills the description", electron[0].note.contains("module"))
    }

    /// Prints one real `capture.md`, so the shape of what an agent receives can
    /// be read rather than inferred — and asserts the one thing that shape must
    /// never do, which is print the same string twice under one marker.
    static func showExport() async {
        print("\n── capture.md as an agent receives it ──")
        let capture = render(scale: 2)
        let size = CGSize(width: capture.image.width, height: capture.image.height)
        let open = RedactionMask([])
        let read = await TextRecognizer.recognize(in: capture.image, hiddenBy: open)

        // Two markers on the same line: one left as Pinpoint pre-filled it, one
        // the user has since described in their own words.
        var pins = [Pin(number: 1, position: capture.ordinaryAnchor),
                    Pin(number: 2, position: capture.ordinaryAnchor)]
        pins.applyRecognition(read, imageSize: size, hiddenBy: open)
        pins[1].note = "this is the error I keep hitting"

        let markdown = Exporter.buildText(pins: pins, shapes: [], context: "why does this happen?",
                                          imageSize: size, preset: .bug)
        print(markdown.split(separator: "\n").map { "   " + $0 }.joined(separator: "\n"))

        let rows = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func lineAfter(_ marker: String) -> String {
            guard let index = rows.firstIndex(where: { $0.hasPrefix("- \(marker) [") }),
                  index + 1 < rows.count else { return "" }
            return rows[index + 1]
        }
        check("the pre-filled marker prints its text once, as its description",
              rows.contains { $0.hasPrefix("- M1 [") && $0.contains(ordinary) }
              && !lineAfter("M1").hasPrefix("  - Text:"))
        check("the marker described by the user carries both its words and the read",
              rows.contains { $0.hasPrefix("- M2 [") && $0.contains("this is the error") }
              && lineAfter("M2").hasPrefix("  - Text: “"))
        check("the read is never printed twice under one marker",
              rows.filter { $0.hasPrefix("  - Text:") }.count == 1)
    }

    /// One redaction, taken all the way through to the two files a capture is
    /// handed over in.
    static func verify(covering label: String, rect: CGRect,
                       capture: Capture, size: CGSize) async {
        print("   redaction over \(label):")
        let shapes = [Markup(kind: .redaction,
                             start: CGPoint(x: rect.minX, y: rect.minY),
                             end: CGPoint(x: rect.maxX, y: rect.maxY))]
        let mask = RedactionMask(shapes)

        let read = await TextRecognizer.recognize(in: capture.image, hiddenBy: mask)
        check("      no recognized line contains the secret", !contains(read, secret))
        check("      the ordinary line is still read", contains(read, ordinary))

        // Two markers: one on the covered secret, one on the untouched line.
        // Both start with an empty description, the way a marker dropped in the
        // editor does, so `applyRecognition` runs its pre-fill.
        var pins = [Pin(number: 1, position: capture.ordinaryAnchor),
                    Pin(number: 2, position: capture.secretAnchor)]
        pins.applyRecognition(read, imageSize: size, hiddenBy: mask)

        check("      the marker on the redaction gets no text", pins[1].recognized == nil)
        check("      its description is left empty", pins[1].note.isEmpty)
        check("      the other marker is still pre-filled",
              pins[0].note.contains("module"))

        // The case a naive implementation gets wrong: the marker was dropped
        // *before* the bar was drawn, so its description was pre-filled with
        // the secret and is still carrying it when the redaction arrives.
        var late = [Pin(number: 1, position: capture.secretAnchor)]
        let openMask = RedactionMask([])
        let open = await TextRecognizer.recognize(in: capture.image, hiddenBy: openMask)
        late.applyRecognition(open, imageSize: size, hiddenBy: openMask)
        check("      (before the bar) the description holds the secret",
              late[0].note.contains(secret))
        late.applyRecognition(open, imageSize: size, hiddenBy: mask)
        check("      drawing the bar takes the secret back out of the description",
              !late[0].note.contains(secret) && late[0].recognized == nil)

        // A description the user typed themselves is theirs, and stays.
        var typed = [Pin(number: 1, position: capture.secretAnchor, note: "look at this line")]
        typed.applyRecognition(open, imageSize: size, hiddenBy: mask)
        check("      a description the user typed is not touched",
              typed[0].note == "look at this line")

        // And finally the files. Both markers keep whatever they hold — this is
        // the exporters' own redaction check being tested, not the editor's.
        let all = pins + late + typed
        let markdown = Exporter.buildText(pins: all.enumerated().map { renumber($1, $0 + 1) },
                                          shapes: shapes, context: "check this out",
                                          imageSize: size)
        check("      capture.md does not contain the secret", !markdown.contains(secret))
        check("      capture.md still carries the ordinary line", markdown.contains("module"))

        let json = Exporter.buildJSON(pins: all.enumerated().map { renumber($1, $0 + 1) },
                                      shapes: shapes, context: "check this out",
                                      imageSize: size, style: .disc) ?? ""
        check("      capture.json does not contain the secret", !json.contains(secret))
        check("      capture.json carries the recognized text as its own key",
              json.contains("\"recognizedText\""))
    }

    // MARK: - The synthetic screen

    struct Capture {
        let image: CGImage
        /// Where a marker dropped on each line would sit, normalized.
        let ordinaryAnchor: CGPoint
        let secretAnchor: CGPoint
        /// The rendered extent of the secret, normalized — what a user painting
        /// over it would cover.
        let secretBox: CGRect
    }

    /// A plain white screen with two lines of dark text on it, at `scale` times
    /// a 1280×800 point grid.
    static func render(scale: Int) -> Capture {
        let width = 1280 * scale
        let height = 800 * scale
        let fontSize = CGFloat(22 * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let size = CGSize(width: width, height: height)
        let ordinaryBox = draw(ordinary, baseline: ordinaryBaseline, fontSize: fontSize,
                               in: context, size: size)
        let secretBox = draw("API key: " + secret, baseline: secretBaseline, fontSize: fontSize,
                             in: context, size: size)

        return Capture(image: context.makeImage()!,
                       ordinaryAnchor: CGPoint(x: ordinaryBox.midX, y: ordinaryBox.midY),
                       secretAnchor: CGPoint(x: secretBox.maxX - secretBox.width * 0.15,
                                             y: secretBox.midY),
                       secretBox: secretBox)
    }

    /// Draws one line and hands back the box it covers, normalized, top-left.
    static func draw(_ string: String, baseline: CGPoint, fontSize: CGFloat,
                     in context: CGContext, size: CGSize) -> CGRect {
        let font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: CGColor(gray: 0.08, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let origin = CGPoint(x: baseline.x * size.width, y: (1 - baseline.y) * size.height)
        context.textPosition = origin
        CTLineDraw(line, context)

        // CTLine bounds are relative to the baseline, y up; the capture's
        // convention is 0…1 from the top.
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let box = CGRect(x: origin.x + bounds.minX, y: origin.y + bounds.minY,
                         width: bounds.width, height: bounds.height)
        return CGRect(x: box.minX / size.width,
                      y: (size.height - box.maxY) / size.height,
                      width: box.width / size.width,
                      height: box.height / size.height)
    }

    // MARK: - Assertions

    static func contains(_ recognition: TextRecognition, _ needle: String) -> Bool {
        recognition.lines.contains { $0.text.contains(needle) }
    }

    static func renumber(_ pin: Pin, _ number: Int) -> Pin {
        var copy = pin
        copy.number = number
        return copy
    }

    static func check(_ what: String, _ passed: Bool) {
        print("   \(passed ? "\u{2713}" : "\u{2717}") \(what)")
        if !passed { failures += 1 }
    }
}
