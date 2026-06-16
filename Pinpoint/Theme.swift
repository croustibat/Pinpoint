import AppKit
import SwiftUI

/// Pinpoint's accent palette — vermillon, the marker colour. Chosen to stay
/// legible on any capture rather than blend in like the system blue
/// (design system §02). One source of truth for both AppKit (export) and
/// SwiftUI (editor).
extension NSColor {
    static let pinpointVermillon = NSColor(srgbRed: 255.0 / 255, green: 77.0 / 255, blue: 46.0 / 255, alpha: 1)
    static let pinpointVermillonLight = NSColor(srgbRed: 255.0 / 255, green: 106.0 / 255, blue: 69.0 / 255, alpha: 1)
    static let pinpointVermillonDark = NSColor(srgbRed: 232.0 / 255, green: 53.0 / 255, blue: 15.0 / 255, alpha: 1)
}

extension Color {
    static let pinpointVermillon = Color(nsColor: .pinpointVermillon)
    static let pinpointVermillonLight = Color(nsColor: .pinpointVermillonLight)
    static let pinpointVermillonDark = Color(nsColor: .pinpointVermillonDark)
}
