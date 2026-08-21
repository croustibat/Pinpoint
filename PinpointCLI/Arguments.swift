import Foundation

/// The parsed command line.
///
/// Hand-rolled rather than pulled from swift-argument-parser: this tool ships
/// inside the app bundle and is signed and notarized with it, so every
/// dependency added here is one more thing to sign, one more thing to audit,
/// and one more reason the app itself fails to build. The grammar is five
/// options wide.
struct Arguments {
    enum Command {
        case capture
        case last
        case mcp
        case help
        case version
    }

    /// How the result is printed.
    enum Format: String {
        /// The `capture.json` contract, wrapped in an envelope.
        case json
        /// The contents of `capture.md`, byte for byte.
        case md
        /// A few lines for a person.
        case text
    }

    var command: Command = .help
    var format: Format = .text
    /// Where to copy the annotated PNG, if anywhere.
    var out: URL?
    var timeout: TimeInterval = 120
    /// Whether `capture` waits for the handoff or just fires the deep link.
    var waits = true

    /// Whether the caller asked for JSON *anywhere* on the command line.
    ///
    /// Read before parsing so that a command line which fails to parse still
    /// fails in JSON when JSON was asked for. A caller that pipes stdout into a
    /// parser gets a document either way; nothing is worse than an error format
    /// that depends on how early the error was.
    static func wantsJSON(_ arguments: [String]) -> Bool {
        if arguments.contains("--json") { return true }
        for (index, argument) in arguments.enumerated() where argument == "--format" {
            if arguments.indices.contains(index + 1), arguments[index + 1] == "json" { return true }
        }
        return false
    }

    static func parse(_ arguments: [String]) throws -> Arguments {
        var result = Arguments()
        var iterator = arguments.makeIterator()
        var positional: String?

        func nextValue(for option: String) throws -> String {
            guard let value = iterator.next(), !value.hasPrefix("--") else {
                throw CLIError.usage("\(option) needs a value.")
            }
            return value
        }

        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help":
                return Arguments(command: .help)
            case "--version":
                return Arguments(command: .version)
            case "--json":
                result.format = .json
            case "--format":
                let raw = try nextValue(for: "--format")
                guard let format = Format(rawValue: raw) else {
                    throw CLIError.usage("Unknown format “\(raw)”. Use json, md or text.")
                }
                result.format = format
            case "--out":
                // Resolved against the working directory here rather than at
                // use: the message about a bad path should name the path the
                // user typed, and by the time we write we are several steps
                // from them.
                result.out = URL(fileURLWithPath: try nextValue(for: "--out")).standardizedFileURL
            case "--timeout":
                let raw = try nextValue(for: "--timeout")
                guard let seconds = TimeInterval(raw), seconds > 0, seconds <= 3600 else {
                    throw CLIError.usage("--timeout takes a number of seconds between 1 and 3600.")
                }
                result.timeout = seconds
            case "--no-wait":
                result.waits = false
            case "--region":
                // Named in the issue that asked for this tool, and accepted so
                // the documented spelling works — but there is nothing to
                // switch on: a hand-picked region is the only capture a deep
                // link can start. See URLCommand.
                break
            default:
                guard !argument.hasPrefix("-") else {
                    throw CLIError.usage("Unknown option “\(argument)”.")
                }
                guard positional == nil else {
                    throw CLIError.usage("Unexpected argument “\(argument)”.")
                }
                positional = argument
            }
        }

        switch positional {
        case "capture": result.command = .capture
        case "last": result.command = .last
        case "mcp": result.command = .mcp
        case nil: result.command = .help
        case let other?: throw CLIError.usage("Unknown command “\(other)”.")
        }
        return result
    }

    private init(command: Command) {
        self.command = command
    }

    private init() {}
}
