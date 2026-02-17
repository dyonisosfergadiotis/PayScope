import SwiftUI
import SwiftData

@main
struct WageWiseApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DayEntry.self,
            TimeSegment.self,
            Settings.self,
            NetWageMonthConfig.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
