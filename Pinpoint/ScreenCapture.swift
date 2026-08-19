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
    static func captureDisplayUnderCursor() async throws -> NSImage {
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

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Captures a single region of one display, at native (Retina) resolution.
    ///
    /// The region's `rect` is passed straight through as the configuration's
    /// `sourceRect` (points, top-left origin, display-relative), while the output
    /// pixel dimensions are the region size multiplied by the display scale — so
    /// the result keeps native resolution without any rescaling.
    @MainActor
    static func captureRegion(_ region: CaptureRegion) async throws -> NSImage {
        guard await ensurePermission() else { throw ScreenCaptureError.permissionDenied }

        let content = try await SCShareableContent.current

        guard let display = content.displays.first(where: { $0.displayID == region.displayID })
                ?? content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }

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

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
