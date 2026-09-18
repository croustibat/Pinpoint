import SwiftUI

/// Pinpoint's Liquid Glass layer (#99, `docs/liquid-glass-redesign.md`).
///
/// The one place that knows about macOS 26: every view goes through these
/// helpers, so the day the deployment target moves to 26 only the fallback
/// branches below have to go.
///
/// Two gates, for two different questions:
/// - `#if compiler(>=6.2)` — can this toolchain even name `glassEffect`? Swift
///   6.2 ships with Xcode 26 and the macOS 26 SDK; an older Xcode still builds
///   the app, with the fallback everywhere.
/// - `#available(macOS 26, *)` — is the machine running it able to draw glass?
///
/// The fallback is a translucent material with a hairline stroke and a soft
/// shadow, and it turns opaque under Reduce Transparency — the native glass
/// handles that setting (and Increase Contrast) on its own.
extension View {
    /// A glass surface for panels, bars and cards.
    ///
    /// `interactive` makes native glass react to hover and press; it has no
    /// fallback equivalent. Never nest two of these without a
    /// `PinpointGlassContainer`: glass can't sample glass, and stacked surfaces
    /// turn milky.
    func pinpointGlass<S: Shape>(
        in shape: S = RoundedRectangle(cornerRadius: PinpointGlass.cornerPanel, style: .continuous),
        interactive: Bool = false
    ) -> some View {
        modifier(PinpointGlassSurface(shape: shape, interactive: interactive))
    }

    /// `.glass` / `.glassProminent` on macOS 26+, `.bordered` /
    /// `.borderedProminent` before. A prominent button takes its colour from
    /// `.tint(…)` — vermillon for the primary action, and nothing else.
    @ViewBuilder
    func pinpointGlassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            legacyButtonStyle(prominent: prominent)
        }
        #else
        legacyButtonStyle(prominent: prominent)
        #endif
    }

    @ViewBuilder
    private func legacyButtonStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

/// Groups neighbouring glass elements (a toolbar's buttons, a card's actions)
/// so they sample the same backdrop and can merge into one another on macOS 26.
/// A plain pass-through before that.
struct PinpointGlassContainer<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct PinpointGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(PinpointGlass.strokeOpacity(for: colorScheme)),
                                      lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
    }
}
