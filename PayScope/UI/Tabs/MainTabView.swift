import SwiftUI
import SwiftData

struct MainTabView: View {
    @Bindable var settings: Settings

    var body: some View {
        TabView {
            TodayTabView(settings: settings)
                .tabItem {
                    Label("Heute", systemImage: "sun.max")
                }

            CalendarTabView(settings: settings)
                .tabItem {
                    Label("Kalender", systemImage: "calendar")
                }

            StatsTabView(settings: settings, referenceMonth: Date())
                .tabItem {
                    Label("Statistik", systemImage: "chart.bar")
                }

            SettingsTabView(settings: settings)
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape")
                }
        }
        .tint(settings.themeAccent.color)
        .wageWiseBackground(accent: settings.themeAccent.color)
    }
}
