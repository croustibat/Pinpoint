import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var editorController: EditorWindowController?
    private var regionController: RegionSelectionController?
    private var settingsController: SettingsWindowController?
    private let recentMenu = NSMenu()

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

        let recentItem = NSMenuItem(title: "Captures récentes", action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quitter Pinpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Recent captures submenu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        rebuildRecentMenu()
    }

    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()

        let records = CaptureHistory.shared.records
        guard !records.isEmpty else {
            let empty = NSMenuItem(title: "Aucune capture récente", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }

        for record in records {
            let item = NSMenuItem(title: title(for: record), action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = record.id.uuidString
            recentMenu.addItem(item)
        }

        recentMenu.addItem(.separator())
        let clear = NSMenuItem(title: "Vider l’historique", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        recentMenu.addItem(clear)
    }

    private func title(for record: CaptureRecord) -> String {
        let when = record.date.formatted(date: .abbreviated, time: .shortened)
        return "\(when) · \(record.width)×\(record.height)"
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let record = CaptureHistory.shared.records.first(where: { $0.id == id }),
              let image = CaptureHistory.shared.image(for: record) else { return }
        presentEditor(image: image, recordID: record.id,
                      pins: record.pins, shapes: record.shapes, context: record.context)
    }

    @objc private func clearHistory() {
        CaptureHistory.shared.clear()
    }

    // MARK: - Capture actions

    @objc private func captureFromMenu() { startCapture() }

    @objc private func captureFullScreen() {
        Task { @MainActor in
            do {
                let image = try await ScreenCapture.captureDisplayUnderCursor()
                let record = CaptureHistory.shared.add(image: image)
                presentEditor(image: image, recordID: record?.id)
            } catch {
                presentCaptureError(error)
            }
        }
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
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
                let record = CaptureHistory.shared.add(image: image)
                presentEditor(image: image, recordID: record?.id)
            } catch {
                presentCaptureError(error)
            }
        }
    }

    @MainActor
    private func presentEditor(image: NSImage, recordID: UUID?,
                               pins: [Pin] = [], shapes: [Markup] = [], context: String = "") {
        let controller = EditorWindowController(
            image: image,
            initialPins: pins,
            initialShapes: shapes,
            initialContext: context,
            onPersist: { pins, shapes, context in
                guard let recordID else { return }
                CaptureHistory.shared.update(id: recordID, pins: pins, shapes: shapes, context: context)
            }
        )
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
