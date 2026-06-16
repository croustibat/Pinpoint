import SwiftUI

/// Annotation tools the user can switch between in the editor.
enum EditorTool: String, CaseIterable, Identifiable {
    case pin, arrow, rectangle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pin: return "Repère"
        case .arrow: return "Flèche"
        case .rectangle: return "Rectangle"
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

    @State private var pins: [Pin] = []
    @State private var shapes: [Markup] = []
    @State private var context: String = ""
    @State private var tool: EditorTool = .pin
    @State private var selectedPinID: Pin.ID?
    @State private var selectedShapeID: Markup.ID?
    @State private var draft: Markup?
    @State private var didCopy = false

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
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Outil", selection: $tool) {
                ForEach(EditorTool.allCases) { tool in
                    Label(tool.label, systemImage: tool.symbol).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Spacer()

            Text(toolHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolHint: String {
        switch tool {
        case .pin: return "Clique pour poser un repère"
        case .arrow: return "Glisse pour tracer une flèche"
        case .rectangle: return "Glisse pour tracer un rectangle"
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
                    PinMarker(number: pin.number, selected: pin.id == selectedPinID)
                        .position(
                            x: fitted.minX + pin.position.x * fitted.width,
                            y: fitted.minY + pin.position.y * fitted.height
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectPin(pin.id)
                                    pin.position = clamp01(normalize(value.location, in: fitted))
                                }
                        )
                        .allowsHitTesting(tool == .pin)
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(in: fitted))
        }
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
                .stroke(Color.accentColor, lineWidth: width)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
        case .arrow:
            ArrowShape(
                start: absolutePoint(shape.start, in: fitted),
                end: absolutePoint(shape.end, in: fitted)
            )
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
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

            Text("Instructions pour l’agent")
                .font(.headline)
            TextEditor(text: $context)
                .font(.body)
                .frame(minHeight: 70, maxHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            Button(action: copy) {
                Label(didCopy ? "Copié !" : "Copier pour l’agent",
                      systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: [.command])
        }
        .padding(14)
    }

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repères")
                .font(.headline)

            if pins.isEmpty {
                Text("Clique sur l’image pour poser un repère numéroté.")
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
                .background(Circle().fill(Color.accentColor))

            TextField("Décris ce repère…", text: pin.note)
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
                .fill(pin.wrappedValue.id == selectedPinID ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .onTapGesture { selectPin(pin.wrappedValue.id) }
    }

    private func shapeRow(_ shape: Markup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: shape.symbol)
                .foregroundStyle(Color.accentColor)
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
                .fill(shape.id == selectedShapeID ? Color.accentColor.opacity(0.12) : Color.clear)
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
        Exporter.copyToPasteboard(base: image, pins: pins, shapes: shapes, context: context)
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

        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - headLength * cos(angle - spread),
            y: end.y - headLength * sin(angle - spread)
        ))
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - headLength * cos(angle + spread),
            y: end.y - headLength * sin(angle + spread)
        ))
        return path
    }
}

struct PinMarker: View {
    let number: Int
    var selected: Bool = false

    var body: some View {
        Text("\(number)")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 2))
            .shadow(radius: 2, y: 1)
    }
}
