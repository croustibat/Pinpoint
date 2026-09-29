import AppKit
import SwiftUI

/// A short glass message that shows and fades by itself, for feedback that
/// doesn't deserve a modal alert — "nothing on the clipboard" after a global
/// shortcut, where an alert would steal focus from whatever the user was doing.
///
/// Same window recipe as the capture countdown: borderless, click-through,
/// never key, so the frontmost app stays frontmost.
@MainActor
final class ToastController {
    static let shared = ToastController()

    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    /// Shows `message` on the screen under the pointer, replacing any toast
    /// already on screen.
    func show(_ message: String, systemImage: String, duration: TimeInterval = 1.8) {
        dismissTask?.cancel()
        window?.orderOut(nil)

        let hosting = NSHostingView(rootView: ToastView(message: message, systemImage: systemImage))
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        // Lower third, where the system puts its own volume/brightness HUDs.
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.minY + visible.height * 0.2)
        let window = ToastWindow(contentRect: NSRect(origin: origin, size: size),
                                 styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        self.window = window

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.18
            window.animator().alphaValue = 1
        }
        VoiceOver.announce(message)

        dismissTask = Task { [weak self, weak window] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let window else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.3
                window.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            window.orderOut(nil)
            if self?.window === window { self?.window = nil }
        }
    }
}

private struct ToastView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .pinpointGlass(in: Capsule())
            // Room for the fallback's shadow inside the borderless window.
            .padding(12)
            .fixedSize()
    }
}

private final class ToastWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum VoiceOver {
    /// The toast never takes focus, so VoiceOver wouldn't read it on its own.
    static func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
