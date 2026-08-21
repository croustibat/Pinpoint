import CoreGraphics
import Foundation

/// A numbered marker placed on the captured image.
/// `position` is normalized (0...1) in image space, top-left origin.
struct Pin: Identifiable, Equatable, Codable {
    var id = UUID()
    var number: Int
    var position: CGPoint
    var note: String = ""
    /// The text Pinpoint read in the pixels under this marker (#49).
    ///
    /// Kept apart from `note` so the two provenances never blur: `note` is what
    /// the user wrote — even when it started life as a copy of this — and this
    /// is what the machine read. Nothing downstream has to guess which it is
    /// holding, and the editor can take back its own pre-fill when a redaction
    /// covers the source without ever touching a word the user typed.
    ///
    /// Nil when nothing legible sat within reach, when the marker is on a
    /// redacted region, when the accessibility tree already named the same
    /// thing (see `EditorView.syncRecognizedText`), or when the feature is off.
    var recognized: RecognizedText?
}

extension UUID {
    /// Short, readable form of the identifier (first 6 hex characters), used to
    /// give every annotation a stable ID in the agent-ready text: it survives
    /// the renumbering that follows a deletion, so two exports of the same
    /// session refer to the same marker by the same code.
    var shortToken: String {
        String(uuidString.prefix(6)).lowercased()
    }
}
