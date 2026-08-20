import ApplicationServices
import AppKit
import CoreGraphics
import QuartzCore

/// Walks the accessibility tree over a captured region and freezes it into an
/// `AXSnapshot`.
///
/// Three rules shape everything below, in this order:
///
/// 1. **A capture must never fail because of this.** Every path returns an
///    optional and swallows its own errors; the caller treats `nil` as "no
///    context", not as a failure.
/// 2. **It must never block the UI.** The whole walk runs off the main actor,
///    behind a hard wall-clock ceiling, and each individual accessibility call
///    is bounded by `AXUIElementSetMessagingTimeout` so one unresponsive app
///    can't stall the rest.
/// 3. **It must never read a password.** Secure fields are recognised before
///    their value is fetched, so the contents never enter the process at all —
///    not "fetched then dropped".
enum AXSnapshotCollector {

    // MARK: - Limits
    //
    // A full tree walk of a browser is unbounded work: a content-heavy page can
    // hold tens of thousands of nodes. These caps are what turn it into a fixed
    // cost. Whichever is hit first, the walk stops and reports `truncated`.

    /// Elements kept. Beyond this the snapshot stops growing — it also caps the
    /// size of the sidecar written next to every capture in the history.
    private static let maxElements = 900
    /// Nodes looked at, kept or not. Guards against a deep tree that lies almost
    /// entirely outside the region (each miss still costs two AX round trips).
    private static let maxVisited = 20_000
    /// How deep to descend. A web view can nest far past anything useful.
    private static let maxDepth = 40
    /// Applications whose windows are walked, frontmost first. Sized to absorb
    /// the system processes that crowd the top of the window list (Control
    /// Center alone owns one window per menu-bar icon) without pushing the
    /// user's actual apps out of range.
    private static let maxApplications = 8
    /// Soft budget: checked inside the walk, which then returns what it has.
    private static let walkBudget: CFTimeInterval = 1.5
    /// Hard ceiling: if the walk hasn't answered by then, the capture goes on
    /// without it. Only reachable if an accessibility call wedges past its own
    /// timeout — the walk is otherwise self-limiting.
    private static let hardCeiling: TimeInterval = 3.0
    /// Per-message timeout for one app. Deliberately short: a hung app costs a
    /// third of a second here, not the whole budget.
    private static let messagingTimeout: Float = 0.35

    // MARK: - Roles

    /// Roles whose value is a password. Never read.
    private static let secureRoles: Set<String> = ["AXSecureTextField", "AXSecureTextArea"]

    /// Roles whose value is text the user typed. Withheld unless the user opted
    /// in — see `AXContextSettings.includesFieldValues`.
    private static let typedTextRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"
    ]

    /// Roles whose value is state rather than content (a checkbox's 0/1, a
    /// slider's number, a static label's own text). Always safe to report: for
    /// `AXStaticText` in particular the value *is* what the screenshot already
    /// shows, so quoting it adds no exposure.
    private static let statefulValueRoles: Set<String> = [
        "AXStaticText", "AXCheckBox", "AXRadioButton", "AXSlider", "AXPopUpButton",
        "AXMenuItem", "AXDisclosureTriangle", "AXStepper", "AXIncrementor",
        "AXProgressIndicator", "AXLevelIndicator", "AXSwitch", "AXValueIndicator"
    ]

    /// Longest value string kept, in characters. A text area can hold a whole
    /// document; the point here is to identify an element, not to mirror it.
    private static let maxValueLength = 200

    /// Longest name (title, label, help, placeholder) kept.
    ///
    /// Not a cosmetic cap. Real apps build labels by concatenation: a Slack
    /// conversation row announces itself with the sender, the subject and the
    /// last several messages, running to thousands of characters — text that is
    /// partly scrolled out of the picture. Cutting at a length that still
    /// identifies the element keeps the export readable *and* keeps it from
    /// carrying more than the screenshot itself showed.
    private static let maxNameLength = 120

    // MARK: - Entry point

    /// Reads the tree covering `region`, or returns nil when there's nothing to
    /// report — no permission, no window, or the ceiling was hit.
    ///
    /// Call it *alongside* the screenshot rather than after it: the two then
    /// describe the same instant, which is the whole contract of the snapshot.
    static func capture(region: CaptureRegion, includeFieldValues: Bool) async -> AXSnapshot? {
        guard AXPermission.isTrusted else { return nil }

        let display = CGDisplayBounds(region.displayID)
        let screenRect = screenRect(for: region, on: display)
        guard screenRect.width >= 1, screenRect.height >= 1 else { return nil }

        // Not `async let` over a detached task alone: cancelling a Swift task
        // does nothing to an accessibility call already blocked in IPC, so the
        // ceiling has to be able to answer *without* the walk. A one-shot box
        // lets whichever finishes first resume, and lets the loser be ignored.
        return await withCheckedContinuation { continuation in
            let box = SingleResume(continuation)
            Task.detached(priority: .userInitiated) {
                box.resume(walk(screenRect: screenRect, display: display,
                                includeFieldValues: includeFieldValues))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + hardCeiling) {
                box.resume(nil)
            }
        }
    }

    /// The captured region in the accessibility APIs' own space: points, global
    /// top-left origin. `CGDisplayBounds` already returns the display's origin
    /// in exactly that space, so multiple displays and negative origins (#26)
    /// need no special case — the sum simply works.
    private static func screenRect(for region: CaptureRegion, on display: CGRect) -> CGRect {
        CGRect(
            x: display.minX + region.rect.minX,
            y: display.minY + region.rect.minY,
            width: region.rect.width,
            height: region.rect.height
        )
    }

    // MARK: - The walk

    private static func walk(screenRect: CGRect, display: CGRect, includeFieldValues: Bool) -> AXSnapshot? {
        var state = State(region: screenRect,
                          includeFieldValues: includeFieldValues,
                          deadline: CACurrentMediaTime() + walkBudget)

        for (order, pid) in owningProcesses(over: screenRect, on: display).enumerated() {
            guard !state.reachedElementLimit() else { break }

            let application = AXUIElementCreateApplication(pid)
            _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)

            let appIndex = state.applications.count
            let running = NSRunningApplication(processIdentifier: pid)
            state.applications.append(AXSnapshot.Application(
                name: running?.localizedName,
                bundleIdentifier: running?.bundleIdentifier,
                processIdentifier: pid
            ))

            // The application element's children, not just `AXWindows`: that way
            // an open menu or a popover — exactly what the capture timer exists
            // to let people photograph — is walked like any other top-level
            // container.
            let roots = children(of: application) ?? []
            for root in roots {
                descend(root, parent: nil, depth: 0, application: appIndex,
                        windowOrder: order, into: &state)
            }
        }

        guard !state.elements.isEmpty else { return nil }
        return AXSnapshot(
            captureRect: screenRect,
            applications: state.applications,
            elements: state.elements,
            truncated: state.truncated,
            capturedAt: Date(),
            includesFieldValues: includeFieldValues
        )
    }

    /// Depth-first, parents recorded before their children so `parent` indices
    /// always point backwards into the array.
    ///
    /// Pruning is by intersection with the captured region, not by containment
    /// in the parent: an element whose box misses the region can't have anything
    /// to say about it. (A child drawn outside its parent's frame — rare, and
    /// only in clipped scroll content — is missed with it. The alternative is
    /// walking every node of every window, which is the cost this exists to
    /// avoid.)
    private static func descend(_ element: AXUIElement, parent: Int?, depth: Int,
                                application: Int, windowOrder: Int, into state: inout State) {
        guard depth <= maxDepth, !state.reachedElementLimit() else { return }

        state.visited += 1
        if state.visited > maxVisited || CACurrentMediaTime() > state.deadline {
            state.truncated = true
            return
        }

        guard let frame = frame(of: element), frame.intersects(state.region) else { return }
        guard let role = string(element, kAXRoleAttribute) else { return }

        let index = state.elements.count
        state.elements.append(describe(element, role: role, frame: frame, depth: depth,
                                       parent: parent, application: application,
                                       windowOrder: windowOrder,
                                       includeFieldValues: state.includeFieldValues))

        for child in children(of: element) ?? [] {
            descend(child, parent: index, depth: depth + 1, application: application,
                    windowOrder: windowOrder, into: &state)
        }
    }

    /// Reads the attributes worth keeping. Two of them are conditional on
    /// purpose: `AXHelp` only when nothing else names the element (it's usually
    /// a whole sentence), `AXPlaceholderValue` only for inputs.
    private static func describe(_ element: AXUIElement, role: String, frame: CGRect,
                                 depth: Int, parent: Int?, application: Int, windowOrder: Int,
                                 includeFieldValues: Bool) -> AXSnapshot.Element {
        let title = string(element, kAXTitleAttribute)
        let label = string(element, kAXDescriptionAttribute)
        let identifier = string(element, kAXIdentifierAttribute)
        let isInput = typedTextRoles.contains(role) || secureRoles.contains(role)

        let (value, redaction) = readValue(element, role: role, includeFieldValues: includeFieldValues)

        return AXSnapshot.Element(
            role: role,
            subrole: string(element, kAXSubroleAttribute),
            title: title,
            label: label,
            identifier: identifier,
            help: (title == nil && label == nil && identifier == nil)
                ? string(element, kAXHelpAttribute) : nil,
            placeholder: isInput ? string(element, kAXPlaceholderValueAttribute) : nil,
            value: value,
            redaction: redaction,
            frame: frame,
            enabled: bool(element, kAXEnabledAttribute),
            application: application,
            windowOrder: windowOrder,
            depth: depth,
            parent: parent
        )
    }

    // MARK: - Values, and what is never read

    /// The privacy gate. Returns the value to keep, or the reason there isn't
    /// one.
    ///
    /// A capture leaves the machine — that's the point of the whole app — and the
    /// accessibility tree is far more talkative than the pixels: it hands over
    /// the *entire* contents of a field, including the part scrolled out of
    /// sight, and it does so for the password field too. So:
    ///
    /// - secure fields are identified by role **or** subrole and never read;
    /// - anything the user typed is withheld unless they explicitly opted in;
    /// - state-like values (a checkbox, a slider, a label's own text) are kept,
    ///   since they're already visible in the image;
    /// - every other role's value is ignored, because "unknown role, unknown
    ///   sensitivity" is not a bet worth taking.
    private static func readValue(_ element: AXUIElement, role: String,
                                  includeFieldValues: Bool) -> (String?, AXSnapshot.Redaction?) {
        let subrole = string(element, kAXSubroleAttribute)
        if secureRoles.contains(role) || isSecure(subrole) || isSecure(role) {
            return (nil, .secureField)
        }
        if typedTextRoles.contains(role) {
            guard includeFieldValues else { return (nil, .textFieldPolicy) }
            return (text(of: element).map { truncate($0, to: maxValueLength) }, nil)
        }
        guard statefulValueRoles.contains(role) else { return (nil, nil) }
        return (text(of: element).map { truncate($0, to: maxValueLength) }, nil)
    }

    /// Catches the roles and subroles Apple didn't name in a constant —
    /// `AXSecureTextField` as a subrole, and anything a framework spells with
    /// "password" in it.
    private static func isSecure(_ token: String?) -> Bool {
        guard let token = token?.lowercased() else { return false }
        return token.contains("secure") || token.contains("password")
    }

    /// `AXValue` as a readable string. Numbers and booleans are formatted rather
    /// than skipped: a checkbox's `1` is exactly the state an agent needs.
    private static func text(of element: AXUIElement) -> String? {
        guard let raw = copy(element, kAXValueAttribute) else { return nil }
        let string: String?
        switch raw {
        case let value as String: string = value
        case let value as NSNumber: string = value.stringValue
        default: string = nil
        }
        guard let string else { return nil }
        let flattened = string.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return flattened.isEmpty ? nil : flattened
    }

    private static func truncate(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "…"
    }

    // MARK: - Which applications to walk

    /// The processes owning on-screen windows over the region, frontmost first.
    ///
    /// Starting from the window list rather than from every running application
    /// is what keeps this cheap: a machine with thirty apps open usually has two
    /// or three of them showing anything inside a selection. The list's order is
    /// front-to-back, which is also the tie-break used when two overlapping apps
    /// both contain a marker's point.
    ///
    /// One correction is applied to that order, and it matters more than it
    /// sounds. Some system processes keep a full-screen host window permanently
    /// "on screen" above every app while showing nothing at all — Notification
    /// Center's is the one you meet in practice: layer 21, 2880×1620, alpha 1,
    /// present whether or not the panel is open. Ranked naively it sits in front
    /// of every real window, and *every* marker on the screen resolves to
    /// `AXWindow "Notification Center" › AXGroup`. Such windows are therefore
    /// moved behind everything else rather than dropped, so a capture that
    /// genuinely is of one still gets an answer — it just stops answering for
    /// the app it was covering.
    private static func owningProcesses(over rect: CGRect, on display: CGRect) -> [pid_t] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var ordered: [pid_t] = []
        var deferred: [pid_t] = []
        for window in raw {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.intersects(rect) else { continue }

            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            if isFullScreenOverlay(frame, layer: layer, display: display) {
                if !deferred.contains(pid) { deferred.append(pid) }
                continue
            }
            guard !ordered.contains(pid) else { continue }
            ordered.append(pid)
            if ordered.count == maxApplications { break }
        }

        // A process only reached through an overlay window still gets walked,
        // last: its other windows (Notification Center's desktop widgets, say)
        // are real, and it costs nothing to have an answer of last resort.
        for pid in deferred where !ordered.contains(pid) && ordered.count < maxApplications {
            ordered.append(pid)
        }
        return ordered
    }

    /// A window floating above the normal level (`layer > 0`) that covers
    /// essentially a whole display. Menu-bar items, popovers and open menus all
    /// float too, but they are small — the size is what separates a real overlay
    /// the user can see from a host window parked over everything.
    private static func isFullScreenOverlay(_ frame: CGRect, layer: Int, display: CGRect) -> Bool {
        guard layer > 0 else { return false }
        let covered = frame.intersection(display)
        guard !covered.isNull, display.width > 0, display.height > 0 else { return false }
        return (covered.width * covered.height) >= 0.9 * (display.width * display.height)
    }

    // MARK: - Accessibility plumbing

    private static func copy(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let value = copy(element, attribute) as? String else { return nil }
        // Newlines folded to spaces: these end up on a single line of the
        // Markdown, where a raw \n would break the list item in two.
        let flattened = value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return flattened.isEmpty ? nil : truncate(flattened, to: maxNameLength)
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copy(element, attribute) as? NSNumber)?.boolValue
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        copy(element, kAXChildrenAttribute) as? [AXUIElement]
    }

    /// `AXFrame` in one call — global, top-left, already flipped for us. It is
    /// undocumented but universally implemented; `AXPosition` + `AXSize` is the
    /// fallback for the handful of elements that don't answer it.
    private static func frame(of element: AXUIElement) -> CGRect? {
        if let value = copy(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() {
            var rect = CGRect.zero
            if AXValueGetValue(value as! AXValue, .cgRect, &rect) { return rect }
        }
        guard let originValue = copy(element, kAXPositionAttribute),
              let sizeValue = copy(element, kAXSizeAttribute),
              CFGetTypeID(originValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(originValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Bookkeeping

    private struct State {
        let region: CGRect
        let includeFieldValues: Bool
        let deadline: CFTimeInterval
        var applications: [AXSnapshot.Application] = []
        var elements: [AXSnapshot.Element] = []
        var visited = 0
        var truncated = false

        /// Stops the walk once the element budget is spent, marking the result
        /// so a reader knows the snapshot is partial.
        mutating func reachedElementLimit() -> Bool {
            guard elements.count >= AXSnapshotCollector.maxElements else { return false }
            truncated = true
            return true
        }
    }
}

/// Resumes a continuation exactly once, whoever gets there first.
///
/// The walk and its wall-clock ceiling race each other and neither can cancel
/// the other; this is what makes "first one wins, second one is dropped" safe
/// rather than a double-resume crash.
private final class SingleResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AXSnapshot?, Never>?

    init(_ continuation: CheckedContinuation<AXSnapshot?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: AXSnapshot?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
