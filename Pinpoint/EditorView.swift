import SwiftUI

struct EditorView: View {
    let image: NSImage
    var onClose: () -> Void

    @State private var pins: [Pin] = []
    @State private var context: String = ""
    @State private var selectedPinID: Pin.ID?
    @State private var didCopy = false

    var body: some View {
        HSplitView {
            canvas
                .frame(minWidth: 360, minHeight: 360)
                .layoutPriority(1)

            sidePanel
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 360)
        }
        .frame(minWidth: 680, minHeight: 420)
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

                ForEach($pins) { $pin in
                    PinMarker(number: pin.number, selected: pin.id == selectedPinID)
                        .position(
                            x: fitted.minX + pin.position.x * fitted.width,
                            y: fitted.minY + pin.position.y * fitted.height
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectedPinID = pin.id
                                    let nx = (value.location.x - fitted.minX) / fitted.width
                                    let ny = (value.location.y - fitted.minY) / fitted.height
                                    pin.position = CGPoint(
                                        x: min(max(nx, 0), 1),
                                        y: min(max(ny, 0), 1)
                                    )
                                }
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let nx = (value.location.x - fitted.minX) / fitted.width
                        let ny = (value.location.y - fitted.minY) / fitted.height
                        guard (0...1).contains(nx), (0...1).contains(ny) else { return }
                        let pin = Pin(number: pins.count + 1, position: CGPoint(x: nx, y: ny))
                        pins.append(pin)
                        selectedPinID = pin.id
                    }
            )
        }
    }

    // MARK: - Side panel

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repères")
                .font(.headline)

            if pins.isEmpty {
                Text("Clique sur l’image pour poser un repère numéroté.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($pins) { $pin in
                            pinRow($pin)
                        }
                    }
                }
            }

            Divider()

            Text("Instructions pour l’agent")
                .font(.headline)
            TextEditor(text: $context)
                .font(.body)
                .frame(minHeight: 70, maxHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            Spacer(minLength: 0)

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
                remove(pin.wrappedValue)
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
        .onTapGesture { selectedPinID = pin.wrappedValue.id }
    }

    // MARK: - Actions

    private func remove(_ pin: Pin) {
        pins.removeAll { $0.id == pin.id }
        // Renumber so the list stays 1..n.
        for index in pins.indices { pins[index].number = index + 1 }
    }

    private func copy() {
        Exporter.copyToPasteboard(base: image, pins: pins, context: context)
        withAnimation { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { didCopy = false }
        }
    }

    // MARK: - Geometry

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
