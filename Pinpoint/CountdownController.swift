import AppKit

/// Affiche un compte à rebours cliquable-transparent (HUD) pendant le délai de
/// capture, pour laisser l'utilisateur disposer l'UI ou ouvrir un menu avant
/// la prise de vue.
///
/// Le HUD est `ignoresMouseEvents = true` et non actif : les clics traversent
/// vers les fenêtres/menus situés dessous (cas clé : ouvrir un menu pendant le
/// compte à rebours pour le capturer). Pinpoint se désactive pour que l'app
/// ciblée reste au premier plan. Échap annule la capture.
@MainActor
final class CountdownController {
    private var window: CountdownWindow?
    private var view: CountdownView?
    private var cancelled = false
    private var escLocalMonitor: Any?
    private var escGlobalMonitor: Any?

    /// Attend `seconds` secondes en affichant le décompte sur `screen`.
    /// Retourne `false` si l'utilisateur a appuyé sur Échap, `true` sinon.
    /// Sans effet si `seconds <= 0`.
    func run(seconds: Int, on screen: NSScreen?) async -> Bool {
        guard seconds > 0 else { return true }
        cancelled = false
        show(on: screen ?? NSScreen.main ?? NSScreen.screens.first)
        startEscMonitor()
        defer {
            stopEscMonitor()
            window?.orderOut(nil)
            window = nil
        }

        for n in stride(from: seconds, through: 1, by: -1) {
            guard !cancelled else { return false }
            view?.number = n
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return !cancelled
    }

    // MARK: - Presentation

    private func show(on screen: NSScreen?) {
        guard let screen else { return }
        let size: CGFloat = 220
        let frame = NSRect(
            x: screen.frame.midX - size / 2,
            y: screen.frame.midY - size / 2,
            width: size,
            height: size
        )
        let window = CountdownWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true   // cliquable-transparent
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = CountdownView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = view
        self.window = window
        self.view = view

        // Laisse l'app ciblée au premier plan (menus accessibles sans clic de
        // réactivation). `orderFront` sans `makeKey` ni `NSApp.activate`.
        NSApp.deactivate()
        window.orderFront(nil)
    }

    // MARK: - Esc cancel

    private func startEscMonitor() {
        // Moniteur local : couvre le cas où Pinpoint a encore le focus clavier.
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() } // Esc
            return event
        }
        // Moniteur global : couvre le cas où l'utilisateur a cliqué dans une
        // autre app pour ouvrir un menu (Échap vient de cette app). Le rappel
        // peut être invoqué hors main actor : on rebascule dessus via `cancel`.
        // Note : peut nécessiter la permission « Input Monitoring » ; si elle
        // manque, le décompte se termine simplement (dégradation silencieuse).
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() } // Esc
        }
    }

    /// Marque le décompte comme annulé. Comme cette méthode est isolée sur le
    /// main actor (classe `@MainActor`), l'appeler depuis le moniteur global —
    /// dont le handler tourne hors main thread — rebascule automatiquement sur
    /// le main actor, évitant la course de données sur `cancelled`.
    private func cancel() {
        cancelled = true
    }

    private func stopEscMonitor() {
        if let escLocalMonitor { NSEvent.removeMonitor(escLocalMonitor); self.escLocalMonitor = nil }
        if let escGlobalMonitor { NSEvent.removeMonitor(escGlobalMonitor); self.escGlobalMonitor = nil }
    }
}

// MARK: - View

private final class CountdownView: NSView {
    var number: Int = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let text = "\(number)" as NSString
        let font = NSFont.systemFont(ofSize: 130, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let pad: CGFloat = 30
        let side = max(textSize.width, textSize.height) + pad * 2 // carré → cercle
        let rect = NSRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        NSColor.pinpointVermillon.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: rect).fill()

        let textOrigin = CGPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        text.draw(at: textOrigin, withAttributes: attrs)
    }
}

// MARK: - Window

/// Fenêtre cliquable-transparent pour le HUD de décompte. Pas `canBecomeKey`
/// (on ne veut PAS voler le focus clavier) — cf. `OverlayWindow` dans
/// `RegionSelectionController.swift` pour le motif inverse (sélection de région).
private final class CountdownWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
