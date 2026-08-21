import AppKit
import Foundation

/// Puts the bundled `pinpoint` CLI (#56) on a Terminal's `PATH` after a plain
/// DMG install (#89).
///
/// The Homebrew cask already does this with a `binary` stanza, but someone who
/// dragged Pinpoint.app out of a DMG has no such thing — the README used to
/// tell them to `ln -s` it into `/usr/local/bin` themselves, which fails for
/// most people (root-owned directory, often missing outright on a fresh Mac).
/// This is that same one `ln -s`, done for them, modelled on VS Code's
/// "Install 'code' command in PATH".
///
/// Three rules shape everything below:
/// - Never write into `/opt/homebrew/bin` — that is Homebrew's territory, read
///   only to notice it already did the job.
/// - Never touch a `pinpoint` we didn't create ourselves, even one that
///   happens to resolve to the exact same bundle (see `computeStatus`).
/// - Never claim success without actually running the installed command.
@MainActor
final class CLIInstaller: ObservableObject {
    static let shared = CLIInstaller()

    enum Status: Equatable {
        case checking
        case notInstalled
        /// A symlink Pinpoint created itself, still resolving to a real CLI.
        case installedByPinpoint
        /// Something already answers to `pinpoint` on the PATH that Pinpoint
        /// did not put there — Homebrew's cask, or a manual link from the old
        /// README. Left alone.
        case installedExternally
        /// Pinpoint's own link now points at a bundle that moved or was
        /// deleted. Offered the same "Install" action to re-point it.
        case brokenPinpointLink
        /// The last install/remove attempt failed; the message is already
        /// user-facing and localized.
        case failed(String)
    }

    /// Where Pinpoint installs its own link. Chosen over `/opt/homebrew/bin`
    /// because it needs no Homebrew installation to already exist, and it is
    /// the directory the old README instructions (and most "install a CLI
    /// tool by hand" advice) already point at.
    ///
    /// `nonisolated`: these are immutable constants read from the detached
    /// tasks below (privileged execution and verification must not block the
    /// main actor), not app state that needs actor protection.
    private nonisolated static let installDirectory = URL(fileURLWithPath: "/usr/local/bin")
    private nonisolated static let linkURL = installDirectory.appendingPathComponent("pinpoint")
    /// The other place a `pinpoint` might already live. Read-only: this is how
    /// an existing Homebrew install is recognized, never a second target to
    /// write to.
    private nonisolated static let homebrewCandidatePath = "/opt/homebrew/bin/pinpoint"

    private static let recordedLinkKey = "cliInstall.linkPath"

    @Published private(set) var status: Status = .checking
    @Published private(set) var isWorking = false

    private init() {
        refresh()
    }

    /// Re-reads the filesystem. Cheap local `stat` calls, so this is called
    /// every time the Settings section appears rather than cached — Homebrew
    /// or a Terminal session could have changed things since Pinpoint last
    /// looked.
    func refresh() {
        let recorded = UserDefaults.standard.string(forKey: Self.recordedLinkKey)
        status = Self.computeStatus(recordedLinkPath: recorded)
    }

    /// Creates (or repairs) the link, asking for administrator privileges
    /// exactly once for the whole operation, then proves it actually works
    /// before calling it installed.
    func install() async {
        isWorking = true
        defer { isWorking = false }

        let target = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/pinpoint")
        guard FileManager.default.fileExists(atPath: target.path) else {
            status = .failed(String(
                localized: "settings.cli.error.missingBinary",
                defaultValue: "The pinpoint tool couldn’t be found inside this app. Try reinstalling Pinpoint."
            ))
            return
        }

        // One privileged call for both steps (#89 pitfall 3): `/usr/local/bin`
        // may not exist yet, and a second dialog right after the first would
        // read as the app being confused rather than thorough.
        let shell = "mkdir -p \(Self.shellQuote(Self.installDirectory.path))"
            + " && ln -sf \(Self.shellQuote(target.path)) \(Self.shellQuote(Self.linkURL.path))"

        do {
            try await Self.runElevated(shell)
        } catch ElevationError.cancelled {
            // #89 pitfall 4: closing the auth dialog is a normal "never mind",
            // not a failure — back to whatever was true before, no alert.
            refresh()
            return
        } catch {
            status = .failed(String(
                localized: "settings.cli.error.install",
                defaultValue: "Couldn’t install the command line tool: \(error.localizedDescription)"
            ))
            return
        }

        UserDefaults.standard.set(Self.linkURL.path, forKey: Self.recordedLinkKey)

        // #89 pitfall 5: a symlink that exists is not the same claim as "the
        // command works". Run the thing a Terminal would run.
        guard await Self.verifyInstalledCLIResponds() else {
            try? FileManager.default.removeItem(at: Self.linkURL)
            UserDefaults.standard.removeObject(forKey: Self.recordedLinkKey)
            status = .failed(String(
                localized: "settings.cli.error.verify",
                defaultValue: "The link was created, but pinpoint --version didn’t respond. Nothing was left in place."
            ))
            return
        }

        refresh()
    }

    /// Removes Pinpoint's own link. Never reachable from the UI unless
    /// `status == .installedByPinpoint`, so there is nothing to re-check here
    /// (#89 pitfall 6) — the gate lives in `computeStatus`, once, not twice.
    func remove() async {
        isWorking = true
        defer { isWorking = false }

        let shell = "rm -f \(Self.shellQuote(Self.linkURL.path))"

        do {
            try await Self.runElevated(shell)
        } catch ElevationError.cancelled {
            refresh()
            return
        } catch {
            status = .failed(String(
                localized: "settings.cli.error.remove",
                defaultValue: "Couldn’t remove the command line tool: \(error.localizedDescription)"
            ))
            return
        }

        UserDefaults.standard.removeObject(forKey: Self.recordedLinkKey)
        refresh()
    }

    // MARK: - State

    private nonisolated static func computeStatus(recordedLinkPath: String?) -> Status {
        let fileManager = FileManager.default

        // Pinpoint's own record wins first. This is the only way to tell
        // "Pinpoint installed this" from "Homebrew installed this" apart when
        // both would resolve to the very same `/Applications/Pinpoint.app` —
        // the path alone can't disambiguate that (#89 pitfall 2).
        if let recordedLinkPath {
            if let resolved = resolvedTarget(ofSymlinkAt: recordedLinkPath) {
                return isValidCLIBinary(at: resolved) ? .installedByPinpoint : .brokenPinpointLink
            }
            // Recorded, but nothing is there anymore (removed outside
            // Pinpoint, e.g. `brew uninstall` clobbering the same path) — fall
            // through and look at the world fresh.
        }

        for path in [linkURL.path, homebrewCandidatePath] {
            guard let resolved = resolvedTarget(ofSymlinkAt: path), isValidCLIBinary(at: resolved) else { continue }
            return .installedExternally
        }

        return .notInstalled

        func resolvedTarget(ofSymlinkAt path: String) -> String? {
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: path) else { return nil }
            if destination.hasPrefix("/") { return destination }
            return (path as NSString).deletingLastPathComponent + "/" + destination
        }

        func isValidCLIBinary(at path: String) -> Bool {
            fileManager.fileExists(atPath: path) && path.contains(".app/Contents/Helpers/pinpoint")
        }
    }

    // MARK: - Privileged execution

    private enum ElevationError: Error {
        case cancelled
        case failed(String)
    }

    /// Runs `shellCommand` with `do shell script … with administrator
    /// privileges` — the standard macOS auth dialog, and the one route that
    /// works from a notarized, non-sandboxed app without a separate
    /// `SMJobBless` helper (overkill for a single symlink) or the long-
    /// deprecated `AuthorizationExecuteWithPrivileges`.
    ///
    /// Runs off the main actor: `NSAppleScript.executeAndReturnError` blocks
    /// for as long as the auth dialog is on screen, which must not freeze the
    /// Settings window's spinner.
    private nonisolated static func runElevated(_ shellCommand: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let source = "do shell script \"\(appleScriptQuote(shellCommand))\" with administrator privileges"
            guard let script = NSAppleScript(source: source) else {
                throw ElevationError.failed("Couldn’t build the privileged command.")
            }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            guard let errorInfo else { return }

            // -128 is AppleScript's "user cancelled" across every flavor of
            // `with administrator privileges` dialog, closed button or Esc alike.
            if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 {
                throw ElevationError.cancelled
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error."
            throw ElevationError.failed(message)
        }.value
    }

    /// Runs the link a Terminal would run and checks it actually answers —
    /// not just that a file with the right name exists at the right path.
    private nonisolated static func verifyInstalledCLIResponds() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = linkURL
            process.arguments = ["--version"]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return false
            }
            process.waitUntilExit()

            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return process.terminationStatus == 0 && output.lowercased().contains("pinpoint")
        }.value
    }

    /// Quotes `value` as a single-quoted shell literal — the standard POSIX
    /// trick of closing the quote, escaping a literal `'`, and reopening it —
    /// so a bundle path containing a space or an apostrophe (the app can run
    /// from anywhere, including a messily-named folder in ~/Downloads) can't
    /// break the command it's embedded in.
    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes an already shell-quoted command so it can sit inside the
    /// double-quoted AppleScript string literal `do shell script "…"` needs.
    private nonisolated static func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
