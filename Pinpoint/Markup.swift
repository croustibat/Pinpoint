import CoreGraphics
import Foundation

/// A non-numbered visual annotation (arrow, rectangle or redaction) drawn on
/// the capture.
///
/// Unlike `Pin`, markups carry no number and no user description: they're
/// visual emphasis. The agent-ready text still describes each of them (kind,
/// endpoints and bounding box) so an agent can situate them without the image.
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
