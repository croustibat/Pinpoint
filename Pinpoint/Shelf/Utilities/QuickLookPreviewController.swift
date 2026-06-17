import AppKit
@preconcurrency import QuickLookUI

final class QuickLookPreviewController: NSObject {
    @MainActor
    static let shared = QuickLookPreviewController()

    private var items: [URL] = []
    private var currentIndex = 0

    @MainActor
    func preview(_ urls: [URL], currentURL: URL? = nil) {
        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard existingURLs.isEmpty == false else {
            return
        }

        items = existingURLs
        if let currentURL, let index = existingURLs.firstIndex(of: currentURL) {
            currentIndex = index
        } else {
            currentIndex = 0
        }

        guard let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = currentIndex
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension QuickLookPreviewController: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as NSURL
    }
}

extension QuickLookPreviewController: QLPreviewPanelDelegate {}
