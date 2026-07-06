import AppKit
import SwiftUI

struct ShelfView: View {
    var onOpenSettings: () -> Void = {}
    var onOpenInPinpoint: (ScreenshotItem) -> Void = { _ in }
    var onOpenDetail: (ScreenshotItem) -> Void = { _ in }

    @EnvironmentObject private var store: ScreenshotStore
    @State private var renameTarget: ScreenshotItem?
    @State private var selectionMode = false
    @State private var selectedIDs = Set<URL>()
    @State private var activeItemID: URL?
    @State private var keyMonitor: Any?
    private let gridSpacing: CGFloat = 14
    private let gridPadding: CGFloat = 16
    private let gridColumnCount = 2

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .background(.background)
        .sheet(item: $renameTarget) { item in
            RenameScreenshotView(
                filename: item.filename,
                onCancel: { renameTarget = nil },
                onSave: { newName in
                    store.rename(item, to: newName)
                    renameTarget = nil
                }
            )
        }
        .onAppear(perform: installKeyboardMonitor)
        .onDisappear(perform: removeKeyboardMonitor)
        .onChange(of: visibleItems.map(\.id), initial: true) { _, _ in
            syncActiveItem()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shelf")
                        .font(.title3.weight(.semibold))

                    Text(store.watchedFolderURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectionMode {
                    Button("Done") {
                        selectionMode = false
                        selectedIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button("Select") {
                        selectionMode = true
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)

                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Menu {
                    ForEach(ScreenshotDateFilter.allCases) { filter in
                        Button {
                            store.selectedDateFilter = filter
                        } label: {
                            if store.selectedDateFilter == filter {
                                Label(filter.title, systemImage: "checkmark")
                            } else {
                                Text(filter.title)
                            }
                        }
                    }
                } label: {
                    Label(store.selectedDateFilter.title, systemImage: "calendar")
                }
                .menuStyle(.borderlessButton)

                Button {
                    store.showsFavoritesOnly.toggle()
                } label: {
                    Label("Favorites", systemImage: store.showsFavoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(store.showsFavoritesOnly ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Show favorites only")

                Spacer()

                Menu {
                    ForEach(ScreenshotSortOrder.allCases) { order in
                        Button {
                            store.selectedSortOrder = order
                        } label: {
                            if store.selectedSortOrder == order {
                                Label(order.title, systemImage: "checkmark")
                            } else {
                                Text(order.title)
                            }
                        }
                    }
                } label: {
                    Label(store.selectedSortOrder.title, systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
            }
            .font(.subheadline)

            if selectionMode, selectedItems.isEmpty == false {
                selectionBar
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.screenshots.isEmpty {
            ProgressView("Loading screenshots…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.groupedScreenshots.isEmpty {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "No screenshots",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Drop screenshots into \(store.watchedFolderURL.lastPathComponent) or change the watched folder in Settings.")
                )

                if let error = store.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            GeometryReader { proxy in
                let cardWidth = gridCardWidth(for: proxy.size.width)
                let columns = gridColumns(for: cardWidth)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let error = store.lastErrorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        ForEach(store.groupedScreenshots, id: \.section.id) { group in
                            if store.selectedDateFilter == .all {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeaderView(title: group.section.title, count: group.items.count)
                                    screenshotGrid(items: group.items, columns: columns, cardWidth: cardWidth)
                                }
                            }
                        }

                        if store.selectedDateFilter != .all {
                            screenshotGrid(items: store.filteredScreenshots, columns: columns, cardWidth: cardWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(gridPadding)
                }
            }
        }
    }

    private var selectedItems: [ScreenshotItem] {
        store.screenshots.filter { selectedIDs.contains($0.id) }
    }

    private var visibleItems: [ScreenshotItem] {
        store.filteredScreenshots
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Label(selectionSummaryText, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                MultiFileDragButton(items: selectedItems, compact: true)
                    .frame(width: 30, height: 30)

                Button {
                    store.quickLook(selectedItems, current: selectedItems.first)
                } label: {
                    Image(systemName: "space")
                }
                .help("Quick Look")
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    store.copyFiles(selectedItems)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy files")
                .keyboardShortcut("c")

                Button {
                    let items = selectedItems
                    selectedIDs.removeAll()
                    selectionMode = false
                    store.move(items)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Move selection")

                Menu {
                    Button(allSelectedItemsAreFavorites ? String(localized: "Remove from favorites") : String(localized: "Add to favorites"), systemImage: allSelectedItemsAreFavorites ? "star.slash" : "star") {
                        store.setFavorite(allSelectedItemsAreFavorites == false, for: selectedItems)
                    }

                    Divider()

                    Button("Copy paths", systemImage: "link") {
                        store.copyPaths(selectedItems)
                    }

                    Button("Move to folder", systemImage: "folder") {
                        let items = selectedItems
                        selectedIDs.removeAll()
                        selectionMode = false
                        store.move(items)
                    }

                    Button("Reveal in Finder", systemImage: "finder") {
                        store.revealInFinder(selectedItems)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More actions")

                Button(role: .destructive) {
                    let items = selectedItems
                    selectedIDs.removeAll()
                    selectionMode = false
                    store.delete(items)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete selection")
                .keyboardShortcut(.delete, modifiers: [])

                Button {
                    selectedIDs.removeAll()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Clear selection")
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var selectionSummaryText: String {
        selectedItems.count == 1
            ? String(localized: "1 selected")
            : String(localized: "selection.count", defaultValue: "\(selectedItems.count) selected")
    }

    private func toggleSelection(for item: ScreenshotItem) {
        activeItemID = item.id

        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else {
            return
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
        }
        syncActiveItem()
    }

    private func removeKeyboardMonitor() {
        guard let keyMonitor else {
            return
        }

        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard shouldHandleKeyEvent else {
            return event
        }

        let commandPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)

        if commandPressed, event.charactersIgnoringModifiers?.lowercased() == "c" {
            copyFocusedItems()
            return nil
        }

        if commandPressed, event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectionMode = true
            selectedIDs = Set(visibleItems.map(\.id))
            return nil
        }

        if event.charactersIgnoringModifiers?.lowercased() == "f" {
            toggleFavoriteFocusedItems()
            return nil
        }

        switch event.keyCode {
        case 123:
            moveActiveItem(horizontalStep: -1)
            return nil
        case 124:
            moveActiveItem(horizontalStep: 1)
            return nil
        case 125:
            moveActiveItem(verticalStep: gridColumnCount)
            return nil
        case 126:
            moveActiveItem(verticalStep: -gridColumnCount)
            return nil
        case 49:
            quickLookFocusedItem()
            return nil
        case 36, 76:
            revealFocusedItem()
            return nil
        case 51, 117:
            deleteFocusedItems()
            return nil
        case 53: // Esc — exit selection mode
            if selectionMode {
                selectionMode = false
                selectedIDs.removeAll()
                return nil
            }
            return event
        default:
            return event
        }
    }

    private var shouldHandleKeyEvent: Bool {
        guard visibleItems.isEmpty == false else {
            return false
        }

        if renameTarget != nil {
            return false
        }

        if let firstResponder = NSApp.keyWindow?.firstResponder, firstResponder is NSTextView {
            return false
        }

        return true
    }

    private func syncActiveItem() {
        guard visibleItems.isEmpty == false else {
            activeItemID = nil
            return
        }

        if let activeItemID, visibleItems.contains(where: { $0.id == activeItemID }) {
            return
        }

        activeItemID = visibleItems.first?.id
    }

    private func moveActiveItem(horizontalStep: Int = 0, verticalStep: Int = 0) {
        guard visibleItems.isEmpty == false else {
            return
        }

        let currentIndex = visibleItems.firstIndex { $0.id == activeItemID } ?? 0
        let rawTarget = currentIndex + horizontalStep + verticalStep
        let clampedIndex = min(max(rawTarget, 0), visibleItems.count - 1)
        activeItemID = visibleItems[clampedIndex].id
    }

    private func gridCardWidth(for totalWidth: CGFloat) -> CGFloat {
        let contentWidth = max(totalWidth - (gridPadding * 2), 0)
        let totalSpacing = CGFloat(gridColumnCount - 1) * gridSpacing
        return floor((contentWidth - totalSpacing) / CGFloat(gridColumnCount))
    }

    private func gridColumns(for cardWidth: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.fixed(cardWidth), spacing: gridSpacing), count: gridColumnCount)
    }

    @ViewBuilder
    private func screenshotGrid(items: [ScreenshotItem], columns: [GridItem], cardWidth: CGFloat) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
            ForEach(items) { item in
                ScreenshotCardView(
                    item: item,
                    title: store.displayTitle(for: item),
                    width: cardWidth,
                    isFavorite: store.isFavorite(item),
                    isSelected: selectedIDs.contains(item.id),
                    isActive: activeItemID == item.id,
                    selectionMode: selectionMode,
                    onActivate: { activeItemID = item.id },
                    onEditInPinpoint: { onOpenInPinpoint(item) },
                    onSetTitle: { store.setCustomTitle($0, for: item) },
                    onToggleFavorite: { store.toggleFavorite(item) },
                    onSelect: { toggleSelection(for: item) },
                    onCopyImage: { store.copyImage(item) },
                    onCopyPath: { store.copyPaths([item]) },
                    onOpenDetails: { openDetailWindow(for: item) },
                    onDelete: { store.delete(item) },
                    onQuickLook: { store.quickLook(item) },
                    onMove: { store.move(item) },
                    onRename: {
                        renameTarget = item
                    },
                    onReveal: { store.revealInFinder(item) }
                )
            }
        }
    }

    private var focusedItem: ScreenshotItem? {
        visibleItems.first { $0.id == activeItemID } ?? visibleItems.first
    }

    private var allSelectedItemsAreFavorites: Bool {
        selectedItems.isEmpty == false && selectedItems.allSatisfy(store.isFavorite(_:))
    }

    private func copyFocusedItems() {
        if selectionMode, selectedItems.isEmpty == false {
            store.copyFiles(selectedItems)
            return
        }

        guard let focusedItem else {
            return
        }

        store.copyFiles([focusedItem])
    }

    private func quickLookFocusedItem() {
        if selectionMode, selectedItems.isEmpty == false {
            store.quickLook(selectedItems, current: focusedItem ?? selectedItems.first)
            return
        }

        guard let focusedItem else {
            return
        }

        store.quickLook(focusedItem)
    }

    private func revealFocusedItem() {
        if selectionMode, selectedItems.isEmpty == false {
            store.revealInFinder(selectedItems)
            return
        }

        guard let focusedItem else {
            return
        }

        store.revealInFinder(focusedItem)
    }

    private func deleteFocusedItems() {
        if selectionMode, selectedItems.isEmpty == false {
            let items = selectedItems
            selectedIDs.removeAll()
            selectionMode = false
            store.delete(items)
            return
        }

        guard let focusedItem else {
            return
        }

        activeItemID = nil
        store.delete(focusedItem)
    }

    private func toggleFavoriteFocusedItems() {
        if selectionMode, selectedItems.isEmpty == false {
            store.setFavorite(allSelectedItemsAreFavorites == false, for: selectedItems)
            return
        }

        guard let focusedItem else {
            return
        }

        store.toggleFavorite(focusedItem)
    }

    private func openSettingsWindow() {
        onOpenSettings()
    }

    private func openDetailWindow(for item: ScreenshotItem) {
        onOpenDetail(item)
    }
}

private struct RenameScreenshotView: View {
    let filename: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var newName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename screenshot")
                .font(.title3.weight(.semibold))

            TextField("File name", text: $newName)
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

struct ShelfView_Previews: PreviewProvider {
    static var previews: some View {
        ShelfView()
            .environmentObject(PreviewSampleData.store)
            .frame(width: 440, height: 620)
    }
}
