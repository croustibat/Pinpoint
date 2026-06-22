import SwiftUI
import KeyboardShortcuts

// Default global shortcuts: ⌘⇧1 capture, ⌘⇧2 étagère.
extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.one, modifiers: [.command, .shift]))
    static let openShelf = Self("openShelf", default: .init(.two, modifiers: [.command, .shift]))
}

@main
struct PinpointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar only app (LSUIElement = true). The Settings scene gives us a
        // standard ⌘, preferences window without forcing a main window open.
        Settings {
            SettingsView()
        }
    }
}

/// Fenêtre Réglages unifiée : onglet Capture (raccourci, repères, partage agent)
/// et onglet Étagère (dossier surveillé, lancement au démarrage). Les deux
/// onglets pilotent le même `ScreenshotStore` partagé que la fenêtre Étagère.
struct SettingsView: View {
    var body: some View {
        TabView {
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }

            ShelfSettingsView()
                .environmentObject(ScreenshotStore.shared)
                .tabItem { Label("Shelf", systemImage: "tray.full") }
        }
        .frame(width: 460, height: 340)
    }
}

struct CaptureSettingsView: View {
    @AppStorage(PinStyle.storageKey) private var pinStyle: PinStyle = .disc
    @AppStorage("includeLegend") private var includeLegend = true

    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder(String(localized: "Capture screen:"), name: .capture)
                KeyboardShortcuts.Recorder(String(localized: "Open shelf:"), name: .openShelf)
            }
            Section("Marker style") {
                Picker("Style:", selection: $pinStyle) {
                    ForEach(PinStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text(pinStyle.caption)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Section("Agent sharing") {
                Toggle("Embed legend in the image", isOn: $includeLegend)
                Text("Adds the marker descriptions and instructions below the capture so a single paste carries everything to the agent.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
