import CoreGraphics
import Foundation

/// A numbered marker placed on the captured image.
/// `position` is normalized (0...1) in image space, top-left origin.
struct Pin: Identifiable, Equatable, Codable {
    var id = UUID()
    var number: Int
    var position: CGPoint
    var note: String = ""
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
