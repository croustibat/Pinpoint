import SwiftUI

struct ShelfSettingsView: View {
    @EnvironmentObject private var store: ScreenshotStore
    @EnvironmentObject private var settings: SettingsViewModel

    var body: some View {
        Form {
            Section("Screenshot Location") {
                Toggle("Follow current macOS screenshot location", isOn: Binding(
                    get: { store.followsSystemScreenshotLocation },
                    set: { newValue in
                        store.setFollowsSystemScreenshotLocation(newValue)
                        settings.syncFromStore(store)
                    }
                ))

                LabeledContent("macOS location") {
                    Text(settings.systemScreenshotFolderPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if store.followsSystemScreenshotLocation == false {
                    Button("Use Current macOS Location") {
                        store.applyCurrentSystemScreenshotLocation()
                        settings.syncFromStore(store)
                    }
                }
            }

            Section("Watched Folder") {
                HStack {
                    Text(settings.watchedFolderPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()

                    Button("Choose Folder") {
                        store.chooseWatchedFolder()
                        settings.syncFromStore(store)
                    }
                    .disabled(store.followsSystemScreenshotLocation)
                }
            }

            Section("Launch") {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { newValue in
                        store.setLaunchAtLogin(enabled: newValue)
                        settings.syncFromStore(store)
                    }
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
        .padding()
        .onAppear {
            settings.syncFromStore(store)
        }
    }
}

struct ShelfSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let store = ScreenshotStore()
        let settings = SettingsViewModel()
        settings.bind(to: store)

        return ShelfSettingsView()
            .environmentObject(store)
            .environmentObject(settings)
            .frame(width: 460, height: 280)
    }
}
