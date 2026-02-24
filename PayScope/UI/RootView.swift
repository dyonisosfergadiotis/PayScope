import SwiftUI
import SwiftData
import Combine
import Network
import CoreData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [Settings]
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]
    @Query(sort: \NetWageMonthConfig.monthStart) private var netWageConfigs: [NetWageMonthConfig]
    @Query(sort: \HolidayCalendarDay.date) private var holidayDays: [HolidayCalendarDay]

    @State private var didRunInitialLiveActivitySync = false
    @State private var isSyncingLiveActivity = false
    @State private var didBootstrapSettings = false
    @State private var didRunInitialICloudForceSync = false
    @State private var isApplyingCloudSync = false
    @State private var hasSeenOfflineState = false
    @State private var pendingLiveActivitySyncTask: Task<Void, Never>?
    @State private var pendingCloudExportTask: Task<Void, Never>?
    @StateObject private var connectivityMonitor = ConnectivityMonitor()

    private let liveActivityTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let iCloudSettingsChangePublisher = NotificationCenter.default.publisher(
        for: NSUbiquitousKeyValueStore.didChangeExternallyNotification
    )
    private let userDefaultsChangePublisher = NotificationCenter.default.publisher(
        for: UserDefaults.didChangeNotification
    )
    private let modelContextDidSavePublisher = NotificationCenter.default.publisher(
        for: .NSManagedObjectContextDidSave
    )

    var body: some View {
        Group {
            if let settings = settingsList.first {
                if settings.hasCompletedOnboarding {
                    ZStack {
                        Color.clear
                            .payScopeBackground(accent: settings.themeAccent.color)
                        CalendarTabView(
                            settings: settings,
                            isOffline: !connectivityMonitor.isOnline
                        )
                    }
                    .task {
                        scheduleLaunchICloudSyncIfNeeded(
                            settings,
                            entries: entries,
                            netWageConfigs: netWageConfigs,
                            holidayDays: holidayDays
                        )
                        guard !didRunInitialLiveActivitySync else { return }
                        didRunInitialLiveActivitySync = true
                        await syncLiveActivity()
                    }
                } else {
                    OnboardingContainerView(settings: settings)
                        .task {
                            scheduleLaunchICloudSyncIfNeeded(
                                settings,
                                entries: entries,
                                netWageConfigs: netWageConfigs,
                                holidayDays: holidayDays
                            )
                        }
                }
            } else {
                ProgressView("PayScope wird vorbereitet...")
                    .task {
                        guard !didBootstrapSettings else { return }
                        didBootstrapSettings = true
                        await bootstrapInitialData()
                    }
            }
        }
        .onReceive(liveActivityTimer) { _ in
            guard scenePhase == .active else { return }
            scheduleLiveActivitySync()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if let settings = settingsList.first, !didRunInitialICloudForceSync {
                    scheduleLaunchICloudSyncIfNeeded(
                        settings,
                        entries: entries,
                        netWageConfigs: netWageConfigs,
                        holidayDays: holidayDays
                    )
                }
                scheduleLiveActivitySync()
                scheduleCloudExport()
                return
            }

            scheduleCloudExport(requiresActiveScene: false)
        }
        .onReceive(modelContextDidSavePublisher) { _ in
            scheduleLiveActivitySync(delayNanoseconds: 300_000_000)
            scheduleCloudExport(delayNanoseconds: 700_000_000)
        }
        .onReceive(iCloudSettingsChangePublisher) { notification in
            Task { @MainActor in
                guard ICloudSettingsSync.shouldHandleExternalChange(notification) else { return }
                guard let settings = settingsList.first else { return }
                forceSyncFromICloud(
                    settings,
                    entries: entries,
                    netWageConfigs: netWageConfigs,
                    holidayDays: holidayDays
                )
            }
        }
        .onReceive(userDefaultsChangePublisher) { _ in
            scheduleCloudExport()
        }
        .onChange(of: connectivityMonitor.isOnline) { _, isOnline in
            guard !isOnline else {
                guard hasSeenOfflineState else { return }
                hasSeenOfflineState = false
                Task { @MainActor in
                    guard let settings = settingsList.first else { return }
                    forceSyncFromICloud(
                        settings,
                        entries: entries,
                        netWageConfigs: netWageConfigs,
                        holidayDays: holidayDays
                    )
                }
                return
            }

            hasSeenOfflineState = true
        }
        .onDisappear {
            pendingLiveActivitySyncTask?.cancel()
            pendingCloudExportTask?.cancel()
        }
    }

    private func scheduleLiveActivitySync(delayNanoseconds: UInt64 = 0) {
        pendingLiveActivitySyncTask?.cancel()
        pendingLiveActivitySyncTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard scenePhase == .active else { return }
            await syncLiveActivity()
        }
    }

    private func scheduleCloudExport(
        delayNanoseconds: UInt64 = 300_000_000,
        requiresActiveScene: Bool = true
    ) {
        pendingCloudExportTask?.cancel()
        pendingCloudExportTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            if requiresActiveScene && scenePhase != .active {
                return
            }
            exportICloudSnapshotIfPossible()
        }
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

    private func scheduleLaunchICloudSyncIfNeeded(
        _ settings: Settings,
        entries: [DayEntry],
        netWageConfigs: [NetWageMonthConfig],
        holidayDays: [HolidayCalendarDay]
    ) {
        guard !didRunInitialICloudForceSync else { return }
        didRunInitialICloudForceSync = true
        Task { @MainActor in
            // Avoid blocking the first render pass; run iCloud reconciliation shortly after launch.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard scenePhase == .active else { return }
            forceSyncFromICloud(
                settings,
                entries: entries,
                netWageConfigs: netWageConfigs,
                holidayDays: holidayDays
            )
        }
    }

    @MainActor
    private func forceSyncFromICloud(
        _ settings: Settings,
        entries: [DayEntry],
        netWageConfigs: [NetWageMonthConfig],
        holidayDays: [HolidayCalendarDay]
    ) {
        isApplyingCloudSync = true
        defer { isApplyingCloudSync = false }

        guard ICloudSettingsSync.forceSyncDownIntoStore(
            settings: settings,
            localEntries: entries,
            localNetWageConfigs: netWageConfigs,
            localHolidayDays: holidayDays,
            modelContext: modelContext
        ) else { return }
        modelContext.persistIfPossible()
    }

    @MainActor
    private func exportICloudSnapshotIfPossible() {
        guard !isApplyingCloudSync else { return }
        guard let settings = settingsList.first else { return }
        ICloudSettingsSync.export(
            settings: settings,
            entries: entries,
            netWageConfigs: netWageConfigs,
            holidayDays: holidayDays
        )
    }

    @MainActor
    private func bootstrapInitialData() async {
        guard settingsList.isEmpty else { return }

        let initialSettings = Settings()
        modelContext.insert(initialSettings)

        for attempt in 1...4 {
            do {
                try modelContext.save()
                return
            } catch {
                #if DEBUG
                print("Initial settings bootstrap save attempt \(attempt) failed: \(error)")
                #endif
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 300_000_000)
            }
        }

        #if DEBUG
        print("Initial settings bootstrap exhausted retries; pending unsaved state remains.")
        #endif
    }
}

private final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PayScope.ConnectivityMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
