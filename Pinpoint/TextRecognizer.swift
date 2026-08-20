import CoreGraphics
import Foundation
import Vision

/// A line of text Pinpoint read in a capture, and where it sits (#49).
///
/// The point of the feature in one sentence: an agent handed a screenshot has
/// to guess at the small text in it — a module name, a stack frame, a hex code
/// — and it guesses badly. macOS can read those pixels on this machine, so the
/// string itself travels in `capture.md` and `capture.json` next to the picture
/// instead of only being *in* the picture.
///
/// `box` is normalized (0…1) in image space, top-left origin: the convention
/// `Pin`, `Markup` and `RedactionMask` already speak, so the mask can be asked
/// about a read without converting anything — which is what makes the
/// redaction check at the export boundary a one-liner.
struct RecognizedText: Equatable, Codable, Sendable {
    /// What was read. Trimmed, whitespace-collapsed, never empty.
    var text: String
    /// Where it was read, normalized in image space, top-left origin.
    var box: CGRect
}

/// Everything one recognition pass over a capture found, and the only question
/// the editor asks of it: "what is this marker pointing at?".
///
/// A pass covers the whole image rather than a crop around each marker, and
/// that is deliberate. Vision recognizes *lines*, using the layout of the page
/// around them; a window cut around a marker slices words in half and hands the
/// recognizer a fragment to guess at, which is exactly the failure this feature
/// exists to fix. One pass also costs one pass, however many markers get
/// dropped afterwards — and markers are dropped one at a time, interactively,
/// where a per-marker request would be felt.
///
/// So the window is applied to the *results* instead: `text(near:)` picks the
/// line closest to the marker and refuses anything further off than a badge and
/// a half. Whole lines in, whole lines out, nothing cut.
struct TextRecognition: Equatable, Sendable {
    /// The legible lines of the capture, already filtered against the mask the
    /// pass ran under. Empty when nothing was readable — a photo, a video
    /// still, a chart — which is a perfectly ordinary outcome.
    var lines: [RecognizedText]

    static let empty = TextRecognition(lines: [])
}

extension TextRecognition {

    /// The line of text a marker at `point` is pointing at, or nil when there
    /// is nothing legible within reach.
    ///
    /// `mask` is applied again here, on top of the painting the pass already
    /// did (see `TextRecognizer.redacted`): the pass ran under the redactions
    /// as they stood *then*, and the user can paint a new bar at any moment
    /// while its result is still cached. Re-asking is pure geometry and makes
    /// the answer follow the current mask without waiting for a new pass.
    func text(near point: CGPoint, imageSize: CGSize, hiddenBy mask: RedactionMask) -> RecognizedText? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        // A marker dropped on a redacted region reads nothing at all — the same
        // blunt rule `AXSnapshot.element(atNormalized:hiddenBy:)` applies, for
        // the same reason: the user pointed at something they had just decided
        // to hide, and the honest answer is silence.
        guard !mask.hides(point) else { return nil }

        let reach = Self.reach(for: imageSize)
        let anchor = CGPoint(x: point.x * imageSize.width, y: point.y * imageSize.height)

        var best: (line: RecognizedText, distance: CGFloat, area: CGFloat)?
        for line in lines where !mask.hides(line.box) {
            let box = CGRect(x: line.box.minX * imageSize.width,
                             y: line.box.minY * imageSize.height,
                             width: line.box.width * imageSize.width,
                             height: line.box.height * imageSize.height)
            let distance = Self.distance(from: anchor, to: box)
            guard distance <= reach else { continue }
            let area = box.width * box.height
            // Nearest wins; the smaller box breaks a tie, since a marker inside
            // two nested reads is pointing at the more specific one.
            if let current = best, (current.distance, current.area) <= (distance, area) { continue }
            best = (line, distance, area)
        }
        return best?.line
    }

    /// How far from a marker a line of text may sit and still count as what
    /// that marker points at, in image pixels.
    ///
    /// Expressed as the marker badge's own radius (#48) rather than as a fresh
    /// constant, for two reasons. The badge is the thing the user aimed with,
    /// so it is the honest unit for "close enough". And the metric already
    /// scales with the capture — `max(16, width × 0.014)` — so a Retina
    /// screenshot, stored at twice the pixels the 1× one would have, gets twice
    /// the reach and therefore the *same* physical window on screen. Nothing
    /// else in this file needs to know about backing scales.
    ///
    /// Half again as much as the badge covers the ordinary miss of clicking
    /// just under a line of text; much more than that starts pulling in the
    /// sentence above and the one below, which is the failure mode on the other
    /// side — a marker quoting text it was never pointing at.
    static func reach(for imageSize: CGSize) -> CGFloat {
        MarkupMetrics(imageWidth: imageSize.width).pinRadius * 1.5
    }

    /// Euclidean distance from a point to the nearest edge of a rect; zero for
    /// a point inside it, which is how "the marker is on the text" wins.
    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

// MARK: - Recognition

/// Reads the text of a capture with Vision, on this Mac and without a network
/// call of any kind (#49).
enum TextRecognizer {

    /// Longest read kept whole. Past it the line is cut rather than dropped:
    /// the first 200 characters of an error message are still the error
    /// message, while a whole paragraph under one marker is not context.
    static let maximumLength = 200

    /// Reads below this are discarded. `.accurate` reports comfortably above it
    /// for text it actually resolved, so the floor mostly catches what it
    /// hallucinated out of icons, gradients and window chrome — the "noise"
    /// half of "don't put a note there unless there is something to say".
    private static let minimumConfidence: Float = 0.4

    /// Every legible line of `image`, with the regions `mask` covers taken out.
    ///
    /// Fails closed in every branch: an unreadable image, a recognizer error,
    /// a redaction that could not be painted — all of them return no lines
    /// rather than lines from an image that might not have been redacted.
    static func recognize(in image: CGImage, hiddenBy mask: RedactionMask) async -> TextRecognition {
        guard let input = redacted(image, by: mask) else { return .empty }

        var request = RecognizeTextRequest()
        // `.accurate` and not `.fast`. The strings this feature exists for are
        // small, dense and unforgiving — a module path, a hex address, a class
        // name — and `.fast` mangles exactly those: on five such lines of 13 pt
        // Menlo it returned none of them character-perfect at either 1× or 2×,
        // reading `react-dom/client` as `react-doTh/client` and breaking words
        // in two, where `.accurate` got 4 of 5 exact at 2×. A read that is
        // *nearly* right is worse than no read at all here, because nothing
        // downstream can tell the difference.
        //
        // It is 10 to 20 times slower — measured on an M-series Mac, roughly
        // 0.65 s for a 3024×1964 full-screen capture and 0.81 s for a
        // 5120×2880 one, against 0.04 s and 0.06 s — and that is affordable
        // precisely because it is one pass per capture, off the main actor,
        // running while the user is still deciding where to click.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        guard let observations = try? await request.perform(on: input) else { return .empty }

        let size = CGSize(width: input.width, height: input.height)
        let lines = observations
            .compactMap { line(from: $0, in: size) }
            // Second lock. The bars are already painted, so nothing here should
            // touch one; a glyph straddling the edge of a bar can still leave a
            // legible half, and half of a secret is a secret.
            .filter { !mask.hides($0.box) }
        return TextRecognition(lines: lines)
    }

    /// English and French — the two the app speaks — with the user's own first.
    /// Vision weighs the order, and a French interface is far likelier to be
    /// what is on screen when Pinpoint itself is running in French.
    private static var languages: [Locale.Language] {
        let french = Locale.Language(identifier: "fr-FR")
        let english = Locale.Language(identifier: "en-US")
        return Locale.current.language.languageCode?.identifier == "fr"
            ? [french, english]
            : [english, french]
    }

    /// One observation as a `RecognizedText`, or nil when it isn't worth
    /// putting under a marker.
    private static func line(from observation: RecognizedTextObservation,
                             in size: CGSize) -> RecognizedText? {
        guard size.width > 0, size.height > 0,
              let candidate = observation.topCandidates(1).first,
              candidate.confidence >= minimumConfidence,
              let text = cleaned(candidate.string) else { return nil }

        // Vision answers in its own normalized space, bottom-left origin;
        // `.upperLeft` flips it into the image's pixel grid, which the divide
        // then puts back into the 0…1 top-left space the rest of the app uses.
        // Both steps are resolution-independent, which is what makes a 1× and a
        // 2× capture of the same window produce the same box.
        let pixels = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
        return RecognizedText(
            text: text,
            box: CGRect(x: pixels.minX / size.width, y: pixels.minY / size.height,
                        width: pixels.width / size.width, height: pixels.height / size.height)
        )
    }

    /// Collapses the runs of whitespace a recognizer leaves between columns,
    /// and rejects what would be worse than nothing under a marker: an empty
    /// read, a lone stray glyph, a smudge with no letter or digit in it.
    ///
    /// This is the "nothing legible" case the feature has to get right. A
    /// marker whose description is `l` or `—` is not a marker with context, it
    /// is a marker with a wrong answer, and an agent has no way to tell the two
    /// apart.
    static func cleaned(_ string: String) -> String? {
        let collapsed = string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count >= 2,
              collapsed.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        guard collapsed.count > maximumLength else { return collapsed }
        return collapsed.prefix(maximumLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The capture with every redacted region filled solid — the image the
    /// recognizer is actually handed.
    ///
    /// This is the load-bearing half of the promise `RedactionMask` makes, and
    /// the order matters more than it looks. Recognizing first and filtering
    /// afterwards would mean the text under the bar had been read into memory
    /// and was one missed check away from `capture.md`; painting first means
    /// there is nothing there to read. The filter in `recognize` stays as well,
    /// but as a second lock and not as the mechanism.
    ///
    /// Solid black rather than the export's bar-with-a-border: fidelity is
    /// irrelevant to a recognizer, only coverage is, and covering *more* than
    /// the export does can only be safe. The rect is grown by a pixel for the
    /// same reason — an antialiased fringe of a character surviving at the edge
    /// of a bar is exactly the kind of half-glyph `.accurate` is good at
    /// finishing for you.
    ///
    /// Returns nil rather than the original whenever anything fails. A capture
    /// with no redactions at all short-circuits to the original, which is the
    /// only path that hands back an unpainted image.
    private static func redacted(_ image: CGImage, by mask: RedactionMask) -> CGImage? {
        guard !mask.isEmpty else { return image }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let sourceSpace = image.colorSpace
        let space = (sourceSpace?.model == .rgb ? sourceSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)
        for rect in mask.rects {
            // Normalized, top-left → the context's bottom-left pixel grid.
            let pixels = CGRect(x: rect.minX * CGFloat(width),
                                y: (1 - rect.maxY) * CGFloat(height),
                                width: rect.width * CGFloat(width),
                                height: rect.height * CGFloat(height))
            context.fill(pixels.integral.insetBy(dx: -1, dy: -1))
        }
        return context.makeImage()
    }
}

// MARK: - Arbitration with the accessibility context (#55)

extension AXSnapshot {

    /// Whether the interface element under a marker already puts this string
    /// there — as its name, or as the value of the field it points at.
    ///
    /// The arbitration between the two sources of "what is under this marker",
    /// made once and in one place. Neither wins in the abstract, because which
    /// one is worth having depends entirely on what was photographed. On a
    /// native app the tree usually holds the exact string the pixels show, and
    /// holds it *better*: spelled from the source rather than guessed from
    /// antialiased glyphs, and arriving with a role, a box and a path around
    /// it. On an Electron or web window — Slack, VS Code, a Chrome tab — the
    /// tree is often a stack of anonymous groups and the pixels are the only
    /// place the text exists at all, which is where reading them earns its
    /// keep.
    ///
    /// So the rule is not "prefer one" but **never say it twice**: the read is
    /// dropped exactly when the tree already carries it, and kept whenever it
    /// says something the tree did not. Two lines under one marker repeating
    /// each other are not corroboration — they are one source counted twice,
    /// and an agent weighing "the label says X and the pixels say X" would be
    /// weighing a copy of itself.
    ///
    /// Containment either way round, because the two rarely match to the
    /// character: a recognizer reads a button's whole row where `AXTitle` holds
    /// just the word, and reads the word where the label is a full sentence.
    /// Strings under three characters are ignored on both sides — "OK" found
    /// inside anything proves nothing.
    func names(_ text: String, atNormalized point: CGPoint, hiddenBy mask: RedactionMask) -> Bool {
        guard let resolved = element(atNormalized: point, hiddenBy: mask) else { return false }
        let needle = Self.comparable(text)
        guard needle.count >= 3 else { return false }
        return [resolved.element.name, resolved.element.value]
            .compactMap { $0.map(Self.comparable) }
            .filter { $0.count >= 3 }
            .contains { $0.contains(needle) || needle.contains($0) }
    }

    /// Case- and spacing-insensitive form, used only to decide whether two
    /// strings carry the same information. Never displayed, never exported.
    private static func comparable(_ string: String) -> String {
        string.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - Applying a pass to the markers

extension Array where Element == Pin {

    /// Re-derives every marker's recognized text from a pass, and keeps the
    /// descriptions Pinpoint pre-filled in step with it.
    ///
    /// Deliberately here and not in `EditorView`: these are the rules that
    /// decide whether an API key stays in a marker's description after the user
    /// has painted over it, and rules like that should be checkable without a
    /// window on screen (`scripts/verify-ocr-redaction.swift` runs exactly this
    /// function). The editor calls it inside `withUndo`, so every change it
    /// makes is one undo step with the action that caused it.
    ///
    /// The note rules, in the order they are applied:
    ///
    /// - A description that is still *exactly* what Pinpoint put there follows
    ///   its source, including all the way back to empty when a redaction has
    ///   just taken that source away. This is the case #50 hinges on: a
    ///   description auto-filled with a token, then painted over, must not ship
    ///   the token — and this text is Pinpoint's own output, so taking it back
    ///   costs the user nothing they wrote.
    /// - An empty description is filled from a first read.
    /// - Anything else — a description the user typed, or one they deliberately
    ///   cleared — is never touched. The mask governs what Pinpoint collects,
    ///   not what a person chose to write.
    ///
    /// `isSuperseded` is asked before a read is kept at all, and is how the
    /// accessibility context (#55) wins where it already names the same thing.
    mutating func applyRecognition(_ recognition: TextRecognition,
                                   imageSize: CGSize,
                                   hiddenBy mask: RedactionMask,
                                   isSuperseded: (String, CGPoint) -> Bool = { _, _ in false }) {
        for index in indices {
            let position = self[index].position
            var current = recognition.text(near: position, imageSize: imageSize, hiddenBy: mask)
            if let read = current, isSuperseded(read.text, position) { current = nil }

            let previous = self[index].recognized
            guard previous != current else { continue }

            let note = self[index].note.trimmingCharacters(in: .whitespacesAndNewlines)
            if let previous, note == previous.text {
                self[index].note = current?.text ?? ""
            } else if previous == nil, note.isEmpty, let current {
                self[index].note = current.text
            }
            self[index].recognized = current
        }
    }
}

// MARK: - Settings

/// Whether Pinpoint reads the text in a capture at all.
enum TextRecognitionSettings {
    static let enabledKey = "textRecognitionEnabled"

    /// On by default. The recognizer runs on this Mac with no network call, and
    /// everything it can read is already leaving in the picture next to it —
    /// what changes is that the string becomes greppable instead of only
    /// visible, which is the entire point of handing a capture to an agent.
    ///
    /// It is still a switch, because "greppable" is not nothing: a reader who
    /// would never have squinted at the corner of a screenshot will read a
    /// quoted line in a text file. Off, the pixels are unchanged and no
    /// `Text:` line is written.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}
