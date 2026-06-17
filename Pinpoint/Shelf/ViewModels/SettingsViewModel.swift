import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var watchedFolderPath = ""
    @Published private(set) var systemScreenshotFolderPath = ""
    @Published var followSystemScreenshotLocation = false
    @Published var launchAtLogin = false

    func bind(to store: ScreenshotStore) {
        watchedFolderPath = store.watchedFolderURL.path
        systemScreenshotFolderPath = ScreenshotLocationResolver.currentLocation().path
        followSystemScreenshotLocation = store.followsSystemScreenshotLocation
        launchAtLogin = store.launchAtLoginEnabled
    }

    func syncFromStore(_ store: ScreenshotStore) {
        watchedFolderPath = store.watchedFolderURL.path
        systemScreenshotFolderPath = ScreenshotLocationResolver.currentLocation().path
        followSystemScreenshotLocation = store.followsSystemScreenshotLocation
        launchAtLogin = store.launchAtLoginEnabled
    }
}
