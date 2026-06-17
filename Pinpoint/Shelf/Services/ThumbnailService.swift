import AppKit
import Foundation
import QuickLookThumbnailing

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let generator = QLThumbnailGenerator.shared
    private var cache: [URL: NSImage] = [:]

    func thumbnail(for url: URL, size: CGSize = CGSize(width: 220, height: 180), scale: CGFloat = 2) async -> NSImage? {
        if let cached = cache[url] {
            return cached
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        let image = await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            generator.generateBestRepresentation(for: request) { representation, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: representation?.nsImage)
            }
        }

        if let image {
            cache[url] = image
        }

        return image
    }

    func removeCachedThumbnail(for url: URL) {
        cache[url] = nil
    }

    func reset() {
        cache.removeAll()
    }
}
