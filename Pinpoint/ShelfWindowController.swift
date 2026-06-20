import AppKit
import SwiftUI

/// Hosts the screenshot library (`ShelfView`) in a plain AppKit window, driving
/// the shared `ScreenshotStore` and starting the folder watcher.
///
/// SnapShelf's own `MenuBarExtra`/`Settings`/`WindowGroup` scenes are not brought
/// over — Pinpoint owns the menu bar and app lifecycle. The shelf therefore can't
/// rely on SwiftUI's `openWindow`/`showSettingsWindow:`; instead it calls back
/// here to open the unified settings window (via notification) and to present a
/// detail window per screenshot.
@MainActor
final class ShelfWindowController: NSWindowController {
    private let store = ScreenshotStore.shared
    private var detailControllers: [URL: ScreenshotDetailWindowController] = [:]

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

        super.init(window: window)

        let root = ShelfView(
            onOpenSettings: {
                NotificationCenter.default.post(name: .pinpointOpenSettings, object: nil)
            },
            onOpenDetail: { [weak self] item in
                self?.presentDetail(for: item)
            }
        )
        .environmentObject(store)
        window.contentView = NSHostingView(rootView: root)

        window.center()
        Task { await store.start() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func presentDetail(for item: ScreenshotItem) {
        if let existing = detailControllers[item.url] {
            NSApp.activate(ignoringOtherApps: true)
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ScreenshotDetailWindowController(item: item, store: store)
        controller.onClose = { [weak self] in self?.detailControllers[item.url] = nil }
        detailControllers[item.url] = controller

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
