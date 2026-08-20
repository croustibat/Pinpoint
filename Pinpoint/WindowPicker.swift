import AppKit
import CoreGraphics
import ScreenCaptureKit

/// One window the user can point at while choosing what to capture (#51).
///
/// It carries the same rectangle twice, because two coordinate spaces are
/// unavoidable here: ScreenCaptureKit and the accessibility APIs both speak
/// points with a **global top-left** origin, while the selection overlay draws
/// in AppKit's **global bottom-left** one. Converting once, at discovery, keeps
/// every call site from having to remember which is which.
struct PickableWindow: Equatable, Sendable {
    let id: CGWindowID
    let processIdentifier: pid_t
    let applicationName: String?
    let title: String?
    /// Points, global top-left origin — the space `SCWindow.frame` is in.
    let screenFrame: CGRect
    /// The same rectangle in global AppKit coordinates (bottom-left origin).
    let overlayFrame: CGRect

    /// `Safari — Apple`, or just the application when the window is untitled.
    /// Shown on the overlay badge and announced to VoiceOver.
    var displayName: String {
        let title = (self.title?.isEmpty == false) ? self.title : nil
        switch (applicationName, title) {
        case let (app?, title?): return "\(app) — \(title)"
        case let (app?, nil):    return app
        case let (nil, title?):  return title
        case (nil, nil):
            return String(localized: "window.untitled", defaultValue: "Untitled window")
        }
    }
}

/// Lists the windows a capture can target, front-to-back.
///
/// Everything here is best-effort: a failure to enumerate simply means window
/// mode has nothing to highlight, never that a capture fails.
@MainActor
enum WindowPicker {

    /// Smallest window worth offering. System processes keep one- and
    /// zero-pixel windows around that nobody could ever point at.
    private static let minSide: CGFloat = 8

    /// The windows a capture can target, frontmost first.
    static func candidates() async -> [PickableWindow] {
        // `excludingDesktopWindows: true` drops the wallpaper and the desktop
        // icon layer; `onScreenWindowsOnly: true` drops minimised windows and
        // everything living on another Space.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        ) else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let order = frontToBackOrder()
        let flipAxis = flipAxis()
        let screens = NSScreen.screens.map(\.frame)

        return content.windows
            .filter { isPickable($0, ownPID: ownPID) }
            .sorted { (order[$0.windowID] ?? .max) < (order[$1.windowID] ?? .max) }
            .compactMap { window -> PickableWindow? in
                guard let app = window.owningApplication else { return nil }
                let overlay = overlayFrame(for: window.frame, flippingAbout: flipAxis)
                // A window parked entirely off the visible desktop can't be
                // pointed at, so it isn't offered.
                guard screens.contains(where: { $0.intersects(overlay) }) else { return nil }
                return PickableWindow(
                    id: window.windowID,
                    processIdentifier: app.processID,
                    applicationName: app.applicationName,
                    title: window.title,
                    screenFrame: window.frame,
                    overlayFrame: overlay
                )
            }
    }

    /// The frontmost candidate under `point` (global AppKit coordinates), or nil
    /// over bare desktop. `candidates` is already front-to-back, so the first
    /// hit is the one the user can actually see.
    static func window(at point: CGPoint, in candidates: [PickableWindow]) -> PickableWindow? {
        candidates.first { $0.overlayFrame.contains(point) }
    }

    // MARK: - Filtering

    /// Only ordinary application windows are offered.
    ///
    /// `windowLayer == 0` is doing most of the work, and it is deliberate rather
    /// than incidental: everything that floats above the normal level is either
    /// not a window the user thinks of as one (the menu bar, Control Center's
    /// one-window-per-icon menu extras, the orange recording indicator) or is
    /// actively harmful to offer. Notification Center's host window is the case
    /// that bites — layer 21, full-screen, alpha 1, permanently "on screen"
    /// whether or not the panel is open, and ranked in front of every real
    /// window (#55 hit the same thing while walking the accessibility tree).
    /// Highlighting it would put an invisible full-screen rectangle over the
    /// app the user is actually pointing at.
    private static func isPickable(_ window: SCWindow, ownPID: pid_t) -> Bool {
        guard window.isOnScreen, window.windowLayer == 0 else { return false }
        guard let app = window.owningApplication, app.processID != ownPID else { return false }
        return window.frame.width >= minSide && window.frame.height >= minSide
    }

    // MARK: - Ordering

    /// Window numbers mapped to their front-to-back rank.
    ///
    /// `SCShareableContent.windows` makes no promise about ordering, and the
    /// whole point of hovering is to highlight the window on top. The Core
    /// Graphics window list does guarantee it, so it is used purely as the
    /// ranking and joined back by window number.
    private static func frontToBackOrder() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        for (rank, window) in raw.enumerated() {
            guard let number = window[kCGWindowNumber as String] as? CGWindowID else { continue }
            if order[number] == nil { order[number] = rank }
        }
        return order
    }

    // MARK: - Coordinate conversion

    /// The horizontal line both spaces are mirrored about: the top edge of the
    /// screen whose AppKit origin is (0, 0), which is also Core Graphics' own
    /// origin. Every other display — including one sitting at a negative AppKit
    /// origin (#26) — falls out of the same single flip.
    private static func flipAxis() -> CGFloat {
        let zeroScreen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return zeroScreen?.frame.maxY ?? 0
    }

    private static func overlayFrame(for cgFrame: CGRect, flippingAbout axis: CGFloat) -> CGRect {
        CGRect(x: cgFrame.minX, y: axis - cgFrame.maxY, width: cgFrame.width, height: cgFrame.height)
    }
}
