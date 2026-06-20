import Foundation

enum ScreenshotDateFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case yesterday
    case last7Days
    case last30Days
    case thisWeek
    case thisMonth
    case older

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .today:
            return String(localized: "Today")
        case .yesterday:
            return String(localized: "Yesterday")
        case .last7Days:
            return String(localized: "Last 7 days")
        case .last30Days:
            return String(localized: "Last 30 days")
        case .thisWeek:
            return String(localized: "This week")
        case .thisMonth:
            return String(localized: "This month")
        case .older:
            return String(localized: "Older")
        }
    }

    func matches(_ item: ScreenshotItem, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(item.createdAt)
        case .yesterday:
            return calendar.isDateInYesterday(item.createdAt)
        case .last7Days:
            return matchesRecentDays(item, days: 7, calendar: calendar)
        case .last30Days:
            return matchesRecentDays(item, days: 30, calendar: calendar)
        case .thisWeek:
            return ScreenshotSection.section(for: item.createdAt, calendar: calendar) == .thisWeek
        case .thisMonth:
            return ScreenshotSection.section(for: item.createdAt, calendar: calendar) == .thisMonth
        case .older:
            return ScreenshotSection.section(for: item.createdAt, calendar: calendar) == .older
        }
    }

    private func matchesRecentDays(_ item: ScreenshotItem, days: Int, calendar: Calendar) -> Bool {
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: .now)) else {
            return false
        }

        return item.createdAt >= startDate
    }
}
