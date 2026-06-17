import AppKit
import Foundation

enum PreviewSampleData {
    static let items: [ScreenshotItem] = makeItems()
    @MainActor
    static let store: ScreenshotStore = {
        let store = ScreenshotStore()
        store.setWatchedFolder(sampleFolderURL)
        return store
    }()

    private static let sampleFolderURL: URL = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnapShelfPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static func makeItems() -> [ScreenshotItem] {
        let definitions: [(String, NSColor, TimeInterval)] = [
            ("Screenshot 2026-03-27 at 09.14.12.png", .systemBlue, 0),
            ("Screenshot 2026-03-27 at 08.50.21.png", .systemGreen, -900),
            ("Screenshot 2026-03-26 at 18.02.08.png", .systemOrange, -86_400),
            ("Screenshot 2026-03-23 at 14.11.03.png", .systemPink, -6 * 86_400),
            ("Screenshot 2026-03-11 at 10.21.55.png", .systemPurple, -18 * 86_400),
            ("Screenshot 2026-02-19 at 11.07.32.png", .systemTeal, -38 * 86_400)
        ]

        return definitions.compactMap { name, color, offset in
            let url = sampleFolderURL.appendingPathComponent(name)

            if FileManager.default.fileExists(atPath: url.path) == false {
                let image = NSImage(size: NSSize(width: 1440, height: 900))
                image.lockFocus()
                color.setFill()
                NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()

                let title = NSString(string: "SnapShelf")
                title.draw(
                    at: NSPoint(x: 56, y: 56),
                    withAttributes: [
                        .foregroundColor: NSColor.white,
                        .font: NSFont.systemFont(ofSize: 96, weight: .bold)
                    ]
                )
                image.unlockFocus()

                if let tiffData = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiffData),
                   let pngData = rep.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: url)
                }
            }

            let date = Date().addingTimeInterval(offset)
            return ScreenshotItem(url: url, createdAt: date)
        }
    }
}
