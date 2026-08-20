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
    /// Name of the accessibility sidecar (`<uuid>-ax.json`) in the same
    /// directory, when one was written (#55).
    ///
    /// A sidecar rather than a field on this record: a snapshot runs to a few
    /// hundred elements, and `index.json` is read in full at every launch. Nil
    /// for captures taken before the feature existed, taken without the
    /// Accessibility permission, or taken with it switched off — which is also
    /// why decoding an older index still works: an absent key decodes to nil.
    var axFileName: String?
}
