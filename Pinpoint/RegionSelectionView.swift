import AppKit

/// The dimming + rubber-band drawing surface for region selection.
///
/// Tracks the drag in view-local coordinates and reports the finished selection
/// back to `RegionSelectionController` in global (screen) coordinates.
final class RegionSelectionView: NSView {
    /// Called on a finished drag with the selection rect in global AppKit
    /// coordinates (bottom-left origin) and the drag's anchor point.
    var onComplete: ((CGRect, CGPoint) -> Void)?
    /// Called when the user cancels (Esc, or a click without a real drag).
    var onCancel: (() -> Void)?

    private var anchor: CGPoint?  // view-local
    private var current: CGPoint? // view-local

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Current selection in view-local coordinates, or `nil` before a drag.
    private var selectionRect: CGRect? {
        guard let anchor, let current else { return nil }
        return CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(anchor.x - current.x),
            height: abs(anchor.y - current.y)
        )
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { anchor = nil; current = nil; needsDisplay = true }
        guard let rect = selectionRect, rect.width >= 3, rect.height >= 3,
              let anchor, let window else {
            onCancel?()
            return
        }
        let globalRect = window.convertToScreen(rect)
        let globalAnchor = window.convertPoint(toScreen: anchor)
        onComplete?(globalRect, globalAnchor)
    }

    // MARK: - Keyboard (Esc cancels)

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.45)
        dim.setFill()

        guard let sel = selectionRect?.intersection(bounds), sel.width > 0, sel.height > 0 else {
            bounds.fill()
            drawHint()
            return
        }

        // Dim everything except the selection (four strips around it).
        let b = bounds
        NSRect(x: b.minX, y: sel.maxY, width: b.width, height: b.maxY - sel.maxY).fill()       // top
        NSRect(x: b.minX, y: b.minY, width: b.width, height: sel.minY - b.minY).fill()         // bottom
        NSRect(x: b.minX, y: sel.minY, width: sel.minX - b.minX, height: sel.height).fill()    // left
        NSRect(x: sel.maxX, y: sel.minY, width: b.maxX - sel.maxX, height: sel.height).fill()  // right

        // Selection border.
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: sel)
        border.lineWidth = 1.5
        border.stroke()

        drawHandles(sel)
        drawDimensions(sel)
    }

    private func drawHandles(_ sel: CGRect) {
        let r: CGFloat = 4
        let corners = [
            CGPoint(x: sel.minX, y: sel.minY), CGPoint(x: sel.maxX, y: sel.minY),
            CGPoint(x: sel.minX, y: sel.maxY), CGPoint(x: sel.maxX, y: sel.maxY)
        ]
        for c in corners {
            let dot = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            NSColor.white.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }
    }

    private func drawDimensions(_ sel: CGRect) {
        let text = "\(Int(sel.width.rounded())) × \(Int(sel.height.rounded()))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let padX: CGFloat = 8, padY: CGFloat = 4
        let badge = CGSize(width: textSize.width + padX * 2, height: textSize.height + padY * 2)

        var origin = CGPoint(x: sel.midX - badge.width / 2, y: sel.minY - badge.height - 8)
        if origin.y < bounds.minY + 4 { origin.y = sel.minY + 8 } // no room below → inside
        let rect = CGRect(origin: origin, size: badge)

        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: rect.minX + padX, y: rect.minY + padY), withAttributes: attrs)
    }

    private func drawHint() {
        let text = String(localized: "Drag a rectangle · Esc to cancel") as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let textSize = text.size(withAttributes: attrs)
        let padX: CGFloat = 14, padY: CGFloat = 8
        let badge = CGSize(width: textSize.width + padX * 2, height: textSize.height + padY * 2)
        let rect = CGRect(
            x: bounds.midX - badge.width / 2,
            y: bounds.midY - badge.height / 2,
            width: badge.width,
            height: badge.height
        )
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        text.draw(at: CGPoint(x: rect.minX + padX, y: rect.minY + padY), withAttributes: attrs)
    }
}
