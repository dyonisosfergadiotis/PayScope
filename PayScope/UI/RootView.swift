import SwiftUI
import Combine
import Network
import SwiftData
import WatchConnectivity
import WidgetKit

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
        .onReceive(NotificationCenter.default.publisher(for: .watchSnapshotRefreshRequested)) { _ in
            Task {
                await refreshSettingsFromCloud(pushLocalIfMissing: false)
                await loadData()
                syncWatchSnapshotIfPossible()
                reloadAppWidgets()
            }
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
        .onChange(of: settingsList.first?.themeAccent) { _, newAccent in
            guard let newAccent else { return }
            #if os(iOS)
            AppIconManager.applyIcon(for: newAccent)
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                #if os(iOS)
                if let accent = settingsList.first?.themeAccent {
                    AppIconManager.applyIcon(for: accent)
                }
                #endif
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
                preferredEntryForSameDay(existing: existing, candidate: candidate)
            }
        )
        return merged.values.filter(\.isRealTrackedDay).sorted { $0.date < $1.date }
    }

    private func mergedEntriesForWatchSnapshot() -> [DayEntry] {
        let interval = watchSnapshotSyncInterval()
        let localEntries = localStore.loadAll(in: interval)
        let merged = Dictionary(
            (localEntries + entries).map { ($0.date.startOfDayLocal(), $0) },
            uniquingKeysWith: { existing, candidate in
                preferredEntryForSameDay(existing: existing, candidate: candidate)
            }
        )
        return merged.values.filter(\.isRealTrackedDay).sorted { $0.date < $1.date }
    }

    private func preferredEntryForSameDay(existing: DayEntry, candidate: DayEntry) -> DayEntry {
        if existing.isRealTrackedDay != candidate.isRealTrackedDay {
            return candidate.isRealTrackedDay ? candidate : existing
        }
        return candidate.updatedAt > existing.updatedAt ? candidate : existing
    }

    @MainActor
    private func syncWatchSnapshotIfPossible() {
        guard let settings = settingsList.first, settings.hasCompletedOnboarding else { return }

        let mergedEntries = mergedEntriesForWatchSnapshot()
        let entriesByDate = calculationService.makeEntriesByDateLookup(from: mergedEntries)
        let now = Date()
        let days = mergedEntries.map { day in
            let result = calculationService.dayComputation(
                for: day,
                entriesByDate: entriesByDate,
                settings: settings
            )
            let earnedSoFarSeconds = calculationService.earnedSecondsSoFar(
                for: day,
                asOf: now,
                entriesByDate: entriesByDate,
                settings: settings
            )
            return WatchSnapshotDayPayload(
                date: day.date.startOfDayLocal(),
                dayTypeRawValue: day.type.rawValue,
                dayTypeLabel: day.type.label,
                iconName: day.type.icon,
                categoryColorRawValue: settings.categoryColorSelection(for: day.type)?.rawValue ?? settings.themeAccent.rawValue,
                workedSeconds: result.valueSecondsOrZero,
                payCents: result.valueCentsOrZero,
                earnedSoFarSeconds: earnedSoFarSeconds,
                earnedSoFarPayCents: calculationService.payCents(for: earnedSoFarSeconds, settings: settings),
                shiftStart: day.shiftStart,
                shiftEnd: day.shiftEnd,
                breakSeconds: max(0, day.breakSeconds ?? 0),
                tipAmountCents: max(0, day.tipAmountCents ?? 0),
                updatedAt: day.updatedAt
            )
        }

        watchSnapshotBridge.push(
            snapshot: WatchSnapshotPayload(
                generatedAt: now,
                themeAccentRawValue: settings.themeAccent.rawValue,
                calendarSummaryDisplayModeRawValue: settings.effectiveCalendarSummaryDisplayMode.rawValue,
                calendarHoursBreakModeRawValue: settings.effectiveCalendarHoursBreakMode.rawValue,
                showTipsAmount: settings.effectiveShowTipsButtonAmount,
                days: days
            )
        )
    }

    @MainActor
    private func loadData() async {
        guard !isLoadingData else { return }
        isLoadingData = true
        defer { isLoadingData = false }

        let interval = watchSnapshotSyncInterval()
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
                    preferredEntryForSameDay(existing: existing, candidate: candidate)
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
    case stats
    case hoursAccount
    case settings
    case today
}

private struct MainTabNavigationView: View {
    @Bindable var settings: Settings
    let entries: [DayEntry]
    let isOffline: Bool

    @State private var selection: MainAppTab = .calendar
    @State private var previousContentSelection: MainAppTab = .calendar
    @State private var displayedMonth = Date().startOfMonthLocal()
    @State private var tabSelectionFeedbackTrigger = 0
    @State private var isTodayFocusSheetPresented = false
    @State private var now = Date()
    @AppStorage(FeatureSplashNotes.storageKey) private var hasSeenFeatureSplash = false

    private let service = CalculationService()
    private let todayTabRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Kalender", systemImage: "calendar", value: MainAppTab.calendar) {
                CalendarTabView(displayedMonth: $displayedMonth, settings: settings, isOffline: isOffline)
            }

            Tab("Statistik", systemImage: "chart.bar.xaxis", value: MainAppTab.stats) {
                StatsTabView(
                    settings: settings,
                    referenceMonth: $displayedMonth,
                    includesTimeAccount: false,
                    isActive: selection == .stats
                )
            }

            if !settings.effectiveAushilfeModeEnabled {
                Tab("Stundenkonto", systemImage: "plusminus.circle", value: MainAppTab.hoursAccount) {
                    HoursAccountTabView(settings: settings, referenceMonth: $displayedMonth)
                }
            }

            Tab("Einstellungen", systemImage: "gearshape", value: MainAppTab.settings) {
                SettingsTabView(settings: settings)
                    .payScopeBackground(accent: settings.themeAccent.color)
            }

            Tab(
                "Heute",
                systemImage: todayTabIcon,
                value: MainAppTab.today,
                role: {
                    if #available(iOS 27, *) {
                        return .prominent
                    } else {
                        return .search
                    }
                }()
            ) {
                Color.clear
            }
        }
            .tint(settings.themeAccent.color)
            .sensoryFeedback(.selection, trigger: tabSelectionFeedbackTrigger)
            .onChange(of: selection) { oldSelection, newSelection in
                tabSelectionFeedbackTrigger += 1
                if newSelection == .today {
                    isTodayFocusSheetPresented = true
                    selection = oldSelection == .today ? previousContentSelection : oldSelection
                } else {
                    previousContentSelection = newSelection
                }
            }
            .onChange(of: settings.effectiveAushilfeModeEnabled) { _, isEnabled in
                guard isEnabled, selection == .hoursAccount else { return }
                selection = .calendar
            }
            .onReceive(todayTabRefreshTimer) { value in
                now = value
            }
            .sheet(isPresented: $isTodayFocusSheetPresented) {
                TodayFocusView(settings: settings, entriesOverride: entries)
                    .presentationDetents([.fraction(0.58), .large])
                    .presentationDragIndicator(.visible)
                    .payScopeSheetSurface(accent: settings.themeAccent.color)
            }
            .sheet(isPresented: featureSplashSheetBinding) {
                FeatureSplashSheetView(
                    cards: FeatureSplashNotes.cards,
                    accent: settings.themeAccent.color,
                    onDone: {
                        hasSeenFeatureSplash = true
                    }
                )
            }
    }

    private var todayTabIcon: String {
        todayFocusEntry?.type.icon ?? DayType.work.icon
    }

    private var todayFocusEntry: DayEntry? {
        let todayStart = now.startOfDayLocal()

        if let active = service.activeShiftEntry(at: now, entries: entries) {
            return active
        }

        if let today = entries.first(where: { $0.isRealTrackedDay && $0.date.isSameLocalDay(as: todayStart) }) {
            if let end = today.shiftEnd,
               now >= end.addingTimeInterval(15 * 60),
               let next = nextShiftEntry(after: now) {
                return next
            }

            return today
        }

        return nextShiftEntry(after: now)
    }

    private func nextShiftEntry(after referenceDate: Date) -> DayEntry? {
        entries
            .filter { entry in
                guard entry.type == .work || entry.type == .manual else { return false }
                guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else { return false }
                return start > referenceDate
            }
            .min { lhs, rhs in
                (lhs.shiftStart ?? .distantFuture) < (rhs.shiftStart ?? .distantFuture)
            }
    }

    private var featureSplashSheetBinding: Binding<Bool> {
        Binding(
            get: {
                !hasSeenFeatureSplash
            },
            set: { isPresented in
                guard !isPresented else { return }
                hasSeenFeatureSplash = true
            }
        )
    }
}

struct HoursAccountTabView: View {
    enum Presentation {
        case standalone
        case embedded
    }

    private enum DataLoadMode {
        case localOnly
        case fullSync
    }

    private enum MonthSelectorStyle {
        case largeTitle
        case subtitle
    }

    @EnvironmentObject private var cloudKitService: CloudKitService
    @Bindable var settings: Settings
    @Binding var referenceMonth: Date
    var presentation: Presentation = .standalone

    @State private var entries: [DayEntry] = []
    @State private var isLoadingData = false
    @State private var showMonthYearPicker = false

    private let localStore = LocalDayEntryStore.shared
    private let service = CalculationService()
    private static let accountStartDate = Date(timeIntervalSince1970: 0)
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    private static let compactMonthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    var body: some View {
        Group {
            switch presentation {
            case .standalone:
                NavigationStack {
                    ScrollView {
                        accountContent
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                    }
                    .navigationTitle("Stundenkonto")
                    .toolbarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("PayScope")
                        }
                        ToolbarItem(placement: .subtitle) {
                            monthYearPickerButton(style: .subtitle)
                        }
                    }
                    .sheet(isPresented: $showMonthYearPicker) {
                        MonthYearPickerSheet(
                            initialMonth: referenceMonth,
                            yearRange: monthYearPickerRange,
                            accent: settings.themeAccent.color
                        ) { selectedMonth in
                            referenceMonth = selectedMonth
                        }
                    }
                }
                .payScopeBackground(accent: settings.themeAccent.color)
            case .embedded:
                accountContent
            }
        }
        .task(id: referenceMonth) {
            await loadData()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .dayEntriesDidChange)
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
        ) { _ in
            Task { await loadData(mode: .localOnly) }
        }
    }

    private var accountContent: some View {
        VStack(spacing: 18) {
            monthBalanceCard
            overallBalanceCard
            detailCards
            accountFlowCard
        }
    }

    private var monthRange: DateInterval {
        Calendar.current.dateInterval(of: .month, for: referenceMonth) ?? DateInterval(start: referenceMonth, end: referenceMonth)
    }

    private var accountLoadInterval: DateInterval {
        DateInterval(
            start: Self.accountStartDate,
            end: monthRange.end.addingTimeInterval(-1)
        )
    }

    private var monthEntries: [DayEntry] {
        entries
            .filter { $0.date >= monthRange.start && $0.date < monthRange.end }
            .sorted { $0.date < $1.date }
    }

    private var entriesBeforeMonth: [DayEntry] {
        entries
            .filter { $0.date < monthRange.start }
            .sorted { $0.date < $1.date }
    }

    private var entriesThroughReferenceMonth: [DayEntry] {
        entries
            .filter { $0.date < monthRange.end }
            .sorted { $0.date < $1.date }
    }

    private var accountStart: Date? {
        entriesThroughReferenceMonth
            .map { $0.date.startOfDayLocal() }
            .min()
    }

    private var monthTotals: HoursAccountTotals {
        totals(for: monthEntries)
    }

    private var beforeMonthTotals: HoursAccountTotals {
        totals(for: entriesBeforeMonth)
    }

    private var overallTotals: HoursAccountTotals {
        totals(for: entriesThroughReferenceMonth)
    }

    private var monthTargetSeconds: Int? {
        targetSeconds(from: monthRange.start, to: monthRange.end)
    }

    private var beforeMonthTargetSeconds: Int? {
        guard let accountStart, accountStart < monthRange.start else { return 0 }
        return targetSeconds(from: accountStart, to: monthRange.start)
    }

    private var overallTargetSeconds: Int? {
        guard let accountStart else { return nil }
        return targetSeconds(from: accountStart, to: monthRange.end)
    }

    private var monthBalanceSeconds: Int? {
        monthTargetSeconds.map { monthTotals.seconds - $0 }
    }

    private var beforeMonthBalanceSeconds: Int? {
        beforeMonthTargetSeconds.map { beforeMonthTotals.seconds - $0 }
    }

    private var overallBalanceSeconds: Int? {
        overallTargetSeconds.map { overallTotals.seconds - $0 }
    }

    private var monthDays: Int {
        max(1, Calendar.current.range(of: .day, in: .month, for: referenceMonth)?.count ?? 30)
    }

    private var activeDaysCount: Int {
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        return monthEntries
            .filter { computedSeconds(for: $0, entriesByDate: entriesByDate) > 0 }
            .count
    }

    private var averageBalancePerDaySeconds: Int? {
        monthBalanceSeconds.map { Int((Double($0) / Double(monthDays)).rounded()) }
    }

    private var monthTargetProgress: Double? {
        guard let target = monthTargetSeconds, target > 0 else { return nil }
        return min(1, max(0, Double(monthTotals.seconds) / Double(target)))
    }

    private var monthTitle: String {
        Self.monthTitleFormatter.string(from: referenceMonth)
    }

    private var compactMonthTitle: String {
        Self.compactMonthTitleFormatter.string(from: referenceMonth)
    }

    private var monthYearPickerRange: ClosedRange<Int> {
        let currentYear = Calendar.current.component(.year, from: Date())
        let referenceYear = Calendar.current.component(.year, from: referenceMonth)
        return min(currentYear, referenceYear) - 25...max(currentYear, referenceYear) + 25
    }

    private var monthBalanceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(monthBalanceTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(monthPrimaryValue)
                        .font(.system(.largeTitle, design: .rounded).weight(.black))
                        .foregroundStyle(monthBalanceSeconds.map(balanceColor) ?? settings.themeAccent.color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .payScopeNumericTransition(value: monthPrimaryValue)
                    Text(monthBalanceSubtitle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: monthBalanceIcon)
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(monthBalanceSeconds.map(balanceColor) ?? settings.themeAccent.color)
                    )
            }

            HStack(spacing: 10) {
                focusPill(
                    icon: "clock.fill",
                    value: PayScopeFormatters.hoursString(seconds: monthTotals.seconds),
                    label: "Ist"
                )
                focusPill(
                    icon: "target",
                    value: monthTargetSeconds.map { PayScopeFormatters.hoursString(seconds: $0) } ?? "-",
                    label: "Soll"
                )
            }

            if let monthTargetProgress, let monthTargetSeconds {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Monatsziel")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((monthTargetProgress * 100).rounded()))% · \(PayScopeFormatters.hoursString(seconds: monthTargetSeconds))")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .payScopeNumericTransition(value: Int((monthTargetProgress * 100).rounded()))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(settings.themeAccent.color.opacity(0.13))
                            Capsule()
                                .fill(monthBalanceSeconds.map(balanceColor) ?? settings.themeAccent.color)
                                .frame(width: max(10, proxy.size.width * monthTargetProgress))
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .padding(20)
        .payScopeGlassSurface(
            accent: settings.themeAccent.color,
            cornerRadius: 28,
            tintOpacity: 0.07,
            shadowOpacity: 0.09,
            isInteractive: true
        )
        .payScopeLiquidGlassTapFeedback(
            accent: monthBalanceSeconds.map(balanceColor) ?? settings.themeAccent.color,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tintOpacity: 0.05
        )
    }

    private var overallBalanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(title: "Allgemein", subtitle: overallPeriodText)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(overallBalanceSeconds.map(signedHoursString) ?? "-")
                    .font(.system(.title, design: .rounded).weight(.black))
                    .foregroundStyle(overallBalanceSeconds.map(balanceColor) ?? .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .payScopeNumericTransition(value: overallBalanceSeconds ?? 0)
                Spacer()
                Text("Gesamtkonto")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            VStack(spacing: 10) {
                infoRow(
                    icon: "tray.full.fill",
                    title: "Übertrag vor Monat",
                    value: beforeMonthBalanceSeconds.map(signedHoursString) ?? "-"
                )
                infoRow(
                    icon: "calendar",
                    title: "Monat",
                    value: monthBalanceSeconds.map(signedHoursString) ?? "-"
                )
                infoRow(
                    icon: "sum",
                    title: "Ist gesamt",
                    value: PayScopeFormatters.hoursString(seconds: overallTotals.seconds)
                )
            }
        }
        .payScopeCard(accent: settings.themeAccent.color, isInteractive: true)
    }

    private var detailCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            metricCard(
                title: "Ist-Stunden",
                value: PayScopeFormatters.hoursString(seconds: monthTotals.seconds),
                icon: "clock",
                tint: settings.themeAccent.color
            )
            metricCard(
                title: "Soll-Stunden",
                value: monthTargetSeconds.map { PayScopeFormatters.hoursString(seconds: $0) } ?? "Fehlt",
                icon: "target",
                tint: .teal
            )
            metricCard(
                title: "Aktive Tage",
                value: "\(activeDaysCount)",
                icon: "calendar.badge.checkmark",
                tint: .indigo
            )
            metricCard(
                title: "Ø Saldo/Tag",
                value: averageBalancePerDaySeconds.map(signedHoursString) ?? "-",
                icon: "divide.circle",
                tint: averageBalancePerDaySeconds.map(balanceColor) ?? .orange
            )
        }
    }

    private var accountFlowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(title: "Kontoaufbau", subtitle: "")

            VStack(spacing: 10) {
                infoRow(
                    icon: "arrow.uturn.backward.circle.fill",
                    title: "Startsaldo",
                    value: beforeMonthBalanceSeconds.map(signedHoursString) ?? "-"
                )
                infoRow(
                    icon: "plusminus.circle.fill",
                    title: "Monatssaldo",
                    value: monthBalanceSeconds.map(signedHoursString) ?? "-"
                )
                infoRow(
                    icon: "equal.circle.fill",
                    title: "Stand nach Monat",
                    value: overallBalanceSeconds.map(signedHoursString) ?? "-"
                )
                if totalErroredDaysCount > 0 {
                    infoRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Nicht berechnet",
                        value: "\(totalErroredDaysCount) \(totalErroredDaysCount == 1 ? "Tag" : "Tage")"
                    )
                }
            }
        }
        .payScopeCard(accent: settings.themeAccent.color, isInteractive: true)
    }

    private var monthBalanceTitle: String {
        guard let monthBalanceSeconds else { return "Ist-Stunden" }
        if monthBalanceSeconds > 0 { return "Überstunden" }
        if monthBalanceSeconds < 0 { return "Minusstunden" }
        return "Ausgeglichen"
    }

    private var monthPrimaryValue: String {
        monthBalanceSeconds.map(signedHoursString) ?? PayScopeFormatters.hoursString(seconds: monthTotals.seconds)
    }

    private var monthBalanceSubtitle: String {
        guard let monthBalanceSeconds else {
            return "Kein Wochenziel gesetzt"
        }
        if monthBalanceSeconds > 0 {
            return "Mehr gearbeitet als Soll im ausgewählten Monat"
        }
        if monthBalanceSeconds < 0 {
            return "Weniger gearbeitet als Soll im ausgewählten Monat"
        }
        return "Ist und Soll sind für diesen Monat gleich"
    }

    private var monthBalanceIcon: String {
        guard let monthBalanceSeconds else { return "clock.fill" }
        if monthBalanceSeconds > 0 { return "plus.circle.fill" }
        if monthBalanceSeconds < 0 { return "minus.circle.fill" }
        return "checkmark.seal.fill"
    }

    private var overallPeriodText: String {
        guard let accountStart else { return "Noch keine Einträge bis zu diesem Monat" }
        return "Seit \(PayScopeFormatters.day.string(from: accountStart))"
    }

    private var totalErroredDaysCount: Int {
        monthTotals.erroredDaysCount + beforeMonthTotals.erroredDaysCount
    }

    private var hoursAccountLargeTitle: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Stundenkonto")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .layoutPriority(1)
            Spacer()
            VStack {
                monthYearPickerButton(style: .largeTitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthYearPickerButton(style: MonthSelectorStyle) -> some View {
        Button {
            showMonthYearPicker = true
        } label: {
            HStack(spacing: style == .largeTitle ? 5 : 4) {
                ViewThatFits(in: .horizontal) {
                    Text(monthTitle)
                        .payScopeTextTransition(value: monthTitle)
                    Text(compactMonthTitle)
                        .payScopeTextTransition(value: compactMonthTitle)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.76)

                Image(systemName: "chevron.down")
                    .font(.system(size: style == .largeTitle ? 11 : 9, weight: .bold))
            }
            .font(monthSelectorFont(style: style))
            .foregroundStyle(monthSelectorForeground(style: style))
            .padding(.horizontal, style == .largeTitle ? 10 : 0)
            .padding(.vertical, style == .largeTitle ? 6 : 0)
            .background {
                if style == .largeTitle {
                    Capsule()
                        .fill(settings.themeAccent.color.opacity(0.14))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Monat und Jahr auswählen")
        .accessibilityValue(monthTitle)
    }

    private func monthSelectorFont(style: MonthSelectorStyle) -> Font {
        switch style {
        case .largeTitle:
            return .system(.subheadline, design: .rounded).weight(.bold)
        case .subtitle:
            return .system(.caption, design: .rounded).weight(.semibold)
        }
    }

    private func monthSelectorForeground(style: MonthSelectorStyle) -> HierarchicalShapeStyle {
        switch style {
        case .largeTitle:
            return .primary
        case .subtitle:
            return .secondary
        }
    }

    private func focusPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundStyle(settings.themeAccent.color)
                .frame(width: 28, height: 28)
                .payScopeLiquidGlassIcon(accent: settings.themeAccent.color, tintOpacity: 0.12, shadowOpacity: 0.06)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .payScopeNumericTransition(value: value)
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.72))
        )
    }

    private func metricCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(.subheadline, design: .rounded).weight(.black))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .payScopeLiquidGlassIcon(
                    accent: tint,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    tintOpacity: 0.12,
                    shadowOpacity: 0.06
                )

            Spacer(minLength: 0)

            Text(value)
                .font(.system(.title3, design: .rounded).weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .payScopeNumericTransition(value: value)
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .payScopeGlassSurface(
            accent: settings.themeAccent.color,
            cornerRadius: 22,
            tintOpacity: 0.052,
            shadowOpacity: 0.07,
            isInteractive: true
        )
        .payScopeLiquidGlassTapFeedback(
            accent: tint,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tintOpacity: 0.05
        )
    }

    private func cardHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.black))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundStyle(settings.themeAccent.color)
                .frame(width: 30, height: 30)
                .payScopeLiquidGlassIcon(accent: settings.themeAccent.color, tintOpacity: 0.13, shadowOpacity: 0.06)

            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .payScopeNumericTransition(value: value)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.62))
        )
    }

    private func totals(for source: [DayEntry]) -> HoursAccountTotals {
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        return source.reduce(into: HoursAccountTotals()) { totals, entry in
            let result = service.dayComputation(for: entry, entriesByDate: entriesByDate, settings: settings)
            switch result {
            case let .ok(seconds, _), let .warning(seconds, _, _):
                totals.seconds += max(0, seconds)
            case .error:
                totals.erroredDaysCount += 1
            }
        }
    }

    private func computedSeconds(for day: DayEntry, entriesByDate: [Date: DayEntry]) -> Int {
        let result = service.dayComputation(for: day, entriesByDate: entriesByDate, settings: settings)
        switch result {
        case let .ok(seconds, _), let .warning(seconds, _, _):
            return max(0, seconds)
        case .error:
            return 0
        }
    }

    private func targetSeconds(from start: Date, to end: Date) -> Int? {
        guard let weeklyTarget = settings.weeklyTargetSeconds, weeklyTarget > 0 else { return nil }
        let calendar = Calendar.current
        let startDay = start.startOfDayLocal(calendar: calendar)
        let endDay = end.startOfDayLocal(calendar: calendar)
        guard endDay > startDay else { return 0 }
        let days = max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)
        return Int((Double(weeklyTarget) / 7.0 * Double(days)).rounded())
    }

    private func signedHoursString(seconds: Int) -> String {
        let sign: String
        if seconds > 0 {
            sign = "+"
        } else if seconds < 0 {
            sign = "-"
        } else {
            sign = ""
        }
        return "\(sign)\(PayScopeFormatters.hoursString(seconds: abs(seconds)))"
    }

    private func balanceColor(for seconds: Int) -> Color {
        if seconds > 0 { return .green }
        if seconds < 0 { return .red }
        return settings.themeAccent.color
    }

    @MainActor
    private func loadData(mode: DataLoadMode = .fullSync) async {
        guard !isLoadingData else { return }
        isLoadingData = true
        defer { isLoadingData = false }

        let localSnapshot = deduplicateEntriesByLocalDayKeepingNewest(localStore.loadAll())
            .filter { $0.date < monthRange.end }
        if mode == .localOnly || entries.isEmpty {
            applyEntriesIfChanged(localSnapshot)
        }
        guard mode == .fullSync else { return }

        let tombstonesByDay = Dictionary(
            localStore.loadDeletionTombstones().map { (dayKey($0.date), $0.lastModified) },
            uniquingKeysWith: { current, incoming in
                incoming > current ? incoming : current
            }
        )

        do {
            let cloudEntries = deduplicateEntriesByLocalDayKeepingNewest(
                try await cloudKitService.fetchDayEntries(in: accountLoadInterval)
            )
            let cloudEntriesWithoutLocallyDeleted = cloudEntries.filter { cloudEntry in
                guard let deletedAt = tombstonesByDay[dayKey(cloudEntry.date)] else { return true }
                return deletedAt < cloudEntry.updatedAt
            }
            .filter(\.isRealTrackedDay)
            let mergedEntries = deduplicateEntriesByLocalDayKeepingNewest(localSnapshot + cloudEntriesWithoutLocallyDeleted)
                .filter { $0.date < monthRange.end }

            applyEntriesIfChanged(mergedEntries)
            localStore.upsertMany(cloudEntriesWithoutLocallyDeleted, notify: false)
        } catch {
            applyEntriesIfChanged(localSnapshot)
        }
    }

    private func applyEntriesIfChanged(_ newEntries: [DayEntry]) {
        guard dayEntriesSignature(newEntries) != dayEntriesSignature(entries) else { return }
        entries = newEntries
    }

    private func dayEntriesSignature(_ values: [DayEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(values.count)
        for value in values.sorted(by: { $0.date < $1.date }) {
            hasher.combine(value.date.timeIntervalSinceReferenceDate)
            hasher.combine(value.type.rawValue)
            hasher.combine(value.manualWorkedSeconds ?? -1)
            hasher.combine(value.creditedOverrideSeconds ?? -1)
            hasher.combine(value.shiftStart?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(value.shiftEnd?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(value.breakSeconds ?? -1)
            hasher.combine(value.updatedAt.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    private func deduplicateEntriesByLocalDayKeepingNewest(_ source: [DayEntry]) -> [DayEntry] {
        let byDay = Dictionary(
            source.map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                preferredEntryForSameDay(existing: existing, candidate: candidate)
            }
        )
        return byDay.values.filter(\.isRealTrackedDay).sorted { $0.date < $1.date }
    }

    private func preferredEntryForSameDay(existing: DayEntry, candidate: DayEntry) -> DayEntry {
        if existing.isRealTrackedDay != candidate.isRealTrackedDay {
            return candidate.isRealTrackedDay ? candidate : existing
        }
        return candidate.updatedAt > existing.updatedAt ? candidate : existing
    }

    private func dayKey(_ date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }
}

private struct HoursAccountTotals {
    var seconds: Int = 0
    var erroredDaysCount: Int = 0
}

private enum WatchSnapshotBridgeKeys {
    static let payloadData = "payscope.watch.snapshot.data.v1"
    static let generatedAt = "payscope.watch.snapshot.generatedAt.v1"
    static let requestSnapshot = "requestSnapshot"
    static let reloadComplications = "reloadComplications"
    static let reloadIOSWidgets = "reloadIOSWidgets"
}

private extension Notification.Name {
    static let watchSnapshotRefreshRequested = Notification.Name("PayScope.watchSnapshotRefreshRequested")
}

private struct WatchSnapshotDayPayload: Codable {
    let date: Date
    let dayTypeRawValue: String
    let dayTypeLabel: String
    let iconName: String
    let categoryColorRawValue: String
    let workedSeconds: Int
    let payCents: Int
    let earnedSoFarSeconds: Int
    let earnedSoFarPayCents: Int
    let shiftStart: Date?
    let shiftEnd: Date?
    let breakSeconds: Int
    let tipAmountCents: Int
    let updatedAt: Date
}

private struct WatchSnapshotPayload: Codable {
    let generatedAt: Date
    let themeAccentRawValue: String
    let calendarSummaryDisplayModeRawValue: String
    let calendarHoursBreakModeRawValue: String
    let showTipsAmount: Bool
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

        guard (message[WatchSnapshotBridgeKeys.requestSnapshot] as? Bool) == true else {
            replyHandler([:])
            return
        }

        requestFreshSnapshotFromRootView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            replyHandler(self?.currentContextForReply(from: session) ?? [:])
        }
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if (userInfo[WatchSnapshotBridgeKeys.reloadIOSWidgets] as? Bool) == true {
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }

        guard (userInfo[WatchSnapshotBridgeKeys.requestSnapshot] as? Bool) == true else { return }
        requestFreshSnapshotFromRootView()
        guard let context = currentContextForReply(from: WCSession.default) else { return }
        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            #if DEBUG
            print("Failed to refresh watch snapshot context from userInfo request: \(error)")
            #endif
        }
    }

    private func requestFreshSnapshotFromRootView() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .watchSnapshotRefreshRequested, object: nil)
        }
    }
}
