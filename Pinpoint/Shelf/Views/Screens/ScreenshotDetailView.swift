import AppKit
import SwiftUI

struct ScreenshotDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ScreenshotStore

    let item: ScreenshotItem
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onQuickLook: () -> Void
    let onReveal: () -> Void
    let onCopyImage: () -> Void
    let onCopyPath: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    @State private var image: NSImage?
    @State private var metadata = ScreenshotDetailMetadata.empty
    @State private var renameValue = ""
    @State private var showsRenameSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    previewCard
                    metadataSection
                    actionsSection
                }
                .padding(20)
            }
        }
        .frame(width: 760, height: 620)
        .background(.background)
        .task(id: item.id) {
            await loadContent()
        }
        .sheet(isPresented: $showsRenameSheet) {
            RenameDetailView(
                filename: renameValue,
                onCancel: { showsRenameSheet = false },
                onSave: { newName in
                    store.rename(item, to: newName)
                    showsRenameSheet = false
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(item.url.deletingLastPathComponent().lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove Favorite" : "Favorite")

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(16)
    }

    private var previewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(.quaternary.opacity(0.22))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            } else {
                ProgressView()
                    .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                detailValue(title: "Captured", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                detailValue(title: "Dimensions", value: metadata.dimensionsText)
                detailValue(title: "Format", value: item.fileExtension.uppercased())
                detailValue(title: "File Size", value: metadata.fileSizeText)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 10) {
                Button("Quick Look", systemImage: "space", action: onQuickLook)
                Button("Reveal", systemImage: "finder", action: onReveal)
                Button("Copy Image", systemImage: "doc.on.doc", action: onCopyImage)
                Button("Copy Path", systemImage: "link", action: onCopyPath)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                Button("Rename", systemImage: "pencil") {
                    renameValue = item.filename
                    showsRenameSheet = true
                }
                Button("Move", systemImage: "folder", action: onMove)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    dismiss()
                    onDelete()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func detailValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadContent() async {
        image = NSImage(contentsOf: item.url)
        metadata = ScreenshotDetailMetadata(url: item.url, image: image)
    }
}

private struct ScreenshotDetailMetadata {
    let dimensionsText: String
    let fileSizeText: String

    static let empty = ScreenshotDetailMetadata(dimensionsText: "Loading…", fileSizeText: "Loading…")

    init(dimensionsText: String, fileSizeText: String) {
        self.dimensionsText = dimensionsText
        self.fileSizeText = fileSizeText
    }

    init(url: URL, image: NSImage?) {
        if let image {
            let size = image.size
            dimensionsText = "\(Int(size.width)) × \(Int(size.height))"
        } else {
            dimensionsText = "Unknown"
        }

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize {
            fileSizeText = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        } else {
            fileSizeText = "Unknown"
        }
    }
}

struct ScreenshotDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenshotDetailView(
            item: PreviewSampleData.items.first!,
            isFavorite: true,
            onToggleFavorite: {},
            onQuickLook: {},
            onReveal: {},
            onCopyImage: {},
            onCopyPath: {},
            onMove: {},
            onDelete: {}
        )
        .environmentObject(PreviewSampleData.store)
    }
}

private struct RenameDetailView: View {
    let filename: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var newName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Screenshot")
                .font(.title3.weight(.semibold))

            TextField("Filename", text: $newName)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(newName)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            newName = filename
            isFocused = true
        }
    }
}
