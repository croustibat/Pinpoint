import CoreGraphics

/// The regions of a capture the user painted over, and the only questions the
/// exporters ever ask about them (#50).
///
/// ## Why this type exists at all
///
/// Hiding pixels is the easy half. Pinpoint doesn't only hand over an image:
/// every copy also writes `capture.md` and `capture.json` next to it (#54), and
/// each numbered marker in those files carries the role, the label and
/// sometimes the *value* of the interface element the accessibility tree found
/// under it (#55). A redaction that only painted the picture would therefore
/// blank out an API key on screen and ship the very same string, in plain text,
/// two files over — the worst possible outcome, because the image *looks*
/// clean. So the mask is threaded through both text exporters, not just the
/// renderer.
///
/// Rects are normalized (0…1) in image space, top-left origin: the same
/// convention `Markup`, `Pin` and `AXSnapshot.normalizedRect(for:)` speak, so
/// nothing has to be converted at the call sites.
struct RedactionMask {
    /// The redacted regions, normalized. Empty for a capture with no redaction,
    /// which is the case every check below short-circuits on.
    let rects: [CGRect]

    /// Reads the redactions out of a set of markups. Taking the whole array
    /// rather than a pre-filtered one is deliberate: every exporter already has
    /// `shapes` in hand, so there is no way to build the document and forget
    /// the mask.
    init(_ shapes: [Markup]) {
        rects = shapes.filter(\.isRedaction).map(\.rect)
    }

    var isEmpty: Bool { rects.isEmpty }

    /// Whether a normalized point falls inside a redacted region — a marker
    /// dropped on something the user chose to hide.
    func hides(_ point: CGPoint) -> Bool {
        rects.contains { $0.contains(point) }
    }

    /// Whether a normalized rect touches a redacted region.
    ///
    /// Any overlap counts, however small, and that is the whole point. An
    /// element's text is rendered inside its own frame, so a redaction covering
    /// a tenth of a label covers a tenth of that label's characters — and those
    /// characters are exactly what the user meant to hide. There is no safe
    /// threshold above zero, so there isn't one.
    ///
    /// A degenerate (empty) frame counts as hidden whenever anything is
    /// redacted at all: it can't be reasoned about geometrically, and erring
    /// towards hiding costs nothing — such an element contains no point, so it
    /// is never what a marker resolves to.
    func hides(_ rect: CGRect) -> Bool {
        guard !rects.isEmpty else { return false }
        guard rect.width > 0, rect.height > 0 else { return true }
        return rects.contains { $0.intersects(rect) }
    }
}

// MARK: - Accessibility

extension AXSnapshot {

    /// The interface element under a marker, with everything a redaction covers
    /// taken out of the answer — the only resolution the exporters are allowed
    /// to use.
    ///
    /// Two rules, both deliberately blunt:
    ///
    /// 1. **A marker sitting on a redacted region resolves to nothing.** Not to
    ///    a nameless element, not to its parent: nothing. The user pointed at
    ///    something they had just decided to hide, and the honest answer is
    ///    silence. Without this, `element(atNormalized:)`'s promotion step could
    ///    hand back the *actionable ancestor* of the hidden leaf — a button
    ///    whose own label was never covered — and quietly name what was under
    ///    the bar.
    ///
    /// 2. **Any element whose frame a redaction touches loses its name and its
    ///    value**, whether it is the resolved element or one of the ancestors
    ///    printed in its path. Its role, its box and its position stay: they
    ///    describe geometry the black bar already advertises, and they are what
    ///    still lets an agent say "there is a text field here I can't read".
    ///
    /// Rule 2 is coarse on purpose, and it costs something: a redaction
    /// anywhere in a window also strips that window's title from every path,
    /// since the window's frame contains the redaction. That is the trade this
    /// feature is *for* — a name kept by mistake is a leak, a name dropped by
    /// mistake is a slightly duller export.
    ///
    /// The snapshot itself is never mutated: it stays whole in the editor's
    /// state and in its sidecar, which is what lets undoing a redaction bring
    /// the context back (#44). Only the copy that leaves the app is stripped.
    func element(atNormalized point: CGPoint, hiddenBy mask: RedactionMask) -> Resolved? {
        guard !mask.hides(point) else { return nil }
        guard var resolved = element(atNormalized: point) else { return nil }
        guard !mask.isEmpty else { return resolved }

        resolved.element = redacting(resolved.element, under: mask)
        resolved.ancestors = resolved.ancestors.map { redacting($0, under: mask) }
        return resolved
    }

    /// Strips every human-readable field from an element a redaction covers,
    /// and says so through `redaction` rather than leaving a silent gap a reader
    /// could take for "this element had nothing to show".
    private func redacting(_ element: Element, under mask: RedactionMask) -> Element {
        guard mask.hides(normalizedRect(for: element.frame)) else { return element }
        var stripped = element
        stripped.title = nil
        stripped.label = nil
        stripped.identifier = nil
        stripped.help = nil
        stripped.placeholder = nil
        stripped.value = nil
        stripped.redaction = .userRedaction
        return stripped
    }
}

// MARK: - Recognized text

extension Pin {

    /// What Pinpoint read in the pixels under this marker (#49), with anything
    /// a redaction covers taken out of the answer — the only reading the
    /// exporters are allowed to publish.
    ///
    /// The recognizer already worked on an image with the bars painted onto it,
    /// so in the ordinary flow there is nothing left here to catch. This is the
    /// check that makes that a *belt* rather than the only strap, and it earns
    /// its keep in the cases where the two can drift apart:
    ///
    /// - a read taken before the bar was drawn, still cached on the marker
    ///   while the next pass runs;
    /// - a capture re-opened from the Shelf or the history, whose markers carry
    ///   reads recorded in an earlier session;
    /// - any future caller that builds a document straight from stored pins
    ///   without an editor in the loop.
    ///
    /// In each of those the mask is right there in `shapes` and the read is
    /// right there on the pin, so the exporters can simply ask — the same shape
    /// as `AXSnapshot.element(atNormalized:hiddenBy:)`, and for the same
    /// reason: this file is where the question "may this leave?" is answered,
    /// and no exporter should have to trust that another one was careful.
    ///
    /// Two rules, mirroring the accessibility ones. A marker *on* a redacted
    /// region reads nothing. A read whose box a redaction touches — however
    /// little of it — is dropped whole, because a line's characters live inside
    /// its box and the covered ones are exactly the ones the user meant to
    /// hide.
    func recognizedText(hiddenBy mask: RedactionMask) -> RecognizedText? {
        guard let recognized else { return nil }
        guard !mask.hides(position), !mask.hides(recognized.box) else { return nil }
        return recognized
    }
}
