import CoreGraphics
import Foundation

// The JSON contract written to `capture.json`.
//
// Types only. How the fields are filled in from the annotation model lives in
// `HandoffDocumentBuilder.swift`, because this file is compiled into the
// `pinpoint` CLI too (#56) and a reader of the contract must not have to link
// against the editor to decode it.
//
// Spelled out here rather than encoding `Pin` and `Markup` straight to the
// wire, even though both are already `Codable`: this file is read by things
// that live outside the app — the CLI (#56), the MCP server (#57), whatever a
// user scripts on top of it — and it must not shift the day the internal model
// does. Renaming `Pin.note` should break a compile in here, not somebody's
// script.
//
// Everything is derived, nothing is a reference to a live object, and the
// coordinate convention matches `capture.md`: pixels from the top-left corner
// first, then the same point as a percentage of the image size.
extension FileHandoff {
    struct Document: Codable {
        let schemaVersion: Int
        let generator: Generator
        /// When this handoff was written (ISO 8601, with offset).
        let generatedAt: String
        /// When the screenshot itself was taken (ISO 8601), which can be days
        /// before `generatedAt` — a capture is reopened from the history and
        /// re-exported. Absent when nothing recorded it: the instant is read
        /// from the accessibility snapshot (#55), so a capture taken with that
        /// feature off carries no origin date. Same instant as
        /// `accessibility.capturedAt` when both are present.
        let capturedAt: String?
        /// The framing chosen in the editor (#53). Always present: `preset` is
        /// "raw" when the user asked for none, so a consumer never has to tell
        /// "no preset" from "key not written by this version".
        let task: TaskFraming
        let image: Image
        /// How the numbered markers are drawn on the image, so a consumer can
        /// describe or redraw them without looking at the pixels.
        let markerStyle: MarkerStyle
        /// What was in front of the lens: the app and window the capture was
        /// pointed at, and the piece of screen it covers. Absent without an
        /// accessibility snapshot, which is where every one of these facts comes
        /// from.
        let source: Source?
        /// Absolute path of the Markdown twin sitting next to this file — the
        /// same content in prose, for an agent that would rather read that.
        /// Absent when the JSON was exported on its own ("Export JSON…"), where
        /// there is no twin and no image to point at.
        let markdownPath: String?
        /// The user's instructions, verbatim. Empty string when they wrote none
        /// (the key is always present, so a consumer never has to branch on its
        /// absence).
        let context: String
        /// What the accessibility tree contributed, or absent when it
        /// contributed nothing (feature off, permission not granted, no element
        /// under any marker). Present with `available: false` only when a walk
        /// happened and came back thin, so a consumer can tell "not looked at"
        /// from "looked at, found nothing".
        let accessibility: AccessibilityContext?
        let markers: [Marker]
        let shapes: [Shape]

        struct Generator: Codable {
            let name: String
            let version: String
        }

        struct Image: Codable {
            /// Absolute path of the annotated PNG next to this file. Absent when
            /// the JSON was exported alone — see `markdownPath`.
            let path: String?
            /// Pixel dimensions of that PNG — the grid every `x`/`y` below is
            /// expressed in.
            ///
            /// Always the grid of the file this document describes, never the
            /// capture's own: the clipboard copy is downscaled to stay pasteable,
            /// and quoting the original dimensions there is exactly what sent
            /// agents 1.28× off the mark (#76).
            let width: Int
            let height: Int
            /// Image pixels per screen point — 2 on a Retina display. Lets a
            /// consumer go from a pixel here back to the point on screen it was
            /// read from, together with `source.screenRect`. Absent when the
            /// captured region isn't known (no accessibility snapshot).
            let scale: Double?
        }

        /// The task framing that was written into the export (#53).
        struct TaskFraming: Codable {
            /// The stable token — "raw", "bug", "review" or "implement". The
            /// only field here meant to be switched on; the two below are prose
            /// in the user's language.
            let preset: String
            /// The preset's name as the editor showed it.
            let label: String
            /// The paragraph that went into `capture.md` above the user's
            /// instructions, repeated verbatim so a consumer building its own
            /// prompt gets the same framing. Absent for the "raw" preset.
            let guidance: String?
        }

        /// How the numbered badges are drawn.
        struct MarkerStyle: Codable {
            /// "disc", "pointer" or "outline".
            let kind: String
            /// `#RRGGBB`, sRGB — the vermillon every marker and outline is drawn
            /// in. A constant today, stated rather than assumed so a consumer
            /// looking for the badges in the pixels knows what to look for.
            let color: String
        }

        /// The screen the capture was taken from.
        struct Source: Codable {
            /// The app owning the window under the middle of the capture.
            let application: String?
            let bundleIdentifier: String?
            /// That window's title, when it has one.
            let windowTitle: String?
            /// The region the image covers, in screen points. With `image.scale`
            /// this is what turns a pixel in the image back into a point the
            /// macOS APIs accept.
            let screenRect: ScreenRect
        }

        /// A rectangle in screen points, global top-left origin. Not
        /// percentages: it isn't relative to the image.
        struct ScreenRect: Codable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }

        /// A point in the image, given twice: pixels for an agent working on
        /// the file, percentages for one reasoning about a resized copy.
        struct Point: Codable {
            let x: Int
            let y: Int
            /// 0…100, two decimals.
            let xPercent: Double
            let yPercent: Double
        }

        /// Axis-aligned box, same dual units as `Point`.
        struct Box: Codable {
            let x: Int
            let y: Int
            let width: Int
            let height: Int
            let xPercent: Double
            let yPercent: Double
            let widthPercent: Double
            let heightPercent: Double
        }

        /// Snapshot-wide facts about the accessibility pass (#55). Lets a
        /// consumer reason about *why* a marker has no element attached.
        struct AccessibilityContext: Codable {
            /// Whether at least one element was collected.
            let available: Bool
            /// ISO 8601 instant the tree was read — the capture instant.
            let capturedAt: String
            /// How many elements the snapshot holds, across every app walked.
            let elementCount: Int
            /// `true` when the walk stopped on one of its own limits (time,
            /// node budget). A missing element may then mean "not looked at".
            let truncated: Bool
            /// What was deliberately left out, so nobody has to guess whether a
            /// missing `value` means "empty" or "withheld".
            let policy: Policy

            struct Policy: Codable {
                /// Always true. Password fields are never read, at any setting.
                let secureFieldValuesOmitted: Bool
                /// True unless the user opted in: the text typed in ordinary
                /// fields is withheld by default, because the accessibility
                /// tree hands over the whole field — including the part that was
                /// scrolled out of the picture.
                let textFieldValuesOmitted: Bool
            }
        }

        /// The interface element found under a marker.
        ///
        /// This is the point of the whole file: a marker is a pixel, and a pixel
        /// is not something you can go and edit. `role` + `identifier` + `path`
        /// are what turn it into a thing with a name in somebody's source code.
        struct AccessibilityElement: Codable {
            /// Raw accessibility role, e.g. "AXButton". Not translated into
            /// prose on purpose — it's the vocabulary every inspector shares.
            let role: String
            let subrole: String?
            /// `AXTitle` — the control's visible label.
            let title: String?
            /// `AXDescription` — what a screen reader announces.
            let label: String?
            /// `AXIdentifier`, usually the `accessibilityIdentifier` written in
            /// the app's own source. The most directly actionable field here.
            let identifier: String?
            /// `AXHelp`, only collected when nothing else named the element.
            let help: String?
            /// `AXPlaceholderValue`, for inputs.
            let placeholder: String?
            /// The element's value — present only when the privacy policy allows
            /// it (see `redacted`).
            let value: String?
            /// Why `value` is absent: "secureField" (never read),
            /// "textFieldPolicy" (withheld by default) or "userRedaction" (the
            /// user painted over this element, so its name — `title`, `label`,
            /// `identifier`, `help`, `placeholder` — was dropped along with its
            /// value). Absent when the element simply has no value worth
            /// reporting.
            let redacted: String?
            let enabled: Bool?
            /// The element's box in *this image's* pixel grid, the same one
            /// every other coordinate in this file uses. May fall outside the
            /// image when the element extends past the captured region.
            let box: Box
            /// The same box in screen points, global top-left origin — the
            /// space the macOS accessibility APIs speak, for a consumer that
            /// wants to go back and drive the live UI.
            let screenFrame: ScreenFrame
            let application: Application
            /// Containers around the element, outermost first, each rendered as
            /// `AXRole “Name”`.
            let path: [String]

            struct Application: Codable {
                let name: String?
                let bundleIdentifier: String?
                let processIdentifier: Int32
            }

            /// The same shape as `source.screenRect`, and the same space.
            typealias ScreenFrame = FileHandoff.Document.ScreenRect
        }

        /// A numbered marker.
        struct Marker: Codable {
            /// Stable identifier, the same code `capture.md` prints in brackets.
            /// Survives the renumbering that follows a deletion, so two handoffs
            /// of one session refer to the same marker by the same id.
            let id: String
            /// What is actually drawn on the image: "M1", "M2"… Unlike `id` it
            /// changes when earlier markers are deleted.
            let label: String
            let number: Int
            /// The user's description. Empty when they left it blank.
            let note: String
            let position: Point
            /// The interface element under `position`, resolved against the
            /// snapshot taken at capture time. Absent when there is none —
            /// which is the normal case for a capture of something that isn't
            /// an app window, or with the feature switched off — and always
            /// absent for a marker dropped on a redacted region, where naming
            /// what sits under the bar would undo the redaction in text.
            let accessibility: AccessibilityElement?
            /// The text Pinpoint read in the pixels under this marker (#49),
            /// recognized on the user's own Mac with no network call.
            ///
            /// A separate key from `note` rather than folded into it, even
            /// though `note` is often pre-filled from this very string: the two
            /// have different provenance — one is what a person wrote, the
            /// other what a machine read — and a consumer weighing them has to
            /// be able to tell which is which. `capture.md` drops the second
            /// copy when they match because it is prose; this file keeps both,
            /// because a missing key here would be ambiguous between "nothing
            /// was read" and "what was read matched the note".
            ///
            /// Absent when nothing legible sat within reach of the marker, when
            /// the accessibility element above already names the same thing,
            /// when the feature is switched off — and always for a marker on a
            /// redacted region or a read a bar touches.
            let recognizedText: String?
        }

        /// An unnumbered shape: arrow, rectangle or redaction.
        struct Shape: Codable {
            let id: String
            /// "S1", "S2"… matching `capture.md`.
            let label: String
            /// "arrow", "rectangle" or "redaction". Deliberately a plain string
            /// mapped by hand, so renaming the internal enum can't silently
            /// change the contract.
            ///
            /// A "redaction" is a region the user painted over before sharing:
            /// its pixels are gone from the PNG, and no accessibility element
            /// under it is described anywhere in this file. Its box is still
            /// given — where something was hidden is not itself a secret, and a
            /// consumer that knows a region is unreadable asks instead of
            /// guessing.
            let kind: String
            /// Arrow: the tail. Rectangle/redaction: its top-left corner.
            let from: Point
            /// Arrow: the tip, where the head is drawn. Rectangle/redaction:
            /// its bottom-right corner.
            let to: Point
            let boundingBox: Box
        }
    }
}
