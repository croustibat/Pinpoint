import CoreGraphics

/// A resolved screen region to capture.
///
/// `rect` follows the ScreenCaptureKit `sourceRect` convention: points,
/// **top-left** origin, relative to the target display. `scale` is that
/// display's `backingScaleFactor`, so the capture can be requested at native
/// (Retina) pixel resolution.
struct CaptureRegion: Equatable {
    let displayID: CGDirectDisplayID
    /// Selection rect in points, top-left origin, relative to the display.
    let rect: CGRect
    /// Backing scale factor of the target display.
    let scale: CGFloat
}
