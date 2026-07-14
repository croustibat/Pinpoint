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
        VStack(spacing: 0) {
            TabView {
                CaptureSettingsView()
                    .tabItem { Label("Capture", systemImage: "camera.viewfinder") }

                ShelfSettingsView()
                    .environmentObject(ScreenshotStore.shared)
                    .tabItem { Label("Shelf", systemImage: "tray.full") }
            }

            Divider()
            Text(Self.versionString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 6)
        }
        .frame(width: 460, height: 366)
    }

    /// Marketing version + build read from the bundle, e.g. "Pinpoint 0.3.0 (3)".
    /// Selectable so it can be copied into a bug report.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Pinpoint \(short) (\(build))"
    }
}

struct CaptureSettingsView: View {
    @AppStorage(PinStyle.storageKey) private var pinStyle: PinStyle = .disc
    @AppStorage("includeLegend") private var includeLegend = true
    @AppStorage(CaptureDelay.storageKey) private var captureDelay: CaptureDelay = .off

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
            Section("Capture timer") {
                Picker("Delay before capture:", selection: $captureDelay) {
                    ForEach(CaptureDelay.allCases) { delay in
                        Text(delay.label).tag(delay)
                    }
                }
                Text("Pause before the screenshot so you can arrange UI elements or open a menu.")
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
