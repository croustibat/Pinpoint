import SwiftUI

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
}

struct EditorView: View {
    let image: NSImage
    var onClose: () -> Void
    /// Called with the current annotation state so it can be persisted to
    /// history (on copy and when the editor closes).
    var onPersist: ([Pin], [Markup], String) -> Void

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

    init(
        image: NSImage,
        initialPins: [Pin] = [],
        initialShapes: [Markup] = [],
        initialContext: String = "",
        onPersist: @escaping ([Pin], [Markup], String) -> Void = { _, _, _ in },
        onClose: @escaping () -> Void
    ) {
        self.image = image
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
        .onDisappear { onPersist(pins, shapes, context) }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolHint: String {
        switch tool {
        case .pin: return String(localized: "Click to drop a marker")
        case .arrow: return String(localized: "Drag to draw an arrow")
        case .rectangle: return String(localized: "Drag to draw a rectangle")
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let fitted = fittedRect(imageSize: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                    .shadow(radius: 8, y: 2)

                // Committed markups (display-only; selection happens in the panel).
                ForEach(shapes) { shape in
                    markupView(shape, in: fitted, selected: shape.id == selectedShapeID)
                }
                .allowsHitTesting(false)

                // Live preview while drawing.
                if let draft {
                    markupView(draft, in: fitted, selected: true)
                        .allowsHitTesting(false)
                        .opacity(0.9)
                }

                // Numbered pins.
                ForEach($pins) { $pin in
                    let anchor = absolutePoint(pin.position, in: fitted)
                    PinMarker(number: pin.number, style: pinStyle, selected: pin.id == selectedPinID)
                        .position(x: anchor.x, y: anchor.y + PinMarker.anchorYOffset(pinStyle))
                        .gesture(pinDrag($pin, in: fitted))
                        .allowsHitTesting(tool == .pin)
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(in: fitted))
        }
    }

    /// Drag-to-move a pin. Translation-based so grabbing anywhere on the marker
    /// (e.g. the head of a pointer whose anchor is the tip) never makes it jump.
    private func pinDrag(_ pin: Binding<Pin>, in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                selectPin(pin.wrappedValue.id)
                let base = dragStartPosition ?? pin.wrappedValue.position
                if dragStartPosition == nil { dragStartPosition = base }
                pin.wrappedValue.position = clamp01(CGPoint(
                    x: base.x + value.translation.width / fitted.width,
                    y: base.y + value.translation.height / fitted.height
                ))
            }
            .onEnded { _ in dragStartPosition = nil }
    }

    /// One drag gesture for the whole canvas, branching on the active tool. A
    /// zero-distance drag also captures plain clicks (used to drop pins).
    private func canvasGesture(in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch tool {
                case .pin:
                    break
                case .arrow, .rectangle:
                    let kind: Markup.Kind = tool == .arrow ? .arrow : .rectangle
                    updateDraft(kind: kind, value: value, in: fitted)
                }
            }
            .onEnded { value in
                switch tool {
                case .pin:
                    addPin(at: value.location, in: fitted)
                case .arrow, .rectangle:
                    commitDraft(value: value, in: fitted)
                }
            }
    }

    @ViewBuilder
    private func markupView(_ shape: Markup, in fitted: CGRect, selected: Bool) -> some View {
        let width: CGFloat = selected ? 5 : 3.5
        switch shape.kind {
        case .rectangle:
            let r = absoluteRect(shape.rect, in: fitted)
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.pinpointVermillon, lineWidth: width)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
        case .arrow:
            ArrowShape(
                start: absolutePoint(shape.start, in: fitted),
                end: absolutePoint(shape.end, in: fitted)
            )
            .stroke(Color.pinpointVermillon, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
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
            TextEditor(text: $context)
                .font(.body)
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
        }
        .padding(14)
    }

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Markers")
                .font(.headline)

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

            ForEach(shapes) { shape in
                shapeRow(shape)
            }
        }
    }

    private func pinRow(_ pin: Binding<Pin>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(pin.wrappedValue.number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.pinpointVermillon))

            TextField("Describe this marker…", text: pin.note)
                .textFieldStyle(.roundedBorder)

            Button {
                removePin(pin.wrappedValue)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(pin.wrappedValue.id == selectedPinID ? Color.pinpointVermillon.opacity(0.12) : Color.clear)
        )
        .onTapGesture { selectPin(pin.wrappedValue.id) }
    }

    private func shapeRow(_ shape: Markup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: shape.symbol)
                .foregroundStyle(Color.pinpointVermillon)
                .frame(width: 22, height: 22)

            Text(shape.label)

            Spacer()

            Button {
                removeShape(shape)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(shape.id == selectedShapeID ? Color.pinpointVermillon.opacity(0.12) : Color.clear)
        )
        .onTapGesture { selectShape(shape.id) }
    }

    // MARK: - Actions

    private func addPin(at location: CGPoint, in fitted: CGRect) {
        let p = normalize(location, in: fitted)
        guard (0...1).contains(p.x), (0...1).contains(p.y) else { return }
        let pin = Pin(number: pins.count + 1, position: p)
        pins.append(pin)
        selectPin(pin.id)
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
        shapes.append(shape)
        selectShape(shape.id)
    }

    private func selectPin(_ id: Pin.ID) {
        selectedPinID = id
        selectedShapeID = nil
    }

    private func selectShape(_ id: Markup.ID) {
        selectedShapeID = id
        selectedPinID = nil
    }

    private func removePin(_ pin: Pin) {
        pins.removeAll { $0.id == pin.id }
        // Renumber so the list stays 1..n.
        for index in pins.indices { pins[index].number = index + 1 }
        if selectedPinID == pin.id { selectedPinID = nil }
    }

    private func removeShape(_ shape: Markup) {
        shapes.removeAll { $0.id == shape.id }
        if selectedShapeID == shape.id { selectedShapeID = nil }
    }

    private func copy() {
        Exporter.copyToPasteboard(base: image, pins: pins, shapes: shapes, context: context,
                                  style: pinStyle, includeLegend: includeLegend)
        onPersist(pins, shapes, context)
        withAnimation { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { didCopy = false }
        }
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

/// Straight line from `start` to `end` with an arrowhead at `end`. Uses
/// absolute coordinates (it ignores the layout rect), so it must fill the same
/// space as the canvas.
struct ArrowShape: Shape {
    var start: CGPoint
    var end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 16
        let spread = CGFloat.pi / 6.5

        let leftAngle = angle - spread
        let rightAngle = angle + spread
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - headLength * cos(leftAngle), y: end.y - headLength * sin(leftAngle)))
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - headLength * cos(rightAngle), y: end.y - headLength * sin(rightAngle)))
        return path
    }
}

/// Map-pin silhouette filling its rect: a circular head at the top tapering to
/// a tip at the bottom-centre. Used for the `.pointer` marker style.
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
struct PinMarker: View {
    let number: Int
    var style: PinStyle = .disc
    var selected: Bool = false

    static let headDiameter: CGFloat = 28
    static let pointerHeight: CGFloat = 42

    /// Vertical offset to apply when positioning the marker so its anchor lands
    /// on the marked point: centred for disc/outline, tip-anchored for pointer.
    static func anchorYOffset(_ style: PinStyle) -> CGFloat {
        style == .pointer ? -(pointerHeight / 2) : 0
    }

    var body: some View {
        switch style {
        case .disc: disc
        case .outline: outline
        case .pointer: pointer
        }
    }

    private var numberText: some View {
        Text("\(number)").font(.system(size: 14, weight: .bold))
    }

    private var disc: some View {
        numberText
            .foregroundStyle(.white)
            .frame(width: Self.headDiameter, height: Self.headDiameter)
            .background(Circle().fill(Color.pinpointVermillon))
            .overlay(Circle().stroke(.white, lineWidth: selected ? 3.5 : 2.5))
            .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private var outline: some View {
        numberText
            .foregroundStyle(Color.pinpointVermillon)
            .frame(width: Self.headDiameter, height: Self.headDiameter)
            .overlay(Circle().stroke(.white, lineWidth: selected ? 5 : 4))
            .overlay(Circle().stroke(Color.pinpointVermillon, lineWidth: selected ? 3 : 2))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
    }

    private var pointer: some View {
        ZStack(alignment: .top) {
            PinShape()
                .fill(Color.pinpointVermillon)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            Circle()
                .stroke(.white, lineWidth: selected ? 3 : 2)
                .frame(width: Self.headDiameter, height: Self.headDiameter)
            numberText
                .foregroundStyle(.white)
                .frame(width: Self.headDiameter, height: Self.headDiameter)
        }
        .frame(width: Self.headDiameter, height: Self.pointerHeight)
    }
}
