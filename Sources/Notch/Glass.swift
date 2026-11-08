import SwiftUI

/// Liquid Glass on macOS 26+, a frosted white-tint fallback on 14–15.
extension View {
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(shape.fill((tint ?? .white).opacity(0.1)))
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.5))
        }
    }

    /// Groups sibling glass shapes so they blend and morph together (no-op before macOS 26).
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 12) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// The notch shell. Closed it stays solid black so it merges with the hardware notch.
/// Open, the top band stays black so the camera cutout blends in, fading into
/// tinted glass (macOS 26) or a solid fill (older). Tint follows light/dark mode
/// and the opacity set in Settings.
struct NotchBackground: View {
    let shape: NotchShape
    let isOpen: Bool
    let notchFraction: CGFloat
    @AppStorage("glassOpacity") private var opacity = 0.7
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base: Color = scheme == .dark ? .black : .white
        // Light: the band fades out over 6pt around the tab bar's bottom edge (28→34pt), ending 4pt above
        // the content, so dark text never sits on black. Dark keeps its long fade. 1pt = 1/190 (openSize.height).
        let pt: CGFloat = 1 / 190
        let solid = scheme == .dark ? notchFraction : notchFraction - 4 * pt
        let end = scheme == .dark ? notchFraction + 0.35 : notchFraction + 2 * pt
        let fade = shape.fill(LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: solid),
            .init(color: base.opacity(opacity * 0.9), location: min(end, 1)),
        ], startPoint: .top, endPoint: .bottom))
        // Both layers stay mounted and crossfade, so the shape's size animates instead of a
        // freshly inserted full-size layer popping in.
        ZStack {
            Group {
                if #available(macOS 26, *) {
                    fade.glassEffect(.regular.tint(base.opacity(opacity)), in: shape)
                } else {
                    fade.background(shape.fill(base))
                }
            }
            .opacity(isOpen ? 1 : 0)
            shape.fill(.black).opacity(isOpen ? 0 : 1)
        }
    }
}
