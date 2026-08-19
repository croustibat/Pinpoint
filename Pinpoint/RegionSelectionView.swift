import AppKit

/// The dimming + rubber-band drawing surface for region selection.
///
/// The first drag rubber-bands a rectangle, but releasing the mouse doesn't
/// capture yet: the rectangle enters an *adjustable* stage where it can be
/// dragged around, resized from its eight handles and nudged with the arrow
/// keys (1 pt, 10 pt with ⇧). Return — or a click inside the rectangle —
/// captures, Esc cancels the whole selection, and a drag starting outside it
/// rubber-bands a fresh one.
///
/// Everything is tracked in view-local coordinates and handed back to
/// `RegionSelectionController` in global (screen) coordinates.
final class RegionSelectionView: NSView {
    /// Called when the user validates the selection, with the rect in global
    /// AppKit coordinates (bottom-left origin) and the drag's anchor point.
    var onComplete: ((CGRect, CGPoint) -> Void)?
    /// Called when the user cancels (Esc, or a click without a real drag).
    var onCancel: (() -> Void)?
    /// Called on every mouse-down, before anything else. The controller uses it
    /// to hand keyboard focus (and the hint) to the screen the user is actually
    /// selecting on — otherwise a selection started on a secondary display would
    /// leave Esc/Return/arrows going to another window.
    var onBeginSelection: (() -> Void)?
    /// Whether to draw the hint. With one view per screen, only the view the
    /// user is working on sets this, so the hint shows just once.
    var showsHint: Bool = true { didSet { needsDisplay = true } }

    /// Smallest drag that counts as a selection, and smallest side a resize can
    /// leave behind.
    private static let minSide: CGFloat = 3
    /// A press that travels less than this is a click, not a drag.
    private static let clickSlop: CGFloat = 3
    /// Half-size of a handle's hit area — generous, the dots are small.
    private static let handleTolerance: CGFloat = 10
    private static let handleRadius: CGFloat = 4

    /// What the pointer is currently doing.
    private enum Gesture {
        case none
        case drawing                     // rubber-banding a new rect
        case moving                      // dragging the selection around
        case resizing(SelectionHandle)   // dragging one of its handles
    }

    private var gesture: Gesture = .none
    /// The settled selection (view-local), non-nil once a drag produced one.
    /// Always clamped to `bounds`, so it stays reachable and maps cleanly onto
    /// this view's screen.
    private var selection: CGRect?
    private var anchor: CGPoint?   // rubber-band start, view-local
    private var current: CGPoint?  // rubber-band end, view-local
    /// Anchor of the drag that produced `selection`, in global coordinates. It
    /// picks the target display downstream, so adjusting must not disturb it.
    private var globalAnchor: CGPoint?
    /// Pointer position at the previous drag event; gestures apply the delta
    /// since then rather than a cumulative translation.
    private var lastDragPoint: CGPoint?
    /// Where the current press started, to tell a click from a drag.
    private var pressPoint: CGPoint?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Rubber-band rect in view-local coordinates, or `nil` outside a drag.
    private var rubberBandRect: CGRect? {
        guard let anchor, let current else { return nil }
        return CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(anchor.x - current.x),
            height: abs(anchor.y - current.y)
        )
    }

    /// The rect to draw: the live rubber band while drawing, the settled
    /// selection otherwise.
    private var displayRect: CGRect? {
        if case .drawing = gesture { return rubberBandRect }
        return selection
    }

    /// Whether a settled selection is up and waiting to be adjusted.
    private var isAdjusting: Bool {
        if case .drawing = gesture { return false }
        return selection != nil
    }

    /// Drops whatever is selected here. The controller calls this on the other
    /// screens' views when a selection starts, so only one rectangle is ever on
    /// screen across displays.
    func clearSelection() {
        guard selection != nil || anchor != nil else { return }
        selection = nil
        anchor = nil
        current = nil
        globalAnchor = nil
        gesture = .none
        needsDisplay = true
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        onBeginSelection?()
        let point = convert(event.locationInWindow, from: nil)
        pressPoint = point
        lastDragPoint = point

        if let selection {
            if let handle = SelectionHandle.hit(point, in: selection, tolerance: Self.handleTolerance) {
                gesture = .resizing(handle)
                return
            }
            if selection.contains(point) {
                gesture = .moving
                NSCursor.closedHand.set()
                return
            }
        }

        // Outside any selection: rubber-band a new one. The previous selection
        // is kept until this drag proves itself, so a stray click doesn't throw
        // the work away (it is restored in `mouseUp`).
        anchor = point
        current = point
        gesture = .drawing
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { lastDragPoint = point; needsDisplay = true }

        switch gesture {
        case .drawing:
            current = point
        case .moving:
            guard let selection, let last = lastDragPoint else { return }
            self.selection = SelectionHandle.moved(
                selection, dx: point.x - last.x, dy: point.y - last.y, in: bounds
            )
        case .resizing(let handle):
            guard let selection, let last = lastDragPoint else { return }
            self.selection = handle.resize(
                selection, dx: point.x - last.x, dy: point.y - last.y,
                minSide: Self.minSide, in: bounds
            )
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let finished = gesture
        let point = convert(event.locationInWindow, from: nil)
        let travel = pressPoint.map { hypot(point.x - $0.x, point.y - $0.y) } ?? 0
        gesture = .none
        pressPoint = nil
        lastDragPoint = nil
        defer { announceSelection() }

        switch finished {
        case .drawing:
            defer { anchor = nil; current = nil; needsDisplay = true }
            let drawn = rubberBandRect?.intersection(bounds) ?? .null
            guard drawn.width >= Self.minSide, drawn.height >= Self.minSide,
                  let anchor, let window else {
                // A click without a real drag: cancel outright when nothing is
                // selected yet, otherwise keep the selection that was there.
                if selection == nil { onCancel?() }
                return
            }
            selection = drawn
            globalAnchor = window.convertPoint(toScreen: anchor)
        case .moving:
            // A press inside the selection that never moved is a click, and a
            // click validates.
            if travel < Self.clickSlop {
                commit()
            } else {
                cursor(at: point).set()  // back from the closed hand
            }
        case .resizing, .none:
            break
        }
    }

    // MARK: - Keyboard

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 53:            onCancel?()                 // Esc — cancels everything
        case 36, 76:        commit()                    // Return / keypad Enter
        case 123:           nudge(dx: -step, dy: 0)     // ←
        case 124:           nudge(dx: step, dy: 0)      // →
        case 125:           nudge(dx: 0, dy: -step)     // ↓ (unflipped view)
        case 126:           nudge(dx: 0, dy: step)      // ↑
        default:            super.keyDown(with: event)
        }
    }

    /// Slides the selection by a keyboard step. No-op while a mouse gesture is
    /// in flight, or before there is anything to nudge.
    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard isAdjusting, case .none = gesture, let selection else { return }
        self.selection = SelectionHandle.moved(selection, dx: dx, dy: dy, in: bounds)
        needsDisplay = true
        announceSelection()
    }

    /// Hands the settled selection over in global coordinates. Silent when
    /// there is nothing to capture yet (Return before the first drag).
    private func commit() {
        guard isAdjusting, let selection, let window,
              selection.width >= Self.minSide, selection.height >= Self.minSide else { return }
        let globalRect = window.convertToScreen(selection)
        let anchor = globalAnchor
            ?? window.convertPoint(toScreen: CGPoint(x: selection.midX, y: selection.midY))
        onComplete?(globalRect, anchor)
    }

    // MARK: - Accessibility

    /// The overlay is one element as far as VoiceOver is concerned: it has no
    /// subviews, everything it shows is drawn by hand, and the one thing worth
    /// announcing is how big the rectangle currently is.
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? {
        String(localized: "a11y.region.selection", defaultValue: "Region selection")
    }

    override func accessibilityValue() -> Any? {
        guard let selection else {
            return String(localized: "a11y.region.empty", defaultValue: "No region selected yet")
        }
        return String(
            localized: "a11y.region.size",
            defaultValue: "\(Int(selection.width.rounded())) by \(Int(selection.height.rounded()))"
        )
    }

    /// The same sentence the on-screen hint carries, so the keyboard steps are
    /// reachable without reading the badge.
    override func accessibilityHelp() -> String? {
        isAdjusting
            ? String(localized: "Drag or nudge with arrows · ↵ to capture · Esc to cancel")
            : String(localized: "Drag a rectangle · Esc to cancel")
    }

    /// Announces the new size once a gesture settles. Deliberately not called
    /// per drag event: VoiceOver would read a new figure every frame.
    private func announceSelection() {
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    // MARK: - Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,  // ignored with `.inVisibleRect`
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    /// Crosshair everywhere, except over an adjustable selection: its handles
    /// get the matching resize cursor and its interior an open hand, so the rect
    /// reads as draggable. The controller pushes the crosshair; setting a cursor
    /// here only changes what's displayed, so its `pop()` still restores.
    private func cursor(at point: CGPoint) -> NSCursor {
        guard isAdjusting, let selection else { return .crosshair }
        if let handle = SelectionHandle.hit(point, in: selection, tolerance: Self.handleTolerance) {
            return handle.cursor
        }
        return selection.contains(point) ? .openHand : .crosshair
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.45)
        dim.setFill()

        guard let sel = displayRect?.intersection(bounds), sel.width > 0, sel.height > 0 else {
            bounds.fill()
            if showsHint { drawHint(String(localized: "Drag a rectangle · Esc to cancel"), at: bounds.center) }
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
        if showsHint, isAdjusting {
            // Below the selection by default, above it when the rect reaches
            // that low — the hint must not sit on top of what's being framed.
            let low = CGPoint(x: bounds.midX, y: bounds.minY + 56)
            let high = CGPoint(x: bounds.midX, y: bounds.maxY - 56)
            drawHint(
                String(localized: "Drag or nudge with arrows · ↵ to capture · Esc to cancel"),
                at: sel.minY < low.y + 24 ? high : low
            )
        }
    }

    /// Four corner dots while rubber-banding; all eight once the selection is
    /// adjustable, since that's when they actually do something.
    private func drawHandles(_ sel: CGRect) {
        let handles: [SelectionHandle] = isAdjusting
            ? SelectionHandle.allCases
            : [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let r = Self.handleRadius
        for handle in handles {
            let c = handle.point(in: sel)
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
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let padX: CGFloat = 8, padY: CGFloat = 4
        let badge = CGSize(width: textSize.width + padX * 2, height: textSize.height + padY * 2)

        var origin = CGPoint(x: sel.midX - badge.width / 2, y: sel.minY - badge.height - 8)
        if origin.y < bounds.minY + 4 { origin.y = sel.minY + 8 } // no room below → inside
        let rect = CGRect(origin: origin, size: badge)

        // Nearly opaque: the badge sits over whatever the user is framing, and
        // white-on-translucent-black was only legible over dark content.
        NSColor.black.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: rect.minX + padX, y: rect.minY + padY), withAttributes: attrs)
    }

    private func drawHint(_ string: String, at center: CGPoint) {
        let text = string as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let padX: CGFloat = 14, padY: CGFloat = 8
        let badge = CGSize(width: textSize.width + padX * 2, height: textSize.height + padY * 2)
        let rect = CGRect(
            x: center.x - badge.width / 2,
            y: center.y - badge.height / 2,
            width: badge.width,
            height: badge.height
        )
        // Same reasoning as the dimensions badge: 55 % black under 90 % white
        // left the hint hard to read over a light window.
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        text.draw(at: CGPoint(x: rect.minX + padX, y: rect.minY + padY), withAttributes: attrs)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
