import AppKit
import Foundation

actor ScreenshotService {
    private let fileManager = FileManager.default
    private let supportedExtensions = Set(["png", "jpg", "jpeg"])

    func scanFolder(at folderURL: URL) throws -> [ScreenshotItem] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .creationDateKey
        ]

        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url in
            try screenshotItemIfSupported(at: url, resourceKeys: keys)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func resolveChangedItems(at urls: [URL], watchedFolderURL: URL) async -> [URL: ScreenshotItem?] {
        var results: [URL: ScreenshotItem?] = [:]

        for url in urls {
            guard url.deletingLastPathComponent() == watchedFolderURL || url == watchedFolderURL else {
                continue
            }

            if url == watchedFolderURL {
                results[url] = nil
                continue
            }

            let item = await stableScreenshotItemIfSupported(at: url)
            results[url] = item
        }

        return results
    }

    func delete(_ item: ScreenshotItem) throws {
        var resultingItemURL: NSURL?
        try fileManager.trashItem(at: item.url, resultingItemURL: &resultingItemURL)
    }

    func move(_ item: ScreenshotItem, to destinationFolder: URL) throws -> URL {
        let destinationURL = uniqueDestinationURL(for: item.url, in: destinationFolder)
        try fileManager.moveItem(at: item.url, to: destinationURL)
        return destinationURL
    }

    func rename(_ item: ScreenshotItem, to newName: String) throws -> URL {
        let sanitized = sanitizedFilename(newName, originalExtension: item.fileExtension)
        let destinationURL = item.url.deletingLastPathComponent().appendingPathComponent(sanitized)
        let finalURL = uniqueDestinationURL(for: destinationURL, in: destinationURL.deletingLastPathComponent())
        try fileManager.moveItem(at: item.url, to: finalURL)
        return finalURL
    }

    nonisolated func revealInFinder(_ item: ScreenshotItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    nonisolated func revealInFinder(_ items: [ScreenshotItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    private func stableScreenshotItemIfSupported(at url: URL) async -> ScreenshotItem? {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey
        ]

        var previousSize: Int?

        for attempt in 0..<6 {
            do {
                let values = try url.resourceValues(forKeys: keys)

                guard values.isRegularFile == true else {
                    return nil
                }

                let currentSize = values.fileSize ?? 0
                let createdAt = values.creationDate ?? values.contentModificationDate ?? .distantPast
                let item = ScreenshotItem(url: url, createdAt: createdAt)

                if let previousSize, previousSize == currentSize, currentSize > 0 {
                    return item
                }

                previousSize = currentSize
            } catch {
                return nil
            }

            if attempt < 5 {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        return nil
    }

    private func screenshotItemIfSupported(
        at url: URL,
        resourceKeys: Set<URLResourceKey>
    ) throws -> ScreenshotItem? {
        let values = try url.resourceValues(forKeys: resourceKeys)

        guard values.isRegularFile == true else {
            return nil
        }

        let pathExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(pathExtension) else {
            return nil
        }

        let createdAt = values.creationDate ?? values.contentModificationDate ?? .distantPast
        return ScreenshotItem(url: url, createdAt: createdAt)
    }

    private func sanitizedFilename(_ name: String, originalExtension: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Screenshot" : trimmed

        if (baseName as NSString).pathExtension.isEmpty {
            return "\(baseName).\(originalExtension)"
        }

        return baseName
    }

    private func uniqueDestinationURL(for originalURL: URL, in folderURL: URL) -> URL {
        let fileExtension = originalURL.pathExtension
        let filename = originalURL.deletingPathExtension().lastPathComponent
        var candidate = folderURL.appendingPathComponent(originalURL.lastPathComponent)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let suffix = " \(index)"
            let name = fileExtension.isEmpty ? "\(filename)\(suffix)" : "\(filename)\(suffix).\(fileExtension)"
            candidate = folderURL.appendingPathComponent(name)
            index += 1
        }

        return candidate
    }
}
