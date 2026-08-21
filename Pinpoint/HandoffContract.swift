import CoreGraphics
import Foundation

/// Where a handoff lives on disk, and how to read one back.
///
/// This is the half of `FileHandoff` that has no opinion about images. It is
/// split out because the `pinpoint` CLI (#56) is compiled from these very
/// sources: `pinpoint last` reads the file the app wrote, in the directory the
/// app chose, decoded through the type the app encoded. A second copy of any of
/// those three would be a second thing to keep in step — and the first
/// divergence would be a silent one, a path that still resolves or a key that
/// quietly stopped being read.
///
/// What stays in `FileHandoff.swift` is everything that renders and writes: it
/// pulls in AppKit, `Exporter` and the whole annotation model, none of which a
/// file reader needs.
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

    /// How many timestamped folders `archive/` keeps; the oldest are deleted on
    /// every write. Kept deliberately low because each folder carries a
    /// full-resolution copy of the PNG (a Retina capture runs to several MB),
    /// and this directory is never surfaced in the UI — nobody would notice it
    /// growing.
    ///
    /// Part of the contract rather than of the writing half: the MCP server's
    /// `list_recent` (#57) states this cap in its own tool schema and in the
    /// sentence it hands the agent, and a second copy of the number is a second
    /// thing to keep in step.
    static let maxArchiveEntries = 10

    static let pngFileName = "capture.png"
    static let markdownFileName = "capture.md"
    static let jsonFileName = "capture.json"

    /// The three files of the current handoff. Named rather than rebuilt at
    /// each call site: they are quoted in the CLI's output, in the deep-link
    /// handler and in the README, and they have to agree everywhere.
    static var latestPNG: URL { latestDirectory.appendingPathComponent(pngFileName) }
    static var latestMarkdown: URL { latestDirectory.appendingPathComponent(markdownFileName) }
    static var latestJSON: URL { latestDirectory.appendingPathComponent(jsonFileName) }

    /// Whether `url` sits in `last/` — the directory this contract owns.
    ///
    /// Worth asking before writing anything next to a file taken from there:
    /// the folder is replaced wholesale on the next copy (see
    /// `replaceDirectory`), so a sibling written by someone else both pollutes
    /// what an agent reads and disappears without notice.
    static func isInLatestDirectory(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == latestDirectory.standardizedFileURL
    }

    // MARK: - Reading

    /// The one encoder every producer of this contract uses.
    ///
    /// Pretty-printed, key-sorted and unescaped: a human debugging this reads it,
    /// `\/Users\/…` for every path is noise, and a fixed key order keeps two
    /// handoffs of the same annotations byte-identical. Shared with
    /// `Exporter.buildJSON` so the file on disk and the JSON handed to the
    /// clipboard can't drift into two dialects of the same schema.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Reads a handoff document back.
    ///
    /// The contract was write-only until now, which is a strange thing to hand
    /// somebody as an interoperability format: the CLI (#56) and the MCP server
    /// (#57) both have to read `last/capture.json` before they can act on it, and
    /// so does anything a user scripts. Every field decodes the way it encodes,
    /// and the keys added since version 1 are optional, so a document written by
    /// an older build still reads.
    static func readDocument(at url: URL) throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
    }

    /// The most recent handoff, or nil when none has been written yet.
    static func latestDocument() -> Document? {
        try? readDocument(at: latestJSON)
    }

    // MARK: - Shared values

    /// A normalized 0…1 coordinate as a percentage with two decimals. Finer
    /// than the whole percents `capture.md` prints — the text is for reading,
    /// this is for computing against.
    static func percent(_ value: CGFloat) -> Double {
        (Double(value) * 10_000).rounded() / 100
    }

    /// The vermillon `NSColor.pinpointVermillon` draws every marker and outline
    /// in, spelled for the JSON. Hard-coded rather than read back off the colour:
    /// this is a contract value, and it should take an edit here — not a change
    /// of colour space on someone's Mac — to move it.
    static let markerColorHex = "#FF4D2E"
}
