import SwiftUI
import SwiftData
import Combine

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [Settings]
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]

    @State private var didRunInitialLiveActivitySync = false
    @State private var isSyncingLiveActivity = false

    private let liveActivityTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let settings = settingsList.first {
                if settings.hasCompletedOnboarding {
                    ZStack {
                        Color.clear
                            .payScopeBackground(accent: settings.themeAccent.color)
                        CalendarTabView(settings: settings)
                    }
                    .task {
                        guard !didRunInitialLiveActivitySync else { return }
                        didRunInitialLiveActivitySync = true
                        await syncLiveActivity()
                    }
                } else {
                    OnboardingContainerView(settings: settings)
                }
            } else {
                ProgressView("PayScope wird vorbereitet...")
                    .task {
                        modelContext.insert(Settings())
                        modelContext.persistIfPossible()
                }
            }
        }
        .onReceive(liveActivityTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await syncLiveActivity() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await syncLiveActivity() }
        }
        .onChange(of: liveSyncSignature) { _, _ in
            Task { await syncLiveActivity() }
        }
    }

    private var liveSyncSignature: Int {
        var hasher = Hasher()

        if let settings = settingsList.first {
            hasher.combine(settings.hasCompletedOnboarding)
            hasher.combine(settings.themeAccent.rawValue)
            hasher.combine(settings.payMode.rawValue)
            hasher.combine(settings.hourlyRateCents ?? -1)
            hasher.combine(settings.monthlySalaryCents ?? -1)
            hasher.combine(settings.timelineMinMinute ?? -1)
            hasher.combine(settings.timelineMaxMinute ?? -1)
            hasher.combine(settings.weekStart.rawValue)
            hasher.combine(settings.holidayCreditingMode.rawValue)
            hasher.combine(settings.scheduledWorkdaysCount)
            hasher.combine(settings.strictHistoryRequired)
            hasher.combine(settings.countMissingAsZero)
        }

        let today = Date().startOfDayLocal()
        if let day = entries.first(where: { $0.date.isSameLocalDay(as: today) }) {
            hasher.combine(day.type.rawValue)
            hasher.combine(day.manualWorkedSeconds ?? -1)
            for segment in day.segments {
                hasher.combine(segment.start.timeIntervalSinceReferenceDate)
                hasher.combine(segment.end.timeIntervalSinceReferenceDate)
                hasher.combine(segment.breakSeconds)
            }
        } else {
            hasher.combine("no-today-entry")
        }

        return hasher.finalize()
    }

    @MainActor
    private func syncLiveActivity() async {
        guard !isSyncingLiveActivity else { return }
        guard let settings = settingsList.first, settings.hasCompletedOnboarding else { return }

        isSyncingLiveActivity = true
        defer { isSyncingLiveActivity = false }

        await PayScopeLiveActivityManager.syncAtAppLaunch(
            settings: settings,
            entries: entries
        )
    }
}
