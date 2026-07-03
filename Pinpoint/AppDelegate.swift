import AppKit
import SwiftUI
import KeyboardShortcuts
import Sparkle

extension Notification.Name {
    /// Posted by the shelf to open Pinpoint's unified settings window.
    static let pinpointOpenSettings = Notification.Name("pinpointOpenSettings")
    /// Posted by the shelf to reopen one of its screenshots in the annotation
    /// editor, as if it had just been captured. The file `URL` rides in `object`.
    static let pinpointOpenInEditor = Notification.Name("pinpointOpenInEditor")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var editorController: EditorWindowController?
    private var regionController: RegionSelectionController?
    private var countdownController: CountdownController?
    private var settingsController: SettingsWindowController?
    private var shelfController: ShelfWindowController?
    private let recentMenu = NSMenu()
    /// Sparkle updater. Created (and started) at launch so scheduled background
    /// checks run; the menu item below also triggers a manual check.
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        KeyboardShortcuts.onKeyUp(for: .capture) { [weak self] in
            self?.startCapture()
        }
        KeyboardShortcuts.onKeyUp(for: .openShelf) { [weak self] in
            self?.openShelf()
        }

        let center = NotificationCenter.default
        // The shelf's ⚙️ button posts this — it can't use SwiftUI's
        // `showSettingsWindow:` (a no-op for menu-bar apps). Route it to the
        // unified settings window instead.
        center.addObserver(self, selector: #selector(openSettings),
                           name: .pinpointOpenSettings, object: nil)
        // The shelf's "Edit in Pinpoint" action posts this with a file URL so an
        // existing screenshot can be annotated through the normal editor flow.
        center.addObserver(self, selector: #selector(openInEditor(_:)),
                           name: .pinpointOpenInEditor, object: nil)
        // Menu-bar app (LSUIElement = accessory): become a regular app while a
        // content window is on screen, so it shows in the Dock and ⌘Tab, and
        // drop back to accessory once everything is closed.
        center.addObserver(self, selector: #selector(refreshActivationPolicy),
                           name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(refreshActivationPolicy),
                           name: NSWindow.willCloseNotification, object: nil)
    }

    /// Switches the app between `.regular` (Dock icon + ⌘Tab) and `.accessory`
    /// (pure menu-bar) based on whether any normal content window is visible.
    /// Deferred to the next tick so a closing window's state is already updated.
    @objc private func refreshActivationPolicy() {
        DispatchQueue.main.async {
            let hasContentWindow = NSApp.windows.contains {
                $0.isVisible && $0.level == .normal && $0.canBecomeMain
            }
            let policy: NSApplication.ActivationPolicy = hasContentWindow ? .regular : .accessory
            if NSApp.activationPolicy() != policy {
                NSApp.setActivationPolicy(policy)
            }
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
        let regionItem = NSMenuItem(title: String(localized: "Capture a region"), action: #selector(captureFromMenu), keyEquivalent: "1")
        regionItem.keyEquivalentModifierMask = [.command, .shift]
        regionItem.target = self
        menu.addItem(regionItem)

        let fullScreenItem = NSMenuItem(title: String(localized: "Capture the whole screen"), action: #selector(captureFullScreen), keyEquivalent: "3")
        fullScreenItem.keyEquivalentModifierMask = [.command, .shift]
        fullScreenItem.target = self
        menu.addItem(fullScreenItem)
        menu.addItem(.separator())

        let shelfItem = NSMenuItem(title: String(localized: "Shelf…"), action: #selector(openShelf), keyEquivalent: "")
        shelfItem.target = self
        menu.addItem(shelfItem)

        let recentItem = NSMenuItem(title: String(localized: "Recent captures"), action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(.separator())

        let updatesItem = NSMenuItem(title: String(localized: "Check for updates…"),
                                     action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                     keyEquivalent: "")
        updatesItem.target = updaterController
        menu.addItem(updatesItem)

        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: String(localized: "Quit Pinpoint"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
            let empty = NSMenuItem(title: String(localized: "No recent captures"), action: nil, keyEquivalent: "")
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
        let clear = NSMenuItem(title: String(localized: "Clear history"), action: #selector(clearHistory), keyEquivalent: "")
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

    @objc private func openShelf() {
        if shelfController == nil {
            shelfController = ShelfWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        shelfController?.showWindow(nil)
        shelfController?.window?.makeKeyAndOrderFront(nil)
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

            // Pré-délai optionnel : HUD cliquable-transparent pour laisser
            // l'utilisateur disposer l'UI ou ouvrir un menu. Échap annule.
            let delay = CaptureDelay.current
            if delay.seconds > 0 {
                let screen = NSScreen.screens.first { $0.displayID == region.displayID }
                let controller = CountdownController()
                countdownController = controller
                let completed = await controller.run(seconds: delay.seconds, on: screen)
                countdownController = nil
                guard completed else { return } // Échap pendant le décompte
            }

            do {
                let image = try await ScreenCapture.captureRegion(region)
                let record = CaptureHistory.shared.add(image: image)
                presentEditor(image: image, recordID: record?.id)
            } catch {
                presentCaptureError(error)
            }
        }
    }

    /// Reopens an existing shelf screenshot in the editor as a fresh capture:
    /// loads the file, records it in the capture history, and presents the editor.
    @objc private func openInEditor(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        guard let image = Self.loadImage(at: url) else {
            presentImportError()
            return
        }
        let record = CaptureHistory.shared.add(image: image)
        presentEditor(image: image, recordID: record?.id)
    }

    /// Loads a bitmap at its native pixel size. `NSImage(contentsOf:)` would honor
    /// the file's DPI, shrinking Retina screenshots (e.g. ⌘⇧4) to half size; this
    /// keeps the editor canvas at full resolution, like `CaptureHistory.image(for:)`.
    private static func loadImage(at url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        image.addRepresentation(rep)
        return image
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
        alert.messageText = String(localized: "Capture failed")
        alert.informativeText = String(
            localized: "capture.error.body",
            defaultValue: "\(error.localizedDescription)\n\nMake sure Pinpoint has the “Screen Recording” permission in System Settings ▸ Privacy & Security, then relaunch the app."
        )
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @MainActor
    private func presentImportError() {
        let alert = NSAlert()
        alert.messageText = String(localized: "shelf.openInEditor.error.title",
                                   defaultValue: "Couldn’t open this screenshot")
        alert.informativeText = String(
            localized: "shelf.openInEditor.error.body",
            defaultValue: "Pinpoint couldn’t read the image file. It may have been moved or deleted."
        )
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
