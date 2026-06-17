import AppKit
import SwiftUI

/// Hosts the screenshot library (SnapShelf's `ShelfView`) in a plain AppKit
/// window, owning its store/view-model and starting the folder watcher.
///
/// Phase 1 of the SnapShelf → Pinpoint merge: the shelf is reachable from the
/// menu without touching the capture/editor flows. (SnapShelf's own
/// `MenuBarExtra`/`Settings`/`WindowGroup` scenes are intentionally not brought
/// over — Pinpoint owns the menu bar and app lifecycle.)
@MainActor
final class ShelfWindowController: NSWindowController {
    private let store = ScreenshotStore()
    private let settingsViewModel = SettingsViewModel()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Étagère"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PinpointShelfWindow")

        let root = ShelfView()
            .environmentObject(store)
            .environmentObject(settingsViewModel)
        window.contentView = NSHostingView(rootView: root)

        super.init(window: window)
        window.center()

        settingsViewModel.bind(to: store)
        Task { await store.start() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
