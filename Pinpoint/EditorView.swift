import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Annotation tools the user can switch between in the editor.
enum EditorTool: String, CaseIterable, Identifiable {
    case pin, arrow, rectangle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pin: return String(localized: "Marker")
        case .arrow: return String(localized: "Arrow")
        case .rectangle: return String(localized: "Rectangle")
        }
    }

    var symbol: String {
        switch self {
        case .pin: return "mappin"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        }
    }

    /// Used with ⌘. A bare digit or letter would be swallowed by the marker
    /// note fields and the instructions editor while typing.
    var shortcut: KeyEquivalent {
        switch self {
        case .pin: return "1"
        case .arrow: return "2"
        case .rectangle: return "3"
        }
    }
}

/// The editor's text inputs, tracked so keyboard shortcuts can stand down
/// while the user is typing.
private enum EditorField: Hashable {
    case note(Pin.ID)
    case context
}

/// Which end of an arrow a handle drags. `tip` is the end carrying the
/// arrowhead, so re-aiming an arrow is dragging its tip.
private enum ArrowEnd: CaseIterable {
    case tail, tip

    func point(of shape: Markup) -> CGPoint {
        self == .tail ? shape.start : shape.end
    }

    /// VoiceOver name of the handle that drags this end.
    var accessibilityLabel: String {
        switch self {
        case .tail: return String(localized: "a11y.handle.arrow.tail", defaultValue: "Arrow tail handle")
        case .tip: return String(localized: "a11y.handle.arrow.tip", defaultValue: "Arrow tip handle")
        }
    }
}

/// The eight box-handle positions, named for VoiceOver.
///
/// `SelectionHandle` (the shape handles) and `CropOverlay.Handle` are two
/// separate enums covering the same eight spots; both map onto this one so the
/// wording is written once and the two surfaces can't drift apart.
private enum HandleSpot {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var name: String {
        switch self {
        case .topLeft: return String(localized: "a11y.handle.topLeft", defaultValue: "top-left corner")
        case .top: return String(localized: "a11y.handle.top", defaultValue: "top edge")
        case .topRight: return String(localized: "a11y.handle.topRight", defaultValue: "top-right corner")
        case .right: return String(localized: "a11y.handle.right", defaultValue: "right edge")
        case .bottomRight: return String(localized: "a11y.handle.bottomRight", defaultValue: "bottom-right corner")
        case .bottom: return String(localized: "a11y.handle.bottom", defaultValue: "bottom edge")
        case .bottomLeft: return String(localized: "a11y.handle.bottomLeft", defaultValue: "bottom-left corner")
        case .left: return String(localized: "a11y.handle.left", defaultValue: "left edge")
        }
    }

    /// "Resize handle, top-left corner".
    var resizeLabel: String {
        String(localized: "a11y.handle.resize", defaultValue: "Resize handle, \(name)")
    }
}

private extension SelectionHandle {
    var spot: HandleSpot {
        switch self {
        case .topLeft: return .topLeft
        case .top: return .top
        case .topRight: return .topRight
        case .right: return .right
        case .bottomRight: return .bottomRight
        case .bottom: return .bottom
        case .bottomLeft: return .bottomLeft
        case .left: return .left
        }
    }
}

struct EditorView: View {
    /// The editor's base image. Mutable: a crop replaces it in place. Kept at
    /// native pixel size (`.size` == pixels) so export renders at full res.
    @State private var image: NSImage
    /// When the editor was opened from a Shelf file, the source URL so a crop
    /// can be written back as a new `-cropped.png` alongside it.
    private let sourceURL: URL?
    var onClose: () -> Void
    /// Called with the current annotation state and base image so they can be
    /// persisted to history (on copy and when the editor closes).
    var onPersist: ([Pin], [Markup], String, NSImage) -> Void

    @AppStorage(PinStyle.storageKey) private var pinStyle: PinStyle = .disc
    @AppStorage("includeLegend") private var includeLegend = true

    @State private var pins: [Pin] = []
    @State private var shapes: [Markup] = []
    @State private var context: String = ""
    @State private var tool: EditorTool = .pin
    @State private var selectedPinID: Pin.ID?
    @State private var selectedShapeID: Markup.ID?
    @State private var draft: Markup?
    @State private var dragStartPosition: CGPoint?
    @State private var didCopy = false
    /// Non-nil while an export failure is being shown. Copy and save used to
    /// swallow their errors and still report success.
    @State private var exportError: String?
    /// Which text field is being edited, if any. Only used to step aside: the
    /// Delete key equivalent is disabled while typing so ⌫ keeps editing text.
    @FocusState private var focusedField: EditorField?

    /// System-wide "Reduce motion". Every animated state change in the editor
    /// goes through `withMotion`, which drops the animation when this is on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Side of the numbered badge in the side panel. Scaled with the caption
    /// text it wraps, so a larger Dynamic Type size doesn't clip the number.
    @ScaledMetric(relativeTo: .caption) private var pinBadgeSide: CGFloat = 22

    // Crop mode state. `cropRect` is normalized (0...1, top-left origin), same
    // convention as pins/markups.
    @State private var isCropping = false
    @State private var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    // MARK: Undo/redo state
    @State private var history = EditorHistory()
    /// Pre-gesture state captured on a drag's first event, recorded once on
    /// release: a drag emits an event per frame, and each one must not become
    /// its own undo entry. Shared by marker and shape gestures — only one of
    /// them can be in flight at a time.
    @State private var dragUndoSnapshot: EditorSnapshot?
    /// Pre-edit state captured when a text field takes focus, recorded when it
    /// gives it up. See `flushTextEdit()` for why typing is coalesced this way.
    @State private var textEditSnapshot: EditorSnapshot?
    /// The shape as it stood before the gesture in progress, captured on its
    /// first event. Every frame applies the gesture's *cumulative* translation
    /// to this copy rather than to the live shape — same rule as `pinDrag`, and
    /// what keeps a drag from accelerating against its own output. Doubles as
    /// the "a shape gesture is running" flag.
    @State private var shapeDragOrigin: Markup?

    init(
        image: NSImage,
        initialPins: [Pin] = [],
        initialShapes: [Markup] = [],
        initialContext: String = "",
        sourceURL: URL? = nil,
        onPersist: @escaping ([Pin], [Markup], String, NSImage) -> Void = { _, _, _, _ in },
        onClose: @escaping () -> Void
    ) {
        _image = State(initialValue: image)
        self.sourceURL = sourceURL
        self.onPersist = onPersist
        self.onClose = onClose
        _pins = State(initialValue: initialPins)
        _shapes = State(initialValue: initialShapes)
        _context = State(initialValue: initialContext)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                canvas
            }
            .frame(minWidth: 360, minHeight: 360)
            .layoutPriority(1)

            sidePanel
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 360)
        }
        .frame(minWidth: 680, minHeight: 440)
        .onDisappear { onPersist(pins, shapes, context, image) }
        // A text field changing hands closes one typing session and opens the
        // next. See `flushTextEdit()`.
        .onChange(of: focusedField) { _, newValue in
            flushTextEdit()
            if newValue != nil { textEditSnapshot = snapshot() }
        }
        .alert(
            String(localized: "Export failed"),
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            if isCropping {
                // Crop mode owns the toolbar: Cancel/Replace replace the picker.
                Button(String(localized: "Cancel"), action: cancelCrop)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(String(localized: "Done"), action: applyCrop)
                    .buttonStyle(.borderedProminent)
                    .tint(.pinpointVermillon)
                    .keyboardShortcut(.return, modifiers: [])
            } else {
                // `fixedSize()` locks the segmented picker to its intrinsic
                // width so it can't be squeezed when the trailing hint grows
                // (e.g. switching to Rectangle). Without it, a growing hint in
                // a narrow window shrank the picker and shifted the Crop button
                // left — see "Drag to draw a rectangle" being the longest hint.
                Picker("Tool", selection: $tool) {
                    ForEach(EditorTool.allCases) { tool in
                        Label(tool.label, systemImage: tool.symbol).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(toolPickerHelp)
                // No `accessibilityLabel` here: `labelsHidden()` only takes the
                // picker's title off screen, VoiceOver still reads it, and a
                // second label is appended to it rather than replacing it.
                .background(hiddenShortcuts)

                Button {
                    enterCropMode()
                } label: {
                    Label(String(localized: "Crop"), systemImage: "crop")
                }
                .buttonStyle(.bordered)
                .help(String(localized: "Crop"))

                Divider().frame(height: 18)

                // Visible undo/redo, deliberately without key equivalents of
                // their own: those live on the hidden buttons below, which step
                // aside while a text field is being edited. These stay clickable
                // at all times so the history is reachable mid-typing too.
                Button(action: undo) {
                    Label(String(localized: "Undo"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .disabled(!history.canUndo)
                .help(undoHelp)

                Button(action: redo) {
                    Label(String(localized: "Redo"), systemImage: "arrow.uturn.forward")
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
                .disabled(!history.canRedo)
                .help(redoHelp)

                Spacer()

                // Hint yields first when the row is tight (layoutPriority -1),
                // truncating instead of pushing the picker/buttons around.
                Text(toolHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// One tooltip for the whole picker: a segmented control's segments carry no
    /// tooltip of their own on macOS, so the picker advertises every tool and
    /// its key equivalent at once. Built from the localized labels, so it can't
    /// drift from what the segments show.
    private var toolPickerHelp: String {
        EditorTool.allCases
            .map { "\($0.label) ⌘\($0.shortcut.character)" }
            .joined(separator: " · ")
    }

    /// The toolbar buttons carry no key equivalent themselves (the hidden ones
    /// do), so their tooltips are what advertise ⌘Z / ⇧⌘Z. Built as plain
    /// strings, like `toolPickerHelp`, to keep the key glyphs out of the
    /// localized value.
    private var undoHelp: String { String(localized: "Undo") + " ⌘Z" }
    private var redoHelp: String { String(localized: "Redo") + " ⇧⌘Z" }

    /// Invisible buttons that exist only to own key equivalents: a segmented
    /// `Picker` can't carry one per segment, and the canvas can't reliably hold
    /// keyboard focus for an `.onKeyPress`. Rendered inside the picker's
    /// background with hit-testing off.
    private var hiddenShortcuts: some View {
        ZStack {
            ForEach(EditorTool.allCases) { item in
                Button("") { tool = item }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
            }

            // ⌫ / ⌦ remove the selected marker or annotation. Disabled while a
            // text field has focus — a disabled button doesn't claim its key
            // equivalent, so ⌫ keeps deleting characters while typing.
            Button("") { deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(focusedField != nil || !hasSelection)

            Button("") { deleteSelection() }
                .keyboardShortcut(.deleteForward, modifiers: [])
                .disabled(focusedField != nil || !hasSelection)

            // ⌘Z / ⇧⌘Z. Disabled while a text field has focus so the key
            // equivalent goes unclaimed and AppKit's own field-editor undo
            // handles it — one stack at a time, never two competing ones.
            Button("") { undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(focusedField != nil || !history.canUndo)

            Button("") { redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(focusedField != nil || !history.canRedo)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var toolHint: String {
        if isCropping {
            return String(localized: "Drag handles to crop · Esc to cancel")
        }
        // Once something of the active kind is on the canvas, the hint also
        // advertises that it can be picked back up.
        switch tool {
        case .pin:
            return String(localized: "Click to drop a marker")
        case .arrow:
            return shapes.contains { $0.kind == .arrow }
                ? String(localized: "Drag to draw an arrow · click one to move or re-aim it")
                : String(localized: "Drag to draw an arrow")
        case .rectangle:
            return shapes.contains { $0.kind == .rectangle }
                ? String(localized: "Drag to draw a rectangle · click one to move or resize it")
                : String(localized: "Drag to draw a rectangle")
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let fitted = fittedRect(imageSize: image.size, in: geo.size)
            // Sizes every annotation against the capture, then down to the
            // fitted rect — so what the canvas shows is what the export draws
            // (#48). One instance per layout pass, shared by every layer below.
            let metrics = MarkupMetrics(imageSize: image.size, fitted: fitted)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                    .shadow(radius: 8, y: 2)
                    .accessibilityLabel(String(localized: "a11y.canvas.image", defaultValue: "Screenshot being annotated"))

                // Committed markups. Drawing and interaction are two layers:
                // every shape draws first and takes no clicks, then the
                // manipulable ones take them on top, so a handle is never
                // buried under the outline of a shape drawn after it.
                ForEach(shapes) { shape in
                    // The drawing layer is what VoiceOver reads: it carries
                    // every shape, where the grab bands below only exist for
                    // the ones the active tool can manipulate.
                    markupView(shape, in: fitted, metrics: metrics, selected: shape.id == selectedShapeID)
                        .accessibilityElement()
                        .accessibilityLabel(accessibilityLabel(for: shape))
                        .accessibilityAddTraits(shape.id == selectedShapeID ? .isSelected : [])
                }
                .allowsHitTesting(false)

                // Grab bands along the outlines, then the selected shape's
                // handles above every band. Non-manipulable shapes are left out
                // of the layer entirely rather than hit-test-disabled inside it,
                // so switching tools mid-hover takes their cursor with them.
                ForEach(shapes.filter(isManipulable)) { shape in
                    // Pure hit-test surface: the drawing layer above already
                    // announces the shape, and two elements for one annotation
                    // would only make VoiceOver say it twice.
                    shapeGrabBand(shape, in: fitted, metrics: metrics)
                        .accessibilityHidden(true)
                }
                if let shape = selectedShape, isManipulable(shape) {
                    shapeHandles(shape, in: fitted)
                }

                // Live preview while drawing.
                if let draft {
                    markupView(draft, in: fitted, metrics: metrics, selected: true)
                        .allowsHitTesting(false)
                        .opacity(0.9)
                }

                // Numbered pins.
                ForEach($pins) { $pin in
                    let anchor = clampedMarkerAnchor(absolutePoint(pin.position, in: fitted),
                                                     in: fitted, metrics: metrics)
                    let markerSize = PinMarker.size(pinStyle, metrics: metrics)
                    PinMarker(number: pin.number, metrics: metrics, style: pinStyle,
                              selected: pin.id == selectedPinID)
                        // The badge is centred inside its grab area, so the
                        // anchor offset keeps measuring the same distance.
                        .frame(width: max(Self.pinGrabSize, markerSize.width),
                               height: max(Self.pinGrabSize, markerSize.height))
                        .contentShape(Rectangle())
                        .position(x: anchor.x, y: anchor.y + PinMarker.anchorYOffset(pinStyle, metrics: metrics))
                        .gesture(pinDrag($pin, in: fitted))
                        .allowsHitTesting(tool == .pin && !isCropping)
                        .accessibilityElement()
                        .accessibilityLabel(accessibilityLabel(for: pin))
                        .accessibilityValue(accessibilityPosition(of: pin))
                        .accessibilityHint(String(localized: "a11y.marker.hint", defaultValue: "Drag to move this marker"))
                        .accessibilityAddTraits(pin.id == selectedPinID ? .isSelected : [])
                }

                // Crop overlay sits on top and owns interaction while active.
                if isCropping {
                    CropOverlay(cropRect: $cropRect, fitted: fitted)
                        .allowsHitTesting(true)
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(in: fitted))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "a11y.canvas", defaultValue: "Annotation canvas"))
        }
    }

    // MARK: - Accessibility wording

    /// What VoiceOver reads for a marker: its number and the note, or a plain
    /// statement that it has none yet — "Marker 3" alone would leave the
    /// listener wondering whether the description failed to load.
    private func accessibilityLabel(for pin: Pin) -> String {
        let note = pin.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.isEmpty == false else {
            return String(localized: "a11y.marker.untitled", defaultValue: "Marker \(pin.number), no description")
        }
        return String(localized: "a11y.marker", defaultValue: "Marker \(pin.number): \(note)")
    }

    /// Where the marker sits, as whole percentages of the image. Spelled out in
    /// words rather than with a percent sign, which VoiceOver reads unevenly
    /// depending on the voice.
    private func accessibilityPosition(of pin: Pin) -> String {
        let x = Int((pin.position.x * 100).rounded())
        let y = Int((pin.position.y * 100).rounded())
        return String(localized: "a11y.marker.position",
                      defaultValue: "\(x) percent from the left, \(y) percent from the top")
    }

    private func accessibilityLabel(for shape: Markup) -> String {
        switch shape.kind {
        case .arrow: return String(localized: "a11y.shape.arrow", defaultValue: "Arrow annotation")
        case .rectangle: return String(localized: "a11y.shape.rectangle", defaultValue: "Rectangle annotation")
        }
    }

    /// Drag-to-move a pin. Translation-based so grabbing anywhere on the marker
    /// (e.g. the head of a pointer whose anchor is the tip) never makes it jump.
    ///
    /// The whole gesture is one undo entry: the pre-drag state is captured on
    /// the first event and recorded on release. A plain click (this gesture has
    /// no minimum distance) moves nothing, so it records nothing.
    private func pinDrag(_ pin: Binding<Pin>, in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartPosition == nil {
                    flushTextEdit()
                    dragUndoSnapshot = snapshot()
                    dragStartPosition = pin.wrappedValue.position
                }
                selectPin(pin.wrappedValue.id)
                let base = dragStartPosition ?? pin.wrappedValue.position
                pin.wrappedValue.position = clamp01(CGPoint(
                    x: base.x + value.translation.width / fitted.width,
                    y: base.y + value.translation.height / fitted.height
                ))
            }
            .onEnded { _ in
                dragStartPosition = nil
                guard let before = dragUndoSnapshot else { return }
                dragUndoSnapshot = nil
                if snapshot() != before { history.record(before) }
            }
    }

    /// One drag gesture for the whole canvas, branching on the active tool. A
    /// zero-distance drag also captures plain clicks (used to drop pins). No-ops
    /// while cropping — the CropOverlay owns interaction in that mode.
    private func canvasGesture(in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isCropping else { return }
                switch tool {
                case .pin:
                    break
                case .arrow, .rectangle:
                    let kind: Markup.Kind = tool == .arrow ? .arrow : .rectangle
                    updateDraft(kind: kind, value: value, in: fitted)
                }
            }
            .onEnded { value in
                guard !isCropping else { return }
                switch tool {
                case .pin:
                    addPin(at: value.location, in: fitted)
                case .arrow, .rectangle:
                    commitDraft(value: value, in: fitted)
                }
            }
    }

    @ViewBuilder
    private func markupView(_ shape: Markup, in fitted: CGRect, metrics: MarkupMetrics,
                            selected: Bool) -> some View {
        // The stroke the export will use, thickened while selected — that part
        // is an editor affordance and never reaches the exported image.
        let width = metrics.lineWidth * (selected ? Self.selectedStrokeBoost : 1)
        switch shape.kind {
        case .rectangle:
            let r = absoluteRect(shape.rect, in: fitted)
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .stroke(Color.pinpointVermillon, lineWidth: width)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
        case .arrow:
            ArrowShape(
                start: absolutePoint(shape.start, in: fitted),
                end: absolutePoint(shape.end, in: fitted),
                headLength: metrics.arrowHeadLength
            )
            .stroke(Color.pinpointVermillon, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
    }

    // MARK: - Shape manipulation

    /// Width of the invisible band that makes a shape's outline clickable.
    /// A floor, not the whole story: `grabBandWidth(_:)` widens it when the
    /// stroke it has to cover is wider still.
    private static let shapeGrabBand: CGFloat = 14

    /// The grab band actually used, never narrower than the outline it covers —
    /// a small capture blown up to fill the canvas draws strokes far thicker
    /// than 14 pt, and a band thinner than its own outline would leave the
    /// middle of the stroke unclickable.
    private static func grabBandWidth(_ metrics: MarkupMetrics) -> CGFloat {
        max(shapeGrabBand, metrics.lineWidth * 2)
    }

    /// Floor on a marker's grab area. Badges scale with the preview now, so a
    /// large capture in a small window draws them genuinely small: the dot
    /// stays faithful to the export while the area you can grab it by doesn't
    /// shrink past what a pointer can hit — the same split `shapeHandleSize` /
    /// `shapeHandleHitSize` already make for handles.
    private static let pinGrabSize: CGFloat = 24

    /// How much heavier a selected shape's outline is drawn. Editor-only: the
    /// export always renders `MarkupMetrics.lineWidth`.
    private static let selectedStrokeBoost: CGFloat = 1.4

    /// Visible diameter of a manipulation handle, and the larger square that
    /// actually takes the click — the dots are small, the grab area is not
    /// (`RegionSelectionView` is equally generous with its 10pt tolerance).
    private static let shapeHandleSize: CGFloat = 9
    private static let shapeHandleHitSize: CGFloat = 20
    /// Floor on a rectangle's on-screen sides while resizing. Small enough to
    /// stay under anything `commitDraft` lets through, so touching a handle can
    /// never inflate a shape that was already committed.
    private static let shapeMinSide: CGFloat = 6

    private var selectedShape: Markup? {
        shapes.first { $0.id == selectedShapeID }
    }

    /// Whether a shape currently takes clicks on the canvas.
    ///
    /// The rule, chosen deliberately: a shape is manipulable exactly when the
    /// tool that draws it is active — the same rule markers already follow, so
    /// every tool owns its own objects and ⌘1/⌘2/⌘3 remain the single switch for
    /// "what am I working on". A dedicated selection tool was the other option;
    /// it would add a fourth segment and a mode to leave, to save one keystroke
    /// in the only case where the rules differ (re-editing a shape whose tool
    /// isn't the current one). Inert while cropping, like undo/redo: the crop
    /// overlay is modal and owns interaction.
    private func isManipulable(_ shape: Markup) -> Bool {
        guard !isCropping else { return false }
        switch shape.kind {
        case .arrow: return tool == .arrow
        case .rectangle: return tool == .rectangle
        }
    }

    /// The clickable band along a shape's outline. Deliberately not its
    /// interior: a rectangle annotation is mostly hole, and clicking through it
    /// has to keep dropping markers and drawing new shapes.
    @ViewBuilder
    private func shapeGrabBand(_ shape: Markup, in fitted: CGRect, metrics: MarkupMetrics) -> some View {
        let band = Self.grabBandWidth(metrics)
        Group {
            switch shape.kind {
            case .rectangle:
                let r = absoluteRect(shape.rect, in: fitted)
                Color.clear
                    .frame(width: r.width, height: r.height)
                    .contentShape(OutlineHitShape(base: RoundedRectangle(cornerRadius: metrics.cornerRadius),
                                                  width: band))
                    .position(x: r.midX, y: r.midY)
            case .arrow:
                // Sized to the arrow's bounding box, band included, and the
                // endpoints re-expressed inside it: `ArrowShape` draws in
                // whatever space it is handed, and a view no larger than the
                // shape keeps the hover cursor off the rest of the canvas.
                let a = absolutePoint(shape.start, in: fitted)
                let b = absolutePoint(shape.end, in: fitted)
                // The head splays out sideways from the tip, so the box is
                // grown by its length as well as by the band — otherwise a
                // scaled-up arrowhead would stick out of the view holding its
                // own hit shape. `contentShape` still narrows the clickable
                // area back down to the outline itself.
                let margin = band + metrics.arrowHeadLength
                let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                 width: abs(b.x - a.x), height: abs(b.y - a.y))
                    .insetBy(dx: -margin, dy: -margin)
                Color.clear
                    .frame(width: box.width, height: box.height)
                    .contentShape(OutlineHitShape(
                        base: ArrowShape(start: CGPoint(x: a.x - box.minX, y: a.y - box.minY),
                                         end: CGPoint(x: b.x - box.minX, y: b.y - box.minY),
                                         headLength: metrics.arrowHeadLength),
                        width: band
                    ))
                    .position(x: box.midX, y: box.midY)
            }
        }
        .gesture(shapeMoveDrag(shape, in: fitted))
        .hoverCursor(.openHand)
    }

    /// The handles of the selected shape: the two endpoints of an arrow (so a
    /// mis-aimed one gets re-aimed instead of redrawn), the eight box handles of
    /// a rectangle — `SelectionHandle`, the same geometry the capture overlay
    /// uses, read in SwiftUI's top-left orientation.
    @ViewBuilder
    private func shapeHandles(_ shape: Markup, in fitted: CGRect) -> some View {
        switch shape.kind {
        case .arrow:
            ForEach(ArrowEnd.allCases, id: \.self) { end in
                handleDot(at: absolutePoint(end.point(of: shape), in: fitted),
                          cursor: .crosshair,
                          label: end.accessibilityLabel)
                    .gesture(arrowEndDrag(shape, end: end, in: fitted))
            }
        case .rectangle:
            let r = absoluteRect(shape.rect, in: fitted)
            ForEach(SelectionHandle.allCases, id: \.self) { handle in
                handleDot(at: handle.point(in: r, orientation: .yDown),
                          cursor: handle.cursor,
                          label: handle.spot.resizeLabel)
                    .gesture(rectangleResizeDrag(shape, handle: handle, in: fitted))
            }
        }
    }

    /// One handle dot, styled like the crop overlay's so the two read as the
    /// same control. The outer frame is the grab area, the inner one the dot.
    private func handleDot(at point: CGPoint, cursor: NSCursor, label: String) -> some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().stroke(Color.pinpointVermillon, lineWidth: 2)
        }
        .frame(width: Self.shapeHandleSize, height: Self.shapeHandleSize)
        .frame(width: Self.shapeHandleHitSize, height: Self.shapeHandleHitSize)
        .contentShape(Rectangle())
        .position(point)
        .hoverCursor(cursor)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    // MARK: Shape gestures

    /// Shared prologue for every shape gesture: on the drag's first event it
    /// closes any typing session, captures the pre-gesture state for undo and
    /// the shape as it was, and selects it. Returns that pre-gesture copy, which
    /// every mutation below applies the gesture's cumulative translation to.
    private func beginShapeDrag(_ shape: Markup) -> Markup {
        if shapeDragOrigin == nil {
            flushTextEdit()
            dragUndoSnapshot = snapshot()
            shapeDragOrigin = shape
        }
        selectShape(shape.id)
        return shapeDragOrigin ?? shape
    }

    /// Closes a shape gesture and records it as a single undo entry — nothing at
    /// all when the drag was really a click, since selecting isn't an edit. Same
    /// bookkeeping as `pinDrag`, which is why the two share `dragUndoSnapshot`:
    /// only one gesture can be in flight at a time.
    private func endShapeDrag() {
        shapeDragOrigin = nil
        guard let before = dragUndoSnapshot else { return }
        dragUndoSnapshot = nil
        if snapshot() != before { history.record(before) }
    }

    /// Writes a mutated shape back in place, if it is still there — an undo can
    /// take it away mid-gesture.
    private func replaceShape(_ shape: Markup) {
        guard let index = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        shapes[index] = shape
    }

    /// Drag anywhere on a shape's outline to move it.
    private func shapeMoveDrag(_ shape: Markup, in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = beginShapeDrag(shape)
                replaceShape(translated(origin, by: value.translation, in: fitted))
            }
            .onEnded { _ in endShapeDrag() }
    }

    /// Drag one of a rectangle's eight handles to resize it.
    private func rectangleResizeDrag(_ shape: Markup, handle: SelectionHandle,
                                     in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = beginShapeDrag(shape)
                // Resized on screen, against the fitted image as bounds: that
                // keeps the minimum side isotropic and the result inside 0...1
                // without a second clamp fighting the first.
                let resized = handle.resize(
                    absoluteRect(origin.rect, in: fitted),
                    dx: value.translation.width,
                    dy: value.translation.height,
                    minSide: Self.shapeMinSide,
                    in: fitted,
                    orientation: .yDown
                )
                var moved = origin
                // Re-anchored to the box corners: `Markup.rect` is
                // order-independent and the exporter reads rectangles through
                // it, so which corner is `start` carries no meaning to lose.
                moved.start = clamp01(normalize(CGPoint(x: resized.minX, y: resized.minY), in: fitted))
                moved.end = clamp01(normalize(CGPoint(x: resized.maxX, y: resized.maxY), in: fitted))
                replaceShape(moved)
            }
            .onEnded { _ in endShapeDrag() }
    }

    /// Drag an arrow's tail or tip to re-aim it. Same arithmetic as `pinDrag`:
    /// one free point following the cursor, clamped to the image.
    private func arrowEndDrag(_ shape: Markup, end: ArrowEnd, in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = beginShapeDrag(shape)
                let base = end.point(of: origin)
                let point = clamp01(CGPoint(
                    x: base.x + value.translation.width / fitted.width,
                    y: base.y + value.translation.height / fitted.height
                ))
                var moved = origin
                switch end {
                case .tail: moved.start = point
                case .tip: moved.end = point
                }
                replaceShape(moved)
            }
            .onEnded { _ in endShapeDrag() }
    }

    /// Moves both defining points by the same on-screen translation, sliding the
    /// shape back inside the image when it runs out. Clamping each point on its
    /// own would squash the shape against the edge instead of stopping it, which
    /// is exactly what `SelectionHandle.moved` already solves for the bounding
    /// box — the effective delta it produces is then applied to both points.
    private func translated(_ shape: Markup, by translation: CGSize, in fitted: CGRect) -> Markup {
        guard fitted.width > 0, fitted.height > 0 else { return shape }
        let box = absoluteRect(shape.rect, in: fitted)
        let moved = SelectionHandle.moved(box, dx: translation.width, dy: translation.height, in: fitted)
        let dx = (moved.minX - box.minX) / fitted.width
        let dy = (moved.minY - box.minY) / fitted.height
        var out = shape
        out.start = clamp01(CGPoint(x: shape.start.x + dx, y: shape.start.y + dy))
        out.end = clamp01(CGPoint(x: shape.end.x + dx, y: shape.end.y + dy))
        return out
    }

    // MARK: - Side panel

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    pinsSection
                    if !shapes.isEmpty { shapesSection }
                }
            }

            Divider()

            Text("Instructions for the agent")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            TextEditor(text: $context)
                .focused($focusedField, equals: .context)
                .font(.body)
                .accessibilityLabel(String(localized: "Instructions for the agent"))
                .frame(minHeight: 70, maxHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            Button(action: copy) {
                Label(didCopy ? String(localized: "Copied!") : String(localized: "Copy for the agent"),
                      systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.pinpointVermillon)
            .keyboardShortcut("c", modifiers: [.command])

            Button(action: save) {
                Label(String(localized: "Save image…"), systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: [.command])
        }
        .padding(14)
    }

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Markers")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if pins.isEmpty {
                Text("Click the image to drop a numbered marker.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($pins) { $pin in
                    pinRow($pin)
                }
            }
        }
    }

    private var shapesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Annotations")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(shapes) { shape in
                shapeRow(shape)
            }
        }
    }

    private func pinRow(_ pin: Binding<Pin>) -> some View {
        let number = pin.wrappedValue.number
        let isSelected = pin.wrappedValue.id == selectedPinID
        let deleteLabel = String(localized: "a11y.marker.delete", defaultValue: "Delete marker \(number)")

        return HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: pinBadgeSide, height: pinBadgeSide)
                .background(Circle().fill(Color.pinpointVermillon))
                // The number is repeated in the field's label right after it,
                // so VoiceOver reads it once instead of twice.
                .accessibilityHidden(true)

            TextField("Describe this marker…", text: pin.note)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .note(pin.wrappedValue.id))
                // Without this the placeholder is the label, and every field in
                // the list announces itself identically.
                .accessibilityLabel(String(localized: "a11y.marker.note",
                                           defaultValue: "Description of marker \(number)"))

            Button {
                removePin(pin.wrappedValue)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(deleteLabel)
            .help(deleteLabel)
        }
        .padding(6)
        .background(rowSelectionBackground(isSelected))
        .onTapGesture { selectPin(pin.wrappedValue.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // `onTapGesture` is a mouse affordance and nothing else; the same
        // selection has to be reachable from VoiceOver's actions menu.
        .accessibilityAction { selectPin(pin.wrappedValue.id) }
    }

    /// Highlight for the selected row of the side panel.
    ///
    /// A 12 % tint on its own barely separated from the panel background, and
    /// carried the whole "this one is selected" message in hue alone. The fill
    /// is stronger now and an outline says the same thing as a shape, so the
    /// row still reads as selected without relying on colour perception.
    private func rowSelectionBackground(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.pinpointVermillon.opacity(0.20) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.pinpointVermillon.opacity(isSelected ? 0.75 : 0), lineWidth: 1.5)
            )
    }

    private func shapeRow(_ shape: Markup) -> some View {
        let isSelected = shape.id == selectedShapeID
        let deleteLabel = String(localized: "a11y.shape.delete", defaultValue: "Delete this annotation")

        return HStack(spacing: 8) {
            Image(systemName: shape.symbol)
                .foregroundStyle(Color.pinpointVermillon)
                .frame(width: pinBadgeSide, height: pinBadgeSide)
                .accessibilityHidden(true)

            Text(shape.label)

            Spacer()

            Button {
                removeShape(shape)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(deleteLabel)
            .help(deleteLabel)
        }
        .padding(6)
        .background(rowSelectionBackground(isSelected))
        .onTapGesture { selectShape(shape.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction { selectShape(shape.id) }
    }

    // MARK: - Actions

    private func addPin(at location: CGPoint, in fitted: CGRect) {
        let p = normalize(location, in: fitted)
        guard (0...1).contains(p.x), (0...1).contains(p.y) else { return }
        // Drawing on the canvas ends any typing session, so ⌘Z (and ⌫) go back
        // to acting on the annotations instead of on the field editor.
        focusedField = nil
        withUndo {
            let pin = Pin(number: pins.count + 1, position: p)
            pins.append(pin)
            selectPin(pin.id)
        }
    }

    private func updateDraft(kind: Markup.Kind, value: DragGesture.Value, in fitted: CGRect) {
        let start = clamp01(normalize(value.startLocation, in: fitted))
        let end = clamp01(normalize(value.location, in: fitted))
        if draft == nil {
            selectedPinID = nil
            selectedShapeID = nil
            draft = Markup(kind: kind, start: start, end: end)
        } else {
            draft?.end = end
        }
    }

    private func commitDraft(value: DragGesture.Value, in fitted: CGRect) {
        defer { draft = nil }
        guard var shape = draft else { return }
        shape.end = clamp01(normalize(value.location, in: fitted))
        // Ignore accidental micro-drags.
        guard hypot(shape.end.x - shape.start.x, shape.end.y - shape.start.y) > 0.01 else { return }
        focusedField = nil   // see `addPin`
        withUndo {
            shapes.append(shape)
            selectShape(shape.id)
        }
    }

    private func selectPin(_ id: Pin.ID) {
        selectedPinID = id
        selectedShapeID = nil
    }

    private func selectShape(_ id: Markup.ID) {
        selectedShapeID = id
        selectedPinID = nil
    }

    private var hasSelection: Bool {
        selectedPinID != nil || selectedShapeID != nil
    }

    /// Removes whatever is currently selected, from wherever it was selected —
    /// canvas or side panel. `removePin` already renumbers the remaining
    /// markers, and both removers clear the selection they consumed.
    private func deleteSelection() {
        guard !isCropping else { return }
        if let id = selectedPinID, let pin = pins.first(where: { $0.id == id }) {
            removePin(pin)
        } else if let id = selectedShapeID, let shape = shapes.first(where: { $0.id == id }) {
            removeShape(shape)
        }
    }

    private func removePin(_ pin: Pin) {
        withUndo {
            pins.removeAll { $0.id == pin.id }
            // Renumber so the list stays 1..n.
            for index in pins.indices { pins[index].number = index + 1 }
            if selectedPinID == pin.id { selectedPinID = nil }
        }
    }

    private func removeShape(_ shape: Markup) {
        withUndo {
            shapes.removeAll { $0.id == shape.id }
            if selectedShapeID == shape.id { selectedShapeID = nil }
        }
    }

    private func copy() {
        guard Exporter.copyToPasteboard(base: image, pins: pins, shapes: shapes, context: context,
                                        style: pinStyle, includeLegend: includeLegend) else {
            exportError = String(localized: "Nothing was written to the clipboard. The annotated image couldn’t be rendered.")
            return
        }
        onPersist(pins, shapes, context, image)

        // The clipboard is only half of it. An agent that can’t render a pasted
        // image — Claude Code being the case that started this — still reads the
        // file triplet by path, so every copy also writes it to disk. Surfaced
        // on failure rather than swallowed: announcing “Copied!” for a handoff
        // that never landed is exactly what #38 stopped doing elsewhere.
        do {
            try FileHandoff.write(base: image, pins: pins, shapes: shapes,
                                  context: context, style: pinStyle)
        } catch {
            exportError = String(
                localized: "handoff.error.body",
                defaultValue: "The capture was copied to the clipboard, but the files for the agent couldn’t be written to \(FileHandoff.latestDirectory.path): \(error.localizedDescription)"
            )
            return
        }

        withMotion { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withMotion { didCopy = false }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Pinpoint.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Full resolution here (no cap): the file is meant to be attached/kept,
        // unlike the pasteboard image which is downscaled to stay pasteable.
        guard let png = Exporter.pngData(base: image, pins: pins, shapes: shapes, context: context,
                                         style: pinStyle, includeLegend: includeLegend, maxDimension: nil) else {
            exportError = String(localized: "The annotated image couldn’t be rendered.")
            return
        }
        do {
            try png.write(to: url)
        } catch {
            exportError = error.localizedDescription
            return
        }
        onPersist(pins, shapes, context, image)
    }

    // MARK: - Undo / redo

    /// Runs `body` animated, or plainly when the system asks for reduced
    /// motion. Every animated state change in the editor goes through this, so
    /// honouring the setting stays one decision instead of one per call site —
    /// and the animations themselves are left intact for everyone else.
    private func withMotion<Result>(_ animation: Animation = .default, _ body: () -> Result) -> Result {
        reduceMotion ? body() : withAnimation(animation, body)
    }

    private func snapshot() -> EditorSnapshot {
        EditorSnapshot(
            image: image,
            pins: pins,
            shapes: shapes,
            context: context,
            selectedPinID: selectedPinID,
            selectedShapeID: selectedShapeID
        )
    }

    /// Runs an editing action as one undo step.
    ///
    /// The pre-action state is compared to the post-action state and only
    /// recorded if the document actually changed, so every caller can keep its
    /// own guards and early returns without also having to reason about the
    /// history. Not re-entrant: wrap the innermost mutation only, or a single
    /// user action lands on the stack twice (`deleteSelection` delegates to
    /// `removePin`/`removeShape`, which are the wrapped ones).
    private func withUndo(_ body: () -> Void) {
        flushTextEdit()
        let before = snapshot()
        body()
        guard snapshot() != before else { return }
        history.record(before)
    }

    /// Closes the current typing session, if any, and folds it into one undo
    /// entry.
    ///
    /// Marker notes and the instructions field are edited through AppKit text
    /// controls that already own a per-keystroke undo stack. Rather than run a
    /// second stack against them, the editor stays out of the way while a field
    /// has focus (⌘Z goes to the field editor) and records the whole editing
    /// session as a single entry once focus moves on — so ⌘Z outside a field
    /// steps over "typed a note", not over one character at a time.
    private func flushTextEdit() {
        guard let before = textEditSnapshot else { return }
        let now = snapshot()
        // A session interrupted by another undoable action restarts from the
        // state that action is about to build on, so the two never overlap.
        textEditSnapshot = focusedField != nil ? now : nil
        if now != before { history.record(before) }
    }

    /// Both steps are inert while cropping: the crop overlay is modal and has
    /// its own Cancel, and `cropRect` isn't part of the history.
    private func undo() {
        guard !isCropping else { return }
        flushTextEdit()
        let current = snapshot()
        guard let previous = history.undo(current: current) else { return }
        restore(previous)
    }

    private func redo() {
        guard !isCropping else { return }
        flushTextEdit()
        let current = snapshot()
        guard let next = history.redo(current: current) else { return }
        restore(next)
    }

    private func restore(_ state: EditorSnapshot) {
        // Drop anything half-finished: a snapshot never contains a live draft
        // or an in-flight drag.
        draft = nil
        dragStartPosition = nil
        dragUndoSnapshot = nil
        shapeDragOrigin = nil

        image = state.image
        pins = state.pins
        shapes = state.shapes
        context = state.context
        // Selection travels with the snapshot, but is re-validated against the
        // restored arrays: it must never point at something that isn't there.
        selectedPinID = state.pins.contains { $0.id == state.selectedPinID } ? state.selectedPinID : nil
        selectedShapeID = state.shapes.contains { $0.id == state.selectedShapeID } ? state.selectedShapeID : nil
        // The restored text is the baseline for whatever gets typed next.
        textEditSnapshot = focusedField != nil ? snapshot() : nil
    }

    // MARK: - Crop

    private func enterCropMode() {
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        selectedPinID = nil
        selectedShapeID = nil
        withMotion(.easeInOut(duration: 0.15)) { isCropping = true }
    }

    private func cancelCrop() {
        withMotion(.easeInOut(duration: 0.15)) { isCropping = false }
    }

    /// Undoable wrapper around `performCrop()`. `isCropping` isn't part of a
    /// snapshot, so the early-outs below — identity crop, unreadable image —
    /// change nothing and record nothing.
    private func applyCrop() {
        withUndo { performCrop() }
    }

    /// Applies the current crop rect to the base image and remaps annotations
    /// into the cropped frame. No-op if the rect covers ~the whole image.
    private func performCrop() {
        let c = cropRect
        // Treat as no-op when within epsilon of the full image, so the user can
        // hit Done on the default rect without an identity crop round-trip.
        if abs(c.minX) < 0.001 && abs(c.minY) < 0.001
            && abs(c.width - 1) < 0.001 && abs(c.height - 1) < 0.001 {
            withMotion(.easeInOut(duration: 0.15)) { isCropping = false }
            return
        }
        guard c.width > 0, c.height > 0,
              let base = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            withMotion(.easeInOut(duration: 0.15)) { isCropping = false }
            return
        }

        // Normalized (top-left) → pixel rect (CGImage is also top-left → no flip).
        let W = CGFloat(base.width)
        let H = CGFloat(base.height)
        let px = CGRect(
            x: floor(c.minX * W),
            y: floor(c.minY * H),
            width:  ceil(c.width  * W),
            height: ceil(c.height * H)
        ).intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard px.width > 1, px.height > 1,
              let cropped = base.cropping(to: px) else {
            withMotion(.easeInOut(duration: 0.15)) { isCropping = false }
            return
        }

        let newImage = NSImage(
            cgImage: cropped,
            size: NSSize(width: cropped.width, height: cropped.height)   // size == pixels
        )

        // Remap each annotation into the cropped frame: normalized coords scale
        // by (p − origin)/size. Drop anything that no longer lands inside.
        let origin = CGPoint(x: c.minX, y: c.minY)
        let size   = CGSize(width: c.width, height: c.height)
        func remap(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - origin.x) / size.width, y: (p.y - origin.y) / size.height)
        }
        func inside(_ p: CGPoint) -> Bool {
            (0...1).contains(p.x) && (0...1).contains(p.y)
        }

        var newPins: [Pin] = []
        for pin in pins {
            let q = remap(pin.position)
            guard inside(q) else { continue }
            newPins.append(Pin(id: pin.id, number: pin.number, position: q, note: pin.note))
        }
        var newShapes: [Markup] = []
        for shape in shapes {
            let s = remap(shape.start)
            let e = remap(shape.end)
            // Keep a markup iff at least one defining point survives the crop.
            // Midpoint-or-endpoint rule; straddlers keep what's inside.
            guard inside(s) || inside(e) || inside(CGPoint(x: (s.x+e.x)/2, y: (s.y+e.y)/2)) else { continue }
            newShapes.append(
                Markup(id: shape.id, kind: shape.kind, start: clamp01(s), end: clamp01(e))
            )
        }

        image = newImage
        pins = newPins
        shapes = newShapes
        selectedPinID = nil
        selectedShapeID = nil
        withMotion(.easeInOut(duration: 0.15)) { isCropping = false }
    }

    // MARK: - Geometry

    private func normalize(_ point: CGPoint, in fitted: CGRect) -> CGPoint {
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - fitted.minX) / fitted.width,
            y: (point.y - fitted.minY) / fitted.height
        )
    }

    private func clamp01(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    private func absolutePoint(_ p: CGPoint, in fitted: CGRect) -> CGPoint {
        CGPoint(x: fitted.minX + p.x * fitted.width, y: fitted.minY + p.y * fitted.height)
    }

    /// Nudges a marker's anchor so its badge stays fully within the fitted image
    /// even when the point is near an edge. Only affects where the badge is
    /// drawn — `pin.position` is untouched — and mirrors `Exporter`'s clamping so
    /// the editor and the exported image agree.
    private func clampedMarkerAnchor(_ anchor: CGPoint, in fitted: CGRect,
                                     metrics: MarkupMetrics) -> CGPoint {
        let side = metrics.badgeHalfSide  // circle half-width incl. ring
        let x = min(max(anchor.x, fitted.minX + side), max(fitted.minX + side, fitted.maxX - side))
        switch pinStyle {
        case .disc, .outline:
            let y = min(max(anchor.y, fitted.minY + side), max(fitted.minY + side, fitted.maxY - side))
            return CGPoint(x: x, y: y)
        case .pointer:
            // The marker sits with its tip at the anchor, extending upward.
            let top = fitted.minY + metrics.pointerHeight
            let y = min(max(anchor.y, top), max(top, fitted.maxY))
            return CGPoint(x: x, y: y)
        }
    }

    private func absoluteRect(_ r: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + r.minX * fitted.width,
            y: fitted.minY + r.minY * fitted.height,
            width: r.width * fitted.width,
            height: r.height * fitted.height
        )
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        let inset: CGFloat = 16
        let avail = CGSize(width: container.width - inset * 2, height: container.height - inset * 2)
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(avail.width / imageSize.width, avail.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}

/// Modal crop overlay rendered above the editor canvas. The crop rect is
/// normalized (0...1, top-left origin); `fitted` is the on-screen image rect.
/// Eight handles (4 corners + 4 edge midpoints) resize the rect; dragging
/// inside moves it. Free aspect ratio. Min size 5% per axis enforced.
///
/// Handle and interior drags track the previous translation in `@State`
/// (`lastMove`/`lastResize`) and apply only the incremental delta —
/// `DragGesture.translation` is cumulative from drag start, so applying it
/// directly against the mutating rect would accelerate (double-count earlier
/// deltas).
struct CropOverlay: View {
    @Binding var cropRect: CGRect
    let fitted: CGRect

    private let handleSize: CGFloat = 11
    private let minDim: CGFloat = 0.05

    // Previous translation for the in-progress interior/handle drag. Reset on
    // drag end; without this, DragGesture's cumulative translation would
    // double-count earlier deltas against the mutating cropRect.
    @State private var lastMove: CGSize = .zero
    @State private var lastResize: CGSize = .zero

    var body: some View {
        let r = absoluteRect(cropRect)
        ZStack(alignment: .topLeading) {
            // Dimmed exterior: 4 strips around the crop rect (even-odd mask).
            Color.black.opacity(0.45)
                .mask(
                    Path { p in
                        p.addRect(fitted)
                        p.addRect(r)
                    }
                    .fill(style: FillStyle(eoFill: true))
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // Border + thirds grid inside the crop rect.
            ZStack {
                Rectangle().stroke(Color.pinpointVermillon, lineWidth: 2)
                thirds
            }
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // Interior drag → move the whole rect (clamped to the image). The
            // DragGesture translation is cumulative from drag start, so we keep
            // the previous translation in @State and apply only the delta
            // (otherwise the rect accelerates). Reset on drag end.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(0, r.width - handleSize), height: max(0, r.height - handleSize))
                .position(x: r.midX, y: r.midY)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let dx = (v.translation.width - lastMove.width) / fitted.width
                            let dy = (v.translation.height - lastMove.height) / fitted.height
                            move(dx: dx, dy: dy)
                            lastMove = v.translation
                        }
                        .onEnded { _ in lastMove = .zero }
                )
                .accessibilityLabel(String(localized: "a11y.crop.move",
                                           defaultValue: "Drag to move the crop area"))

            // 8 handles.
            ForEach(Handle.allCases) { h in
                handleView(h, in: r)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "a11y.crop.overlay", defaultValue: "Crop area"))
    }

    /// Two thirds lines each way, thin and semi-transparent.
    private var thirds: some View {
        Canvas { ctx, size in
            var path = Path()
            for i in 1...2 {
                let x = size.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func handleView(_ h: Handle, in r: CGRect) -> some View {
        let p = h.point(in: r)
        ZStack {
            Circle().fill(Color.white)
            Circle().stroke(Color.pinpointVermillon, lineWidth: 2)
        }
        .frame(width: handleSize, height: handleSize)
        .position(p)
        .accessibilityLabel(h.spot.resizeLabel)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    // Translation is cumulative from drag start; apply only the
                    // delta since the previous event (see interior drag above).
                    let dx = (v.translation.width - lastResize.width) / fitted.width
                    let dy = (v.translation.height - lastResize.height) / fitted.height
                    resize(h, dx: dx, dy: dy)
                    lastResize = v.translation
                }
                .onEnded { _ in lastResize = .zero }
        )
    }

    // MARK: - Crop-rect mutation

    /// Moves the whole rect by a normalized delta, clamped to the image.
    private func move(dx: CGFloat, dy: CGFloat) {
        var r = cropRect
        r.origin.x = min(max(0, r.origin.x + dx), max(0, 1 - r.width))
        r.origin.y = min(max(0, r.origin.y + dy), max(0, 1 - r.height))
        cropRect = r
    }

    /// Resizes the rect by a normalized delta applied to the edges the given
    /// handle owns (a corner moves two edges, an edge handle moves one). Builds
    /// the new rect from explicit x/y/width/height so it stays valid (CGRect's
    /// minX/maxX are read-only). Enforces `minDim` and clamps to the image.
    private func resize(_ handle: Handle, dx: CGFloat, dy: CGFloat) {
        var x = cropRect.minX
        var y = cropRect.minY
        var w = cropRect.width
        var h = cropRect.height

        switch handle {
        case .topLeft, .left, .bottomLeft:
            let nx = min(max(0, x + dx), x + w - minDim)
            w += x - nx
            x = nx
        default: break
        }
        switch handle {
        case .topRight, .right, .bottomRight:
            w = max(minDim, min(x + w + dx, 1) - x)
        default: break
        }
        switch handle {
        case .topLeft, .top, .topRight:
            let ny = min(max(0, y + dy), y + h - minDim)
            h += y - ny
            y = ny
        default: break
        }
        switch handle {
        case .bottomLeft, .bottom, .bottomRight:
            h = max(minDim, min(y + h + dy, 1) - y)
        default: break
        }

        cropRect = CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Geometry

    private func absoluteRect(_ r: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + r.minX * fitted.width,
            y: fitted.minY + r.minY * fitted.height,
            width: r.width * fitted.width,
            height: r.height * fitted.height
        )
    }

    /// The 8 resize handles. `point(in:)` places each on screen.
    private enum Handle: String, CaseIterable, Identifiable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
        var id: String { rawValue }

        /// The shared VoiceOver naming, so a crop handle and a rectangle handle
        /// in the same corner are announced the same way.
        var spot: HandleSpot {
            switch self {
            case .topLeft: return .topLeft
            case .top: return .top
            case .topRight: return .topRight
            case .right: return .right
            case .bottomRight: return .bottomRight
            case .bottom: return .bottom
            case .bottomLeft: return .bottomLeft
            case .left: return .left
            }
        }

        func point(in r: CGRect) -> CGPoint {
            switch self {
            case .topLeft:     return CGPoint(x: r.minX, y: r.minY)
            case .top:         return CGPoint(x: r.midX, y: r.minY)
            case .topRight:    return CGPoint(x: r.maxX, y: r.minY)
            case .right:       return CGPoint(x: r.maxX, y: r.midY)
            case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
            case .bottom:      return CGPoint(x: r.midX, y: r.maxY)
            case .bottomLeft:  return CGPoint(x: r.minX, y: r.maxY)
            case .left:        return CGPoint(x: r.minX, y: r.midY)
            }
        }
    }
}

/// Straight line from `start` to `end` with an arrowhead at `end`. Uses
/// absolute coordinates (it ignores the layout rect), so it must fill the same
/// space as the canvas.
struct ArrowShape: Shape {
    var start: CGPoint
    var end: CGPoint
    /// Length of the two strokes forming the head. Supplied by the caller from
    /// `MarkupMetrics` rather than fixed here, so the preview's arrowhead is
    /// the one the export draws — see #48.
    var headLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let spread = MarkupMetrics.arrowHeadSpread

        let leftAngle = angle - spread
        let rightAngle = angle + spread
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - headLength * cos(leftAngle), y: end.y - headLength * sin(leftAngle)))
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - headLength * cos(rightAngle), y: end.y - headLength * sin(rightAngle)))
        return path
    }
}

/// Another shape's outline thickened into a grab band, used as a
/// `contentShape` so a click lands on a stroke instead of on the empty area the
/// stroke encloses.
struct OutlineHitShape<Base: Shape>: Shape {
    var base: Base
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        base.path(in: rect)
            .strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

/// Shows `cursor` while the pointer is over the view.
///
/// Push/pop rather than `set()`: AppKit resets the cursor from the window's
/// tracking areas on every mouse move, and a bare `set()` loses that race. The
/// pushed state is tracked so a view that vanishes mid-hover — a handle whose
/// shape gets deselected, a shape an undo takes away, a tool switch retiring a
/// whole grab band — still balances its push.
private struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside {
                    guard !pushed else { return }
                    pushed = true
                    cursor.push()
                } else {
                    pop()
                }
            }
            .onDisappear(perform: pop)
    }

    private func pop() {
        guard pushed else { return }
        pushed = false
        NSCursor.pop()
    }
}

private extension View {
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursor(cursor: cursor))
    }
}

/// Map-pin silhouette filling its rect: a circular head at the top tapering to
/// a tip at the bottom-centre. Used for the `.pointer` marker style.
///
/// Everything is derived from the rect, so the caller sets the proportions: a
/// rect of `2r × 3r` puts the head's centre `2r` above the tip, which is what
/// `Exporter` draws for the same style.
struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let diameter = rect.width
        let radius = diameter / 2
        let headCenter = CGPoint(x: rect.midX, y: rect.minY + radius)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)

        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: diameter, height: diameter))
        let baseY = headCenter.y + radius * 0.55
        let halfWidth = radius * 0.7
        path.move(to: CGPoint(x: headCenter.x - halfWidth, y: baseY))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: headCenter.x + halfWidth, y: baseY))
        path.closeSubpath()
        return path
    }
}

/// The numbered marker, rendered in one of the three design-system styles.
///
/// Sized entirely from `MarkupMetrics`, which is what makes it the same badge
/// `Exporter.drawMarker` renders: it used to be a fixed 28 pt disc, so the
/// export of a small capture came out proportionally much heavier than the
/// preview that produced it (#48).
struct PinMarker: View {
    let number: Int
    let metrics: MarkupMetrics
    var style: PinStyle = .disc
    var selected: Bool = false

    /// Vertical offset to apply when positioning the marker so its anchor lands
    /// on the marked point: centred for disc/outline, tip-anchored for pointer.
    static func anchorYOffset(_ style: PinStyle, metrics: MarkupMetrics) -> CGFloat {
        style == .pointer ? -(metrics.pointerHeight / 2) : 0
    }

    /// The marker's laid-out size — its footprint on the canvas, which is also
    /// the grab area `EditorView` starts from before applying its own floor.
    static func size(_ style: PinStyle, metrics: MarkupMetrics) -> CGSize {
        CGSize(width: metrics.pinRadius * 2,
               height: style == .pointer ? metrics.pointerHeight : metrics.pinRadius * 2)
    }

    var body: some View {
        switch style {
        case .disc: disc
        case .outline: outline
        case .pointer: pointer
        }
    }

    private var headDiameter: CGFloat { metrics.pinRadius * 2 }

    /// The ring around the badge, drawn heavier while selected. The extra
    /// weight is an editor affordance only — the export always strokes
    /// `metrics.ringWidth`.
    private var ringWidth: CGFloat { metrics.ringWidth * (selected ? 1.4 : 1) }

    private var numberText: some View {
        Text("\(number)").font(.system(size: metrics.numberFontSize, weight: .bold))
    }

    private var disc: some View {
        numberText
            .foregroundStyle(.white)
            .frame(width: headDiameter, height: headDiameter)
            .background(Circle().fill(Color.pinpointVermillon))
            .overlay(Circle().stroke(.white, lineWidth: ringWidth))
            .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private var outline: some View {
        numberText
            .foregroundStyle(Color.pinpointVermillon)
            .frame(width: headDiameter, height: headDiameter)
            .overlay(Circle().stroke(.white, lineWidth: ringWidth * 1.7))
            .overlay(Circle().stroke(Color.pinpointVermillon, lineWidth: ringWidth))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
    }

    private var pointer: some View {
        ZStack(alignment: .top) {
            PinShape()
                .fill(Color.pinpointVermillon)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            Circle()
                .stroke(.white, lineWidth: ringWidth)
                .frame(width: headDiameter, height: headDiameter)
            numberText
                .foregroundStyle(.white)
                .frame(width: headDiameter, height: headDiameter)
        }
        .frame(width: headDiameter, height: metrics.pointerHeight)
    }
}
