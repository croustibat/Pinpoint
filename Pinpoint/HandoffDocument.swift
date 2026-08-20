import CoreGraphics
import Foundation

// The JSON contract written to `capture.json`.
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
    struct Document: Encodable {
        let schemaVersion: Int
        let generator: Generator
        /// When this handoff was written (ISO 8601, with offset).
        let generatedAt: String
        let image: Image
        /// Absolute path of the Markdown twin sitting next to this file — the
        /// same content in prose, for an agent that would rather read that.
        let markdownPath: String
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

        struct Generator: Encodable {
            let name: String
            let version: String
        }

        struct Image: Encodable {
            /// Absolute path of the annotated PNG next to this file.
            let path: String
            /// Pixel dimensions of that PNG — the grid every `x`/`y` below is
            /// expressed in.
            let width: Int
            let height: Int
        }

        /// A point in the image, given twice: pixels for an agent working on
        /// the file, percentages for one reasoning about a resized copy.
        struct Point: Encodable {
            let x: Int
            let y: Int
            /// 0…100, two decimals.
            let xPercent: Double
            let yPercent: Double
        }

        /// Axis-aligned box, same dual units as `Point`.
        struct Box: Encodable {
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
        struct AccessibilityContext: Encodable {
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

            struct Policy: Encodable {
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
        struct AccessibilityElement: Encodable {
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
            /// Why `value` is absent: "secureField" (never read) or
            /// "textFieldPolicy" (withheld by default). Absent when the element
            /// simply has no value worth reporting.
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

            struct Application: Encodable {
                let name: String?
                let bundleIdentifier: String?
                let processIdentifier: Int32
            }

            /// Points, global top-left origin. Not percentages: this rect isn't
            /// relative to the image.
            struct ScreenFrame: Encodable {
                let x: Double
                let y: Double
                let width: Double
                let height: Double
            }
        }

        /// A numbered marker.
        struct Marker: Encodable {
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
            /// an app window, or with the feature switched off.
            let accessibility: AccessibilityElement?
        }

        /// An unnumbered outline: arrow or rectangle.
        struct Shape: Encodable {
            let id: String
            /// "S1", "S2"… matching `capture.md`.
            let label: String
            /// "arrow" or "rectangle". Deliberately a plain string mapped by
            /// hand, so renaming the internal enum can't silently change the
            /// contract.
            let kind: String
            /// Arrow: the tail. Rectangle: its top-left corner.
            let from: Point
            /// Arrow: the tip, where the head is drawn. Rectangle: its
            /// bottom-right corner.
            let to: Point
            let boundingBox: Box
        }
    }
}

extension FileHandoff.Document {
    /// Builds the document for a set of annotations. `directory` is where the
    /// triplet will live, since the absolute paths below point at its siblings.
    init(pins: [Pin], shapes: [Markup], context: String, imageSize: CGSize, directory: URL,
         accessibility: AXSnapshot? = nil) {
        self.schemaVersion = FileHandoff.schemaVersion
        self.generator = Generator(
            name: "Pinpoint",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.generatedAt = formatter.string(from: Date())
        self.image = Image(
            path: directory.appendingPathComponent(FileHandoff.pngFileName).path,
            width: Int(imageSize.width.rounded()),
            height: Int(imageSize.height.rounded())
        )
        self.markdownPath = directory.appendingPathComponent(FileHandoff.markdownFileName).path
        self.context = context.trimmingCharacters(in: .whitespacesAndNewlines)

        let ordered = pins.sorted { $0.number < $1.number }
        if let snapshot = accessibility {
            self.markers = ordered.map { pin in
                Marker(pin, in: imageSize, accessibility: snapshot.element(atNormalized: pin.position)
                    .map { AccessibilityElement($0, in: snapshot, imageSize: imageSize) })
            }
            self.accessibility = AccessibilityContext(snapshot, formatter: formatter)
        } else {
            self.markers = ordered.map { Marker($0, in: imageSize, accessibility: nil) }
            self.accessibility = nil
        }

        self.shapes = shapes.enumerated().map { index, shape in
            let kind: String
            let from: CGPoint
            let to: CGPoint
            switch shape.kind {
            case .arrow:
                kind = "arrow"
                from = shape.start
                to = shape.end
            case .rectangle:
                kind = "rectangle"
                from = CGPoint(x: shape.rect.minX, y: shape.rect.minY)
                to = CGPoint(x: shape.rect.maxX, y: shape.rect.maxY)
            }
            return Shape(
                id: shape.id.shortToken,
                label: "S\(index + 1)",
                kind: kind,
                from: Point(from, in: imageSize),
                to: Point(to, in: imageSize),
                boundingBox: Box(shape.rect, in: imageSize)
            )
        }
    }
}

extension FileHandoff.Document.Point {
    init(_ point: CGPoint, in size: CGSize) {
        self.init(
            x: Int((point.x * size.width).rounded()),
            y: Int((point.y * size.height).rounded()),
            xPercent: FileHandoff.percent(point.x),
            yPercent: FileHandoff.percent(point.y)
        )
    }
}

extension FileHandoff.Document.Box {
    init(_ rect: CGRect, in size: CGSize) {
        self.init(
            x: Int((rect.minX * size.width).rounded()),
            y: Int((rect.minY * size.height).rounded()),
            width: Int((rect.width * size.width).rounded()),
            height: Int((rect.height * size.height).rounded()),
            xPercent: FileHandoff.percent(rect.minX),
            yPercent: FileHandoff.percent(rect.minY),
            widthPercent: FileHandoff.percent(rect.width),
            heightPercent: FileHandoff.percent(rect.height)
        )
    }
}

extension FileHandoff {
    /// A normalized 0…1 coordinate as a percentage with two decimals. Finer
    /// than the whole percents `capture.md` prints — the text is for reading,
    /// this is for computing against.
    static func percent(_ value: CGFloat) -> Double {
        (Double(value) * 10_000).rounded() / 100
    }
}

extension FileHandoff.Document.Marker {
    init(_ pin: Pin, in size: CGSize,
         accessibility: FileHandoff.Document.AccessibilityElement?) {
        self.init(
            id: pin.id.shortToken,
            label: "M\(pin.number)",
            number: pin.number,
            note: pin.note.trimmingCharacters(in: .whitespacesAndNewlines),
            position: FileHandoff.Document.Point(pin.position, in: size),
            accessibility: accessibility
        )
    }
}

extension FileHandoff.Document.AccessibilityContext {
    init(_ snapshot: AXSnapshot, formatter: ISO8601DateFormatter) {
        self.init(
            available: !snapshot.elements.isEmpty,
            capturedAt: formatter.string(from: snapshot.capturedAt),
            elementCount: snapshot.elements.count,
            truncated: snapshot.truncated,
            policy: Policy(
                // Not a setting: no code path reads the value of a secure field,
                // so this is a statement of fact rather than a configuration.
                secureFieldValuesOmitted: true,
                textFieldValuesOmitted: !snapshot.includesFieldValues
            )
        )
    }
}

extension FileHandoff.Document.AccessibilityElement {
    /// Restates one resolved element in the handoff's own terms: screen points
    /// become image pixels, the ancestor chain becomes a list of strings, and
    /// the redaction reason becomes a plain token a script can switch on.
    init(_ resolved: AXSnapshot.Resolved, in snapshot: AXSnapshot, imageSize: CGSize) {
        let element = resolved.element
        self.init(
            role: element.role,
            subrole: element.subrole,
            title: element.title,
            label: element.label,
            identifier: element.identifier,
            help: element.help,
            placeholder: element.placeholder,
            value: element.value,
            redacted: element.redaction?.rawValue,
            enabled: element.enabled,
            box: FileHandoff.Document.Box(snapshot.normalizedRect(for: element.frame), in: imageSize),
            screenFrame: ScreenFrame(
                x: Double(element.frame.minX),
                y: Double(element.frame.minY),
                width: Double(element.frame.width),
                height: Double(element.frame.height)
            ),
            application: Application(
                name: resolved.application.name,
                bundleIdentifier: resolved.application.bundleIdentifier,
                processIdentifier: resolved.application.processIdentifier
            ),
            path: (resolved.ancestors.map(\.summary) + [element.summary])
        )
    }
}
