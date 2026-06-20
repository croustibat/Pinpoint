import SwiftUI

/// Réglages de l'étagère, présentés comme un onglet de la fenêtre Réglages
/// unifiée de Pinpoint. Pilote directement le `ScreenshotStore` partagé.
struct ShelfSettingsView: View {
    @EnvironmentObject private var store: ScreenshotStore

    private var systemLocationPath: String {
        ScreenshotLocationResolver.currentLocation().path
    }

    var body: some View {
        Form {
            Section("Capture location") {
                Toggle("Follow the macOS screenshot location", isOn: Binding(
                    get: { store.followsSystemScreenshotLocation },
                    set: { store.setFollowsSystemScreenshotLocation($0) }
                ))

                LabeledContent("macOS location") {
                    Text(systemLocationPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if store.followsSystemScreenshotLocation == false {
                    Button("Use the current macOS location") {
                        store.applyCurrentSystemScreenshotLocation()
                    }
                }
            }

            Section("Watched folder") {
                HStack {
                    Text(store.watchedFolderURL.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button("Choose a folder…") {
                        store.chooseWatchedFolder()
                    }
                    .disabled(store.followsSystemScreenshotLocation)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.setLaunchAtLogin(enabled: $0) }
                ))
            }

            if let error = store.lastErrorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShelfSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ShelfSettingsView()
            .environmentObject(ScreenshotStore.shared)
            .frame(width: 460, height: 320)
    }
}
