import SwiftUI
#if os(iOS)
import UIKit
#endif

enum PayScopeTypography {
    static let hero = Font.system(.title2, design: .rounded).weight(.heavy)
    static let section = Font.system(.headline, design: .rounded).weight(.semibold)
    static let metric = Font.system(.title, design: .rounded).weight(.bold)
}

struct PayScopeThemeTokens {
    let backgroundBase: Color
    let backgroundBaseSecondary: Color
    let backgroundAccentOpacity: Double
    let backgroundAccentSecondaryOpacity: Double
    let surfaceFill: Color
    let elevatedSurfaceFill: Color
    let surfaceStroke: Color
    let glassTintOpacity: Double
    let shadowOpacity: Double
    let categoryTintOpacity: Double
    let highlightOpacity: Double

    static func resolve(for colorScheme: ColorScheme) -> PayScopeThemeTokens {
        if colorScheme == .light {
            return PayScopeThemeTokens(
                backgroundBase: Color(red: 0.992, green: 0.995, blue: 1.0),
                backgroundBaseSecondary: Color(red: 0.963, green: 0.972, blue: 0.986),
                backgroundAccentOpacity: 0.09,
                backgroundAccentSecondaryOpacity: 0.045,
                surfaceFill: Color.white.opacity(0.78),
                elevatedSurfaceFill: Color.white.opacity(0.88),
                surfaceStroke: Color.primary.opacity(0.075),
                glassTintOpacity: 0.105,
                shadowOpacity: 0.055,
                categoryTintOpacity: 0.115,
                highlightOpacity: 0.38
            )
        }

        return PayScopeThemeTokens(
            backgroundBase: Color(red: 0.055, green: 0.06, blue: 0.074),
            backgroundBaseSecondary: Color(red: 0.105, green: 0.108, blue: 0.13),
            backgroundAccentOpacity: 0.13,
            backgroundAccentSecondaryOpacity: 0.065,
            surfaceFill: Color(.secondarySystemBackground).opacity(0.58),
            elevatedSurfaceFill: Color(.secondarySystemBackground).opacity(0.72),
            surfaceStroke: Color.white.opacity(0.13),
            glassTintOpacity: 0.075,
            shadowOpacity: 0.16,
            categoryTintOpacity: 0.085,
            highlightOpacity: 0.18
        )
    }
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
    let intensity: Double

    func body(content: Content) -> some View {
        let tokens = PayScopeThemeTokens.resolve(for: colorScheme)
        let normalizedIntensity = min(1.35, max(0.65, intensity))

        content
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            tokens.backgroundBase,
                            accent.opacity(tokens.backgroundAccentOpacity * normalizedIntensity),
                            tokens.backgroundBaseSecondary,
                            accent.opacity(tokens.backgroundAccentSecondaryOpacity * normalizedIntensity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    LinearGradient(
                        colors: [
                            .white.opacity(tokens.highlightOpacity),
                            .clear,
                            .white.opacity(tokens.highlightOpacity * 0.45)
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
    func payScopeBackground(accent: Color, intensity: Double = 1) -> some View {
        modifier(PayScopeBackground(accent: accent, intensity: intensity))
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
        let tokens = PayScopeThemeTokens.resolve(for: colorScheme)
        let normalizedEmphasis = min(1, max(0, emphasis))

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tokens.elevatedSurfaceFill,
                                accent.opacity(tokens.glassTintOpacity + normalizedEmphasis * tokens.categoryTintOpacity),
                                tokens.surfaceFill
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .light ? 0.58 : 0.18), lineWidth: 0.9)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(0.13 + normalizedEmphasis * 0.13), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(tokens.shadowOpacity + normalizedEmphasis * 0.035), radius: 6 + (depth * 7), x: 0, y: 4 + (depth * 3))
    }
}

extension View {
    func payScopeSurface(accent: Color, cornerRadius: CGFloat = 16, emphasis: Double = 0.3) -> some View {
        modifier(PayScopeSurfaceStyle(accent: accent, cornerRadius: cornerRadius, emphasis: emphasis))
    }
}

struct PayScopeContentSurfaceStyle<SurfaceShape: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let shape: SurfaceShape
    let emphasis: Double
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        let normalizedEmphasis = min(1, max(0, emphasis))
        let tokens = PayScopeThemeTokens.resolve(for: colorScheme)

        content
            .background(
                shape
                    .fill(tokens.surfaceFill)
            )
            .overlay(
                shape
                    .stroke(tokens.surfaceStroke, lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape
                    .stroke(accent.opacity(0.05 + normalizedEmphasis * 0.1), lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
            .shadow(
                color: .black.opacity(colorScheme == .light ? shadowOpacity * 0.65 : max(shadowOpacity, tokens.shadowOpacity * 0.65)),
                radius: 5 + normalizedEmphasis * 7,
                x: 0,
                y: 3 + normalizedEmphasis * 4
            )
    }
}

extension View {
    func payScopeContentSurface<SurfaceShape: InsettableShape>(
        accent: Color,
        in shape: SurfaceShape,
        emphasis: Double = 0.3,
        shadowOpacity: Double = 0.06
    ) -> some View {
        modifier(
            PayScopeContentSurfaceStyle(
                accent: accent,
                shape: shape,
                emphasis: emphasis,
                shadowOpacity: shadowOpacity
            )
        )
    }

    func payScopeContentSurface(
        accent: Color,
        cornerRadius: CGFloat = 18,
        emphasis: Double = 0.3,
        shadowOpacity: Double = 0.06
    ) -> some View {
        payScopeContentSurface(
            accent: accent,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            emphasis: emphasis,
            shadowOpacity: shadowOpacity
        )
    }
}

struct PayScopeIconBadgeStyle<IconShape: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let shape: IconShape
    let prominence: Double

    func body(content: Content) -> some View {
        let normalizedProminence = min(1, max(0, prominence))
        let tokens = PayScopeThemeTokens.resolve(for: colorScheme)

        content
            .background(
                shape
                    .fill(accent.opacity(tokens.categoryTintOpacity + normalizedProminence * 0.045))
            )
            .overlay(
                shape
                    .stroke(tokens.surfaceStroke, lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape
                    .stroke(accent.opacity(0.15 + normalizedProminence * 0.11), lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func payScopeIconBadge(
        accent: Color,
        prominence: Double = 0.5
    ) -> some View {
        modifier(
            PayScopeIconBadgeStyle(
                accent: accent,
                shape: Circle(),
                prominence: prominence
            )
        )
    }

    func payScopeIconBadge<IconShape: InsettableShape>(
        accent: Color,
        in shape: IconShape,
        prominence: Double = 0.5
    ) -> some View {
        modifier(
            PayScopeIconBadgeStyle(
                accent: accent,
                shape: shape,
                prominence: prominence
            )
        )
    }
}

struct PayScopeGlassSurfaceStyle: ViewModifier {
    let accent: Color
    let cornerRadius: CGFloat
    let tintOpacity: Double
    let shadowOpacity: Double
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .payScopeContentSurface(
                accent: accent,
                cornerRadius: cornerRadius,
                emphasis: min(0.55, tintOpacity * 4),
                shadowOpacity: shadowOpacity
            )
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

struct PayScopePureGlassSurfaceStyle<SurfaceShape: InsettableShape>: ViewModifier {
    let accent: Color
    let shape: SurfaceShape
    let tintOpacity: Double
    let shadowOpacity: Double
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .payScopeContentSurface(
                accent: accent,
                in: shape,
                emphasis: min(0.5, tintOpacity * 4),
                shadowOpacity: shadowOpacity
            )
    }
}

extension View {
    func payScopePureGlassSurface<SurfaceShape: InsettableShape>(
        accent: Color,
        in shape: SurfaceShape,
        tintOpacity: Double = 0.06,
        shadowOpacity: Double = 0.08,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            PayScopePureGlassSurfaceStyle(
                accent: accent,
                shape: shape,
                tintOpacity: tintOpacity,
                shadowOpacity: shadowOpacity,
                isInteractive: isInteractive
            )
        )
    }

    func payScopePureGlassSurface(
        accent: Color,
        cornerRadius: CGFloat = 18,
        tintOpacity: Double = 0.06,
        shadowOpacity: Double = 0.08,
        isInteractive: Bool = false
    ) -> some View {
        payScopePureGlassSurface(
            accent: accent,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tintOpacity: tintOpacity,
            shadowOpacity: shadowOpacity,
            isInteractive: isInteractive
        )
    }
}

struct PayScopeLiquidGlassStyle: ViewModifier {
    let accent: Color
    let cornerRadius: CGFloat
    let tintOpacity: Double

    func body(content: Content) -> some View {
        content
            .payScopeContentSurface(
                accent: accent,
                cornerRadius: cornerRadius,
                emphasis: min(0.5, tintOpacity * 4),
                shadowOpacity: 0.06
            )
    }
}

extension View {
    func payScopeLiquidGlass(accent: Color, cornerRadius: CGFloat = 16, tintOpacity: Double = 0.1) -> some View {
        modifier(PayScopeLiquidGlassStyle(accent: accent, cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }
}

struct PayScopeLiquidGlassIconStyle<IconShape: InsettableShape>: ViewModifier {
    let accent: Color
    let shape: IconShape
    let tintOpacity: Double
    let shadowOpacity: Double
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .payScopeIconBadge(
                accent: accent,
                in: shape,
                prominence: min(1, tintOpacity * 5)
            )
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
        content
    }
}

struct PayScopeGlassControlStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let cornerRadius: CGFloat
    let tintOpacity: Double
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tokens = PayScopeThemeTokens.resolve(for: colorScheme)
        let activeTint = min(0.14, max(0.06, tintOpacity))

        content
            .background(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                tokens.elevatedSurfaceFill,
                                accent.opacity(activeTint * (colorScheme == .light ? 0.82 : 0.62)),
                                tokens.surfaceFill
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                shape
                    .stroke(tokens.surfaceStroke, lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape
                    .stroke(accent.opacity(activeTint * (isInteractive ? 1.5 : 1.05)), lineWidth: 0.85)
                    .allowsHitTesting(false)
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
            .opacity(configuration.isPressed ? 0.9 : 1)
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
            .presentationBackground(Color.clear)
            .presentationCornerRadius(geometry.outerCornerRadius)
    }
}

struct PayScopePopoverSurface: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        let geometry = PayScopeModalGeometry.popover

        content
            .background(Color.clear)
            .presentationBackground(Color.clear)
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
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        let tokens = PayScopeThemeTokens.resolve(for: colorScheme)

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
            .shadow(color: .black.opacity(tokens.shadowOpacity + 0.04), radius: 7, x: 0, y: 4)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct PayScopeSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        let tokens = PayScopeThemeTokens.resolve(for: colorScheme)

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
                                accent.opacity(configuration.isPressed ? tokens.categoryTintOpacity + 0.08 : tokens.categoryTintOpacity),
                                tokens.surfaceFill
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(colorScheme == .light ? 0.24 : 0.32), lineWidth: 1)
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
