import AppKit
import SwiftUI
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var editorController: EditorWindowController?
    private var regionController: RegionSelectionController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        KeyboardShortcuts.onKeyUp(for: .capture) { [weak self] in
            self?.startCapture()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinpoint")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let regionItem = NSMenuItem(title: "Capturer une région", action: #selector(captureFromMenu), keyEquivalent: "1")
        regionItem.keyEquivalentModifierMask = [.command, .shift]
        regionItem.target = self
        menu.addItem(regionItem)

        let fullScreenItem = NSMenuItem(title: "Capturer tout l’écran", action: #selector(captureFullScreen), keyEquivalent: "3")
        fullScreenItem.keyEquivalentModifierMask = [.command, .shift]
        fullScreenItem.target = self
        menu.addItem(fullScreenItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quitter Pinpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func captureFromMenu() { startCapture() }

    @objc private func captureFullScreen() {
        Task { @MainActor in
            do {
                let image = try await ScreenCapture.captureDisplayUnderCursor()
                presentEditor(with: image)
            } catch {
                presentCaptureError(error)
            }
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Capture flow

    private func startCapture() {
        // Avoid stacking overlays if the shortcut fires repeatedly.
        guard regionController == nil else { return }

        Task { @MainActor in
            let controller = RegionSelectionController()
            regionController = controller
            let region = await controller.selectRegion()
            regionController = nil

            guard let region else { return } // cancelled

            // Let the overlay fully disappear before the screenshot, so the dim
            // layer isn't part of the captured pixels.
            try? await Task.sleep(nanoseconds: 80_000_000)

            do {
                let image = try await ScreenCapture.captureRegion(region)
                presentEditor(with: image)
            } catch {
                presentCaptureError(error)
            }
        }
    }

    @MainActor
    private func presentEditor(with image: NSImage) {
        let controller = EditorWindowController(image: image)
        editorController = controller
        controller.onClose = { [weak self] in self?.editorController = nil }
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func presentCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture impossible"
        alert.informativeText = """
        \(error.localizedDescription)

        Vérifie que Pinpoint a l’autorisation « Enregistrement de l’écran » dans \
        Réglages Système ▸ Confidentialité et sécurité, puis relance l’app.
        """
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
