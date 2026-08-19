import AppKit

/// Presents a full-screen dimming overlay (one borderless window per screen)
/// and lets the user drag, then adjust, a rectangle to pick a capture region.
///
/// One window per `NSScreen` is required because, with "Displays have separate
/// Spaces" (the macOS default), a single window spanning the union of all
/// screens only renders reliably on the primary display.
///
/// Mirrors `EditorWindowController`: this file owns presentation and the
/// windows; `RegionSelectionView` owns drawing and event handling.
@MainActor
final class RegionSelectionController {
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<CaptureRegion?, Never>?

    /// Shows the overlay and resolves with the chosen region, or `nil` if the
    /// user cancelled (Esc, or a click without a meaningful drag) — or if screen
    /// recording isn't allowed.
    ///
    /// The permission is checked *before* anything is put on screen: otherwise the
    /// user drags a region, waits out the countdown, and only then hits a failed
    /// capture. A `nil` here unwinds the whole flow (no overlay, no timer) and the
    /// explanatory alert has already been shown by `ScreenCapture`.
    func selectRegion() async -> CaptureRegion? {
        guard await ScreenCapture.ensurePermission() else { return nil }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    // MARK: - Presentation

    private func present() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { finish(nil); return }

        // The window under the pointer starts out key so Esc works immediately
        // and owns the hint; the others just dim their screen (AppKit routes a
        // drag to the window that got the mouseDown, so the anchor screen owns
        // it). `focus(_:)` hands both over as soon as a drag starts elsewhere.
        let cursor = NSEvent.mouseLocation
        let keyScreen = screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main

        NSApp.activate(ignoringOtherApps: true)

        for screen in screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.showsHint = (screen == keyScreen)
            view.onComplete = { [weak self] globalRect, anchor in
                self?.finish(Self.resolve(globalRect: globalRect, anchor: anchor))
            }
            view.onCancel = { [weak self] in self?.finish(nil) }
            view.onBeginSelection = { [weak self, weak view] in
                guard let view else { return }
                self?.focus(view)
            }
            window.contentView = view

            windows.append(window)

            if screen == keyScreen {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(view)
            } else {
                window.orderFront(nil)
            }
        }

        NSCursor.crosshair.push()
    }

    /// Hands the hint, the keyboard focus and the sole selection to the screen
    /// the user is actually selecting on. The adjustable stage is driven by the keyboard (Return,
    /// Esc, arrows), so the window owning the selection has to be the key one —
    /// otherwise a selection started on a secondary display would have its keys
    /// swallowed by whichever window was key at first.
    private func focus(_ view: RegionSelectionView) {
        for window in windows {
            guard let other = window.contentView as? RegionSelectionView else { continue }
            let isActive = (other === view)
            other.showsHint = isActive
            if !isActive { other.clearSelection() }
        }
        guard let window = view.window, !window.isKeyWindow else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    private func finish(_ region: CaptureRegion?) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        continuation.resume(returning: region)
    }

    // MARK: - Coordinate resolution

    /// Maps a selection rect (global AppKit coordinates, bottom-left origin) onto
    /// the target display, returning a rect in points relative to that display
    /// with a top-left origin (ScreenCaptureKit `sourceRect` convention).
    ///
    /// The target display is the one under the drag's anchor (matching system
    /// behaviour); a selection straddling two displays is clamped to that one.
    private static func resolve(globalRect: CGRect, anchor: CGPoint) -> CaptureRegion? {
        let screens = NSScreen.screens
        let screen = screens.first { NSMouseInRect(anchor, $0.frame, false) }
            ?? screens.max { area($0.frame.intersection(globalRect)) < area($1.frame.intersection(globalRect)) }
            ?? NSScreen.main
        guard let screen, let displayID = screen.displayID else { return nil }

        let clamped = globalRect.intersection(screen.frame)
        guard clamped.width >= 1, clamped.height >= 1 else { return nil }

        let rect = CGRect(
            x: clamped.minX - screen.frame.minX,
            y: screen.frame.maxY - clamped.maxY, // flip bottom-left → top-left
            width: clamped.width,
            height: clamped.height
        )
        return CaptureRegion(displayID: displayID, rect: rect, scale: screen.backingScaleFactor)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

/// Borderless window that can still become key, so it receives key (Esc) and
/// mouse events while floating above everything.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
