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
        case .disc: return "Disque plein"
        case .pointer: return "Pin pointeur"
        case .outline: return "Contour léger"
        }
    }

    var caption: String {
        switch self {
        case .disc: return "Anneau blanc + ombre portée."
        case .pointer: return "La pointe désigne le pixel exact."
        case .outline: return "N’obscurcit pas l’élément visé."
        }
    }
}
