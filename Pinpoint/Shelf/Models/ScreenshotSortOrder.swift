import Foundation

enum ScreenshotSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst:
            return "Newest"
        case .oldestFirst:
            return "Oldest"
        }
    }

    func sort(_ items: [ScreenshotItem]) -> [ScreenshotItem] {
        switch self {
        case .newestFirst:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return items.sorted { $0.createdAt < $1.createdAt }
        }
    }
}
