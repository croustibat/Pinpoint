import Foundation

/// A persisted capture: the raw image (stored as a PNG file alongside) plus the
/// annotation state, so it can be reopened from "Captures récentes" exactly as
/// it was left.
struct CaptureRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// PNG file name within the history directory.
    let imageFileName: String
    /// Pixel dimensions of the capture (used to rebuild the NSImage at native
    /// size). `var` so a crop can replace the image without a new record.
    var width: Int
    var height: Int
    var pins: [Pin]
    var shapes: [Markup]
    var context: String
}
