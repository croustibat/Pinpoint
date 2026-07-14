import Foundation

/// Pré-délai optionnel avant une capture de région (design system §…).
/// Persisté dans UserDefaults via `@AppStorage(CaptureDelay.storageKey)` pour
/// garder la fenêtre Réglages et le chemin de capture synchronisés — même
/// motif que `PinStyle`.
enum CaptureDelay: String, CaseIterable, Identifiable {
    /// Aucune pause (comportement par défaut, capture immédiate).
    case off
    case threeSeconds = "3s"
    case fiveSeconds = "5s"
    case tenSeconds = "10s"

    var id: String { rawValue }

    static let storageKey = "captureDelay"

    /// Nombre entier de secondes à attendre avant la capture (0 si désactivé).
    var seconds: Int {
        switch self {
        case .off: return 0
        case .threeSeconds: return 3
        case .fiveSeconds: return 5
        case .tenSeconds: return 10
        }
    }

    /// Lecture hors SwiftUI (chemin de capture) : retourne `.off` si la valeur
    /// stockée est absente ou invalide.
    static var current: CaptureDelay {
        CaptureDelay(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .off
    }

    var label: String {
        switch self {
        case .off: return String(localized: "Off")
        case .threeSeconds: return String(localized: "3 seconds")
        case .fiveSeconds: return String(localized: "5 seconds")
        case .tenSeconds: return String(localized: "10 seconds")
        }
    }
}
