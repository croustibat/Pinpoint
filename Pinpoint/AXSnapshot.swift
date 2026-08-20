import CoreGraphics
import Foundation

/// A frozen slice of the macOS accessibility tree, read at the instant a
/// capture was taken and kept next to it (#55).
///
/// ## Why a snapshot, and not a live query
///
/// Markers are placed in the editor, *after* the capture — by then the app that
/// was photographed may have scrolled, closed a sheet, or quit. Asking
/// `AXUIElementCopyElementAtPosition` at the moment a marker is dropped would
/// therefore answer about a screen that no longer exists. So the tree is walked
/// once, while the pixels are being read, and every element that overlaps the
/// captured region is stored with its frame. Resolving a marker afterwards is
/// then pure geometry against that frozen list.
///
/// ## Coordinate spaces
///
/// Element frames are kept in the space the accessibility APIs speak: points,
/// **global, top-left origin** — the same one `CGDisplayBounds` returns, which
/// is what makes multi-display setups and negative screen origins fall out for
/// free instead of needing a special case (#26).
///
/// `captureRect` is the piece of that space the image shows. Nothing else ties
/// the elements to the image, which is what makes cropping (#21) trivial:
/// `cropped(to:)` shrinks this one rect and leaves all 800 frames alone.
struct AXSnapshot: Codable, Sendable, Equatable {

    /// The screen area the image covers: points, global top-left origin.
    var captureRect: CGRect

    /// Every application whose windows were walked, referenced by index from
    /// `Element.application`. Stored once rather than per element — a capture of
    /// a single window would otherwise repeat the same bundle id 800 times.
    var applications: [Application]

    /// The flattened tree, parents always before their children (so `parent`
    /// indices only ever point backwards).
    var elements: [Element]

    /// `true` when the walk stopped on one of its own limits (time, node count)
    /// rather than because it had seen everything. Exported, so a reader knows
    /// a missing element may mean "not looked at" and not "not there".
    var truncated: Bool

    /// When the tree was read (the capture instant, near enough).
    var capturedAt: Date

    /// Whether the walk was allowed to keep the contents of ordinary text
    /// fields. Recorded per snapshot because it's decided at capture time — the
    /// value is simply never read when the switch is off, so a later flip of the
    /// setting can't retroactively expose an old capture.
    var includesFieldValues: Bool

    struct Application: Codable, Sendable, Equatable {
        var name: String?
        var bundleIdentifier: String?
        var processIdentifier: Int32
    }

    /// Why an element's value isn't in the snapshot.
    enum Redaction: String, Codable, Sendable {
        /// A password field. Never read, at any setting.
        case secureField
        /// An ordinary text field, withheld by the default privacy policy.
        case textFieldPolicy
    }

    struct Element: Codable, Sendable, Equatable {
        /// `AXButton`, `AXTextField`… The raw accessibility role, deliberately
        /// not translated into prose: it's the stable vocabulary an agent (and
        /// every accessibility inspector) already shares.
        var role: String
        var subrole: String?
        /// `AXTitle` — the visible label of a control.
        var title: String?
        /// `AXDescription` — what a screen reader would announce.
        var label: String?
        /// `AXIdentifier`. Gold for the issue's actual goal: it is usually the
        /// very `accessibilityIdentifier` string written in the app's source.
        var identifier: String?
        /// `AXHelp` (tooltip). Only collected when nothing else names the
        /// element, where it's often the only human-readable clue.
        var help: String?
        /// `AXPlaceholderValue`, for text inputs. Names an empty field.
        var placeholder: String?
        /// The element's value, when the privacy policy allows it.
        var value: String?
        /// Set instead of `value` when the value was withheld.
        var redaction: Redaction?
        /// Frame in points, global top-left origin.
        var frame: CGRect
        var enabled: Bool?
        /// Index into `applications`.
        var application: Int
        /// Front-to-back rank of the owning window (0 = frontmost). Used to
        /// break ties: two overlapping apps both "contain" the same point, and
        /// only the one on top is what the user actually pointed at.
        var windowOrder: Int
        /// Depth below the application element (a window is 0).
        var depth: Int
        /// Index of the parent in `elements`, or nil for a window.
        var parent: Int?

        /// The best single name for this element, or nil when it has none.
        var name: String? { title ?? label ?? identifier ?? placeholder ?? help }

        var area: CGFloat { max(frame.width, 0) * max(frame.height, 0) }
    }

    /// An element together with what it took to find it: its owning app and the
    /// chain of containers above it. Everything a caller needs to render the
    /// element without walking the flat array itself.
    struct Resolved: Sendable {
        var element: Element
        var application: Application
        /// Ancestors, outermost first (window → … → the element's parent).
        var ancestors: [Element]
    }
}

// MARK: - Geometry

extension AXSnapshot {

    /// Maps a normalized image point (0…1, top-left) to the screen point it was
    /// captured from.
    func screenPoint(for normalized: CGPoint) -> CGPoint {
        CGPoint(
            x: captureRect.minX + normalized.x * captureRect.width,
            y: captureRect.minY + normalized.y * captureRect.height
        )
    }

    /// The inverse: a screen rect expressed in the image's normalized space.
    /// Not clamped — an element wider than the capture keeps coordinates outside
    /// 0…1, which is honest information (it sticks out of the frame).
    func normalizedRect(for screenRect: CGRect) -> CGRect {
        guard captureRect.width > 0, captureRect.height > 0 else { return .zero }
        return CGRect(
            x: (screenRect.minX - captureRect.minX) / captureRect.width,
            y: (screenRect.minY - captureRect.minY) / captureRect.height,
            width: screenRect.width / captureRect.width,
            height: screenRect.height / captureRect.height
        )
    }

    /// The same snapshot seen through a sub-rectangle of the image (normalized,
    /// top-left) — what `EditorView.performCrop()` needs.
    ///
    /// Only `captureRect` moves: element frames are in screen space, so they
    /// stay valid word for word. Elements are not dropped either, since a crop
    /// can be undone (#44) and the ones outside simply stop matching.
    func cropped(to rect: CGRect) -> AXSnapshot {
        var copy = self
        copy.captureRect = CGRect(
            x: captureRect.minX + rect.minX * captureRect.width,
            y: captureRect.minY + rect.minY * captureRect.height,
            width: rect.width * captureRect.width,
            height: rect.height * captureRect.height
        )
        return copy
    }
}

// MARK: - Resolution

extension AXSnapshot {

    /// Roles that describe a *thing you can act on* — the answer an agent is
    /// really after ("the Login button"), rather than the leaf that happens to
    /// sit deepest under the pixel ("the label inside the Login button").
    private static let actionableRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXCheckBox",
        "AXRadioButton", "AXLink", "AXTextField", "AXTextArea", "AXSearchField",
        "AXComboBox", "AXSlider", "AXStepper", "AXIncrementor", "AXDisclosureTriangle",
        "AXTab", "AXRow", "AXCell", "AXColorWell", "AXSwitch", "AXToolbarButton"
    ]

    /// Roles that carry no meaning on their own: worth reporting only when
    /// nothing better contains the point.
    private static let passiveRoles: Set<String> = [
        "AXStaticText", "AXImage", "AXUnknown", "AXGroup", "AXSplitGroup",
        "AXScrollArea", "AXLayoutArea", "AXLayoutItem", "AXList", "AXTable",
        "AXOutline", "AXToolbar", "AXSplitter", "AXScrollBar", "AXValueIndicator"
    ]

    /// The element a marker points at, or nil when the snapshot has nothing
    /// under it (no permission, region outside any app, walk truncated…).
    ///
    /// Among everything whose frame contains the point, the winner is the one in
    /// the frontmost window, then the **smallest**, then the deepest.
    ///
    /// Smallest and not deepest: depth reads like specificity and isn't. An
    /// Electron window (Slack, VS Code…) nests generic `AXGroup` wrappers twenty
    /// levels down while each of them still spans the whole window — rank by
    /// depth and every marker anywhere in the app comes back as the same
    /// anonymous group. Area is the honest measure of "this, not that", and
    /// depth only breaks the tie between two elements sharing a frame, where the
    /// inner one is the more precise answer.
    ///
    /// One correction is applied on top: when that leaf is decoration (the text
    /// drawn *inside* a button, an icon inside a link), we hand back the nearest
    /// actionable ancestor of roughly the same size instead. Naming the button
    /// rather than its label is the whole point of the feature; the full chain is
    /// reported either way, so nothing is lost.
    func element(atNormalized point: CGPoint) -> Resolved? {
        let screen = screenPoint(for: point)
        let candidates = elements.indices.filter { elements[$0].frame.contains(screen) }
        guard !candidates.isEmpty else { return nil }

        let best = candidates.min { left, right in
            let a = elements[left], b = elements[right]
            if a.windowOrder != b.windowOrder { return a.windowOrder < b.windowOrder }
            if a.area != b.area { return a.area < b.area }
            return a.depth > b.depth
        }
        guard let best else { return nil }

        let chosen = promoted(from: best)
        let element = elements[chosen]
        guard element.application < applications.count else { return nil }
        return Resolved(element: element,
                        application: applications[element.application],
                        ancestors: ancestors(of: chosen))
    }

    /// Walks up from a decorative leaf to the control it belongs to. Stops as
    /// soon as the ancestor grows much bigger than what was pointed at — a
    /// button wrapping its own label is a promotion, a window wrapping a stray
    /// icon is not.
    private func promoted(from index: Int) -> Int {
        guard Self.passiveRoles.contains(elements[index].role) else { return index }
        let leafArea = max(elements[index].area, 1)

        var current = elements[index].parent
        var hops = 0
        while let candidate = current, hops < 3 {
            let element = elements[candidate]
            guard element.area <= leafArea * 4 else { return index }
            if Self.actionableRoles.contains(element.role) { return candidate }
            current = element.parent
            hops += 1
        }
        return index
    }

    /// The containers above `index`, outermost first, capped so a deeply nested
    /// web view doesn't print a twenty-link path.
    private func ancestors(of index: Int) -> [Element] {
        var chain: [Element] = []
        var current = elements[index].parent
        while let parent = current, chain.count < 8 {
            chain.append(elements[parent])
            current = elements[parent].parent
        }
        return chain.reversed()
    }
}

// MARK: - Description

extension AXSnapshot.Element {
    /// `AXButton “Login”`, or just `AXGroup` when the element has no name.
    /// The role stays raw and the name is quoted, so the two can't blur into
    /// each other when a label happens to look like a role.
    var summary: String {
        guard let name, !name.isEmpty else { return role }
        return "\(role) “\(name)”"
    }
}

extension AXSnapshot.Resolved {
    /// `AXWindow “Sign in” › AXGroup › AXButton “Login”` — the element in its
    /// context, one line, unambiguous to read either way round.
    var path: String {
        (ancestors.map(\.summary) + [element.summary]).joined(separator: " › ")
    }
}
