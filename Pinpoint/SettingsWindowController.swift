import AppKit
import SwiftUI

/// Hosts the SwiftUI settings UI in a plain AppKit window.
///
/// macOS 14+ deprecated the programmatic way to open the SwiftUI `Settings`
/// scene (`showSettingsWindow:`), which doesn't work for menu-bar (`LSUIElement`)
/// apps and logs "Please use SettingsLink…". Presenting our own window — the same
/// way the editor window is shown — opens reliably and avoids that path entirely.
///
/// The window uses a fixed content size + `NSHostingView` (not
/// `NSWindow(contentViewController:)`), because letting the window auto-size to a
/// SwiftUI `Form` triggers a constraint-update loop ("more Update Constraints
/// passes than there are views").
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Pinpoint Settings")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())

        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
