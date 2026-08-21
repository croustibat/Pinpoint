import Foundation

/// `pinpoint mcp` — the stdio server (#57).
///
/// A client launches this process, speaks JSON-RPC to it over stdin/stdout,
/// and expects nothing else on stdout ever — see `MCPTransport`. The eight
/// methods below are the whole surface: a client that sends anything else
/// gets `methodNotFound`, which is the correct answer and not a gap to fill,
/// since MCP defines a much larger protocol (resources, prompts, sampling…)
/// this server has no use for. It offers tools. That's all.
final class MCPServer {
    /// Versions this server will negotiate. Newest first: `initialize` echoes
    /// back the client's requested version when it's one of these, and offers
    /// the newest otherwise — the client then disconnects if it can't follow,
    /// which is the protocol's own rule, not a case this server has to guard.
    private static let supportedProtocolVersions = [
        "2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"
    ]

    private let transport = MCPTransport()

    /// One in-flight `tools/call`: how to cancel it, and how long it's still
    /// entitled to run — the same clamp `capture_region` waits against, so
    /// stdin closing doesn't cut a call off before its own stated deadline.
    private struct PendingCall {
        let cancel: () -> Void
        let deadline: Date
    }

    /// Keyed by request id, so a `notifications/cancelled` can find the right
    /// one. Locked because the read loop's thread and every call's own queue
    /// touch it.
    ///
    /// Each call runs on its own queue rather than the read loop's thread:
    /// `capture_region` blocks for up to an hour by request (`timeoutSeconds`
    /// caps at 3600), and a client is free to send `tools/list` — or cancel
    /// that very call — while it waits.
    private let inFlightLock = NSLock()
    private var inFlight: [JSONRPC.RequestID: PendingCall] = [:]

    /// Counts calls that have started but not yet sent their response.
    ///
    /// stdin closing (the client is done, or the pipe just broke) makes
    /// `readLoop` return — but a `tools/call` dispatched moments earlier is
    /// still running on its own queue, and `main.swift` exits the process the
    /// instant `run()` returns. Without this, a fast `get_last_capture` that
    /// hadn't quite finished writing its reply when EOF landed would simply
    /// never answer: the process would be gone before its `transport.send`
    /// ran. `run()` waits on this after the read loop ends so every call that
    /// was already running gets to finish — bounded by its own deadline, so a
    /// `capture_region` nobody is listening to anymore can't hold the process
    /// open for the full hour.
    private let inFlightGroup = DispatchGroup()

    func run() {
        transport.readLoop { [weak self] line in
            self?.handle(line)
        }

        let deadline: Date = {
            inFlightLock.lock()
            defer { inFlightLock.unlock() }
            return inFlight.values.map(\.deadline).max() ?? Date()
        }()
        let remainingMilliseconds = Int(max(0, deadline.timeIntervalSinceNow) * 1000)
        // Returns as soon as the count reaches zero, whichever comes first —
        // this is an upper bound, not a fixed wait.
        _ = inFlightGroup.wait(timeout: .now() + .milliseconds(remainingMilliseconds))
    }

    private func handle(_ line: String) {
        guard let message = JSONRPC.Message.parse(line) else {
            // Not a request we can address: either the JSON itself didn't
            // parse, or it parsed but named no id and no method we recognize
            // as a notification. Neither has an id to answer to, so — per
            // JSON-RPC — this is logged and dropped rather than met with a
            // response addressed to nobody.
            MCPTransport.log("dropped an unparsable line")
            return
        }

        switch message.method {
        case "initialize":
            respond(to: message, with: initializeResult(message.params))
        case "notifications/initialized":
            break // Acknowledges nothing; there is nothing to set up on our side.
        case "ping":
            respond(to: message, with: [:])
        case "tools/list":
            respond(to: message, with: ["tools": MCPTools.definitions])
        case "tools/call":
            handleToolCall(message)
        case "notifications/cancelled":
            cancel(requestID: message.params["requestId"])
        default:
            guard let id = message.id else { return } // Unknown notification: ignored, per spec.
            transport.send(JSONRPC.response(id: id, error: .methodNotFound,
                                            message: "Unknown method “\(message.method)”."))
        }
    }

    // MARK: - initialize

    private func initializeResult(_ params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String
        let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.supportedProtocolVersions[0]

        return [
            "protocolVersion": version,
            "capabilities": [
                // No `listChanged`: this server's three tools are fixed for
                // the life of the process, so there is never a list-changed
                // notification to send.
                "tools": [String: Any]()
            ],
            "serverInfo": [
                "name": "pinpoint",
                "title": "Pinpoint",
                "version": Usage.version
            ],
            "instructions": """
            Pinpoint annotates a region of this Mac's screen with numbered \
            markers and hands you the result as a file, never as inline image \
            bytes: every tool here returns an absolute PNG path plus structured \
            Markdown, and expects you to open the PNG with your own \
            file-reading tool. Call capture_region to ask for a new one (it \
            blocks until the user finishes drawing and pressing Copy — a real \
            person has to choose what's in frame), get_last_capture to reread \
            the most recent one without prompting for a new screenshot, and \
            list_recent to find an earlier one in the same session.
            """
        ]
    }

    // MARK: - tools/call

    private func handleToolCall(_ message: JSONRPC.Message) {
        guard let name = message.params["name"] as? String else {
            guard let id = message.id else { return }
            transport.send(JSONRPC.response(id: id, error: .invalidParams,
                                            message: "\"tools/call\" needs a \"name\"."))
            return
        }
        let arguments = message.params["arguments"] as? [String: Any] ?? [:]

        // A notification calling a tool is a client bug — there is no id to
        // answer on — but running the tool anyway would leave a capture
        // half-started with nobody watching for it. Refused instead.
        guard let id = message.id else {
            MCPTransport.log("ignored a tools/call notification for “\(name)” (no request id)")
            return
        }

        // The same clamp `capture_region` itself waits against — anything
        // else gets a short, fixed grace, since a `get_last_capture` or
        // `list_recent` that's still running has nothing left to wait on but
        // a couple of file reads.
        let deadline = Date().addingTimeInterval(
            name == "capture_region" ? MCPTools.clampedTimeout(arguments["timeoutSeconds"]) : 5)

        var cancelled = false
        let cancelLock = NSLock()
        inFlightLock.lock()
        inFlight[id] = PendingCall(cancel: {
            cancelLock.lock(); cancelled = true; cancelLock.unlock()
        }, deadline: deadline)
        inFlightLock.unlock()
        inFlightGroup.enter()

        // Off the read loop's thread: `capture_region` can run for up to an
        // hour, and nothing else queued behind it should have to wait that
        // long for a `tools/list` or a `ping`.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = MCPTools.call(name, arguments: arguments, isCancelled: {
                cancelLock.lock(); defer { cancelLock.unlock() }
                return cancelled
            })

            defer { self?.inFlightGroup.leave() }
            guard let self else { return }
            self.inFlightLock.lock()
            self.inFlight.removeValue(forKey: id)
            self.inFlightLock.unlock()

            self.transport.send(JSONRPC.response(id: id, result: [
                "content": [["type": "text", "text": outcome.text]],
                "isError": outcome.isError,
                // Only when there's something to structure: an error result
                // has nothing beyond the sentence a model already read in
                // `content`, and a key holding `nil` is a key a strict decoder
                // might choke rendering, not a fact worth stating twice.
                "structuredContent": outcome.structured as Any
            ].compactMapValues { value in
                if case Optional<Any>.none = value { return nil }
                return value
            }))
        }
    }

    private func cancel(requestID raw: Any?) {
        guard let id = JSONRPC.RequestID(raw) else { return }
        inFlightLock.lock()
        let pending = inFlight[id]
        inFlightLock.unlock()
        pending?.cancel()
    }

    private func respond(to message: JSONRPC.Message, with result: [String: Any]) {
        guard let id = message.id else { return } // A notification: no reply, ever.
        transport.send(JSONRPC.response(id: id, result: result))
    }
}
