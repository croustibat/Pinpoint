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
