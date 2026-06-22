import CoreGraphics
import Foundation

/// A non-numbered visual annotation (arrow or rectangle) drawn on the capture.
///
/// Unlike `Pin`, markups are not numbered and are not referenced in the
/// agent-ready text — they're purely visual emphasis. Coordinates are
/// normalized (0...1) in image space, top-left origin (same convention as
/// `Pin`), so they scale with the canvas and export correctly.
struct Markup: Identifiable, Equatable, Codable {
    enum Kind: String, Equatable, Codable {
        case arrow
        case rectangle
    }

    var id = UUID()
    var kind: Kind
    /// Arrow: tail. Rectangle: one corner.
    var start: CGPoint
    /// Arrow: tip (where the arrowhead is). Rectangle: opposite corner.
    var end: CGPoint

    /// Order-independent normalized rect (for rectangle markups).
    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    var label: String {
        switch kind {
        case .arrow: return String(localized: "Arrow")
        case .rectangle: return String(localized: "Rectangle")
        }
    }

    var symbol: String {
        switch kind {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        }
    }
}
