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

struct SettingsView: View {
    @AppStorage(PinStyle.storageKey) private var pinStyle: PinStyle = .disc

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
            Section {
                Text("Pinpoint vit dans la barre de menus. Appuie sur le raccourci, annote, copie.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
