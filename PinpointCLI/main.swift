import Foundation

// `pinpoint` — the scriptable entry point (#56).
//
// Two commands, split by what they need rather than by what they do:
//
//   pinpoint last      reads ~/Library/Application Support/Pinpoint/last/,
//                      needs nothing else — not the app, not a permission, not
//                      even a logged-in session.
//   pinpoint capture   needs the app, because the screenshot itself does. TCC
//                      grants Screen Recording to the bundle the user allowed
//                      by name; this executable isn't it, so it asks the app
//                      through `pinpoint://` (#58) and waits for the handoff.
//
// That split is the design, and it's why `last` is the one an agent will call
// most: the expensive, permissioned, human-in-the-loop half happens once, and
// everything downstream is a file read.

let arguments = Array(CommandLine.arguments.dropFirst())
let wantsJSON = Arguments.wantsJSON(arguments)

do {
    let parsed = try Arguments.parse(arguments)
    switch parsed.command {
    case .help:
        Out.stdout(Usage.text)
    case .version:
        Out.stdout("\(Usage.toolName) \(Usage.version)")
    case .last:
        try Commands.last(parsed)
    case .capture:
        try Commands.capture(parsed)
    }
    exit(ExitCode.ok.rawValue)
} catch let error as CLIError {
    // The sentence always goes to stderr, whatever the format: stdout belongs
    // to the result. In JSON mode it also goes to stdout as a document, so a
    // caller parsing stdout gets an answer rather than an empty pipe.
    Out.stderr(error.message)
    if wantsJSON {
        Out.jsonError(error)
    }
    exit(error.exitCode.rawValue)
} catch {
    Out.stderr(error.localizedDescription)
    if wantsJSON {
        Out.jsonError(.failure(error.localizedDescription))
    }
    exit(ExitCode.failure.rawValue)
}
