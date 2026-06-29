import AppKit
import SwiftUI

struct ScreenshotCardView: View {
    let item: ScreenshotItem
    let title: String
    let width: CGFloat
    let isFavorite: Bool
    let isSelected: Bool
    let isActive: Bool
    let selectionMode: Bool
    let onActivate: () -> Void
    let onEditInPinpoint: () -> Void
    let onSetTitle: (String) -> Void
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void
    let onCopyImage: () -> Void
    let onCopyPath: () -> Void
    let onOpenDetails: () -> Void
    let onDelete: () -> Void
    let onQuickLook: () -> Void
    let onMove: () -> Void
    let onRename: () -> Void
    let onReveal: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @FocusState private var titleFieldFocused: Bool

    private var thumbnailWidth: CGFloat {
        max(width - 16, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary.opacity(0.35))

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: thumbnailWidth, height: 126)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: thumbnailWidth, height: 126)
            .frame(height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    if !selectionMode {
                        Button(action: onEditInPinpoint) {
                            Image(systemName: "pin.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .padding(.vertical, 8)
                                .padding(.leading, 8)
                        }
                        .buttonStyle(.plain)
                        .help("Edit in Pinpoint")
                    }

                    Menu {
                        Button("Edit in Pinpoint", systemImage: "pin.fill", action: onEditInPinpoint)
                        Divider()
                        Button("Open details", systemImage: "rectangle.portrait.and.arrow.right", action: onOpenDetails)
                        Divider()
                        Button("Quick Look", systemImage: "space", action: onQuickLook)
                        Divider()
                        Button(isFavorite ? String(localized: "Remove from favorites") : String(localized: "Add to favorites"), systemImage: isFavorite ? "star.slash" : "star", action: onToggleFavorite)
                        Divider()
                        Button("Copy image", systemImage: "doc.on.doc", action: onCopyImage)
                        Button("Copy file path", systemImage: "link", action: onCopyPath)
                        Divider()
                        Button("Edit title…", systemImage: "textformat", action: beginTitleEdit)
                        Button("Rename", systemImage: "pencil", action: onRename)
                        Button("Move", systemImage: "folder", action: onMove)
                        Button("Reveal in Finder", systemImage: "finder", action: onReveal)
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white, .black.opacity(0.45))
                            .padding(8)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .overlay(alignment: .topLeading) {
                if selectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary, isSelected ? Color.accentColor : .clear)
                        .padding(8)
                } else {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isFavorite ? .yellow : .secondary, .thinMaterial)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                titleView
                    .frame(width: thumbnailWidth, alignment: .leading)

                Text(item.createdAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: thumbnailWidth, alignment: .leading)
            }
            .frame(width: thumbnailWidth, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
        .padding(8)
        .background(selectionBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(activeBorderColor, lineWidth: isActive ? 2 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            onActivate()

            guard selectionMode else { return }
            onSelect()
        }
        .onTapGesture(count: 2) {
            onActivate()
            onOpenDetails()
        }
        .draggable(item.url) {
            dragPreview
        }
        .task(id: item.url) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: item.url)
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField("Title", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .semibold))
                .focused($titleFieldFocused)
                .onAppear { titleFieldFocused = true }
                .onSubmit(commitTitleEdit)
                .onExitCommand(perform: cancelTitleEdit)
                .onChange(of: titleFieldFocused) { _, focused in
                    if !focused { commitTitleEdit() }
                }
        } else {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: beginTitleEdit)
                .help("Double-click to edit the title")
        }
    }

    private func beginTitleEdit() {
        draftTitle = title
        isEditingTitle = true
    }

    private func commitTitleEdit() {
        guard isEditingTitle else { return }
        isEditingTitle = false
        onSetTitle(draftTitle)
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
    }

    private var selectionBackground: some ShapeStyle {
        isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear)
    }

    private var activeBorderColor: Color {
        isSelected ? .accentColor : .accentColor.opacity(0.7)
    }

    @ViewBuilder
    private var dragPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                }
            }
            .frame(width: 160, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.filename)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(width: 180)
    }
}

struct ScreenshotCardView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenshotCardView(
            item: PreviewSampleData.items.first!,
            title: PreviewSampleData.items.first!.filename,
            width: 220,
            isFavorite: true,
            isSelected: false,
            isActive: true,
            selectionMode: false,
            onActivate: {},
            onEditInPinpoint: {},
            onSetTitle: { _ in },
            onToggleFavorite: {},
            onSelect: {},
            onCopyImage: {},
            onCopyPath: {},
            onOpenDetails: {},
            onDelete: {},
            onQuickLook: {},
            onMove: {},
            onRename: {},
            onReveal: {}
        )
        .padding()
        .frame(width: 240)
    }
}
