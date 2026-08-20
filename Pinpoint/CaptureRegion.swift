import CoreGraphics
import ScreenCaptureKit

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
    /// Set when the capture targets one window rather than a screen rectangle
    /// (#51). It changes *how* the pixels are read — a window filter instead of
    /// a source rect — while `rect` keeps describing the same thing: the piece
    /// of screen the resulting image covers. Everything downstream (the
    /// accessibility snapshot, the marker → screen-point mapping of #55) reads
    /// `rect` and needs no special case.
    let window: WindowTarget?

    init(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat, window: WindowTarget? = nil) {
        self.displayID = displayID
        self.rect = rect
        self.scale = scale
        self.window = window
    }

    /// The same region cut down to what `display` can actually answer for, with
    /// the window target dropped — the result no longer describes that window.
    /// A degenerate intersection leaves the region untouched: there is nothing
    /// better to offer, and the caller's own failure path is the honest one.
    func clampedToDisplay(_ display: SCDisplay) -> CaptureRegion {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        let clamped = rect.intersection(bounds)
        guard clamped.width >= 1, clamped.height >= 1 else { return self }
        return CaptureRegion(displayID: displayID, rect: clamped, scale: scale)
    }

    /// The window a capture is aimed at, identified well enough to be found
    /// again at capture time and to be matched against the accessibility tree.
    struct WindowTarget: Equatable {
        let id: CGWindowID
        let processIdentifier: pid_t
        let applicationName: String?
        let title: String?
        /// The window's frame in points, global **top-left** origin — the space
        /// `AXFrame` also reports in, which is what lets the accessibility walk
        /// pick the matching `AXWindow` out of an application that has several.
        let screenFrame: CGRect
    }
}
