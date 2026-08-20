import Foundation

/// Turns a handoff into whatever the caller asked to see.
enum Report {
    static func emit(_ handoff: Handoff, savedTo: URL?, format: Arguments.Format) throws {
        switch format {
        case .json:
            Out.json(envelope(handoff, savedTo: savedTo))
        case .md:
            // The file goes to stdout untouched; where the PNG landed is a note
            // about the command, not part of the document.
            if let savedTo { Out.stderr("saved \(savedTo.path)") }
            Out.stdout(try markdown())
        case .text:
            Out.stdout(summary(handoff, savedTo: savedTo))
        }
    }

    /// The machine-readable answer.
    ///
    /// An envelope around the contract rather than the contract alone: a caller
    /// needs to know whether the command succeeded and where the copy landed,
    /// and `capture.json` describes a capture, not a command. `capture` holds
    /// the document verbatim — see `Handoff.raw` for why it isn't rebuilt.
    static func envelope(_ handoff: Handoff, savedTo: URL?) -> [String: Any] {
        var body: [String: Any] = [
            "ok": true,
            "capture": handoff.raw,
            "files": [
                "png": FileHandoff.latestPNG.path,
                "markdown": FileHandoff.latestMarkdown.path,
                "json": FileHandoff.latestJSON.path
            ]
        ]
        if let savedTo {
            body["savedTo"] = savedTo.path
        }
        return body
    }

    private static func markdown() throws -> String {
        let url = FileHandoff.latestMarkdown
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw CLIError.failure("Couldn’t read \(url.path).")
        }
        // Trailing newline is added by `Out.stdout`; the file's own would make
        // two, and `pinpoint last --format md | pbcopy` should paste what the
        // editor wrote.
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// A few aligned lines for a person at a terminal. Everything here is also
    /// in the JSON — this is the same facts, shorter.
    private static func summary(_ handoff: Handoff, savedTo: URL?) -> String {
        let document = handoff.document
        var head = "\(document.image.width)×\(document.image.height) px"
        head += " · \(count(document.markers.count, "marker"))"
        if !document.shapes.isEmpty {
            head += " · \(count(document.shapes.count, "shape"))"
        }

        var lines = [head]
        if let source = document.source {
            let app = source.application ?? "unknown app"
            lines.append(row("app", source.windowTitle.map { "\(app) — \($0)" } ?? app))
        }
        lines.append(row("copied", document.generatedAt))
        if !document.context.isEmpty {
            lines.append(row("context", document.context.replacingOccurrences(of: "\n", with: " ")))
        }
        lines.append(row("png", FileHandoff.latestPNG.path))
        lines.append(row("md", FileHandoff.latestMarkdown.path))
        lines.append(row("json", FileHandoff.latestJSON.path))
        if let savedTo {
            lines.append(row("saved", savedTo.path))
        }
        return lines.joined(separator: "\n")
    }

    private static func row(_ label: String, _ value: String) -> String {
        label.padding(toLength: 8, withPad: " ", startingAt: 0) + value
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
