import Foundation

/// What the *text* half of a copy carries (#52).
///
/// The image is always a PNG; the string next to it is a choice. Markdown reads
/// well in a chat window and is what a model does best with unprompted; JSON is
/// the same facts in the shape a script can index, for a flow that pipes the
/// clipboard into something rather than pasting it into a conversation.
///
/// Only ever affects the clipboard. `FileHandoff` writes both `capture.md` and
/// `capture.json` on every copy whatever this says, so choosing one here never
/// costs the other.
enum AgentTextFormat: String, CaseIterable, Identifiable {
    /// The agent-ready Markdown of `Exporter.buildText` — the default, and what
    /// every copy carried before this setting existed.
    case markdown
    /// The versioned `capture.json` contract, serialized to the clipboard.
    case json

    var id: String { rawValue }

    static let storageKey = "agentTextFormat"

    var label: String {
        switch self {
        case .markdown: return String(localized: "format.markdown.label", defaultValue: "Markdown")
        case .json: return String(localized: "format.json.label", defaultValue: "JSON")
        }
    }
}
