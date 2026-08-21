import AppKit

/// Persists recent captures (raw PNG + annotation state) under Application
/// Support, newest first, capped to `maxEntries`. Backed by a JSON index.
@MainActor
final class CaptureHistory {
    static let shared = CaptureHistory()

    private let maxEntries = 15
    private let fileManager = FileManager.default

    private(set) var records: [CaptureRecord] = []

    private lazy var directory: URL = {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Pinpoint/Captures", isDirectory: true)
    }()

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Mutations

    /// Saves the raw image and prepends a new record. Returns it (or nil if the
    /// PNG couldn't be written).
    ///
    /// `accessibility` is the tree read at the same instant as the pixels
    /// (#55), stored beside the PNG so reopening a capture from "Recent
    /// captures" can still name the element under a marker placed days later.
    /// Best effort: if the sidecar can't be written the capture is still
    /// recorded, it just carries no interface details.
    @discardableResult
    func add(image: NSImage, accessibility: AXSnapshot? = nil) -> CaptureRecord? {
        guard let png = Self.pngData(from: image) else { return nil }
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        do {
            try png.write(to: directory.appendingPathComponent(fileName))
        } catch {
            return nil
        }

        let record = CaptureRecord(
            id: id,
            date: Date(),
            imageFileName: fileName,
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded()),
            pins: [],
            shapes: [],
            context: "",
            axFileName: writeSidecar(accessibility, for: id)
        )
        records.insert(record, at: 0)
        prune()
        saveIndex()
        return record
    }

    /// Updates the annotation state of an existing record.
    func update(id: UUID, pins: [Pin], shapes: [Markup], context: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].pins = pins
        records[index].shapes = shapes
        records[index].context = context
        saveIndex()
    }

    /// Replaces the raw image of an existing record (e.g. after a crop). The
    /// filename is kept stable; only the PNG bytes and the pixel dimensions
    /// change, so the capture reopens at its new native size.
    func replaceImage(id: UUID, image: NSImage) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard let png = Self.pngData(from: image) else { return }
        // Only mutate the record if the PNG actually landed on disk, otherwise
        // the index would advertise dimensions that don't match the file.
        do {
            try png.write(to: directory.appendingPathComponent(records[index].imageFileName))
        } catch {
            return
        }
        records[index].width = Int(image.size.width.rounded())
        records[index].height = Int(image.size.height.rounded())
        saveIndex()
    }

    /// Replaces the accessibility snapshot of an existing record — what a crop
    /// (#21) produces, since it narrows the region the snapshot describes.
    ///
    /// A nil snapshot deletes the sidecar rather than leaving a stale one: after
    /// a crop, the old file would describe a region the image no longer shows.
    func replaceAccessibility(id: UUID, snapshot: AXSnapshot?) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        removeSidecar(records[index])
        records[index].axFileName = writeSidecar(snapshot, for: id)
        saveIndex()
    }

    func clear() {
        for record in records {
            try? fileManager.removeItem(at: directory.appendingPathComponent(record.imageFileName))
            removeSidecar(record)
        }
        records.removeAll()
        saveIndex()
    }

    // MARK: - Reads

    /// Rebuilds the NSImage at its native pixel size (PNG reload alone would use
    /// the file's DPI, which can differ from the captured pixel dimensions).
    func image(for record: CaptureRecord) -> NSImage? {
        let url = directory.appendingPathComponent(record.imageFileName)
        guard let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        let image = NSImage(size: NSSize(width: record.width, height: record.height))
        image.addRepresentation(rep)
        return image
    }

    /// The accessibility snapshot stored with a record, if any. Read lazily —
    /// only the capture being edited needs it, and decoding all fifteen at
    /// launch would be pure waste.
    func accessibility(for record: CaptureRecord) -> AXSnapshot? {
        guard let name = record.axFileName,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(AXSnapshot.self, from: data)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([CaptureRecord].self, from: data) else { return }
        // Keep only records whose image file still exists — and take their
        // accessibility sidecars down with them, so a hand-deleted PNG doesn't
        // leave an orphan JSON behind forever.
        records = decoded.filter { record in
            let alive = fileManager.fileExists(atPath: directory.appendingPathComponent(record.imageFileName).path)
            if !alive { removeSidecar(record) }
            return alive
        }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexURL)
    }

    private func prune() {
        guard records.count > maxEntries else { return }
        for record in records[maxEntries...] {
            try? fileManager.removeItem(at: directory.appendingPathComponent(record.imageFileName))
            removeSidecar(record)
        }
        records.removeLast(records.count - maxEntries)
    }

    // MARK: - Accessibility sidecar

    /// Writes `snapshot` as `<uuid>-ax.json` and returns its file name, or nil
    /// when there was nothing to write or the write failed. Never throws: a
    /// missing sidecar costs the interface details, nothing else.
    private func writeSidecar(_ snapshot: AXSnapshot?, for id: UUID) -> String? {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return nil }
        let name = "\(id.uuidString)-ax.json"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        return name
    }

    private func removeSidecar(_ record: CaptureRecord) {
        guard let name = record.axFileName else { return }
        try? fileManager.removeItem(at: directory.appendingPathComponent(name))
    }

    /// Encodes an NSImage as PNG. Static so callers outside this type (e.g. the
    /// editor writing a cropped image next to a Shelf file) reuse the same path.
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
