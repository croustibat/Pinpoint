import AppKit
import SwiftUI

struct MultiFileDragButton: NSViewRepresentable {
    let items: [ScreenshotItem]
    var compact = false

    func makeNSView(context: Context) -> MultiFileDragNSButton {
        let button = MultiFileDragNSButton()
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ nsView: MultiFileDragNSButton, context: Context) {
        nsView.configure(with: items, compact: compact)
    }
}

final class MultiFileDragNSButton: NSButton, NSDraggingSource {
    private var itemURLs: [URL] = []
    private var mouseDownEvent: NSEvent?
    private var hasStartedDrag = false
    private var compact = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        imagePosition = .imageLeading
        imageScaling = .scaleNone
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.14).cgColor
        contentTintColor = .labelColor
        font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Drag selected screenshots")
        image?.isTemplate = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with items: [ScreenshotItem], compact: Bool) {
        itemURLs = items.map(\.url)
        self.compact = compact
        title = compact ? "" : (itemURLs.count == 1 ? "Drag File" : "Drag \(itemURLs.count) Files")
        toolTip = "Drag the selected screenshots into another app"
        isEnabled = itemURLs.isEmpty == false
        alphaValue = isEnabled ? 1 : 0.45
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        if compact {
            return NSSize(width: 30, height: 30)
        }

        let titleSize = attributedTitle.size()
        return NSSize(width: titleSize.width + 42, height: 28)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard hasStartedDrag == false, itemURLs.isEmpty == false, let mouseDownEvent else {
            return
        }

        hasStartedDrag = true
        beginDraggingSession(with: draggingItems(), event: mouseDownEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        hasStartedDrag = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    private func draggingItems() -> [NSDraggingItem] {
        itemURLs.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(draggingFrame(for: index), contents: draggingImage(for: url, index: index))
            return item
        }
    }

    private func draggingFrame(for index: Int) -> CGRect {
        let origin = CGPoint(x: bounds.minX + CGFloat(index * 8), y: bounds.minY - CGFloat(index * 4))
        return CGRect(origin: origin, size: CGSize(width: 96, height: 96))
    }

    private func draggingImage(for url: URL, index: Int) -> NSImage {
        let baseImage = NSWorkspace.shared.icon(forFile: url.path)
        baseImage.size = NSSize(width: 96, height: 96)

        guard index == 0, itemURLs.count > 1 else {
            return baseImage
        }

        let composedImage = NSImage(size: baseImage.size)
        composedImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size))

        let badgeRect = NSRect(x: 62, y: 66, width: 26, height: 22)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 10, yRadius: 10).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let badgeText = "\(itemURLs.count)" as NSString
        let textSize = badgeText.size(withAttributes: attributes)
        let textOrigin = NSPoint(
            x: badgeRect.midX - (textSize.width / 2),
            y: badgeRect.midY - (textSize.height / 2)
        )
        badgeText.draw(at: textOrigin, withAttributes: attributes)

        composedImage.unlockFocus()
        return composedImage
    }
}
