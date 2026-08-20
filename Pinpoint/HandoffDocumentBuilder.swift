import AppKit
import CoreGraphics
import Foundation

// How a handoff document is filled in from the live annotation model.
//
// Split from `HandoffDocument.swift` — the contract itself — because the
// `pinpoint` CLI (#56) compiles that file to read `capture.json` and has no
// business linking `Pin`, `Markup`, `AXSnapshot` or the editor's redaction
// mask. Everything below turns one of those into plain numbers and strings;
// nothing below is needed to read the result back.

extension FileHandoff.Document {
    /// Builds the document for a set of annotations.
    ///
    /// `directory` is where the triplet will live, since the absolute paths
    /// below point at its siblings; nil when the JSON is exported on its own and
    /// there is nothing to point at.
    ///
    /// `imageSize` must be the pixel grid of the image this document describes —
    /// not the capture's own dimensions, which stopped being the same thing the
    /// moment the clipboard copy started downscaling (#76).
    init(pins: [Pin], shapes: [Markup], context: String, imageSize: CGSize, directory: URL?,
         style: PinStyle, preset: TaskPreset, accessibility: AXSnapshot? = nil) {
        self.schemaVersion = FileHandoff.schemaVersion
        self.generator = Generator(
            name: "Pinpoint",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.generatedAt = formatter.string(from: Date())
        self.capturedAt = accessibility.map { formatter.string(from: $0.capturedAt) }
        self.task = TaskFraming(preset: preset.rawValue, label: preset.label, guidance: preset.guidance)
        self.image = Image(
            path: directory?.appendingPathComponent(FileHandoff.pngFileName).path,
            width: Int(imageSize.width.rounded()),
            height: Int(imageSize.height.rounded()),
            scale: accessibility.flatMap { $0.pixelsPerPoint(for: imageSize) }
        )
        self.markerStyle = MarkerStyle(kind: style.rawValue, color: FileHandoff.markerColorHex)
        self.source = accessibility.map { snapshot in
            let window = snapshot.sourceWindow
            return Source(
                application: window?.application.name,
                bundleIdentifier: window?.application.bundleIdentifier,
                windowTitle: window?.title,
                screenRect: ScreenRect(snapshot.captureRect)
            )
        }
        self.markdownPath = directory?.appendingPathComponent(FileHandoff.markdownFileName).path
        self.context = context.trimmingCharacters(in: .whitespacesAndNewlines)

        let ordered = pins.sorted { $0.number < $1.number }
        // The regions the user painted over (#50). This file is the one that
        // makes a redaction worth anything or worth nothing: the PNG next to it
        // is already clean, and without the mask the accessibility block below
        // would hand over the label — and the typed value — of whatever sits
        // under the bar, in plain text, keys sorted, ready to grep.
        let mask = RedactionMask(shapes)
        if let snapshot = accessibility {
            self.markers = ordered.map { pin in
                Marker(pin, in: imageSize, hiddenBy: mask,
                       accessibility: snapshot.element(atNormalized: pin.position, hiddenBy: mask)
                    .map { AccessibilityElement($0, in: snapshot, imageSize: imageSize) })
            }
            self.accessibility = AccessibilityContext(snapshot, formatter: formatter)
        } else {
            self.markers = ordered.map { Marker($0, in: imageSize, hiddenBy: mask, accessibility: nil) }
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
            case .redaction:
                kind = "redaction"
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

extension FileHandoff.Document.Marker {
    /// `mask` is asked about the marker's read rather than about the marker
    /// alone: the redaction has to reach the text Pinpoint recognized the same
    /// way it already reaches the accessibility element, and this is the last
    /// point before it is encoded.
    init(_ pin: Pin, in size: CGSize, hiddenBy mask: RedactionMask,
         accessibility: FileHandoff.Document.AccessibilityElement?) {
        self.init(
            id: pin.id.shortToken,
            label: "M\(pin.number)",
            number: pin.number,
            note: pin.note.trimmingCharacters(in: .whitespacesAndNewlines),
            position: FileHandoff.Document.Point(pin.position, in: size),
            accessibility: accessibility,
            recognizedText: pin.recognizedText(hiddenBy: mask)?.text
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
            screenFrame: ScreenFrame(element.frame),
            application: Application(
                name: resolved.application.name,
                bundleIdentifier: resolved.application.bundleIdentifier,
                processIdentifier: resolved.application.processIdentifier
            ),
            path: (resolved.ancestors.map(\.summary) + [element.summary])
        )
    }
}

extension FileHandoff.Document.ScreenRect {
    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY),
                  width: Double(rect.width), height: Double(rect.height))
    }
}

extension AXSnapshot {
    /// The window the capture was aimed at: whatever sits under the middle of
    /// the image, walked back up to its outermost container.
    ///
    /// The centre rather than a scan of every window, and `element(atNormalized:)`
    /// rather than a second selection rule: that method already knows how to pick
    /// between overlapping windows (frontmost first), and the middle of a region
    /// the user dragged themselves is the least ambiguous statement of what they
    /// meant to photograph. Nothing there — a capture of the desktop, of a menu
    /// that left no accessible window — simply yields nil.
    var sourceWindow: (application: Application, title: String?)? {
        guard let resolved = element(atNormalized: CGPoint(x: 0.5, y: 0.5)) else { return nil }
        let window = resolved.ancestors.first ?? resolved.element
        return (resolved.application, window.title ?? window.name)
    }

    /// How many pixels of an image of `imageSize` cover one screen point — 2 for
    /// a Retina capture, less once the clipboard copy has been downscaled. Nil
    /// when the captured region is degenerate, which would make the ratio
    /// meaningless rather than merely unknown.
    func pixelsPerPoint(for imageSize: CGSize) -> Double? {
        guard captureRect.width > 0 else { return nil }
        return ((Double(imageSize.width) / Double(captureRect.width)) * 1000).rounded() / 1000
    }
}
