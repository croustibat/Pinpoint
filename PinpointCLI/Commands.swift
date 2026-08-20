import Foundation

enum Commands {
    // MARK: - last

    /// Prints the most recent handoff. Files only: no app, no permission, no
    /// window server — which is what makes it safe to call from a hook, a CI
    /// step or an agent loop.
    static func last(_ arguments: Arguments) throws {
        guard let handoff = try Handoff.latest() else { throw CLIError.noCapture }
        let saved = try copyPNG(to: arguments.out)
        try Report.emit(handoff, savedTo: saved, format: arguments.format)
    }

    // MARK: - capture

    /// Asks the app for a capture and waits for the result.
    ///
    /// "The result" is the handoff the editor writes when the user presses Copy
    /// — not the moment the pixels are read. That is the whole shape of this
    /// command: it starts something a person finishes, then notices they did.
    /// Nothing here can shorten that, and nothing here should: a capture the
    /// user never confirmed is one they never chose to share.
    static func capture(_ arguments: Arguments) throws {
        guard AppBridge.isAvailable else { throw CLIError.appUnavailable }

        // Read *before* firing: the comparison that follows is "is this a
        // different handoff from the one that was there when I asked".
        let before = Handoff.currentFingerprint()

        guard AppBridge.open(.capture) else {
            throw CLIError(exitCode: .appUnavailable, token: "app-unavailable",
                           message: "Couldn’t open \(URLCommand.capture.url.absoluteString).")
        }

        guard arguments.waits else {
            let started = "Capture started. Draw a region, then press Copy in the editor."
            switch arguments.format {
            case .json:
                Out.json(["ok": true, "pending": true,
                          "files": [
                            "png": FileHandoff.latestPNG.path,
                            "markdown": FileHandoff.latestMarkdown.path,
                            "json": FileHandoff.latestJSON.path
                          ]])
            case .text:
                Out.stdout(started)
            case .md:
                // There is no Markdown yet — that is the whole point of
                // --no-wait — and stdout in this format belongs to capture.md.
                Out.stderr(started)
            }
            return
        }

        // stderr, always: it is the only sign of life during a two-minute wait,
        // and stdout has to stay either a single JSON document or the file the
        // caller asked for.
        Out.stderr("Waiting for the capture to be copied (\(Int(arguments.timeout))s)…")

        guard let handoff = try waitForHandoff(after: before, timeout: arguments.timeout) else {
            throw CLIError.timedOut(arguments.timeout)
        }
        let saved = try copyPNG(to: arguments.out)
        try Report.emit(handoff, savedTo: saved, format: arguments.format)
    }

    /// Polls `last/capture.json` until it is a different document from `before`.
    ///
    /// Polling rather than a filesystem watcher: this process exists for a few
    /// seconds, the directory is swapped in one move (so there is no
    /// half-written state to catch), and a quarter-second granularity is well
    /// under the time it takes a person to drag a rectangle. A watcher would be
    /// more machinery for a race that cannot happen.
    private static func waitForHandoff(after before: Handoff.Fingerprint,
                                       timeout: TimeInterval) throws -> Handoff? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            // A read that fails here is transient by nature — the directory is
            // being replaced under us — so it doesn't end the wait.
            guard let handoff = try? Handoff.latest() else { continue }
            if handoff.fingerprint != before { return handoff }
        }
        return nil
    }

    // MARK: - Shared

    /// Copies the annotated PNG to `destination`, and returns where it landed.
    private static func copyPNG(to destination: URL?) throws -> URL? {
        guard let destination else { return nil }
        let fileManager = FileManager.default
        let source = FileHandoff.latestPNG
        guard fileManager.fileExists(atPath: source.path) else {
            throw CLIError.failure("\(source.path) doesn’t exist — the handoff has no image.")
        }

        // Checked here rather than left to `copyItem`, whose error names the
        // *source* file and reads like the handoff is missing when the real
        // answer is that the folder isn't there.
        let parent = destination.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue else {
            throw CLIError.failure("\(parent.path) isn’t a directory — nowhere to write \(destination.lastPathComponent).")
        }

        var destinationIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory) {
            // `--out ~/Pictures` must not delete ~/Pictures. The overwrite below
            // is recursive, so the one thing it may never be pointed at is a
            // directory.
            guard !destinationIsDirectory.boolValue else {
                throw CLIError.failure("\(destination.path) is a directory — pass the path of the file to write.")
            }
            // Replacing an existing file is expected: `--out ./bug.png` in a
            // loop is the normal way this gets used.
            do {
                try fileManager.removeItem(at: destination)
            } catch {
                throw CLIError.failure("Couldn’t replace \(destination.path): \(error.localizedDescription)")
            }
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw CLIError.failure("Couldn’t write \(destination.path): \(error.localizedDescription)")
        }
        return destination
    }
}
