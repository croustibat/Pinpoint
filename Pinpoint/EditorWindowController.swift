import AppKit
import SwiftUI

/// Hosts the SwiftUI annotation editor in a standard window.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(
        image: NSImage,
        initialPins: [Pin] = [],
        initialShapes: [Markup] = [],
        initialContext: String = "",
        initialAccessibility: AXSnapshot? = nil,
        sourceURL: URL? = nil,
        onPersist: @escaping ([Pin], [Markup], String, NSImage, AXSnapshot?) -> Void = { _, _, _, _, _ in }
    ) {
        // Size the window to the image, capped to a comfortable on-screen size.
        let maxSize = NSSize(width: 1100, height: 760)
        let imgSize = image.size
        let scale = min(1, min(maxSize.width / imgSize.width, maxSize.height / imgSize.height))
        let canvasSize = NSSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let contentSize = NSSize(width: canvasSize.width + 280, height: max(canvasSize.height, 420))

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Pinpoint"
        // Content runs under a see-through title bar so the glass toolbar can
        // float at the top (#99). `NSHostingView` keeps the SwiftUI layout
        // inside the safe area, so nothing slides under the traffic lights.
        window.titlebarAppearsTransparent = true
        // A full-size content view counts the title bar in its height; grow the
        // window by that much so the canvas keeps the size computed above.
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        window.setContentSize(NSSize(width: contentSize.width, height: contentSize.height + titlebarHeight))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        let root = EditorView(
            image: image,
            initialPins: initialPins,
            initialShapes: initialShapes,
            initialContext: initialContext,
            initialAccessibility: initialAccessibility,
            sourceURL: sourceURL,
            onPersist: onPersist
        ) { [weak window] in
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
