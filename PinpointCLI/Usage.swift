import Foundation

/// What the CLI is and how it is spelled.
enum Usage {
    static let toolName = "pinpoint"

    /// Version stamped at build time. A command-line tool has no bundle, so the
    /// Info.plist is embedded as a section in the binary itself
    /// (`CREATE_INFOPLIST_SECTION_IN_BINARY` in project.yml); `Bundle.main`
    /// reads it back from there.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static let text = """
    \(toolName) \(version) — drive Pinpoint from a script, a hook or an agent.

    USAGE
      \(toolName) capture [--out <file.png>] [--json | --format <fmt>] [--timeout <seconds>] [--no-wait]
      \(toolName) last    [--out <file.png>] [--json | --format <fmt>]
      \(toolName) mcp
      \(toolName) --help | --version

    COMMANDS
      capture   Ask the running Pinpoint app to start a region capture, then wait
                until you copy from the editor and print the handoff it wrote.
                The region is always selected by hand: this tool holds none of
                the app's Screen Recording permission, and no deep link takes a
                picture on its own.
      last      Print the most recent handoff. Reads files only — it needs
                neither the app running nor any permission.
      mcp       Run as a stdio MCP server exposing capture_region,
                get_last_capture and list_recent to an agent (#57). Speaks
                JSON-RPC on stdin/stdout and nothing else — every human sentence
                goes to stderr instead, same rule as --json above but absolute
                here, because one stray line on stdout breaks the protocol. See
                the README for the exact `claude mcp add` invocation.

    OPTIONS
      --out <file>       Copy the annotated PNG to <file>.
      --json             Shorthand for --format json.
      --format <fmt>     json  the full capture.json contract, in an envelope
                         md    the contents of capture.md, verbatim
                         text  a short human summary (default)
      --timeout <sec>    How long `capture` waits for you to copy. Default 120.
      --no-wait          Fire the capture and return immediately.
      --region           Accepted and ignored: hand-picked region is the only
                         mode there is.
      -h, --help         This text.
      --version          Print the version and exit.

    OUTPUT
      With --format json, stdout carries exactly one JSON document and nothing
      else — including on failure, where it is {"ok":false,"error":{…}}. Human
      wording always goes to stderr.

    EXIT CODES
      0  done
      1  something failed (unreadable file, failed write)
      2  bad usage
      3  no capture available yet
      4  timed out waiting for the capture to be copied
      5  Pinpoint isn't installed, or macOS knows no handler for pinpoint://

    FILES
      \(FileHandoff.latestDirectory.path)/
        capture.png   the annotated image, native resolution
        capture.md    the agent-ready text
        capture.json  the same facts, machine-readable (schemaVersion \(FileHandoff.schemaVersion))
    """
}
