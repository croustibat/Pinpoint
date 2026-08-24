import CoreGraphics
import Foundation

/// A non-numbered visual annotation (arrow, rectangle or redaction) drawn on
/// the capture.
///
/// Unlike `Pin`, markups carry no number: they are listed under their own
/// heading in the export rather than in the numbered sequence drawn on the
/// image. They do carry a description (#93) — see `note` — so a circled region
/// can say *why* it was circled and not only where it is; the agent-ready text
/// states each one's kind, endpoints and bounding box either way, so an agent
/// can situate them without the image.
/// Coordinates are normalized (0...1) in image space, top-left origin (same
/// convention as `Pin`), so they scale with the canvas and export correctly.
struct Markup: Identifiable, Equatable, Codable {
    enum Kind: String, Equatable, Codable {
        case arrow
        case rectangle
        /// A region painted over before the capture leaves the app (#50).
        ///
        /// Deliberately a `Kind` and not a type of its own: a redaction is
        /// drawn, selected, moved, resized, deleted and undone exactly like the
        /// other shapes, and every one of those behaviours already exists for
        /// them. What makes it different is not its geometry but what the
        /// exporters do with it — see `RedactionMask`.
        case redaction
    }

    var id = UUID()
    var kind: Kind
    /// Arrow: tail. Rectangle/redaction: one corner.
    var start: CGPoint
    /// Arrow: tip (where the arrowhead is). Rectangle/redaction: opposite corner.
    var end: CGPoint

    /// What the user wrote about this shape (#93). Empty when they wrote
    /// nothing, which stays the common case — a shape is worth drawing on its
    /// own, and the field is an offer rather than a form to fill in.
    ///
    /// Always the user's own words, with no machine-read twin: nothing
    /// pre-fills it the way a marker's note can be pre-filled from an OCR read,
    /// so there is no second provenance to keep apart here — which is precisely
    /// what `Pin.recognized` exists for, and why nothing like it belongs on
    /// this type.
    ///
    /// A redaction carries one too, deliberately. "What I hid, and why" is the
    /// one thing that can be said about a hidden area without undoing the
    /// redaction — and it is said by the user, never read out of the pixels.
    var note: String = ""

    /// Order-independent normalized rect (for rectangle and redaction markups).
    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Whether this markup hides pixels rather than pointing at them.
    var isRedaction: Bool { kind == .redaction }

    var label: String {
        switch kind {
        case .arrow: return String(localized: "Arrow")
        case .rectangle: return String(localized: "Rectangle")
        // Names the shape, never its contents: this string is read by the agent
        // and by VoiceOver, and "what was hidden" is precisely what must not
        // travel with the capture.
        case .redaction: return String(localized: "markup.redaction", defaultValue: "Hidden area")
        }
    }

    var symbol: String {
        switch kind {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .redaction: return "eye.slash"
        }
    }

    /// The description with its surrounding whitespace gone, or nil when there
    /// is nothing left of it.
    ///
    /// Every consumer asks the same question — "is there something to print
    /// here?" — so it is asked once, in one place. Nil rather than an empty
    /// string because that is the shape of the answer: the exporters, the
    /// legend and the JSON contract all omit the description entirely when
    /// there is none, which is what keeps a capture without descriptions
    /// exporting exactly as it did before this field existed.
    var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Placeholder of this shape's description field in the side panel.
    ///
    /// Names the shape it belongs to, because the panel shows a column of
    /// otherwise identical fields and the icon beside them is the only other
    /// thing telling them apart. One string per kind rather than one string
    /// interpolating `label`: French agrees the determiner with the noun
    /// ("ce rectangle", "cette flèche"), and a single template can't.
    var notePlaceholder: String {
        switch kind {
        case .arrow:
            return String(localized: "markup.note.placeholder.arrow",
                          defaultValue: "Describe this arrow…")
        case .rectangle:
            return String(localized: "markup.note.placeholder.rectangle",
                          defaultValue: "Describe this rectangle…")
        case .redaction:
            return String(localized: "markup.note.placeholder.redaction",
                          defaultValue: "Describe this hidden area…")
        }
    }

    /// What VoiceOver calls that field. Without it the placeholder becomes the
    /// label, and two rectangles announce themselves identically.
    var noteAccessibilityLabel: String {
        switch kind {
        case .arrow:
            return String(localized: "a11y.shape.note.arrow",
                          defaultValue: "Description of this arrow")
        case .rectangle:
            return String(localized: "a11y.shape.note.rectangle",
                          defaultValue: "Description of this rectangle")
        case .redaction:
            return String(localized: "a11y.shape.note.redaction",
                          defaultValue: "Description of this hidden area")
        }
    }
}

extension Markup {
    /// Decodes a markup, tolerating a file written before `note` existed (#93).
    ///
    /// Hand-written rather than left to the synthesized initializer, which
    /// would `decode` a non-optional `String` and throw on every markup
    /// recorded by an earlier version. That throw would not stay local:
    /// `CaptureHistory.load()` decodes the whole `index.json` as one array with
    /// `try?`, so a single old shape would empty the history — and the next
    /// `saveIndex()` would write that emptiness back to disk. The upgrade would
    /// silently delete the user's recent captures.
    ///
    /// In an extension so the memberwise initializer survives; `CodingKeys` and
    /// `encode(to:)` are still synthesized from the stored properties.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.start = try container.decode(CGPoint.self, forKey: .start)
        self.end = try container.decode(CGPoint.self, forKey: .end)
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

extension Array where Element == Markup {
    /// The shapes in the order they must be drawn: redactions first, then
    /// everything else.
    ///
    /// One definition for both surfaces — the editor canvas and `Exporter` —
    /// so the preview and the exported image stack them identically. The order
    /// matters twice over: an arrow or a rectangle drawn *before* a redaction
    /// would otherwise be swallowed by the bar that came after it, and a
    /// redaction dropped last over a numbered marker would hide the marker
    /// itself. Markers are drawn last of all by both sides, above every shape.
    var inDrawOrder: [Markup] {
        filter(\.isRedaction) + filter { !$0.isRedaction }
    }
}
