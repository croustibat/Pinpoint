import ApplicationServices
import AppKit

/// The Accessibility (a.k.a. "control your computer") permission, which is what
/// lets Pinpoint read the accessibility tree of *other* apps and turn a visual
/// marker into a named UI element (#55).
///
/// Deliberately a separate grant from Screen Recording: a user who only wants
/// screenshots never has to hand this one over. Everything here therefore
/// follows one rule — **nothing prompts on its own**. The capture path only ever
/// reads `isTrusted`, which is free and silent; the system prompt and the
/// explanatory alert are reachable only from an explicit click in Settings.
///
/// The alert itself mirrors `ScreenCapture.presentPermissionAlert()`: same
/// shape, same deep link into the matching System Settings pane, so the two
/// permissions read as one idea rather than two inventions.
enum AXPermission {

    /// System Settings ▸ Privacy & Security ▸ Accessibility.
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    /// Whether macOS currently lets Pinpoint read other apps' accessibility
    /// trees. Cheap, side-effect free, and — unlike
    /// `AXIsProcessTrustedWithOptions(prompt: true)` — never puts anything on
    /// screen. This is the only entry point the capture flow is allowed to use.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS for the grant, then explains where to finish the job.
    ///
    /// The system dialog raised by `kAXTrustedCheckOptionPrompt` only *offers* a
    /// shortcut to System Settings and always returns the current (still false)
    /// state, so a "granted / not granted" return value would be a lie. Instead
    /// we open the pane ourselves after a short beat, which is the step users
    /// actually have to perform.
    ///
    /// Only ever called from the Settings toggle — see the type comment.
    @MainActor
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return }
        presentPermissionAlert()
    }

    /// States what the feature needs and offers a one-click jump to the right
    /// pane. Kept in the same voice as the Screen Recording alert.
    @MainActor
    static func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "permission.accessibility.title",
                                   defaultValue: "Pinpoint can’t read the interface")
        alert.informativeText = String(
            localized: "permission.accessibility.body",
            defaultValue: "To name the element under each marker, Pinpoint needs the Accessibility permission. Open System Settings ▸ Privacy & Security ▸ Accessibility, turn Pinpoint on, then relaunch the app. Captures keep working without it — they just carry no interface details."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "permission.accessibility.openSettings",
                                          defaultValue: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    /// Deep-links into System Settings ▸ Privacy & Security ▸ Accessibility.
    static func openSettings() {
        guard let settingsURL else { return }
        NSWorkspace.shared.open(settingsURL)
    }
}

/// User-facing switches for the accessibility context, and the single place the
/// capture path reads them from.
///
/// `@AppStorage` can't be used off a SwiftUI view, and the capture runs long
/// before any view exists, so the defaults are spelled out here once and the
/// Settings screen binds to the very same keys.
enum AXContextSettings {
    /// Whether to describe the element under each marker at all.
    static let enabledKey = "axContextEnabled"
    /// Whether the text a user typed into ordinary fields may leave the machine.
    static let fieldValuesKey = "axContextIncludesFieldValues"

    /// On by default: with no Accessibility grant this changes nothing at all
    /// (the walk is skipped, silently), so the switch only starts to matter for
    /// someone who has already, explicitly, allowed it.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Off by default, on purpose. A capture is handed to an outside agent, and
    /// the accessibility tree hands out the *full* contents of a field — including
    /// the part scrolled out of view, which the pixels never showed. Secure
    /// fields are never read whatever this says; see `AXSnapshotCollector`.
    static var includesFieldValues: Bool {
        UserDefaults.standard.bool(forKey: fieldValuesKey)
    }

    /// Whether a capture should actually walk the tree: asked for, and allowed.
    static var shouldCapture: Bool { isEnabled && AXPermission.isTrusted }
}
