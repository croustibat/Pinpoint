import AppKit
import SwiftUI

/// Hosts the SwiftUI annotation editor in a standard window.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(image: NSImage) {
        // Size the window to the image, capped to a comfortable on-screen size.
        let maxSize = NSSize(width: 1100, height: 760)
        let imgSize = image.size
        let scale = min(1, min(maxSize.width / imgSize.width, maxSize.height / imgSize.height))
        let canvasSize = NSSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let contentSize = NSSize(width: canvasSize.width + 280, height: max(canvasSize.height, 420))

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pinpoint"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        let root = EditorView(image: image) { [weak window] in
            window?.close()
        }
        window.contentView = NSHostingView(rootView: root)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
