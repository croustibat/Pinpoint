import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay: return String(localized: "No screen available for capture.")
        }
    }
}

enum ScreenCapture {
    /// Captures the full display that currently contains the mouse cursor,
    /// at native (Retina) resolution, using ScreenCaptureKit.
    @MainActor
    static func captureDisplayUnderCursor() async throws -> NSImage {
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
