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

        /// A numbered marker.
        ///
        /// Issue #55 will add an `accessibility` object here (the element under
        /// the marker, read from the accessibility tree at capture time). That's
        /// an addition, so `schemaVersion` stays at 1 — consumers must tolerate
        /// keys they don't know.
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
    init(pins: [Pin], shapes: [Markup], context: String, imageSize: CGSize, directory: URL) {
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

        self.markers = pins.sorted { $0.number < $1.number }.map { pin in
            Marker(
                id: pin.id.shortToken,
                label: "M\(pin.number)",
                number: pin.number,
                note: pin.note.trimmingCharacters(in: .whitespacesAndNewlines),
                position: Point(pin.position, in: imageSize)
            )
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
