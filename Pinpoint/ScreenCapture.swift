import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case noDisplay
    /// Screen recording is not authorized. `ScreenCapture` has already shown the
    /// dedicated alert (see `ensurePermission()`), so callers only have to abort.
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: return String(localized: "No screen available for capture.")
        case .permissionDenied:
            return String(localized: "permission.screenRecording.error",
                          defaultValue: "Pinpoint isn’t allowed to record the screen.")
        }
    }
}

enum ScreenCapture {

    /// What one capture produced: the pixels, plus the accessibility tree that
    /// covered them at that instant (#55).
    ///
    /// The two travel together on purpose. Markers are placed later, in the
    /// editor, when the photographed UI may already be gone — so the only moment
    /// the tree can be read is this one. `accessibility` is nil whenever the
    /// feature is off, unauthorized, or simply found nothing: it is context, and
    /// its absence never turns a successful capture into a failure.
    struct Capture {
        let image: NSImage
        let accessibility: AXSnapshot?
    }

    // MARK: - Screen recording permission

    /// System Settings ▸ Privacy & Security ▸ Screen Recording.
    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    /// Whether macOS currently grants Pinpoint screen-recording access.
    /// Cheap and side-effect free — never prompts.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Preflight to run *before* anything user-visible starts (selection overlay,
    /// countdown, capture). Returns `true` when a capture may proceed.
    ///
    /// Without it, `SCShareableContent` is queried cold and fails after the user
    /// has already dragged a region and waited out the timer.
    ///
    /// When access is missing it asks the system once — macOS shows its own
    /// authorization sheet on first use, and silently returns `false` forever
    /// after a denial — then falls back to an explicit alert that deep-links into
    /// the right System Settings pane.
    @MainActor
    static func ensurePermission() async -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        // Off the main actor: the call can block for as long as the system sheet
        // is on screen, which would freeze the menu bar.
        let granted = await Task.detached { CGRequestScreenCaptureAccess() }.value
        if granted { return true }

        presentPermissionAlert()
        return false
    }

    /// Explains why the capture was abandoned and offers a one-click jump to the
    /// Screen Recording pane — the previous message only told users to relaunch.
    @MainActor
    static func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "permission.screenRecording.title",
                                   defaultValue: "Pinpoint can’t record the screen")
        alert.informativeText = String(
            localized: "permission.screenRecording.body",
            defaultValue: "Captures stay blocked until Pinpoint is allowed to record the screen. Open System Settings ▸ Privacy & Security ▸ Screen Recording, turn Pinpoint on, then relaunch the app."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "permission.screenRecording.openSettings",
                                          defaultValue: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }

    /// Deep-links into System Settings ▸ Privacy & Security ▸ Screen Recording.
    static func openScreenRecordingSettings() {
        guard let screenRecordingSettingsURL else { return }
        NSWorkspace.shared.open(screenRecordingSettingsURL)
    }

    /// `true` for the error thrown when the preflight failed — its alert has
    /// already been shown, so the generic "Capture failed" one must be skipped.
    static func isPermissionError(_ error: Error) -> Bool {
        guard let error = error as? ScreenCaptureError else { return false }
        if case .permissionDenied = error { return true }
        return false
    }

    // MARK: - Capture

    /// Captures the full display that currently contains the mouse cursor,
    /// at native (Retina) resolution, using ScreenCaptureKit.
    @MainActor
    static func captureDisplayUnderCursor() async throws -> Capture {
        guard await ensurePermission() else { throw ScreenCaptureError.permissionDenied }

        let content = try await SCShareableContent.current

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let targetID = screen?.displayID

        guard let display = content.displays.first(where: { $0.displayID == targetID })
                ?? content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }

        let scale = screen?.backingScaleFactor ?? 2.0

        let filter = SCContentFilter(display: display,
                                     excludingApplications: ownApplications(in: content),
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.scalesToFit = false

        // A whole-display capture is a region capture whose region happens to be
        // the display: expressing it that way lets the accessibility snapshot use
        // one mapping rule instead of two.
        let region = CaptureRegion(
            displayID: display.displayID,
            rect: CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height)),
            scale: scale
        )

        async let snapshot = accessibilitySnapshot(for: region)
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(
            image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
            accessibility: await snapshot
        )
    }

    /// Captures a single region of one display, at native (Retina) resolution.
    ///
    /// The region's `rect` is passed straight through as the configuration's
    /// `sourceRect` (points, top-left origin, display-relative), while the output
    /// pixel dimensions are the region size multiplied by the display scale — so
    /// the result keeps native resolution without any rescaling.
    @MainActor
    static func captureRegion(_ region: CaptureRegion) async throws -> Capture {
        guard await ensurePermission() else { throw ScreenCaptureError.permissionDenied }

        let content = try await SCShareableContent.current

        // Window mode (#51). The window is looked up again *now* rather than
        // trusted from selection time: the capture delay gives it every chance
        // to have moved, resized, or gone. If it's gone, the rect it occupied is
        // still known, so the capture quietly degrades to the region below
        // instead of failing.
        if let target = region.window,
           let window = content.windows.first(where: { $0.windowID == target.id }) {
            return try await capture(window: window, target: target, on: region.displayID)
        }

        guard let display = content.displays.first(where: { $0.displayID == region.displayID })
                ?? content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }

        // A window capture only reaches this line when its window vanished
        // between the pick and the shutter. Such a rect is the window's own
        // frame, which — unlike a dragged rectangle — is free to run past the
        // display it was resolved against, and a `sourceRect` that does comes
        // back stretched. Clamping it keeps the fallback honest: a smaller
        // picture of the right place, at the right scale.
        let region = region.window == nil ? region : region.clampedToDisplay(display)

        let filter = SCContentFilter(display: display,
                                     excludingApplications: ownApplications(in: content),
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.sourceRect = region.rect
        config.width = Int((region.rect.width * region.scale).rounded())
        config.height = Int((region.rect.height * region.scale).rounded())
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best

        // Started before the screenshot rather than after it, so both describe
        // the same instant. It never throws and never blocks past its own
        // ceiling, so awaiting it here can only delay the capture, never break
        // it — and if `captureImage` throws first, the child task is cancelled
        // with the scope.
        async let snapshot = accessibilitySnapshot(for: region)
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(
            image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
            accessibility: await snapshot
        )
    }

    /// Captures one window on its own: no desktop behind it, no neighbouring
    /// windows in front of it, transparent rounded corners.
    ///
    /// ## Why shadows are dropped
    ///
    /// `SCContentFilter(desktopIndependentWindow:)` reports a `contentRect`
    /// equal to the window's own frame, and asking for it at
    /// `pointPixelScale` yields an image aligned to that frame pixel for pixel.
    /// Keeping the drop shadow does *not* enlarge the image: ScreenCaptureKit
    /// fits "window + shadow" into the size that was asked for, which shrinks
    /// the window itself and shifts it (measured on a 1798×1041 pt window: the
    /// opaque content landed at 3247×1881 px offset by 101, 68 instead of
    /// filling 3596×2082). That resamples the pixels *and* breaks the one
    /// invariant this whole feature rests on — that `CaptureRegion.rect` is
    /// exactly the piece of screen the image shows, which is what maps a marker
    /// back to an accessibility element (#55). Dropping the shadow keeps the
    /// mapping exact and still gives clean edges: the corners come back
    /// genuinely transparent, so the PNG carries the window's real silhouette.
    @MainActor
    private static func capture(window: SCWindow,
                                target: CaptureRegion.WindowTarget,
                                on displayID: CGDirectDisplayID) async throws -> Capture {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let contentRect = filter.contentRect

        let config = SCStreamConfiguration()
        config.width = Int((contentRect.width * scale).rounded())
        config.height = Int((contentRect.height * scale).rounded())
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true

        // The region the image actually covers, rebuilt from the filter rather
        // than from what the overlay resolved: those can differ by the time the
        // shutter fires. `contentRect` is global and top-left, the display's
        // bounds are in the same space, so the subtraction is all it takes to
        // get back to the display-relative rect the rest of the app expects.
        let displayOrigin = CGDisplayBounds(displayID).origin
        let effective = CaptureRegion(
            displayID: displayID,
            rect: contentRect.offsetBy(dx: -displayOrigin.x, dy: -displayOrigin.y),
            scale: scale,
            window: CaptureRegion.WindowTarget(
                id: target.id,
                processIdentifier: target.processIdentifier,
                applicationName: target.applicationName,
                title: target.title,
                screenFrame: contentRect
            )
        )

        async let snapshot = accessibilitySnapshot(for: effective)
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(
            image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
            accessibility: await snapshot
        )
    }

    /// Reads the accessibility tree over `region`, or nothing at all.
    ///
    /// The two gates are checked here, together, so no other call site has to
    /// remember them: the feature has to be switched on, and macOS has to have
    /// granted Accessibility. Neither ever prompts — a user who never asked for
    /// this sees precisely the app they had before (#55).
    private static func accessibilitySnapshot(for region: CaptureRegion) async -> AXSnapshot? {
        guard AXContextSettings.shouldCapture else { return nil }
        return await AXSnapshotCollector.capture(
            region: region,
            includeFieldValues: AXContextSettings.includesFieldValues
        )
    }

    /// Pinpoint's own running application(s), so its windows (a leftover editor,
    /// the shelf, the dimming overlay…) are never part of a capture.
    private static func ownApplications(in content: SCShareableContent) -> [SCRunningApplication] {
        let pid = ProcessInfo.processInfo.processIdentifier
        return content.applications.filter { $0.processID == pid }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
