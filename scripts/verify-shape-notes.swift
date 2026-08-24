import AppKit
import Foundation

// Proves, against the real code, that a shape's description (#93) reaches every
// surface a capture is handed over on — and that adding it broke none of the
// three things it could have broken: the stored history, the text of a capture
// that carries no description, and the image of one.
//
// The app has no test target (see `scripts/verify-ocr-redaction.swift`), so
// this is a small executable compiled from the very same sources — `Markup`,
// `CaptureRecord`, `Exporter`, `FileHandoff.Document` — rather than a
// reimplementation of them. What it asserts is what actually ships.
//
//   scripts/verify-shape-notes.sh
//
// The first case is the one with teeth. `CaptureHistory.load()` decodes the
// whole `index.json` as one array with `try?`: a markup recorded before this
// field existed must still decode, or a single old shape would empty the user's
// history — and the next `saveIndex()` would write that emptiness back to disk.

@main
struct VerifyShapeNotes {

    static var failures = 0

    static func main() {
        historyStillDecodes()
        textCarriesTheDescription()
        textIsUnchangedWithoutOne()
        jsonCarriesTheDescription()
        legendGrowsOnlyWhenThereIsSomethingToSay()

        print("")
        if failures == 0 {
            print("✅ every check passed")
        } else {
            print("❌ \(failures) check(s) failed")
            exit(1)
        }
    }

    // MARK: - The history written by an earlier version

    /// `index.json` as Pinpoint 0.7.1 wrote it: two shapes and a marker, and no
    /// `note` key anywhere on the shapes because the field did not exist.
    /// Hand-written rather than round-tripped, so it can't silently follow the
    /// model it is supposed to be older than.
    static let legacyIndex = """
    [{
      "id": "8B0F8B7E-2A1C-4C4B-9E2E-5C3D9A1F0001",
      "date": 776000000,
      "imageFileName": "8B0F8B7E-2A1C-4C4B-9E2E-5C3D9A1F0001.png",
      "width": 1280, "height": 800,
      "context": "the sidebar collapses on hover",
      "pins": [{
        "id": "8B0F8B7E-2A1C-4C4B-9E2E-5C3D9A1F0002",
        "number": 1, "position": [0.4, 0.5], "note": "this button"
      }],
      "shapes": [
        { "id": "8B0F8B7E-2A1C-4C4B-9E2E-5C3D9A1F0003", "kind": "rectangle",
          "start": [0.1, 0.2], "end": [0.3, 0.4] },
        { "id": "8B0F8B7E-2A1C-4C4B-9E2E-5C3D9A1F0004", "kind": "redaction",
          "start": [0.6, 0.7], "end": [0.8, 0.9] }
      ]
    }]
    """

    static func historyStillDecodes() {
        print("\n── an index.json written before the field existed ──")
        guard let records = try? JSONDecoder().decode([CaptureRecord].self,
                                                      from: Data(legacyIndex.utf8)) else {
            check("the stored history still decodes", false)
            print("   (this is the case that would delete the user's recent captures)")
            return
        }
        check("the stored history still decodes", true)
        check("both shapes came back", records.first?.shapes.count == 2)
        check("a shape with no stored description reads as having none",
              records.first?.shapes.allSatisfy { $0.note.isEmpty && $0.trimmedNote == nil } == true)
        // The stored coordinates, not the derived `rect`: 0.3 − 0.1 is not 0.2
        // in binary floating point, and a check that says so is a check about
        // Swift rather than about this field.
        let record = records.first
        let marker = record?.pins.first
        let rectangle = record?.shapes.first
        let markerSurvived = marker?.note == "this button" && marker?.position == CGPoint(x: 0.4, y: 0.5)
        let shapeSurvived = rectangle?.start == CGPoint(x: 0.1, y: 0.2)
            && rectangle?.end == CGPoint(x: 0.3, y: 0.4)
            && record?.shapes.last?.kind == .redaction
        check("everything else survived untouched",
              markerSurvived && shapeSurvived && record?.context == "the sidebar collapses on hover")

        // And the other direction: what this version writes, this version reads.
        let written = [Markup(kind: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1),
                              note: "  the arrow points at the wrong row  ")]
        let round = (try? JSONEncoder().encode(written)).flatMap {
            try? JSONDecoder().decode([Markup].self, from: $0)
        }
        check("a description survives a save and a reload",
              round?.first?.note == "  the arrow points at the wrong row  ")
        check("it is trimmed only where it is read, never where it is stored",
              round?.first?.trimmedNote == "the arrow points at the wrong row")
    }

    // MARK: - capture.md

    static func textCarriesTheDescription() {
        print("\n── capture.md ──")
        let rectangle = Markup(kind: .rectangle, start: CGPoint(x: 0.1, y: 0.2),
                               end: CGPoint(x: 0.3, y: 0.4), note: "  this box is 4 px too wide  ")
        let hidden = Markup(kind: .redaction, start: CGPoint(x: 0.6, y: 0.7),
                            end: CGPoint(x: 0.8, y: 0.9), note: "my API key")
        let text = Exporter.buildText(pins: [], shapes: [rectangle, hidden], context: "",
                                      imageSize: CGSize(width: 1000, height: 800))

        check("the description sits between the shape's kind and its geometry",
              text.contains("- S1 [\(rectangle.id.shortToken)] · \(rectangle.label) · this box is 4 px too wide — "))
        check("it is trimmed on the way out",
              !text.contains("·   this box is 4 px too wide"))
        check("a hidden area says what the user chose to say about it",
              text.contains("- S2 [\(hidden.id.shortToken)] · \(hidden.label) · my API key — "))
        check("the reader is told where that sentence comes from",
              occurrences(of: "is what the user wrote about that shape", in: text) == 1)
    }

    static func textIsUnchangedWithoutOne() {
        print("\n── capture.md, for a capture nobody described ──")
        let shapes = [
            Markup(kind: .rectangle, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.3, y: 0.4)),
            // Whitespace only: the same thing as nothing, everywhere downstream.
            Markup(kind: .arrow, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.9, y: 0.1),
                   note: "   \n  ")
        ]
        let text = Exporter.buildText(pins: [Pin(number: 1, position: CGPoint(x: 0.4, y: 0.5))],
                                      shapes: shapes, context: "look at this",
                                      imageSize: CGSize(width: 1000, height: 800))

        check("the shape lines carry no empty slot",
              text.contains("- S1 [\(shapes[0].id.shortToken)] · \(shapes[0].label) — ")
                  && text.contains("- S2 [\(shapes[1].id.shortToken)] · \(shapes[1].label) — "))
        check("no provenance line promises a description that never comes",
              !text.contains("is what the user wrote about that shape"))
    }

    // MARK: - capture.json

    static func jsonCarriesTheDescription() {
        print("\n── capture.json ──")
        let described = Markup(kind: .rectangle, start: CGPoint(x: 0.1, y: 0.2),
                               end: CGPoint(x: 0.3, y: 0.4), note: "  the empty state  ")
        let bare = Markup(kind: .arrow, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.9, y: 0.1))

        let document = FileHandoff.Document(
            pins: [], shapes: [described, bare], context: "",
            imageSize: CGSize(width: 1000, height: 800), directory: nil,
            style: .disc, preset: .raw
        )
        check("the description is carried, trimmed", document.shapes.first?.note == "the empty state")
        check("a shape with none carries no key at all", document.shapes.last?.note == nil)

        guard let data = try? FileHandoff.encoder.encode(document),
              let json = String(data: data, encoding: .utf8) else {
            check("the document encodes", false)
            return
        }
        check("the encoded file names it once", occurrences(of: "\"note\" : \"the empty state\"", in: json) == 1)
        check("and writes nothing where there is nothing", occurrences(of: "\"note\"", in: json) == 1)

        // The contract is read by the `pinpoint` CLI, including one built before
        // this key existed — and a file written by an older app is read by the
        // CLI shipping today. Both directions have to survive.
        let older = json.replacingOccurrences(of: "\"note\" : \"the empty state\",\n", with: "")
        check("a capture.json written before the key still decodes",
              (try? JSONDecoder().decode(FileHandoff.Document.self,
                                         from: Data(older.utf8)))?.shapes.first?.note == nil)
    }

    // MARK: - The legend baked into the image

    static func legendGrowsOnlyWhenThereIsSomethingToSay() {
        print("\n── the legend strip ──")
        let base = blankImage(width: 400, height: 300)
        let bare = Markup(kind: .rectangle, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.3, y: 0.4))
        var described = bare
        described.note = "the tab bar wraps at this width"

        func height(_ shapes: [Markup]) -> CGFloat {
            Exporter.exportImage(base: base, pins: [], shapes: shapes, context: "",
                                 style: .disc, includeLegend: true).size.height
        }

        // No markers, no instructions, no described shape: there is nothing to
        // write, and the export must be the annotated capture and nothing else —
        // exactly the image this build's predecessor produced.
        check("an undescribed shape adds no strip", height([bare]) == base.size.height)
        check("a described one does", height([described]) > base.size.height)
        check("and a description in whitespace alone counts as none",
              height([Markup(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1), note: " \n ")])
                  == base.size.height)
    }

    // MARK: - Harness

    static func check(_ what: String, _ passed: Bool) {
        print("   \(passed ? "✓" : "✗") \(what)")
        if !passed { failures += 1 }
    }

    static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    /// A plain white capture. The pixels are irrelevant here — only how much
    /// taller the export gets than what it started from.
    static func blankImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
}
