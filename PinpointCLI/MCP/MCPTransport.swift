import Foundation

/// The stdio pipe, and the one rule that makes it work.
///
/// An MCP client launches this process and speaks to it over the standard
/// streams. Messages are newline-delimited JSON, so **stdout carries protocol
/// and nothing else**: one stray line — a `print`, a warning, a progress dot —
/// lands in the middle of the stream, fails to parse as a JSON-RPC message, and
/// takes the whole session down. Every human-facing word goes to stderr, which
/// the client is free to log or drop.
///
/// That is why `Out.stdout` is never called from anywhere under `MCP/`, and why
/// writing goes through `send` alone: it is the only door to stdout, it holds a
/// lock while it writes, and it serializes compactly on purpose. Pretty-printed
/// JSON contains real newlines, which here is not a formatting choice but a
/// framing bug.
final class MCPTransport {
    /// Guards stdout. Tool calls run concurrently (see `MCPServer`), so two
    /// responses can be ready at the same instant; without this they interleave
    /// mid-line and both are lost.
    private let writeLock = NSLock()
    private let handle = FileHandle.standardOutput

    /// Writes one JSON-RPC message, followed by its newline.
    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message,
                                                     options: [.withoutEscapingSlashes]) else {
            // Only reachable if a value isn't JSON-representable — a bug here,
            // not a state of the world. Say so on stderr and write nothing:
            // half a document on stdout is worse than no document.
            Self.log("couldn’t encode an outgoing message")
            return
        }

        // Body and newline in a single write, so nothing can slip between a
        // message and its delimiter.
        var line = data
        line.append(0x0A)

        writeLock.lock()
        defer { writeLock.unlock() }
        do {
            try handle.write(contentsOf: line)
        } catch {
            // The client closed the pipe while we were answering. Nothing to
            // do about it and nowhere to report it to but stderr; the read loop
            // will see EOF on its own and end the process.
            Self.log("couldn’t write to stdout: \(error.localizedDescription)")
        }
    }

    /// Reads lines from stdin until the client closes it, handing each to
    /// `handler`.
    ///
    /// Blocking and single-threaded by design: this is the only reader of
    /// stdin, and the messages on it are ordered. Anything slow that `handler`
    /// starts belongs on another queue — see `MCPServer.handle`.
    func readLoop(_ handler: (String) -> Void) {
        while let line = readLine(strippingNewline: true) {
            // Clients are allowed to send blank lines between messages, and a
            // pipe that ends without a trailing newline produces one here.
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            handler(trimmed)
        }
    }

    /// The only logging channel a stdio server has.
    static func log(_ text: String) {
        FileHandle.standardError.write(Data(("pinpoint mcp: " + text + "\n").utf8))
    }
}
