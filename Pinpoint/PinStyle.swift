import Foundation

/// Visual style of the numbered markers (design system §03). Persisted in
/// UserDefaults via `@AppStorage(PinStyle.storageKey)` so the editor and the
/// Settings window stay in sync.
enum PinStyle: String, CaseIterable, Identifiable {
    /// Filled vermillon disc + white ring (the default).
    case disc
    /// Map-pin whose tip designates the exact pixel.
    case pointer
    /// Hollow ring that doesn't obscure the element underneath.
    case outline

    var id: String { rawValue }

    static let storageKey = "pinStyle"

    var label: String {
        switch self {
        case .disc: return String(localized: "Filled disc")
        case .pointer: return String(localized: "Pointer pin")
        case .outline: return String(localized: "Light outline")
        }
    }

    var caption: String {
        switch self {
        case .disc: return String(localized: "White ring + drop shadow.")
        case .pointer: return String(localized: "The tip marks the exact pixel.")
        case .outline: return String(localized: "Doesn’t obscure the target element.")
        }
    }
}
