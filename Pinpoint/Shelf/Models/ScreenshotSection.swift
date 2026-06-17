import Foundation

enum ScreenshotSection: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .thisWeek:
            return "This Week"
        case .thisMonth:
            return "This Month"
        case .older:
            return "Older"
        }
    }

    static func section(for date: Date, calendar: Calendar = .current) -> Self {
        if calendar.isDateInToday(date) {
            return .today
        }

        if calendar.isDateInYesterday(date) {
            return .yesterday
        }

        if calendar.isDate(date, equalTo: .now, toGranularity: .weekOfYear) {
            return .thisWeek
        }

        if calendar.isDate(date, equalTo: .now, toGranularity: .month) {
            return .thisMonth
        }

        return .older
    }
}
