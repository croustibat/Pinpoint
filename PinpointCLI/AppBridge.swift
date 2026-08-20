import AppKit
import Foundation

/// The half of the tool that needs the app.
///
/// `pinpoint last` reads files and never comes here. `pinpoint capture` has to:
/// TCC grants Screen Recording to a signed bundle the user allowed by name, and
/// this executable is not that bundle even when it is sitting inside it. Asking
/// ScreenCaptureKit from here would raise a second permission prompt, for a
/// binary nobody installed, and would still fail. So the capture is asked of
/// the app that already holds the grant, through `pinpoint://` (#58).
enum AppBridge {
    /// Whether macOS has an app registered for `pinpoint://`.
    ///
    /// Checked before firing rather than after waiting: `NSWorkspace.open`
    /// returns false for an unhandled scheme, but only after LaunchServices has
    /// had its say, and the caller deserves "Pinpoint isn't installed" rather
    /// than "timed out".
    static var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: URLCommand.capture.url) != nil
    }

    /// Fires a deep link. Launches the app if it isn't running.
    @discardableResult
    static func open(_ command: URLCommand) -> Bool {
        NSWorkspace.shared.open(command.url)
    }
}

/// A handoff as this tool sees it: the raw JSON exactly as the app wrote it,
/// plus the decoded document to reason about.
struct Handoff {
    /// The parsed contract — what the summary is built from.
    let document: FileHandoff.Document
    /// The same file as a plain JSON object, untouched.
    ///
    /// Passed through rather than re-encoded from `document`: a newer app can
    /// add keys to the contract without bumping `schemaVersion` (that is the
    /// rule the schema states), and re-serializing a decoded value would drop
    /// every key this build doesn't know about. An older CLI in front of a
    /// newer app must not quietly narrow what the app said.
    let raw: [String: Any]
    /// When `capture.json` was last written, used to tell one handoff from the
    /// next.
    let modified: Date?

    /// Reads the current handoff, or nil when none has been written.
    static func latest() throws -> Handoff? {
        let url = FileHandoff.latestJSON
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CLIError.failure("Couldn’t read \(url.path): \(error.localizedDescription)")
        }

        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let document = try? JSONDecoder().decode(FileHandoff.Document.self, from: data) else {
            throw CLIError(exitCode: .failure, token: "invalid-document",
                           message: "\(url.path) isn’t a handoff document this build can read.")
        }

        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        return Handoff(document: document, raw: raw, modified: modified)
    }

    /// What tells two handoffs apart.
    ///
    /// `last/` is replaced as a whole directory on every copy, so the file is a
    /// new one each time and its modification date moves; `generatedAt` is
    /// there as well because it is what the document itself claims, and a
    /// filesystem with coarse timestamps would otherwise hide two copies made
    /// in the same instant.
    struct Fingerprint: Equatable {
        let generatedAt: String?
        let modified: Date?
    }

    var fingerprint: Fingerprint {
        Fingerprint(generatedAt: document.generatedAt, modified: modified)
    }

    static func currentFingerprint() -> Fingerprint {
        // Deliberately forgiving: a document that can't be read right now is
        // reported as "nothing there", because this is only ever used as a
        // before/after comparison and an unreadable before is not a reason to
        // refuse to capture.
        // `try?` flattens the optional, so this covers both "no handoff yet"
        // and "unreadable right now" in one guard.
        guard let handoff = try? latest() else {
            return Fingerprint(generatedAt: nil, modified: nil)
        }
        return handoff.fingerprint
    }
}
