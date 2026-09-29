import AppKit
import SwiftUI

/// Cleans up the shelf: proposes screenshots to move to the Trash, grouped by
/// reason and all ticked. This sheet is the review — nothing leaves the folder
/// before it's confirmed, and even then it only goes to the Trash.
struct CleanupSheetView: View {
    var onDismiss: () -> Void

    @EnvironmentObject private var store: ScreenshotStore
    @State private var criteria = CleanupCriteria()
    @State private var candidates: [CleanupCandidate] = []
    @State private var isPlanning = true
    /// Unticked captures. Tracking exclusions rather than the selection keeps
    /// new proposals ticked when the criteria change.
    @State private var excluded = Set<URL>()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Clean up the shelf")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Picker("Mode", selection: $criteria.mode) {
                    Text("Smart").tag(CleanupMode.smart)
                    Text("Custom").tag(CleanupMode.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                criteriaControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            results

            Divider()

            footer
                .padding(16)
        }
        .frame(width: 420, height: 560)
        .task(id: criteria) { await plan() }
    }

    // MARK: - Criteria

    @ViewBuilder
    private var criteriaControls: some View {
        switch criteria.mode {
        case .smart:
            Text(String(localized: "cleanup.smart.summary",
                        defaultValue: "Proposes duplicates, retakes from bursts, screenshots never reopened after \(CleanupPlanner.staleDays) days and anything older than \(CleanupPlanner.oldDays) days. Favorites, titled screenshots and the last \(CleanupPlanner.recentDays) days are never touched."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .custom:
            Picker("Older than", selection: $criteria.minimumAgeDays) {
                ForEach(CleanupCriteria.ageChoices, id: \.self) { days in
                    Text(Self.ageTitle(days)).tag(days)
                }
            }
            .fixedSize()

            Toggle("Only screenshots never reopened", isOn: $criteria.neverReopenedOnly)
            Toggle("Only macOS screenshots", isOn: $criteria.screenshotsOnly)

            Text("Favorites and titled screenshots are never touched.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func ageTitle(_ days: Int) -> String {
        switch days {
        case 7: String(localized: "1 week")
        case 30: String(localized: "1 month")
        case 90: String(localized: "3 months")
        case 180: String(localized: "6 months")
        case 365: String(localized: "1 year")
        default: String(localized: "cleanup.age.days", defaultValue: "\(days) days")
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if isPlanning && candidates.isEmpty {
            ProgressView("Looking for screenshots to clean up…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if candidates.isEmpty {
            ContentUnavailableView {
                Label("Nothing to clean up", systemImage: "sparkles")
            } description: {
                Text("No screenshot matches these criteria.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(groups, id: \.reason) { group in
                    Section {
                        ForEach(group.items) { candidate in
                            CleanupRow(
                                candidate: candidate,
                                title: store.displayTitle(for: candidate.item),
                                isIncluded: inclusionBinding(for: [candidate]),
                                onQuickLook: { store.quickLook(candidate.item) }
                            )
                        }
                    } header: {
                        sectionHeader(group.reason, items: group.items)
                    }
                }
            }
            .listStyle(.inset)
            // A new plan is on its way: keep the old one visible but inert
            // rather than flashing an empty list at every criteria change.
            .opacity(isPlanning ? 0.5 : 1)
            .disabled(isPlanning)
        }
    }

    private var groups: [(reason: CleanupReason, items: [CleanupCandidate])] {
        CleanupReason.allCases.compactMap { reason in
            let items = candidates.filter { $0.reason == reason }
            return items.isEmpty ? nil : (reason, items)
        }
    }

    private func sectionHeader(_ reason: CleanupReason, items: [CleanupCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: inclusionBinding(for: items)) {
                HStack {
                    Text(title(for: reason))
                        .font(.headline)
                    Spacer()
                    Text("\(items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Text(explanation(for: reason))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func title(for reason: CleanupReason) -> String {
        switch reason {
        case .duplicate: String(localized: "Duplicates")
        case .burst: String(localized: "Retakes")
        case .stale: String(localized: "Never reopened")
        case .old: String(localized: "Old")
        }
    }

    private func explanation(for reason: CleanupReason) -> String {
        let custom = criteria.mode == .custom
        switch reason {
        case .duplicate:
            return String(localized: "Same image as another screenshot, which is kept.")
        case .burst:
            return String(localized: "Taken seconds before another screenshot, which is kept.")
        case .stale:
            let days = custom ? criteria.minimumAgeDays : CleanupPlanner.staleDays
            return String(localized: "cleanup.reason.stale", defaultValue: "More than \(days) days old and never opened again.")
        case .old:
            let days = custom ? criteria.minimumAgeDays : CleanupPlanner.oldDays
            return String(localized: "cleanup.reason.old", defaultValue: "More than \(days) days old.")
        }
    }

    /// Ticked when every capture in `items` is; setting it ticks or unticks
    /// them all — one row, or a whole section from its header.
    private func inclusionBinding(for items: [CleanupCandidate]) -> Binding<Bool> {
        Binding(
            get: { items.allSatisfy { excluded.contains($0.id) == false } },
            set: { isIncluded in
                if isIncluded {
                    excluded.subtract(items.map(\.id))
                } else {
                    excluded.formUnion(items.map(\.id))
                }
            }
        )
    }

    // MARK: - Footer

    private var selected: [CleanupCandidate] {
        candidates.filter { excluded.contains($0.id) == false }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: selectionSummary)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(String(localized: "shelf.delete.confirm.message", defaultValue: "Nothing is erased until you empty the Trash."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Cancel", role: .cancel, action: onDismiss)
                .keyboardShortcut(.cancelAction)

            // No default-action shortcut: a stray Return must not send a few
            // hundred files to the Trash.
            Button(String(localized: "Move to Trash"), role: .destructive, action: moveSelectionToTrash)
                .pinpointGlassButton(prominent: true)
                .tint(.pinpointVermillon)
                .disabled(selected.isEmpty || isPlanning)
        }
    }

    private var selectionSummary: String {
        let count = selected.count
        let countText = count == 1
            ? String(localized: "1 selected")
            : String(localized: "selection.count", defaultValue: "\(count) selected")
        let bytes = selected.reduce(Int64(0)) { $0 + $1.fileSize }
        return "\(countText) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    // MARK: - Actions

    private func plan() async {
        isPlanning = true
        let result = await store.cleanupCandidates(for: criteria)
        // Superseded by a newer criteria change, whose own task takes over.
        guard Task.isCancelled == false else { return }
        candidates = result
        isPlanning = false
    }

    private func moveSelectionToTrash() {
        let items = selected.map(\.item)
        guard items.isEmpty == false else { return }
        store.delete(items)
        onDismiss()
    }
}

private struct CleanupRow: View {
    let candidate: CleanupCandidate
    let title: String
    @Binding var isIncluded: Bool
    let onQuickLook: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Toggle(title, isOn: $isIncluded)
                .toggleStyle(.checkbox)
                .labelsHidden()

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.35))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 64, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onQuickLook) {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .help("Quick Look")
            .accessibilityLabel(Text("Quick Look"))
        }
        .contentShape(Rectangle())
        .onTapGesture { isIncluded.toggle() }
        // Default size on purpose: `ThumbnailService` caches by URL alone, so
        // asking for a small one here would hand the shelf blurry cards.
        .task(id: candidate.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: candidate.item.url)
        }
    }

    private var detail: String {
        let date = candidate.item.createdAt.formatted(.relative(presentation: .named))
        let size = ByteCountFormatter.string(fromByteCount: candidate.fileSize, countStyle: .file)
        return "\(date) · \(size)"
    }
}
