import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class ScreenshotStore: ObservableObject {
    /// Shared library instance. The shelf window and the settings window both
    /// drive the same store so a folder change in Réglages is reflected live in
    /// the étagère (and vice-versa).
    static let shared = ScreenshotStore()

    @Published private(set) var screenshots: [ScreenshotItem] = []
    @Published var selectedDateFilter: ScreenshotDateFilter = .all
    @Published var selectedSortOrder: ScreenshotSortOrder = .newestFirst
    @Published var showsFavoritesOnly = false
    @Published private(set) var watchedFolderURL: URL
    @Published private(set) var isLoading = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var followsSystemScreenshotLocation: Bool
    @Published private(set) var favoritePaths: Set<String>
    @Published private(set) var customTitles: [String: String]
    @Published var lastErrorMessage: String?

    private let service = ScreenshotService()
    private let watcher = ScreenshotWatcher()
    private let defaults = UserDefaults.standard
    private let watchedFolderBookmarkKey = "watchedFolderBookmark"
    private let followSystemLocationKey = "followSystemScreenshotLocation"
    private let favoritePathsKey = "favoriteScreenshotPaths"
    private let customTitlesKey = "customScreenshotTitles"

    init() {
        let followsSystemScreenshotLocation = defaults.bool(forKey: followSystemLocationKey)
        self.followsSystemScreenshotLocation = followsSystemScreenshotLocation
        self.favoritePaths = Set(defaults.stringArray(forKey: favoritePathsKey) ?? [])
        self.customTitles = (defaults.dictionary(forKey: customTitlesKey) as? [String: String]) ?? [:]
        self.watchedFolderURL = followsSystemScreenshotLocation
            ? ScreenshotLocationResolver.currentLocation()
            : (Self.loadPersistedFolder() ?? Self.defaultWatchedFolder())
        self.launchAtLoginEnabled = Self.currentLaunchAtLoginState()
    }

    var filteredScreenshots: [ScreenshotItem] {
        let filtered = screenshots.filter { item in
            let matchesDate = selectedDateFilter.matches(item)
            let matchesFavorites = showsFavoritesOnly == false || isFavorite(item)
            return matchesDate && matchesFavorites
        }
        return selectedSortOrder.sort(filtered)
    }

    var groupedScreenshots: [(section: ScreenshotSection, items: [ScreenshotItem])] {
        ScreenshotSection.allCases.compactMap { section in
            let items = filteredScreenshots.filter { ScreenshotSection.section(for: $0.createdAt) == section }
            return items.isEmpty ? nil : (section, items)
        }
    }

    func start() async {
        if followsSystemScreenshotLocation {
            applyCurrentSystemScreenshotLocation()
        }
        await refresh()
        startWatcher()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            screenshots = try await service.scanFolder(at: watchedFolderURL)
            pruneMissingFavorites()
            pruneMissingCustomTitles()
            lastErrorMessage = nil
        } catch {
            screenshots = []
            lastErrorMessage = String(localized: "store.error.read", defaultValue: "Couldn’t read \(watchedFolderURL.lastPathComponent).")
        }
    }

    func chooseWatchedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.directoryURL = watchedFolderURL

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        if followsSystemScreenshotLocation {
            setFollowsSystemScreenshotLocation(false)
        }

        setWatchedFolder(url)
    }

    func setWatchedFolder(_ url: URL) {
        watchedFolderURL = url
        persistWatchedFolder(url)
        Task {
            await refresh()
            startWatcher()
        }
    }

    func delete(_ item: ScreenshotItem) {
        performMutation(removing: item) { [self] in
            try await self.service.delete(item)
        }
    }

    func move(_ item: ScreenshotItem) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move"
        panel.directoryURL = item.url.deletingLastPathComponent()

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        Task {
            do {
                let destinationURL = try await service.move(item, to: folderURL)
                updateFavoritePath(from: item.url.path, to: destinationURL.path)
                updateCustomTitlePath(from: item.url.path, to: destinationURL.path)
                await ThumbnailService.shared.removeCachedThumbnail(for: item.url)
                await refresh()
            } catch {
                lastErrorMessage = String(localized: "store.error.update", defaultValue: "Couldn’t update \(item.filename).")
            }
        }
    }

    func move(_ items: [ScreenshotItem]) {
        guard let referenceItem = items.first else {
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move"
        panel.directoryURL = referenceItem.url.deletingLastPathComponent()

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        Task {
            for item in items {
                do {
                    let destinationURL = try await service.move(item, to: folderURL)
                    updateFavoritePath(from: item.url.path, to: destinationURL.path)
                    updateCustomTitlePath(from: item.url.path, to: destinationURL.path)
                    await ThumbnailService.shared.removeCachedThumbnail(for: item.url)
                } catch {
                    lastErrorMessage = String(localized: "store.error.move", defaultValue: "Couldn’t move \(item.filename).")
                }
            }

            await refresh()
        }
    }

    func rename(_ item: ScreenshotItem, to newName: String) {
        Task {
            do {
                let destinationURL = try await service.rename(item, to: newName)
                updateFavoritePath(from: item.url.path, to: destinationURL.path)
                updateCustomTitlePath(from: item.url.path, to: destinationURL.path)
                await ThumbnailService.shared.removeCachedThumbnail(for: item.url)
                await refresh()
            } catch {
                lastErrorMessage = String(localized: "store.error.update", defaultValue: "Couldn’t update \(item.filename).")
            }
        }
    }

    func revealInFinder(_ item: ScreenshotItem) {
        service.revealInFinder(item)
    }

    func revealInFinder(_ items: [ScreenshotItem]) {
        service.revealInFinder(items)
    }

    func quickLook(_ item: ScreenshotItem) {
        quickLook([item], current: item)
    }

    func quickLook(_ items: [ScreenshotItem], current: ScreenshotItem? = nil) {
        QuickLookPreviewController.shared.preview(items.map(\.url), currentURL: current?.url)
    }

    func copyImage(_ item: ScreenshotItem) {
        guard let image = NSImage(contentsOf: item.url) else {
            lastErrorMessage = String(localized: "store.error.copy", defaultValue: "Couldn’t copy \(item.filename).")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if pasteboard.writeObjects([image]) == false {
            lastErrorMessage = String(localized: "store.error.copy", defaultValue: "Couldn’t copy \(item.filename).")
            return
        }

        lastErrorMessage = nil
    }

    func copyFiles(_ items: [ScreenshotItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let urls = items.map(\.url) as [NSURL]
        if pasteboard.writeObjects(urls) == false {
            lastErrorMessage = String(localized: "Couldn’t copy the selected files.")
            return
        }

        lastErrorMessage = nil
    }

    func copyPaths(_ items: [ScreenshotItem]) {
        let paths = items.map(\.url.path).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
        lastErrorMessage = nil
    }

    func isFavorite(_ item: ScreenshotItem) -> Bool {
        favoritePaths.contains(item.url.path)
    }

    func toggleFavorite(_ item: ScreenshotItem) {
        setFavorite(isFavorite(item) == false, for: [item])
    }

    func setFavorite(_ isFavorite: Bool, for items: [ScreenshotItem]) {
        let paths = items.map { $0.url.path }

        if isFavorite {
            favoritePaths.formUnion(paths)
        } else {
            favoritePaths.subtract(paths)
        }

        persistFavoritePaths()
        objectWillChange.send()
    }

    /// The custom display title for an item, if one was set (independent of the
    /// file name on disk).
    func customTitle(for item: ScreenshotItem) -> String? {
        customTitles[item.url.path]
    }

    /// The title to show in the UI: the custom title if set, otherwise the file
    /// name.
    func displayTitle(for item: ScreenshotItem) -> String {
        let custom = customTitles[item.url.path]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (custom?.isEmpty == false ? custom : nil) ?? item.filename
    }

    /// Sets a custom display title. An empty title — or one equal to the file
    /// name — clears it, reverting to the file name. Never touches the file.
    func setCustomTitle(_ title: String, for item: ScreenshotItem) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == item.filename {
            customTitles.removeValue(forKey: item.url.path)
        } else {
            customTitles[item.url.path] = trimmed
        }
        persistCustomTitles()
        objectWillChange.send()
    }

    func delete(_ items: [ScreenshotItem]) {
        Task {
            for item in items {
                do {
                    try await service.delete(item)
                    favoritePaths.remove(item.url.path)
                    customTitles.removeValue(forKey: item.url.path)
                    await ThumbnailService.shared.removeCachedThumbnail(for: item.url)
                } catch {
                    lastErrorMessage = String(localized: "store.error.update", defaultValue: "Couldn’t update \(item.filename).")
                }
            }

            persistFavoritePaths()
            persistCustomTitles()
            await refresh()
        }
    }

    func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            launchAtLoginEnabled = enabled
            lastErrorMessage = nil
        } catch {
            launchAtLoginEnabled = Self.currentLaunchAtLoginState()
            lastErrorMessage = String(localized: "Couldn’t update Launch at Login.")
        }
    }

    func setFollowsSystemScreenshotLocation(_ enabled: Bool) {
        followsSystemScreenshotLocation = enabled
        defaults.set(enabled, forKey: followSystemLocationKey)

        if enabled {
            applyCurrentSystemScreenshotLocation()
        }
    }

    func applyCurrentSystemScreenshotLocation() {
        let systemURL = ScreenshotLocationResolver.currentLocation()
        setWatchedFolder(systemURL)
    }

    private func performMutation(removing item: ScreenshotItem, operation: @escaping @Sendable () async throws -> Void) {
        Task {
            do {
                try await operation()
                await ThumbnailService.shared.removeCachedThumbnail(for: item.url)
                await refresh()
            } catch {
                lastErrorMessage = String(localized: "store.error.update", defaultValue: "Couldn’t update \(item.filename).")
            }
        }
    }

    private func startWatcher() {
        watcher.startMonitoring(folderURL: watchedFolderURL) { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.handleWatcherEvent(event)
            }
        }
    }

    private func handleWatcherEvent(_ event: ScreenshotWatcherEvent) async {
        if event.requiresFullRescan || event.changedURLs.contains(watchedFolderURL) {
            await refresh()
            return
        }

        let results = await service.resolveChangedItems(at: event.changedURLs, watchedFolderURL: watchedFolderURL)
        applyIncrementalChanges(results)
    }

    private func applyIncrementalChanges(_ changes: [URL: ScreenshotItem?]) {
        guard changes.isEmpty == false else {
            return
        }

        var updated = Dictionary(uniqueKeysWithValues: screenshots.map { ($0.url, $0) })

        for (url, item) in changes {
            if let item {
                updated[url] = item
            } else {
                updated.removeValue(forKey: url)
                favoritePaths.remove(url.path)
                customTitles.removeValue(forKey: url.path)
            }
        }

        screenshots = updated.values.sorted { $0.createdAt > $1.createdAt }
        persistFavoritePaths()
        persistCustomTitles()
        lastErrorMessage = nil
    }

    private func updateFavoritePath(from oldPath: String, to newPath: String) {
        guard favoritePaths.contains(oldPath) else {
            return
        }

        favoritePaths.remove(oldPath)
        favoritePaths.insert(newPath)
        persistFavoritePaths()
    }

    private func updateCustomTitlePath(from oldPath: String, to newPath: String) {
        guard let title = customTitles.removeValue(forKey: oldPath) else {
            return
        }

        customTitles[newPath] = title
        persistCustomTitles()
    }

    private func pruneMissingFavorites() {
        let pruned = favoritePaths.filter { FileManager.default.fileExists(atPath: $0) }
        guard pruned != favoritePaths else {
            return
        }

        favoritePaths = pruned
        persistFavoritePaths()
    }

    private func pruneMissingCustomTitles() {
        let pruned = customTitles.filter { FileManager.default.fileExists(atPath: $0.key) }
        guard pruned.count != customTitles.count else {
            return
        }

        customTitles = pruned
        persistCustomTitles()
    }

    private func persistFavoritePaths() {
        defaults.set(Array(favoritePaths).sorted(), forKey: favoritePathsKey)
    }

    private func persistCustomTitles() {
        defaults.set(customTitles, forKey: customTitlesKey)
    }

    private func persistWatchedFolder(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: watchedFolderBookmarkKey)
        } catch {
            lastErrorMessage = String(localized: "Couldn’t save the watched folder.")
        }
    }

    private static func loadPersistedFolder() -> URL? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "watchedFolderBookmark") else {
            return nil
        }

        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private static func defaultWatchedFolder() -> URL {
        let systemLocation = ScreenshotLocationResolver.currentLocation()

        if FileManager.default.fileExists(atPath: systemLocation.path) {
            return systemLocation
        }

        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private static func currentLaunchAtLoginState() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
