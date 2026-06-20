import SwiftUI
import KeyboardShortcuts

// Default global shortcut: ⌘⇧1
extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.one, modifiers: [.command, .shift]))
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
                .tabItem { Label("Étagère", systemImage: "tray.full") }
        }
        .frame(width: 460, height: 340)
    }
}

struct CaptureSettingsView: View {
    @AppStorage(PinStyle.storageKey) private var pinStyle: PinStyle = .disc
    @AppStorage("includeLegend") private var includeLegend = true

    var body: some View {
        Form {
            Section("Raccourci de capture") {
                KeyboardShortcuts.Recorder("Capturer l’écran :", name: .capture)
            }
            Section("Style des repères") {
                Picker("Style :", selection: $pinStyle) {
                    ForEach(PinStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Text(pinStyle.caption)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Section("Partage pour l’agent") {
                Toggle("Inclure la légende dans l’image", isOn: $includeLegend)
                Text("Ajoute les descriptions des repères et les instructions sous la capture, pour qu’un seul collage transmette tout à l’agent.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
