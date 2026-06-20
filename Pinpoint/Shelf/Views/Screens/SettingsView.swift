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
            Section("Emplacement des captures") {
                Toggle("Suivre l’emplacement des captures de macOS", isOn: Binding(
                    get: { store.followsSystemScreenshotLocation },
                    set: { store.setFollowsSystemScreenshotLocation($0) }
                ))

                LabeledContent("Emplacement macOS") {
                    Text(systemLocationPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if store.followsSystemScreenshotLocation == false {
                    Button("Utiliser l’emplacement macOS actuel") {
                        store.applyCurrentSystemScreenshotLocation()
                    }
                }
            }

            Section("Dossier surveillé") {
                HStack {
                    Text(store.watchedFolderURL.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button("Choisir un dossier…") {
                        store.chooseWatchedFolder()
                    }
                    .disabled(store.followsSystemScreenshotLocation)
                }
            }

            Section("Démarrage") {
                Toggle("Lancer au démarrage de session", isOn: Binding(
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
