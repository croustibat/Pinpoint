import Foundation

/// The three tools this server exposes (#57), and the one rule every one of
/// them obeys: **never return image bytes**. Claude Code doesn't render an
/// image an MCP tool returns inline — the base64 lands in the transcript as
/// raw text (anthropics/claude-code#31208, closed "not planned") — so a tool
/// that tried would burn the model's context on a wall of characters it can't
/// even look at. What actually reaches the model is a file path it reads with
/// its own `Read` tool, which is the one thing every one of these result
/// bodies leads with and says outright.
///
/// Built on `Handoff` and `HandoffWatcher` rather than a second reading of
/// `capture.json`: the CLI (#56) and this server answer the same two
/// questions — "what's the latest handoff" and "wait for the next one" — and
/// a second implementation of either is a second place for the two to drift.
enum MCPTools {
    // MARK: - Definitions

    /// What `tools/list` answers. `inputSchema` is JSON Schema, by the
    /// protocol's own rule — not `Codable`, because a schema is data a client
    /// introspects, not a type this process needs to decode.
    static let definitions: [[String: Any]] = [
        [
            "name": "capture_region",
            "title": "Capture a region",
            "description": """
            Ask Pinpoint to start an interactive screen capture. The screen dims, \
            the user drags a rectangle by hand, drops numbered markers on what \
            matters, optionally types instructions, and presses Copy in the \
            editor — this call blocks until that happens. Pinpoint cannot select \
            a region or take the screenshot on its own; there is no parameter \
            here that skips the human step, because a capture is only ever what \
            somebody chose to point at.

            Returns the absolute path of the annotated PNG plus the same \
            structured Markdown Pinpoint would have put on the clipboard — never \
            the image itself. Open the PNG with your own file-reading tool; the \
            Markdown alone tells you where every marker sits (pixels and percent \
            of the image), what accessibility element and on-screen text was \
            found under it, and what the user asked for.
            """,
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "timeoutSeconds": [
                        "type": "number",
                        "minimum": 1,
                        "maximum": 3600,
                        "default": 120,
                        "description": "How long to wait for the user to press Copy before giving up."
                    ]
                ]
            ]
        ],
        [
            "name": "get_last_capture",
            "title": "Get the last capture",
            "description": """
            Read the most recent handoff Pinpoint wrote — files only, no app, no \
            permission, no new screenshot. Use this when the user says "look at \
            what I just captured" or "the screenshot I sent you" rather than \
            calling capture_region again: the capture they mean already exists on \
            disk.

            Returns the same shape as capture_region: the PNG's absolute path \
            plus structured Markdown, never inline image bytes. Fails with a \
            distinct error when nothing has been handed off yet, so you can tell \
            "no capture" from "something broke".
            """,
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [:]
            ]
        ],
        [
            "name": "list_recent",
            "title": "List recent captures",
            "description": """
            List the most recent captures Pinpoint has archived, newest first — \
            up to the last \(FileHandoff.maxArchiveEntries), which is all this \
            Mac keeps. Each entry names its PNG and Markdown paths plus a short \
            summary (dimensions, marker count, when it was copied) but, like \
            every tool here, never the image bytes themselves; open a PNG with \
            your own file-reading tool once you know which capture you want.

            Use this to find an earlier capture in the same session rather than \
            the very latest one — for a "the screenshot from a minute ago, not \
            this one" kind of request.
            """,
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "limit": [
                        "type": "integer",
                        "minimum": 1,
                        "maximum": FileHandoff.maxArchiveEntries,
                        "default": 5,
                        "description": "How many captures to list, newest first."
                    ]
                ]
            ]
        ]
    ]

    // MARK: - Dispatch

    /// A tool's outcome, kept apart from the transport: `MCPServer` is the
    /// only thing that knows how a `CallToolResult` is spelled on the wire.
    struct Outcome {
        /// One line for the model to read, Markdown-formatted like every other
        /// text this app produces.
        let text: String
        /// Whether this is a tool-level failure (`isError: true` on the
        /// result) rather than a success. Per the spec, a capture that timed
        /// out or a missing handoff is *not* a protocol error — the model has
        /// to see it in the result and can act on it, the same way a person
        /// reading `pinpoint`'s exit code can.
        let isError: Bool
        /// The parsed handoff, verbatim, alongside the prose — for a client
        /// that would rather index the facts than parse them back out of
        /// Markdown. Absent on error, where there is nothing to structure.
        let structured: [String: Any]?

        static func success(text: String, structured: [String: Any]) -> Outcome {
            Outcome(text: text, isError: false, structured: structured)
        }
        static func failure(_ text: String) -> Outcome {
            Outcome(text: text, isError: true, structured: nil)
        }
    }

    /// Runs `name` with `arguments`, blocking the calling thread — `MCPServer`
    /// is what keeps a long-running `capture_region` from starving the rest of
    /// the session, by giving each call its own queue.
    static func call(_ name: String, arguments: [String: Any],
                     isCancelled: @escaping () -> Bool) -> Outcome {
        switch name {
        case "capture_region":
            return captureRegion(arguments: arguments, isCancelled: isCancelled)
        case "get_last_capture":
            return getLastCapture()
        case "list_recent":
            return listRecent(arguments: arguments)
        default:
            return .failure("Unknown tool “\(name)”. Known tools: capture_region, get_last_capture, list_recent.")
        }
    }

    // MARK: - capture_region

    private static func captureRegion(arguments: [String: Any],
                                      isCancelled: @escaping () -> Bool) -> Outcome {
        guard AppBridge.isAvailable else {
            return .failure("""
            Pinpoint isn’t installed, or macOS has no handler registered for \
            pinpoint://. Install it from https://pinpoint-ashy.vercel.app and \
            launch it once, then try again.
            """)
        }

        let timeout = clampedTimeout(arguments["timeoutSeconds"])

        // Read *before* firing, same as `Commands.capture`: the wait that
        // follows is "is this a different handoff from the one that was there
        // when I asked", and that comparison only means anything if the
        // baseline was taken first.
        let before = Handoff.currentFingerprint()

        guard AppBridge.open(.capture) else {
            return .failure("Couldn’t open \(URLCommand.capture.url.absoluteString).")
        }

        switch HandoffWatcher.wait(after: before, timeout: timeout, isCancelled: isCancelled) {
        case .handoff(let handoff):
            return .success(text: agentText(for: handoff), structured: structured(handoff))
        case .timedOut:
            return .failure("""
            No capture was copied within \(Int(timeout))s. The user may still be \
            drawing the region, may have pressed Esc to cancel, or the editor \
            window may be waiting off-screen. Ask before retrying — a second \
            capture_region call opens a second overlay on top of whatever is \
            already there.
            """)
        case .cancelled:
            return .failure("Cancelled before a capture was copied.")
        }
    }

    /// Shared with `MCPServer`, which needs the same bound to decide how long
    /// to keep the process alive for an in-flight `capture_region` after stdin
    /// closes — a second clamp there, disagreeing with this one by even a
    /// second, would let a still-running call get killed before it could
    /// answer.
    static func clampedTimeout(_ raw: Any?) -> TimeInterval {
        let seconds: Double
        switch raw {
        case let number as NSNumber: seconds = number.doubleValue
        default: seconds = 120
        }
        return min(max(seconds, 1), 3600)
    }

    // MARK: - get_last_capture

    private static func getLastCapture() -> Outcome {
        guard let handoff = (try? Handoff.latest()) ?? nil else {
            return .failure("""
            No capture has been handed off yet. Ask the user to take one — with \
            ⌘⇧1, or by calling capture_region — then try again.
            """)
        }
        return .success(text: agentText(for: handoff), structured: structured(handoff))
    }

    // MARK: - list_recent

    private static func listRecent(arguments: [String: Any]) -> Outcome {
        let limit = clampedLimit(arguments["limit"])
        let handoffs = Handoff.recent(limit: limit)
        guard !handoffs.isEmpty else {
            return .failure("""
            No captures have been archived yet. Ask the user to take one — with \
            ⌘⇧1, or by calling capture_region — then try again.
            """)
        }

        var lines = ["# \(handoffs.count) recent capture\(handoffs.count == 1 ? "" : "s")", ""]
        for handoff in handoffs {
            let document = handoff.document
            lines.append("- `\(handoff.png.path)` — \(document.image.width)×\(document.image.height) px · "
                         + "\(document.markers.count) marker\(document.markers.count == 1 ? "" : "s") · "
                         + document.generatedAt)
        }
        lines.append("")
        lines.append("Open the PNG at the path of whichever entry you mean with your own file-reading "
                     + "tool. Call get_last_capture for the full Markdown of the newest one, or read its "
                     + "sibling `.md` file directly for any of the others.")

        let structured: [String: Any] = [
            "captures": handoffs.map { handoff -> [String: Any] in
                [
                    "png": handoff.png.path,
                    "markdown": handoff.markdown.path,
                    "json": handoff.json.path,
                    "capture": handoff.raw
                ]
            }
        ]
        return .success(text: lines.joined(separator: "\n"), structured: structured)
    }

    private static func clampedLimit(_ raw: Any?) -> Int {
        let value: Int
        switch raw {
        case let number as NSNumber: value = number.intValue
        default: value = 5
        }
        return min(max(value, 1), FileHandoff.maxArchiveEntries)
    }

    // MARK: - Shared

    /// The Markdown handed back for a single handoff: `capture.md`, verbatim,
    /// with the file paths stated up front so the instruction to open the PNG
    /// is the first thing read rather than a footnote.
    private static func agentText(for handoff: Handoff) -> String {
        let header = """
        PNG: \(handoff.png.path)
        Open that file with your own file-reading tool to see the image — this \
        result deliberately carries no image bytes.

        """
        let markdown = (try? String(contentsOf: handoff.markdown, encoding: .utf8)) ?? """
        (capture.md couldn’t be read at \(handoff.markdown.path); the facts below \
        come from capture.json instead.)

        \(handoff.document.markers.count) marker(s), \(handoff.document.shapes.count) shape(s).
        """
        return header + markdown
    }

    private static func structured(_ handoff: Handoff) -> [String: Any] {
        [
            "png": handoff.png.path,
            "markdown": handoff.markdown.path,
            "json": handoff.json.path,
            "capture": handoff.raw
        ]
    }
}
