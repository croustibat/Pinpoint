import AppKit
import SwiftUI

/// Hosts the SwiftUI settings UI in a plain AppKit window.
///
/// macOS 14+ deprecated the programmatic way to open the SwiftUI `Settings`
/// scene (`showSettingsWindow:`), which doesn't work for menu-bar (`LSUIElement`)
/// apps and logs "Please use SettingsLink…". Presenting our own window — the same
/// way the editor window is shown — opens reliably and avoids that path entirely.
final class SettingsWindowController: NSWindowController {
    init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Réglages Pinpoint"
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
