import AppKit
import SwiftUI

/// Hosts `ScreenshotDetailView` for a single shelf item in a plain AppKit window.
///
/// SnapShelf opened the detail view through SwiftUI's `openWindow(id:)`, but
/// Pinpoint registers no `WindowGroup` for it — so we present our own window,
/// the same way the editor and shelf are shown.
@MainActor
final class ScreenshotDetailWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(item: ScreenshotItem, store: ScreenshotStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = item.filename
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let root = ScreenshotDetailContainer(item: item, store: store) { [weak window] in
            window?.close()
        }
        .environmentObject(store)
        window.contentView = NSHostingView(rootView: root)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// Wraps `ScreenshotDetailView` and observes the store so the favorite state
/// stays live (the detail view takes `isFavorite` as a plain value).
private struct ScreenshotDetailContainer: View {
    @ObservedObject var store: ScreenshotStore
    let item: ScreenshotItem
    let onClose: () -> Void

    init(item: ScreenshotItem, store: ScreenshotStore, onClose: @escaping () -> Void) {
        self.item = item
        self.store = store
        self.onClose = onClose
    }

    var body: some View {
        ScreenshotDetailView(
            item: item,
            isFavorite: store.isFavorite(item),
            onToggleFavorite: { store.toggleFavorite(item) },
            onQuickLook: { store.quickLook(item) },
            onReveal: { store.revealInFinder(item) },
            onCopyImage: { store.copyImage(item) },
            onCopyPath: { store.copyPaths([item]) },
            onMove: { store.move(item) },
            onDelete: { store.delete(item) },
            onClose: onClose
        )
    }
}
