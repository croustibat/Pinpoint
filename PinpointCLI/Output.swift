import Foundation

/// How the process ends. An agent reads this before it reads anything else, so
/// the distinctions it draws are the ones worth drawing: "nothing to report" is
/// not "something broke", and "you didn't finish the capture" is not "the app
/// isn't there".
enum ExitCode: Int32 {
    case ok = 0
    /// An operation failed: a file wouldn't read, a copy wouldn't write.
    case failure = 1
    /// The command line didn't parse.
    case usage = 2
    /// Nothing has been handed off yet. Not an error — a state.
    case noCapture = 3
    /// `capture` gave up waiting: the region was never copied, or the user
    /// cancelled with Esc, which looks the same from out here.
    case timedOut = 4
    /// No app is registered for `pinpoint://`.
    case appUnavailable = 5
}

/// A failure with a stable token for a program and a sentence for a human.
struct CLIError: Error {
    let exitCode: ExitCode
    /// Machine-readable, kebab-case, and part of the contract: switch on this
    /// rather than on `message`, which is prose and may be reworded.
    let token: String
    let message: String

    static func usage(_ message: String) -> CLIError {
        CLIError(exitCode: .usage, token: "usage", message: message)
    }
    static func failure(_ message: String) -> CLIError {
        CLIError(exitCode: .failure, token: "failed", message: message)
    }
    static var noCapture: CLIError {
        CLIError(exitCode: .noCapture, token: "no-capture",
                 message: "No capture has been handed off yet. Take one, press Copy in the editor, then try again.")
    }
    static var appUnavailable: CLIError {
        CLIError(exitCode: .appUnavailable, token: "app-unavailable",
                 message: "macOS knows no handler for pinpoint://. Install Pinpoint.app and launch it once.")
    }
    static func timedOut(_ seconds: TimeInterval) -> CLIError {
        CLIError(exitCode: .timedOut, token: "timed-out",
                 message: "No capture was copied within \(Int(seconds))s. The selection may have been cancelled.")
    }
}

/// The two streams, kept strictly apart.
///
/// The rule this enum exists to enforce: in `--format json`, stdout carries one
/// JSON document and nothing else. Every note, warning and error sentence goes
/// to stderr, so a caller can pipe stdout into a parser without filtering it
/// first — and still show a person what went wrong.
enum Out {
    static func stdout(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func stderr(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// Writes one JSON object to stdout, in the same dialect the app writes
    /// `capture.json` in: sorted keys, indented, slashes left alone.
    static func json(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            // Only reachable if a value isn't JSON-representable, which would be
            // a bug here rather than a state of the world. Say so on stderr and
            // leave stdout empty rather than printing half a document.
            stderr("Couldn’t encode the result as JSON.")
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    /// The failure envelope. Mirrors the success one: `ok` is always there and
    /// is always the first thing to read.
    static func jsonError(_ error: CLIError) {
        json([
            "ok": false,
            "error": [
                "code": error.token,
                "exitCode": Int(error.exitCode.rawValue),
                "message": error.message
            ]
        ])
    }
}
