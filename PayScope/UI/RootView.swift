import SwiftUI
import Combine
import Network
import SwiftData
import WatchConnectivity
import WidgetKit
import Notelet

struct RootView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let localStore = LocalDayEntryStore.shared
    private let calculationService = CalculationService()
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
    @State private var pendingWatchSnapshotSyncTask: Task<Void, Never>?
    @StateObject private var connectivityMonitor = ConnectivityMonitor()
    @StateObject private var watchSnapshotBridge = WatchSnapshotBridge()

    @State private var isLoadingData = false
    @State private var isShowingLaunchSplash = true

    var body: some View {
        Group {
            if let settings = settingsList.first {
                let hasCompletedOnboarding = settings.hasCompletedOnboarding || onboardingCompletionSticky
                if isResolvingOnboardingGate && !hasCompletedOnboarding {
                    ProgressView("iCloud-Status wird geprüft...")
                } else if hasCompletedOnboarding {
                    MainTabNavigationView(
                        settings: settings,
                        entries: entries,
                        isOffline: !connectivityMonitor.isOnline
                    )
                    .task {
                        guard !didRunInitialLiveActivitySync else { return }
                        didRunInitialLiveActivitySync = true
                        await syncLiveActivity()
                        scheduleWatchSnapshotSync()
                        Task { @MainActor in
                            await loadData()
                            await syncLiveActivity()
                            scheduleWatchSnapshotSync()
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
        .overlay {
            if isShowingLaunchSplash {
                PayScopeLaunchSplashView(accent: settingsList.first?.themeAccent.color ?? .blue)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: isShowingLaunchSplash)
        .task {
            guard isShowingLaunchSplash else { return }
            try? await Task.sleep(nanoseconds: 1_350_000_000)
            await MainActor.run {
                isShowingLaunchSplash = false
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .dayEntriesDidChange)
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
        ) { _ in
            guard scenePhase == .active else { return }
            Task { await loadData() }
            scheduleLiveActivitySync()
            scheduleWatchSnapshotSync()
            reloadAppWidgets()
        }
        .onChange(of: settingsList.first?.effectiveShowLiveActivity ?? true) { _, _ in
            guard scenePhase == .active else { return }
            scheduleLiveActivitySync()
        }
        .onChange(of: settingsList.first?.updatedAt) { _, _ in
            scheduleLiveActivitySync()
            scheduleWatchSnapshotSync()
            reloadAppWidgets()
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
                scheduleWatchSnapshotSync()
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
            pendingWatchSnapshotSyncTask?.cancel()
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

    private func scheduleWatchSnapshotSync(delayNanoseconds: UInt64 = 0) {
        pendingWatchSnapshotSyncTask?.cancel()
        pendingWatchSnapshotSyncTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            syncWatchSnapshotIfPossible()
        }
    }

    @MainActor
    private func reloadAppWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func liveActivitySyncInterval(reference: Date = .now) -> DateInterval {
        let dayStart = reference.startOfDayLocal()
        let weekStart = calculationService.weekStartDate(for: dayStart)
        return DateInterval(start: weekStart, end: dayStart.addingDays(35))
    }

    private func watchSnapshotSyncInterval(reference: Date = .now) -> DateInterval {
        let dayStart = reference.startOfDayLocal()
        return DateInterval(start: dayStart.addingDays(-84), end: dayStart.addingDays(84))
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

    private func mergedEntriesForWatchSnapshot() -> [DayEntry] {
        let interval = watchSnapshotSyncInterval()
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
    private func syncWatchSnapshotIfPossible() {
        guard let settings = settingsList.first, settings.hasCompletedOnboarding else { return }

        let mergedEntries = mergedEntriesForWatchSnapshot()
        let entriesByDate = calculationService.makeEntriesByDateLookup(from: mergedEntries)
        let days = mergedEntries.map { day in
            let result = calculationService.dayComputation(
                for: day,
                entriesByDate: entriesByDate,
                settings: settings
            )
            return WatchSnapshotDayPayload(
                date: day.date.startOfDayLocal(),
                dayTypeLabel: day.type.label,
                iconName: day.type.icon,
                workedSeconds: result.valueSecondsOrZero,
                payCents: result.valueCentsOrZero,
                shiftStart: day.shiftStart,
                shiftEnd: day.shiftEnd
            )
        }

        watchSnapshotBridge.push(
            snapshot: WatchSnapshotPayload(
                generatedAt: .now,
                days: days
            )
        )
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
            scheduleWatchSnapshotSync()
        }

        do {
            let tombstonesByDay = Dictionary(
                localStore.loadDeletionTombstones().map { (dayKey($0.date), $0.lastModified) },
                uniquingKeysWith: { current, incoming in
                    incoming > current ? incoming : current
                }
            )
            let cloudEntries = try await cloudKitService.fetchDayEntries(in: interval).filter { cloudEntry in
                guard let deletedAt = tombstonesByDay[dayKey(cloudEntry.date)] else { return true }
                return deletedAt < cloudEntry.updatedAt
            }
            let merged = Dictionary(
                (localEntries + cloudEntries).map { ($0.date.startOfDayLocal(), $0) },
                uniquingKeysWith: { existing, candidate in
                    candidate.updatedAt > existing.updatedAt ? candidate : existing
                }
            )
            entries = merged.values.sorted { $0.date < $1.date }
            localStore.upsertMany(cloudEntries, notify: false)
            scheduleWatchSnapshotSync()
        } catch {
            #if DEBUG
            print("Failed to load data from CloudKit: \(error)")
            #endif
            scheduleWatchSnapshotSync()
        }
    }

    private func dayKey(_ date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    @MainActor
    private func refreshSettingsFromCloud(pushLocalIfMissing: Bool) async {
        defer { scheduleWatchSnapshotSync() }
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

private enum MainAppTab: Hashable {
    case calendar
    case hoursAccount
    case stats
    case settings
    case today
}

private struct MainTabNavigationView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var settings: Settings
    let entries: [DayEntry]
    let isOffline: Bool

    @State private var selection: MainAppTab = .calendar
    @State private var displayedMonth = Date().startOfMonthLocal()
    @State private var showTodaySheet = false
    @State private var tabSelectionFeedbackTrigger = 0
    @State private var todayActionFeedbackTrigger = 0
    @AppStorage(FeatureSplashNotes.storageKey) private var hasSeenFeatureSplash = false

    private var todayEntry: DayEntry? {
        let today = Date().startOfDayLocal()
        return entries.first { $0.date.isSameLocalDay(as: today) }
    }

    private var todayFabIcon: String {
        todayEntry?.type.icon ?? "sun.max.fill"
    }

    private var todayFabAccessibilityLabel: String {
        if let todayEntry {
            return "Heute, \(todayEntry.type.label)"
        }
        return "Heute"
    }


    private var tabBarVisibility: Visibility {
        horizontalSizeClass == .compact ? .hidden : .visible
    }

    var body: some View {
        ZStack {
            Color.clear
                .payScopeBackground(accent: settings.themeAccent.color)

            TabView(selection: $selection) {
                Tab("Kalender", systemImage: "calendar", value: MainAppTab.calendar) {
                    CalendarTabView(displayedMonth: $displayedMonth, settings: settings, isOffline: isOffline)
                }

                if !settings.effectiveAushilfeModeEnabled {
                    Tab("Stundenkonto", systemImage: "plusminus.circle", value: MainAppTab.hoursAccount) {
                        HoursAccountTabView(settings: settings, referenceMonth: $displayedMonth)
                    }
                }

                Tab("Statistik", systemImage: "chart.bar.xaxis", value: MainAppTab.stats) {
                    StatsTabView(settings: settings, referenceMonth: $displayedMonth)
                }

                Tab("Einstellungen", systemImage: "gearshape", value: MainAppTab.settings) {
                    SettingsTabView(settings: settings)
                }
                
                Tab(value: MainAppTab.today, role: .search) {
                    Color.clear
                } label: {
                    Label("Heute", systemImage: todayFabIcon)
                }
            }
            .tint(settings.themeAccent.color)
            .toolbarBackground(settings.themeAccent.color.opacity(0.22), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .tabBarMinimizeBehavior(.onScrollDown)
            .onChange(of: selection) { oldSelection, newSelection in
                if newSelection == .today {
                    todayActionFeedbackTrigger += 1
                    selection = oldSelection
                    showTodaySheet = true
                } else {
                    tabSelectionFeedbackTrigger += 1
                }
            }
            .onChange(of: settings.effectiveAushilfeModeEnabled) { _, isEnabled in
                if isEnabled, selection == .hoursAccount {
                    selection = .calendar
                }
            }
            .sensoryFeedback(.selection, trigger: tabSelectionFeedbackTrigger)
            .sensoryFeedback(.selection, trigger: todayActionFeedbackTrigger)
            .sheet(isPresented: $showTodaySheet) {
                TodayFocusView(
                    settings: settings,
                    entriesOverride: entries
                )
                .presentationDetents([.fraction(0.58)])
                .payScopeSheetSurface(accent: settings.themeAccent.color)
            }
        }
        .tint(settings.themeAccent.color)
        .noteletSheet(
            notes: FeatureSplashNotes.notes,
            version: hasSeenFeatureSplash ? nil : .v(FeatureSplashNotes.version),
            onDismiss: {
                hasSeenFeatureSplash = true
            },
            configuration: NoteletConfiguration(
                nextButtonLabel: "Weiter",
                doneButtonLabel: "Loslegen",
                accentColor: settings.themeAccent.color
            )
        )
    }

}

private enum WatchSnapshotBridgeKeys {
    static let payloadData = "payscope.watch.snapshot.data.v1"
    static let generatedAt = "payscope.watch.snapshot.generatedAt.v1"
    static let requestSnapshot = "requestSnapshot"
    static let reloadComplications = "reloadComplications"
    static let reloadIOSWidgets = "reloadIOSWidgets"
}

private struct WatchSnapshotDayPayload: Codable {
    let date: Date
    let dayTypeLabel: String
    let iconName: String
    let workedSeconds: Int
    let payCents: Int
    let shiftStart: Date?
    let shiftEnd: Date?
}

private struct WatchSnapshotPayload: Codable {
    let generatedAt: Date
    let days: [WatchSnapshotDayPayload]
}

private final class WatchSnapshotBridge: NSObject, ObservableObject {
    private let contextQueue = DispatchQueue(label: "PayScope.WatchSnapshotBridge.ContextQueue")
    private let encoder = JSONEncoder()
    private let session: WCSession?

    private var latestContext: [String: Any] = [:]

    override init() {
        if WCSession.isSupported() {
            session = WCSession.default
        } else {
            session = nil
        }

        super.init()
        session?.delegate = self
        session?.activate()
    }

    func push(snapshot: WatchSnapshotPayload) {
        guard let session else { return }
        guard let encoded = try? encoder.encode(snapshot) else { return }

        let context: [String: Any] = [
            WatchSnapshotBridgeKeys.payloadData: encoded,
            WatchSnapshotBridgeKeys.generatedAt: snapshot.generatedAt.timeIntervalSince1970
        ]

        contextQueue.sync {
            latestContext = context
        }

        do {
            try session.updateApplicationContext(context)
        } catch {
            #if DEBUG
            print("Failed to push watch snapshot context: \(error)")
            #endif
        }

        notifyWatchComplicationsReload(
            from: session,
            generatedAt: snapshot.generatedAt
        )
    }

    private func notifyWatchComplicationsReload(from session: WCSession, generatedAt: Date) {
        let payload: [String: Any] = [
            WatchSnapshotBridgeKeys.reloadComplications: true,
            WatchSnapshotBridgeKeys.generatedAt: generatedAt.timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }

        guard session.isPaired, session.isWatchAppInstalled else { return }

        if session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(payload)
        } else {
            _ = session.transferUserInfo(payload)
        }
    }

    private func currentContextForReply(from session: WCSession) -> [String: Any]? {
        let cached = contextQueue.sync { latestContext }
        if !cached.isEmpty {
            return cached
        }

        let received = session.receivedApplicationContext
        if received[WatchSnapshotBridgeKeys.payloadData] != nil {
            return received
        }

        return nil
    }
}

#Preview("Root") {
    let container = try! ModelContainer(
        for: Settings.self,
            DayEntry.self,
            HolidayCalendarDay.self,
            NetWageMonthConfig.self,
            TimeSegment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let settings = Settings(
        hasCompletedOnboarding: true,
        payMode: .hourly,
        hourlyRateCents: 1450,
        weeklyTargetSeconds: 20 * 3600,
        holidayFixedSeconds: 8 * 3600,
        scheduledWorkdaysCount: 5,
        themeAccent: .teal,
        showCalendarWeekNumbers: true,
        showLiveActivity: false,
        shiftShortcut1: "540-1020",
        shiftShortcut2: "720-1080",
        shiftShortcut3: "1080-1440",
        shiftShortcutName1: "Früh",
        shiftShortcutName2: "Mitte",
        shiftShortcutName3: "Spät"
    )
    container.mainContext.insert(settings)

    return RootView()
        .environment(\.locale, Locale(identifier: "de_DE"))
        .environmentObject(CloudKitService.shared)
        .modelContainer(container)
}

extension WatchSnapshotBridge: WCSessionDelegate {
    func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {}

    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if (message[WatchSnapshotBridgeKeys.reloadIOSWidgets] as? Bool) == true {
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }

        guard (message[WatchSnapshotBridgeKeys.requestSnapshot] as? Bool) == true else { return }
        guard let context = currentContextForReply(from: session) else { return }
        replyHandler(context)
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard (userInfo[WatchSnapshotBridgeKeys.reloadIOSWidgets] as? Bool) == true else { return }
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
