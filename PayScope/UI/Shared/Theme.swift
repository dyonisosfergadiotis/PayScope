import SwiftUI

enum WageWiseTypography {
    static let hero = Font.system(.title2, design: .serif).weight(.bold)
    static let section = Font.system(.headline, design: .rounded).weight(.semibold)
    static let metric = Font.system(.title, design: .rounded).weight(.bold)
}

struct WageWiseBackground: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            accent.opacity(0.08),
                            Color(.secondarySystemBackground)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    RadialGradient(
                        colors: [accent.opacity(0.22), .clear],
                        center: .topTrailing,
                        startRadius: 10,
                        endRadius: 380
                    )
                    .ignoresSafeArea()

                    RadialGradient(
                        colors: [accent.opacity(0.14), .clear],
                        center: .bottomLeading,
                        startRadius: 30,
                        endRadius: 420
                    )
                    .ignoresSafeArea()

                    LinearGradient(
                        colors: [.white.opacity(0.24), .clear, .white.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.softLight)
                    .ignoresSafeArea()
                }
            )
    }
}

extension View {
    func wageWiseBackground(accent: Color) -> some View {
        modifier(WageWiseBackground(accent: accent))
    }
}

struct CardStyle: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: accent.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func wageWiseCard(accent: Color) -> some View {
        modifier(CardStyle(accent: accent))
    }
}

struct WageWiseSheetSurface: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .wageWiseBackground(accent: accent)
    }
}

extension View {
    func wageWiseSheetSurface(accent: Color) -> some View {
        modifier(WageWiseSheetSurface(accent: accent))
    }
}

struct WageWisePrimaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct WageWiseSecondaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(accent)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(configuration.isPressed ? 0.14 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == WageWisePrimaryButtonStyle {
    static func wageWisePrimary(accent: Color) -> WageWisePrimaryButtonStyle {
        WageWisePrimaryButtonStyle(accent: accent)
    }
}

extension ButtonStyle where Self == WageWiseSecondaryButtonStyle {
    static func wageWiseSecondary(accent: Color) -> WageWiseSecondaryButtonStyle {
        WageWiseSecondaryButtonStyle(accent: accent)
    }
}
