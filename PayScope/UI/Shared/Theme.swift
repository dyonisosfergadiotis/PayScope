import SwiftUI

enum PayScopeTypography {
    static let hero = Font.system(.title2, design: .rounded).weight(.heavy)
    static let section = Font.system(.headline, design: .rounded).weight(.semibold)
    static let metric = Font.system(.title, design: .rounded).weight(.bold)
}

struct PayScopeBackground: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(.systemGroupedBackground),
                            Color(.systemBackground),
                            accent.opacity(0.1),
                            Color(.secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    RadialGradient(
                        colors: [accent.opacity(0.24), .clear],
                        center: .topTrailing,
                        startRadius: 6,
                        endRadius: 420
                    )
                    .ignoresSafeArea()

                    RadialGradient(
                        colors: [accent.opacity(0.18), .clear],
                        center: .bottomLeading,
                        startRadius: 20,
                        endRadius: 460
                    )
                    .ignoresSafeArea()

                    LinearGradient(
                        colors: [.white.opacity(0.24), .clear, .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.softLight)
                    .ignoresSafeArea()

                    Ellipse()
                        .fill(accent.opacity(0.08))
                        .frame(width: 360, height: 180)
                        .blur(radius: 34)
                        .offset(x: -120, y: 210)
                }
            )
    }
}

extension View {
    func payScopeBackground(accent: Color) -> some View {
        modifier(PayScopeBackground(accent: accent))
    }
}

struct PayScopeSurfaceStyle: ViewModifier {
    let accent: Color
    let cornerRadius: CGFloat
    let emphasis: Double

    func body(content: Content) -> some View {
        let depth = CGFloat(max(0, emphasis))

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.secondarySystemBackground).opacity(0.96),
                                accent.opacity(0.06 + (emphasis * 0.08)),
                                Color(.systemBackground).opacity(0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 0.9)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(0.16 + (emphasis * 0.14)), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.06 + (emphasis * 0.05)), radius: 9 + (depth * 10), x: 0, y: 6 + (depth * 5))
            .shadow(color: accent.opacity(0.08 + (emphasis * 0.08)), radius: 14 + (depth * 12), x: 0, y: 7 + (depth * 4))
    }
}

extension View {
    func payScopeSurface(accent: Color, cornerRadius: CGFloat = 16, emphasis: Double = 0.3) -> some View {
        modifier(PayScopeSurfaceStyle(accent: accent, cornerRadius: cornerRadius, emphasis: emphasis))
    }
}

struct CardStyle: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .padding(16)
            .payScopeSurface(accent: accent, cornerRadius: 22, emphasis: 0.42)
    }
}

extension View {
    func payScopeCard(accent: Color) -> some View {
        modifier(CardStyle(accent: accent))
    }
}

struct PayScopeSheetSurface: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .payScopeBackground(accent: accent)
    }
}

extension View {
    func payScopeSheetSurface(accent: Color) -> some View {
        modifier(PayScopeSheetSurface(accent: accent))
    }
}

struct PayScopePrimaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.98), accent.opacity(0.82), accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
            .shadow(color: accent.opacity(0.26), radius: 12, x: 0, y: 6)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PayScopeSecondaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(accent)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(configuration.isPressed ? 0.2 : 0.16),
                                Color(.systemBackground).opacity(0.86)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.1), radius: 6, x: 0, y: 3)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PayScopePrimaryButtonStyle {
    static func payScopePrimary(accent: Color) -> PayScopePrimaryButtonStyle {
        PayScopePrimaryButtonStyle(accent: accent)
    }
}

extension ButtonStyle where Self == PayScopeSecondaryButtonStyle {
    static func payScopeSecondary(accent: Color) -> PayScopeSecondaryButtonStyle {
        PayScopeSecondaryButtonStyle(accent: accent)
    }
}
