import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [Settings]

    var body: some View {
        Group {
            if let settings = settingsList.first {
                if settings.hasCompletedOnboarding {
                    ZStack {
                        Color.clear
                            .wageWiseBackground(accent: settings.themeAccent.color)
                        CalendarTabView(settings: settings)
                    }
                } else {
                    OnboardingContainerView(settings: settings)
                }
            } else {
                ProgressView("WageWise wird vorbereitet...")
                    .task {
                        modelContext.insert(Settings())
                        modelContext.persistIfPossible()
                    }
            }
        }
    }
}
