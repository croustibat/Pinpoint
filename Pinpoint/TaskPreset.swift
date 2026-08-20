import Foundation

/// The framing put in front of the user's own instructions when the capture is
/// handed to an agent (#53).
///
/// The Instructions field starts empty at every capture, so the same three
/// sentences of scaffolding got retyped over and over — "this is a bug, find the
/// cause first", "just review this, don't rewrite it". A preset writes that part,
/// and the field goes back to carrying only what is specific to *this* screenshot.
///
/// Persisted in UserDefaults via `@AppStorage(TaskPreset.storageKey)`, like
/// `PinStyle`: the choice is a working habit, not a property of one capture, and
/// a user who always debugs should find "Bug" already selected. The token in
/// `rawValue` is the stable one — it is what lands in the JSON, and what the CLI
/// (#56) and the MCP server (#57) will accept as `--task bug`.
enum TaskPreset: String, CaseIterable, Identifiable {
    /// No framing at all: the export is exactly what it was before presets
    /// existed. The default, so nothing changes for anyone who ignores this.
    case raw
    case bug
    case review
    case implement

    var id: String { rawValue }

    static let storageKey = "taskPreset"

    /// Name shown in the editor's picker.
    var label: String {
        switch self {
        case .raw: return String(localized: "task.raw.label", defaultValue: "Raw")
        case .bug: return String(localized: "task.bug.label", defaultValue: "Bug")
        case .review: return String(localized: "task.review.label", defaultValue: "Review")
        case .implement: return String(localized: "task.implement.label", defaultValue: "Implement")
        }
    }

    /// The paragraph written into the export above the user's instructions, or
    /// nil for `.raw`.
    ///
    /// Localized like the rest of the export: this is prose the user reads in
    /// the tooltip before choosing, and prose they will find again in
    /// `capture.md`. Each one says what to *do first* rather than describing a
    /// role — an agent given "you are a debugging expert" behaves no differently
    /// from one given nothing, whereas "find the cause before proposing a fix"
    /// changes the order it works in. They also all license an "I can't tell
    /// from this screenshot", which is the answer a capture most often deserves
    /// and the one a model is least likely to volunteer.
    var guidance: String? {
        switch self {
        case .raw:
            return nil
        case .bug:
            return String(
                localized: "task.bug.guidance",
                defaultValue: "The markers point at a defect. Find its cause before proposing anything: locate the code that produces what is marked, explain why it behaves this way, then propose the smallest change that addresses the cause rather than the symptom. If the capture isn’t enough to be sure, say what you would need to look at."
            )
        case .review:
            return String(
                localized: "task.review.guidance",
                defaultValue: "The markers point at things to assess, not to fix. Give a short verdict on each one — what works, what doesn’t, and what it would cost to change — and order your remarks by importance rather than by position on the image. Say plainly when something is fine as it is; only suggest a change where it is worth the effort."
            )
        case .implement:
            return String(
                localized: "task.implement.guidance",
                defaultValue: "The markers point at what has to be built or changed. Match what is already there: reuse the existing components, naming and spacing rather than introducing your own. Change only what is marked, and list at the end anything you had to assume because the capture didn’t say."
            )
        }
    }

    /// The heading the guidance sits under in the exported text, e.g. "Task — Bug".
    var heading: String {
        String(localized: "export.task.heading", defaultValue: "Task — \(label)")
    }
}
