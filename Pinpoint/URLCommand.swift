import Foundation

/// A `pinpoint://` deep link, reduced to the single named action it is allowed
/// to ask for (#58).
///
/// The scheme exists because a second process holds none of this app's
/// permissions. The `pinpoint` CLI (#56) — and the MCP server after it (#57) —
/// cannot call ScreenCaptureKit themselves: TCC grants Screen Recording to a
/// signed bundle, not to a bare executable, so a helper that tried would only
/// ever produce its own permission prompt for a binary the user never
/// installed. It asks the app that already holds the grant instead.
///
/// Which also means anyone can send one. `open pinpoint://capture` works from a
/// terminal, from a shell script, and from a web page the user merely visited —
/// LaunchServices does not tell us which. The answer to that is this type:
///
/// * The URL selects between a handful of named actions and carries nothing
///   else. No coordinates, no destination path, no display id — nothing a
///   caller could use to aim the camera or to choose where bytes land.
/// * `capture` starts the same interactive region selection ⌘⇧1 does. A page
///   that fires it gets a dimming overlay the user has to drag on and an editor
///   window they have to press Copy in; it does not get a screenshot. There is
///   deliberately no URL that photographs the screen on its own — that is why
///   the full-screen capture in the menu has no deep link.
/// * Nothing ever answers back. The scheme is one-way, so a page that fires one
///   of these learns nothing about this Mac, not even whether Pinpoint is
///   installed.
///
/// Anything unrecognized parses to nil and is dropped in silence: an unknown
/// URL is either a typo or someone probing, and neither deserves a dialog.
enum URLCommand: Equatable {
    /// `pinpoint://capture` — start the interactive region selection.
    case capture
    /// `pinpoint://last` — reopen the last handoff in the annotation editor.
    case openLast
    /// `pinpoint://last?format=json|md|png` — reveal that file in the Finder.
    ///
    /// Reveal rather than open: the app that would handle a `.json` is the
    /// user's business, and showing the file in place also shows them the
    /// directory this whole contract lives in.
    case revealLast(HandoffFile)

    /// One file of the handoff triplet.
    enum HandoffFile: Equatable {
        case png, markdown, json

        var url: URL {
            switch self {
            case .png: return FileHandoff.latestPNG
            case .markdown: return FileHandoff.latestMarkdown
            case .json: return FileHandoff.latestJSON
            }
        }

        /// What `?format=` spells for this file.
        var formatToken: String {
            switch self {
            case .png: return "png"
            case .markdown: return "md"
            case .json: return "json"
            }
        }
    }

    static let scheme = "pinpoint"

    /// The canonical URL for this command.
    ///
    /// Here rather than spelled out in the CLI: the tool that fires these deep
    /// links and the handler that reads them are then the same piece of code,
    /// so a spelling can't drift on one side only. (`URLCommand.swift` is
    /// compiled into both binaries — see project.yml.)
    var url: URL {
        let string: String
        switch self {
        case .capture: string = "\(Self.scheme)://capture"
        case .openLast: string = "\(Self.scheme)://last"
        case .revealLast(let file): string = "\(Self.scheme)://last?format=\(file.formatToken)"
        }
        // Constants, all of them: the only way this fails is a typo above, and
        // the round trip through `init?` in the tests of the day would catch it.
        return URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    /// Parses a URL, or nil when it isn't one of ours.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        // `pinpoint://capture` puts the action in the host; `pinpoint:capture`,
        // which is what a terminal or a Markdown link often produces, puts it
        // in the path. Both are the same request, so both are read.
        let host = url.host.map { $0.lowercased() } ?? ""
        let action = host.isEmpty
            ? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            : host

        switch action {
        case "capture":
            self = .capture
        case "last":
            switch Self.value(of: "format", in: url)?.lowercased() {
            case nil, "", "editor":
                self = .openLast
            case "json":
                self = .revealLast(.json)
            case "md", "markdown":
                self = .revealLast(.markdown)
            case "png", "image":
                self = .revealLast(.png)
            default:
                // A format we don't write. Refused rather than fallen back to a
                // default: guessing what someone meant is how a narrow door
                // turns into a wide one.
                return nil
            }
        default:
            return nil
        }
    }

    private static func value(of name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .last { $0.name.lowercased() == name }?
            .value
    }
}
