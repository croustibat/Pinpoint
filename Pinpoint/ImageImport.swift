import AppKit

/// Brings an image that wasn't captured by Pinpoint into the editor (#100):
/// whatever is on the clipboard, or a file dropped on the menu-bar icon.
///
/// Every path ends in a bitmap at its native pixel size, like the shelf's
/// "Edit in Pinpoint": `NSImage(contentsOf:)` / `NSImage(pasteboard:)` honour
/// the DPI and would halve a Retina screenshot on the canvas.
enum ImageImport {
    /// Whether `url` is a file `NSBitmapImageRep` can decode — PNG, JPEG,
    /// HEIC, TIFF, GIF, BMP… Asked of the decoder itself rather than of
    /// `UTType.image`, which also admits SVG and other formats it can't read.
    static func isSupportedImageFile(_ url: URL) -> Bool {
        guard url.isFileURL,
              let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return NSBitmapImageRep.imageTypes.contains(type.identifier)
    }

    /// Image files among the file URLs on `pasteboard`, in pasteboard order.
    static func imageFiles(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(isSupportedImageFile)
    }

    /// The image on the clipboard.
    ///
    /// A file copied in the Finder comes first: the pasteboard then also
    /// carries the file's icon as TIFF, which is not what anyone means by
    /// "the image I copied". Otherwise the bitmap itself — PNG before TIFF,
    /// because browsers put the original encoding in PNG and a re-encoded
    /// copy in TIFF.
    static func clipboardImage(_ pasteboard: NSPasteboard = .general) -> NSImage? {
        if let file = imageFiles(on: pasteboard).first {
            return load(at: file)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = image(from: data) {
                return image
            }
        }
        return nil
    }

    static func load(at url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return image(from: data)
    }

    private static func image(from data: Data) -> NSImage? {
        guard let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            return nil
        }
        let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        image.addRepresentation(rep)
        return image
    }
}

/// Makes the menu-bar icon a drop target for image files (#100).
///
/// `NSStatusBarButton` can't be subclassed from outside, so the button's
/// window is registered instead: AppKit hands the dragging-destination calls
/// to the window's delegate when no view under the cursor takes them.
@MainActor
final class StatusItemDropTarget: NSObject, NSWindowDelegate, NSDraggingDestination {
    private weak var button: NSStatusBarButton?
    private let onDrop: (URL) -> Void

    init(button: NSStatusBarButton, onDrop: @escaping (URL) -> Void) {
        self.button = button
        self.onDrop = onDrop
        super.init()
        button.window?.registerForDraggedTypes([.fileURL])
        button.window?.delegate = self
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !ImageImport.imageFiles(on: sender.draggingPasteboard).isEmpty else { return [] }
        button?.highlight(true)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ImageImport.imageFiles(on: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        button?.highlight(false)
    }

    func draggingEnded(_ sender: NSDraggingInfo) {
        button?.highlight(false)
    }

    /// Several files open the first one: the editor holds a single capture,
    /// and a stack of editor windows from one drop is rarely what was meant.
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        button?.highlight(false)
        guard let url = ImageImport.imageFiles(on: sender.draggingPasteboard).first else { return false }
        onDrop(url)
        return true
    }
}
