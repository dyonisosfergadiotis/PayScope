import SwiftUI
import Combine
import Network
import SwiftData

struct RootView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let localStore = LocalDayEntryStore.shared
    @AppStorage("payscope.onboarding.completed.sticky") private var onboardingCompletionSticky = false
    @State private var settingsList: [Settings] = []
    @State private var entries: [DayEntry] = []

    @State private var didRunInitialLiveActivitySync = false
    @State private var isSyncingLiveActivity = false
    @State private var didBootstrapSettings = false
    @State private var hasSeenOfflineState = false
    @State private var hasHandledInitialActivePhase = false
    @State private var isResolvingOnboardingGate = true
    @State private var pendingLiveActivitySyncTask: Task<Void, Never>?
    @StateObject private var connectivityMonitor = ConnectivityMonitor()

    @State private var isLoadingData = false

    var body: some View {
        Group {
            if let settings = settingsList.first {
                let hasCompletedOnboarding = settings.hasCompletedOnboarding || onboardingCompletionSticky
                if isResolvingOnboardingGate && !hasCompletedOnboarding {
                    ProgressView("iCloud-Status wird geprüft...")
                } else if hasCompletedOnboarding {
                    ZStack {
                        Color.clear
                            .payScopeBackground(accent: settings.themeAccent.color)
                        CalendarTabView(
                            settings: settings,
                            isOffline: !connectivityMonitor.isOnline
                        )
                    }
                    .task {
                        guard !didRunInitialLiveActivitySync else { return }
                        didRunInitialLiveActivitySync = true
                        await syncLiveActivity()
                        Task { @MainActor in
                            await loadData()
                            await syncLiveActivity()
                        }
                    }
                } else {
                    OnboardingContainerView(settings: settings)
                }
            } else {
                ProgressView("PayScope wird vorbereitet...")
                    .task {
                        guard !didBootstrapSettings else { return }
                        didBootstrapSettings = true

                        // Local-first: load (and de-duplicate) the local Settings singleton
                        let descriptor = FetchDescriptor<Settings>(predicate: #Predicate<Settings> { $0.key == "singleton" })
                        let fetched = (try? modelContext.fetch(descriptor)) ?? []

                        let local: Settings
                        if let newest = fetched.max(by: { $0.updatedAt < $1.updatedAt }) {
                            local = newest

                            // Delete any duplicates so we never flip onboarding due to old records
                            for s in fetched where s !== newest {
                                modelContext.delete(s)
                            }
                            try? modelContext.save()
                        } else {
                            // Fresh local installs should not outrank an existing cloud singleton.
                            let created = Settings(key: "singleton", updatedAt: .distantPast)
                            modelContext.insert(created)
                            try? modelContext.save()
                            local = created
                        }

                        settingsList = [local]
                        if local.hasCompletedOnboarding {
                            onboardingCompletionSticky = true
                        }
                        await refreshSettingsFromCloud(pushLocalIfMissing: true)
                        isResolvingOnboardingGate = false
                    }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .dayEntriesDidChange)
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
        ) { _ in
            guard scenePhase == .active else { return }
            scheduleLiveActivitySync()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Initial activation already runs startup tasks above.
                if !hasHandledInitialActivePhase {
                    hasHandledInitialActivePhase = true
                    return
                }
                // Refresh all cloud-backed state when returning to foreground.
                Task {
                    await refreshSettingsFromCloud(pushLocalIfMissing: false)
                    await loadData()
                }
                scheduleLiveActivitySync()
                return
            }
        }
        .onChange(of: connectivityMonitor.isOnline) { _, isOnline in
            guard isOnline else {
                hasSeenOfflineState = true
                return
            }

            guard hasSeenOfflineState else { return }
            hasSeenOfflineState = false
            Task { await refreshSettingsFromCloud(pushLocalIfMissing: true) }
        }
        .onDisappear {
            pendingLiveActivitySyncTask?.cancel()
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

    private func liveActivitySyncInterval(reference: Date = .now) -> DateInterval {
        let dayStart = reference.startOfDayLocal()
        return DateInterval(start: dayStart.addingDays(-2), end: dayStart.addingDays(35))
    }

    @MainActor
    private func syncLiveActivity() async {
        guard !isSyncingLiveActivity else { return }
        guard let settings = settingsList.first, settings.hasCompletedOnboarding else { return }

        isSyncingLiveActivity = true
        defer { isSyncingLiveActivity = false }

        await PayScopeLiveActivityManager.syncAtAppLaunch(
            settings: settings,
            entries: mergedEntriesForLiveActivity()
        )
    }

    private func mergedEntriesForLiveActivity() -> [DayEntry] {
        let interval = liveActivitySyncInterval()
        let localEntries = localStore.loadAll(in: interval)
        let merged = Dictionary(
            (localEntries + entries).map { ($0.date.startOfDayLocal(), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        return merged.values.sorted { $0.date < $1.date }
    }

    @MainActor
    private func loadData() async {
        guard !isLoadingData else { return }
        isLoadingData = true
        defer { isLoadingData = false }

        let interval = liveActivitySyncInterval()
        let localEntries = localStore.loadAll(in: interval)
        if entries.isEmpty {
            entries = localEntries.sorted { $0.date < $1.date }
        }

        do {
            let cloudEntries = try await cloudKitService.fetchDayEntries(in: interval)
            let merged = Dictionary(
                (localEntries + cloudEntries).map { ($0.date.startOfDayLocal(), $0) },
                uniquingKeysWith: { existing, candidate in
                    candidate.updatedAt > existing.updatedAt ? candidate : existing
                }
            )
            entries = merged.values.sorted { $0.date < $1.date }
            localStore.upsertMany(cloudEntries, notify: false)
        } catch {
            #if DEBUG
            print("Failed to load data from CloudKit: \(error)")
            #endif
        }
    }

    @MainActor
    private func refreshSettingsFromCloud(pushLocalIfMissing: Bool) async {
        guard let local = settingsList.first else { return }

        if onboardingCompletionSticky && !local.hasCompletedOnboarding {
            local.hasCompletedOnboarding = true
            try? modelContext.save()
            settingsList = [local]
        }

        do {
            if let remote = try await cloudKitService.fetchSettingsSingleton() {
                let keepCompletedOnboarding = local.hasCompletedOnboarding || onboardingCompletionSticky
                let localLooksUnconfigured =
                    !local.hasCompletedOnboarding &&
                    local.hourlyRateCents == nil &&
                    local.monthlySalaryCents == nil &&
                    local.weeklyTargetSeconds == nil

                // If local state is still a blank default, prefer remote regardless of timestamps.
                if remote.updatedAt > local.updatedAt || localLooksUnconfigured {
                    local.applyValues(from: remote)
                    if keepCompletedOnboarding || remote.hasCompletedOnboarding {
                        local.hasCompletedOnboarding = true
                    }
                    if local.hasCompletedOnboarding {
                        onboardingCompletionSticky = true
                    }
                    try? modelContext.save()
                    settingsList = [local]
                } else if remote.hasCompletedOnboarding && !local.hasCompletedOnboarding {
                    // Onboarding completion is monotonic: once completed on any device,
                    // do not force onboarding again on this device.
                    local.hasCompletedOnboarding = true
                    local.updatedAt = max(local.updatedAt, remote.updatedAt)
                    onboardingCompletionSticky = true
                    try? modelContext.save()
                    settingsList = [local]
                } else if local.hasCompletedOnboarding && !remote.hasCompletedOnboarding {
                    // Keep completion monotonic across devices even if the cloud copy is stale.
                    try? modelContext.save()
                    try await cloudKitService.saveSettings(local)
                } else if pushLocalIfMissing && local.updatedAt > remote.updatedAt {
                    try? modelContext.save()
                    try await cloudKitService.saveSettings(local)
                }
                return
            }

            if pushLocalIfMissing || local.hasCompletedOnboarding {
                try? modelContext.save()
                try await cloudKitService.saveSettings(local)
            }
        } catch {
            // Offline or CloudKit error: keep local settings.
        }
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
