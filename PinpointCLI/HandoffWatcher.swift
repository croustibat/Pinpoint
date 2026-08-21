import Foundation

/// Waits for the app to write the next handoff.
///
/// Both halves of this tool need it: `pinpoint capture` (#56) fires the deep
/// link and blocks until the user presses Copy, and the MCP server's
/// `capture_region` (#57) does the same thing on behalf of an agent. Written
/// once, here, rather than twice — the tricky part isn't the loop, it's what
/// counts as "the next handoff" (see `Handoff.Fingerprint`) and getting that
/// answer to differ between the two would mean one of them returns the
/// *previous* capture.
///
/// Polling rather than a filesystem watcher: this process exists for a few
/// seconds to a couple of minutes, `last/` is swapped in one move so there is
/// no half-written state to catch, and a quarter-second granularity is well
/// under the time it takes a person to drag a rectangle. A watcher would be
/// more machinery for a race that cannot happen.
enum HandoffWatcher {
    /// The interval between two reads of `last/capture.json`.
    ///
    /// Also the granularity at which `isCancelled` is consulted, which is why
    /// it stays short: an agent that gave up shouldn't wait a second to be told
    /// we noticed.
    static let pollInterval: TimeInterval = 0.25

    enum Result {
        /// A handoff different from the one that was there when we started.
        case handoff(Handoff)
        /// The deadline passed: the region was never copied, or the user
        /// cancelled with Esc, which looks the same from out here.
        case timedOut
        /// `isCancelled` came back true. Only the MCP server passes one — a
        /// client can cancel a request mid-flight.
        case cancelled
    }

    /// Blocks until a new handoff lands, the deadline passes, or `isCancelled`
    /// returns true.
    ///
    /// - Parameters:
    ///   - before: what `last/` looked like *before* the capture was asked for.
    ///     Read by the caller ahead of firing the deep link — comparing against
    ///     a fingerprint taken afterwards would race with a fast user.
    ///   - isCancelled: consulted once per poll. Defaults to "never", which is
    ///     the CLI's case: there is nobody to cancel it but the terminal.
    static func wait(after before: Handoff.Fingerprint,
                     timeout: TimeInterval,
                     isCancelled: () -> Bool = { false }) -> Result {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isCancelled() { return .cancelled }
            Thread.sleep(forTimeInterval: pollInterval)
            // A read that fails here is transient by nature — the directory is
            // being replaced under us — so it doesn't end the wait.
            guard let handoff = try? Handoff.latest() else { continue }
            if handoff.fingerprint != before { return .handoff(handoff) }
        }
        return .timedOut
    }
}
