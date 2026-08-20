import AppKit

/// Writes the annotated capture to a stable, predictable place on disk so an
/// agent can pick it up with its own file tools.
///
/// The clipboard alone is not a reliable channel. Claude Code doesn't render
/// images returned inline by an MCP server — the base64 lands in the transcript
/// as raw text (anthropics/claude-code#31208, closed "not planned") — so what
/// actually reaches the model is a *file path* it reads itself. Every copy
/// therefore also drops a triplet on disk:
///
///     ~/Library/Application Support/Pinpoint/last/capture.png   annotated image, native resolution
///     ~/Library/Application Support/Pinpoint/last/capture.md    the agent-ready text
///     ~/Library/Application Support/Pinpoint/last/capture.json  the same facts, machine-readable
///
/// plus a timestamped copy under `…/Pinpoint/archive/<stamp>/`.
///
/// Application Support rather than the user's screenshot folder: the path has
/// to be hard-codable by an agent that never saw this machine, and the
/// screenshot folder is neither fixed (see `ScreenshotLocationResolver`) nor
/// ours to pollute — the Shelf watches it, so writing there would feed our own
/// output back into the library. `CaptureHistory` already owns
/// `Application Support/Pinpoint/Captures`, so we stay in the same root.
enum FileHandoff {
    // MARK: - Contract

    /// Version of the JSON contract written to `capture.json`.
    ///
    /// Bumped only on a *breaking* change — a key removed, renamed, or given a
    /// new meaning. Adding keys is not breaking, which is why #55 hanging an
    /// `accessibility` object off each marker (and one on the document) left
    /// this at 1: a consumer written against version 1 reads exactly what it
    /// read before. Read what you know, ignore the rest.
    static let schemaVersion = 1

    /// How many timestamped folders `archive/` keeps; the oldest are deleted on
    /// every write. Kept deliberately low because each folder carries a
    /// full-resolution copy of the PNG (a Retina capture runs to several MB),
    /// and this directory is never surfaced in the UI — nobody would notice it
    /// growing.
    static let maxArchiveEntries = 10

    /// `~/Library/Application Support/Pinpoint`.
    static var rootDirectory: URL {
        // No temp-directory fallback (unlike `CaptureHistory`): the whole point
        // of this location is that an agent can hard-code it, so a random path
        // would be worse than useless. If the lookup ever fails we rebuild the
        // very path it would have returned.
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Pinpoint", isDirectory: true)
    }

    /// The fixed location an agent reads: always the most recent handoff.
    static var latestDirectory: URL {
        rootDirectory.appendingPathComponent("last", isDirectory: true)
    }

    /// Timestamped copies of past handoffs, capped to `maxArchiveEntries`.
    static var archiveDirectory: URL {
        rootDirectory.appendingPathComponent("archive", isDirectory: true)
    }

    static let pngFileName = "capture.png"
    static let markdownFileName = "capture.md"
    static let jsonFileName = "capture.json"

    /// Where a handoff landed. Returned so the callers that come next (the CLI
    /// of #56, the MCP server of #57) can report the paths without rebuilding
    /// them.
    struct Output {
        let directory: URL
        let png: URL
        let markdown: URL
        let json: URL
        /// The timestamped copy, or nil when the archive couldn't be written —
        /// see `write(base:pins:shapes:context:style:)`.
        let archive: URL?
    }

    enum Failure: LocalizedError {
        /// The annotated PNG couldn't be produced, so there is nothing to hand
        /// off. Write failures aren't listed here: `FileManager` already throws
        /// localized errors, which we let through untouched.
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                return String(localized: "The annotated image couldn’t be rendered.")
            }
        }
    }

    // MARK: - Writing

    /// Renders the capture and writes the triplet to `last/`, then archives a
    /// timestamped copy.
    ///
    /// Throws when the `last/` triplet couldn't be written — that failure has to
    /// reach the user rather than be swallowed behind a "Copied!" (#38). The
    /// archive is best effort: it's a convenience, not the contract, so a
    /// failure there only leaves `Output.archive` nil.
    @discardableResult
    static func write(base: NSImage, pins: [Pin], shapes: [Markup],
                      context: String, style: PinStyle,
                      accessibility: AXSnapshot? = nil) throws -> Output {
        // No legend strip, whatever the editor's `includeLegend` setting says.
        // The legend grows the image downwards, which would shift every pixel
        // coordinate in the .md and .json off the pixels they describe — and
        // the point of the triplet is that the text travels with the image, so
        // baking it in buys nothing here. Native resolution, no clipboard cap:
        // this file is read, not pasted.
        guard let render = Exporter.renderPNG(base: base, pins: pins, shapes: shapes, context: context,
                                              style: style, includeLegend: false, maxDimension: nil) else {
            throw Failure.renderFailed
        }
        let png = render.data
        // Measured off the PNG we just produced, not taken from `base.size`.
        // The renderer now draws into a bitmap of exactly the requested pixel
        // size (#76), so the two agree — but the .md and .json quote pixel
        // coordinates in the grid of the file sitting next to them, and that
        // guarantee belongs to whoever wrote the bytes, not to a caller's
        // assumption about them.
        let pixelSize = render.pixelSize

        // Always the full agent-ready text, again regardless of `includeLegend`
        // — which is what keeps the enriched export (#41) reachable even in the
        // default configuration, where the clipboard only carries the image
        // (#69).
        let markdown = Exporter.buildText(pins: pins, shapes: shapes,
                                          context: context, imageSize: pixelSize,
                                          accessibility: accessibility)

        let latest = latestDirectory
        try replaceDirectory(latest, with: files(png: png, markdown: markdown,
                                                 pins: pins, shapes: shapes, context: context,
                                                 imageSize: pixelSize, directory: latest,
                                                 accessibility: accessibility))

        let archived = try? archive(png: png, markdown: markdown, pins: pins, shapes: shapes,
                                    context: context, imageSize: pixelSize,
                                    accessibility: accessibility)

        return Output(
            directory: latest,
            png: latest.appendingPathComponent(pngFileName),
            markdown: latest.appendingPathComponent(markdownFileName),
            json: latest.appendingPathComponent(jsonFileName),
            archive: archived
        )
    }

    /// The three files of a handoff, in the order they're written. `directory`
    /// is where they will *end up*: the JSON quotes absolute paths, so it has to
    /// be built for its final home, not for the staging folder.
    private static func files(png: Data, markdown: String, pins: [Pin], shapes: [Markup],
                              context: String, imageSize: CGSize, directory: URL,
                              accessibility: AXSnapshot?) throws -> [(name: String, data: Data)] {
        let document = Document(pins: pins, shapes: shapes, context: context,
                                imageSize: imageSize, directory: directory,
                                accessibility: accessibility)
        let encoder = JSONEncoder()
        // Pretty-printed, key-sorted and unescaped: a human debugging this reads
        // it, `\/Users\/…` for every path is noise, and a fixed key order keeps
        // two handoffs of the same annotations byte-identical.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return [
            (pngFileName, png),
            (markdownFileName, Data(markdown.utf8)),
            (jsonFileName, try encoder.encode(document))
        ]
    }

    /// Writes `files` into `directory`, replacing whatever was there.
    ///
    /// Staged in a sibling folder and swapped in with a single `replaceItemAt`,
    /// so an agent reading `last/` gets either the previous handoff or the new
    /// one — never a half-written PNG, and never a fresh `.md` describing the
    /// previous `.png`.
    private static func replaceDirectory(_ directory: URL,
                                         with files: [(name: String, data: Data)]) throws {
        let fileManager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let staging = parent.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        // Only fires when something below threw; a successful swap consumes it.
        defer { try? fileManager.removeItem(at: staging) }

        for file in files {
            try file.data.write(to: staging.appendingPathComponent(file.name), options: .atomic)
        }

        if fileManager.fileExists(atPath: directory.path) {
            _ = try fileManager.replaceItemAt(directory, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: directory)
        }
    }

    /// Writes a timestamped copy of the handoff and prunes the oldest ones.
    private static func archive(png: Data, markdown: String, pins: [Pin], shapes: [Markup],
                                context: String, imageSize: CGSize,
                                accessibility: AXSnapshot?) throws -> URL {
        let folder = archiveDirectory.appendingPathComponent(timestamp(), isDirectory: true)
        try replaceDirectory(folder, with: files(png: png, markdown: markdown,
                                                 pins: pins, shapes: shapes, context: context,
                                                 imageSize: imageSize, directory: folder,
                                                 accessibility: accessibility))
        prune()
        return folder
    }

    /// `2026-08-20-141203-482` — sorts chronologically as text, and carries
    /// milliseconds so two copies in the same second don't collide.
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        // POSIX locale so the pattern isn't rewritten by the user's regional
        // settings; local time because these folder names are read by a human
        // browsing the archive.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    /// Keeps the `maxArchiveEntries` most recent folders. Without it the archive
    /// grows one folder per copy for the life of the install.
    private static func prune() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return }

        let folders = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard folders.count > maxArchiveEntries else { return }

        // By creation date rather than by name: the names carry local time, so
        // a DST rollback would sort an hour's worth of them the wrong way round.
        let newestFirst = folders.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return leftDate > rightDate
        }
        for folder in newestFirst.dropFirst(maxArchiveEntries) {
            try? fileManager.removeItem(at: folder)
        }
    }
}
