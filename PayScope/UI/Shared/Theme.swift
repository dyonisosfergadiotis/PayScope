import SwiftUI
#if os(iOS)
import UIKit
#endif

enum PayScopeTypography {
    static let hero = Font.system(.title2, design: .rounded).weight(.heavy)
    static let section = Font.system(.headline, design: .rounded).weight(.semibold)
    static let metric = Font.system(.title, design: .rounded).weight(.bold)
}

struct PayScopeModalGeometry {
    static var sheet: PayScopeModalGeometry {
        PayScopeModalGeometry(displayCornerRadius: estimatedDisplayCornerRadius, edgePadding: 10)
    }

    static let popover = PayScopeModalGeometry(outerCornerRadius: 20, edgePadding: 0)

    private static let sheetCornerRadiusRange: ClosedRange<CGFloat> = 24...34
    private static let cardCornerRadiusRange: ClosedRange<CGFloat> = 15...25

    private static var estimatedDisplayCornerRadius: CGFloat {
        #if os(iOS)
        let minSide = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds }
            .first
            .map { min($0.width, $0.height) } ?? 390
        return min(44, max(34, minSide * 0.1))
        #else
        return 38
        #endif
    }

    let outerCornerRadius: CGFloat
    let edgePadding: CGFloat

    private init(displayCornerRadius: CGFloat, edgePadding: CGFloat) {
        self.outerCornerRadius = Self.clamp(displayCornerRadius - edgePadding, to: Self.sheetCornerRadiusRange)
        self.edgePadding = edgePadding
    }

    private init(outerCornerRadius: CGFloat, edgePadding: CGFloat) {
        self.outerCornerRadius = outerCornerRadius
        self.edgePadding = edgePadding
    }

    var innerCornerRadius: CGFloat {
        Self.clamp(outerCornerRadius - edgePadding, to: Self.cardCornerRadiusRange)
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

struct PayScopeBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color

    func body(content: Content) -> some View {
        let isLightMode = colorScheme == .light

        content
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            isLightMode ? Color(red: 0.994, green: 0.996, blue: 1.0) : Color(.systemBackground),
                            accent.opacity(isLightMode ? 0.06 : 0.08),
                            isLightMode ? Color(red: 0.982, green: 0.986, blue: 0.994) : Color(.systemGroupedBackground),
                            accent.opacity(isLightMode ? 0.035 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    LinearGradient(
                        colors: [
                            .white.opacity(isLightMode ? 0.4 : 0.32),
                            .clear,
                            .white.opacity(isLightMode ? 0.2 : 0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.softLight)
                    .ignoresSafeArea()
                }
            )
    }
}

extension View {
    func payScopeBackground(accent: Color) -> some View {
        modifier(PayScopeBackground(accent: accent))
    }

    func payScopeNumericTransition<Value: Equatable>(value: Value) -> some View {
        self
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.32), value: value)
    }

    func payScopeTextTransition<Value: Equatable>(value: Value) -> some View {
        self
            .contentTransition(.interpolate)
            .animation(.snappy(duration: 0.32), value: value)
    }
}

struct PayScopeSurfaceStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let cornerRadius: CGFloat
    let emphasis: Double

    func body(content: Content) -> some View {
        let depth = CGFloat(max(0, emphasis))
        let isLightMode = colorScheme == .light

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                isLightMode ? Color.white.opacity(0.97) : Color(.secondarySystemBackground).opacity(0.96),
                                accent.opacity((isLightMode ? 0.045 : 0.06) + (emphasis * (isLightMode ? 0.055 : 0.08))),
                                isLightMode ? Color(red: 0.992, green: 0.994, blue: 1.0).opacity(0.99) : Color(.systemBackground).opacity(0.98)
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
            .shadow(color: .black.opacity(0.05 + (emphasis * 0.03)), radius: 6 + (depth * 7), x: 0, y: 4 + (depth * 3))
    }
}

extension View {
    func payScopeSurface(accent: Color, cornerRadius: CGFloat = 16, emphasis: Double = 0.3) -> some View {
        modifier(PayScopeSurfaceStyle(accent: accent, cornerRadius: cornerRadius, emphasis: emphasis))
    }
}

struct PayScopeGlassSurfaceStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let cornerRadius: CGFloat
    let tintOpacity: Double
    let shadowOpacity: Double
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isLightMode = colorScheme == .light

        content
            .background(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                isLightMode ? Color.white.opacity(0.8) : Color(.secondarySystemBackground).opacity(0.5),
                                accent.opacity(tintOpacity * (isLightMode ? 1.1 : 1.35)),
                                isLightMode ? Color.white.opacity(0.64) : Color(.systemBackground).opacity(0.38)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .glassEffect(
                .regular
                    .tint(accent.opacity(tintOpacity))
                    .interactive(isInteractive),
                in: shape
            )
            .shadow(color: accent.opacity(shadowOpacity), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(isLightMode ? 0.04 : 0.1), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func payScopeGlassSurface(
        accent: Color,
        cornerRadius: CGFloat = 18,
        tintOpacity: Double = 0.06,
        shadowOpacity: Double = 0.08,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            PayScopeGlassSurfaceStyle(
                accent: accent,
                cornerRadius: cornerRadius,
                tintOpacity: tintOpacity,
                shadowOpacity: shadowOpacity,
                isInteractive: isInteractive
            )
        )
    }
}

struct PayScopeLiquidGlassStyle: ViewModifier {
    let accent: Color
    let cornerRadius: CGFloat
    let tintOpacity: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(
                shape
                    .fill(accent.opacity(tintOpacity))
            )
            .glassEffect(.regular.tint(accent.opacity(tintOpacity * 0.85)), in: shape)
            .shadow(color: accent.opacity(0.08), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func payScopeLiquidGlass(accent: Color, cornerRadius: CGFloat = 16, tintOpacity: Double = 0.1) -> some View {
        modifier(PayScopeLiquidGlassStyle(accent: accent, cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }
}

struct PayScopeLiquidGlassIconStyle<IconShape: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let shape: IconShape
    let tintOpacity: Double
    let shadowOpacity: Double
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let isLightMode = colorScheme == .light

        content
            .background(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                isLightMode ? Color.white.opacity(0.58) : Color.white.opacity(0.16),
                                accent.opacity(tintOpacity),
                                isLightMode ? Color.white.opacity(0.28) : Color(.systemBackground).opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .glassEffect(
                .regular
                    .tint(accent.opacity(tintOpacity * 0.9))
                    .interactive(isInteractive),
                in: shape
            )
            .overlay(
                shape
                    .stroke(.white.opacity(isLightMode ? 0.42 : 0.22), lineWidth: 0.8)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape
                    .stroke(accent.opacity(tintOpacity * 0.78), lineWidth: 0.8)
                    .allowsHitTesting(false)
            )
            .shadow(color: accent.opacity(shadowOpacity), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func payScopeLiquidGlassIcon(
        accent: Color,
        tintOpacity: Double = 0.14,
        shadowOpacity: Double = 0.09,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            PayScopeLiquidGlassIconStyle(
                accent: accent,
                shape: Circle(),
                tintOpacity: tintOpacity,
                shadowOpacity: shadowOpacity,
                isInteractive: isInteractive
            )
        )
    }

    func payScopeLiquidGlassIcon<IconShape: InsettableShape>(
        accent: Color,
        in shape: IconShape,
        tintOpacity: Double = 0.14,
        shadowOpacity: Double = 0.09,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            PayScopeLiquidGlassIconStyle(
                accent: accent,
                shape: shape,
                tintOpacity: tintOpacity,
                shadowOpacity: shadowOpacity,
                isInteractive: isInteractive
            )
        )
    }
}

struct PayScopeGlassControlGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

struct PayScopeGlassControlStyle: ViewModifier {
    let accent: Color
    let cornerRadius: CGFloat
    let tintOpacity: Double
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(
                shape
                    .fill(accent.opacity(tintOpacity * 0.65))
            )
            .glassEffect(
                .regular
                    .tint(accent.opacity(tintOpacity))
                    .interactive(isInteractive),
                in: shape
            )
    }
}

extension View {
    func payScopeGlassControl(
        accent: Color,
        cornerRadius: CGFloat = 16,
        tintOpacity: Double = 0.16,
        isInteractive: Bool = true
    ) -> some View {
        modifier(
            PayScopeGlassControlStyle(
                accent: accent,
                cornerRadius: cornerRadius,
                tintOpacity: tintOpacity,
                isInteractive: isInteractive
            )
        )
    }
}

struct PayScopeLiquidGlassTapFeedbackStyle<FeedbackShape: InsettableShape>: ViewModifier {
    @State private var isAnimatingTap = false

    let accent: Color
    let shape: FeedbackShape
    let tintOpacity: Double
    let pressedScale: CGFloat

    func body(content: Content) -> some View {
        content
            .contentShape(shape)
            .scaleEffect(isAnimatingTap ? pressedScale : 1)
            .overlay(
                shape
                    .fill(accent.opacity(isAnimatingTap ? tintOpacity : 0))
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape
                    .stroke(.white.opacity(isAnimatingTap ? 0.28 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        withAnimation(.smooth(duration: 0.14, extraBounce: 0.18)) {
                            isAnimatingTap = true
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            withAnimation(.smooth(duration: 0.32, extraBounce: 0)) {
                                isAnimatingTap = false
                            }
                        }
                    }
            )
    }
}

struct PayScopeLiquidGlassPressButtonStyle<FeedbackShape: InsettableShape>: ButtonStyle {
    let accent: Color
    let shape: FeedbackShape
    let tintOpacity: Double
    let pressedScale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .overlay(
                shape
                    .fill(accent.opacity(configuration.isPressed ? tintOpacity : 0))
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape
                    .stroke(.white.opacity(configuration.isPressed ? 0.32 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .animation(.smooth(duration: 0.16, extraBounce: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func payScopeLiquidGlassTapFeedback<FeedbackShape: InsettableShape>(
        accent: Color,
        in shape: FeedbackShape,
        tintOpacity: Double = 0.055,
        pressedScale: CGFloat = 0.988
    ) -> some View {
        modifier(
            PayScopeLiquidGlassTapFeedbackStyle(
                accent: accent,
                shape: shape,
                tintOpacity: tintOpacity,
                pressedScale: pressedScale
            )
        )
    }
}

struct CardStyle: ViewModifier {
    let accent: Color
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let geometry = PayScopeModalGeometry.sheet
        let shape = RoundedRectangle(cornerRadius: geometry.innerCornerRadius, style: .continuous)
        let card = content
            .padding(16)
            .payScopeGlassSurface(
                accent: accent,
                cornerRadius: geometry.innerCornerRadius,
                tintOpacity: 0.055,
                shadowOpacity: 0.075,
                isInteractive: isInteractive
            )

        if isInteractive {
            card
                .payScopeLiquidGlassTapFeedback(accent: accent, in: shape)
        } else {
            card
        }
    }
}

extension View {
    func payScopeCard(accent: Color, isInteractive: Bool = false) -> some View {
        modifier(CardStyle(accent: accent, isInteractive: isInteractive))
    }
}

struct PayScopeSheetSurface: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        let geometry = PayScopeModalGeometry.sheet

        content
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .presentationBackground(.clear)
            .presentationCornerRadius(geometry.outerCornerRadius)
    }
}

struct PayScopePopoverSurface: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        let geometry = PayScopeModalGeometry.popover

        content
            .presentationBackground(.clear)
            .presentationCornerRadius(geometry.outerCornerRadius)
    }
}

extension View {
    func payScopeSheetSurface(accent: Color) -> some View {
        modifier(PayScopeSheetSurface(accent: accent))
    }

    func payScopePopoverSurface(accent: Color) -> some View {
        modifier(PayScopePopoverSurface(accent: accent))
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
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
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
