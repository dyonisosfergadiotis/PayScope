import SwiftUI

struct PayScopeLaunchSplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color

    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let isDarkMode = colorScheme == .dark

            ZStack {
                Color("LaunchBackground")
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        accent.opacity(isDarkMode ? 0.92 : 0.82),
                        accent.opacity(isDarkMode ? 0.58 : 0.44),
                        isDarkMode ? Color.black : Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        LinearGradient(
                            colors: [
                                .white.opacity(isDarkMode ? 0.18 : 0.28),
                                accent.opacity(isDarkMode ? 0.18 : 0.16),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        RadialGradient(
                            colors: [
                                .white.opacity(isDarkMode ? 0.2 : 0.34),
                                accent.opacity(isDarkMode ? 0.14 : 0.12),
                                .clear
                            ],
                            center: .top,
                            startRadius: 24,
                            endRadius: max(geometry.size.width, geometry.size.height) * 0.7
                        )
                    }
                    .frame(height: geometry.size.height * 0.6)

                    Spacer(minLength: 0)
                }
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 104, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                        .shadow(color: accent.opacity(0.32), radius: 16, y: 8)
                        .frame(width: 136, height: 120)

                    Text("PayScope")
                        .font(.system(size: 46, weight: .bold, design: .default))
                        .kerning(-1)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(isDarkMode ? 0.22 : 0.12), radius: 8, y: 4)
                        .fixedSize()
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                VStack {
                    Spacer()

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.08))

                        Capsule()
                            .fill(.white)
                            .frame(width: 100 * progress)
                    }
                    .frame(width: 100, height: 2)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 36)
                }
            }
        }
        .onAppear {
            progress = 0
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                progress = 1
            }
        }
    }
}

#Preview {
    PayScopeLaunchSplashView(accent: .blue)
}
