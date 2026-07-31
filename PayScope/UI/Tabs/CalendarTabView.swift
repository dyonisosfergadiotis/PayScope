import SwiftUI
import Combine
import SwiftData
import UIKit

struct CalendarTabView: View {
    private enum CalendarViewMode {
        case month
        case shiftList
    }

    private enum DataLoadMode: Equatable {
        case localOnly
        case fullSync
    }

    private struct MonthSyncWindow: Equatable {
        var startMonth: Date
        var endMonth: Date

        func dateInterval(calendar: Calendar = .current) -> DateInterval {
            let normalizedStart = startMonth.startOfMonthLocal(calendar: calendar)
            let normalizedEndMonth = endMonth.startOfMonthLocal(calendar: calendar)
            let endExclusive = calendar.date(
                byAdding: .month,
                value: 1,
                to: normalizedEndMonth
            ) ?? normalizedEndMonth.addingDays(32, calendar: calendar)
            return DateInterval(start: normalizedStart, end: endExclusive)
        }
    }

    private struct MonthWeekHourSummary: Identifiable, Sendable {
        let id: Date
        let weekNumber: Int
        let seconds: Int
    }

    private struct CalendarHolidaySnapshot: Sendable {
        let date: Date
        let countryCode: String
        let subdivisionCode: String?

        init(_ holiday: HolidayCalendarDay) {
            self.date = holiday.date
            self.countryCode = holiday.countryCode
            self.subdivisionCode = holiday.subdivisionCode
        }
    }

    private struct CalendarDerivedOptions: Sendable {
        let displayedMonth: Date
        let showsWeekNumbers: Bool
        let showsWeekHours: Bool
        let showsWeekPay: Bool
        let holidayCountryCode: String?
        let holidaySubdivisionCode: String?
    }

    private struct CalendarDerivedSnapshot: Sendable {
        var key: String
        var displayedMonthSummary: TotalsSummary
        var monthWeekHourSummaries: [MonthWeekHourSummary]
        var dayResultsByDate: [Date: ComputationResult]
        var weekBadgesByDate: [Date: WeekBadgeData]
        var displayedMonthTipTotalCents: Int
        var tipCentsByDate: [Date: Int]
        var holidayDates: Set<Date>

        static let empty = CalendarDerivedSnapshot(
            key: "",
            displayedMonthSummary: TotalsSummary(),
            monthWeekHourSummaries: [],
            dayResultsByDate: [:],
            weekBadgesByDate: [:],
            displayedMonthTipTotalCents: 0,
            tipCentsByDate: [:],
            holidayDates: []
        )
    }

    private static let initialBackgroundCloudSyncRadiusMonths = 3

    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    private let localStore = LocalDayEntryStore.shared
    @State private var entries: [DayEntry] = []
    @State private var tipEntries: [TipEntry] = []
    @State private var netConfigs: [NetWageMonthConfig] = []
    @State private var importedHolidays: [HolidayCalendarDay] = []
    @Binding var displayedMonth: Date
    @Bindable var settings: Settings
    let isOffline: Bool

    @State private var activeSheet: CalendarSheet?
    @State private var selectedPopoverDay: Date?
    @State private var selectedEditorDay: CalendarDaySelection?
    @State private var selectedTipEditorState: TipEntryEditorState?
    @State private var showNetWageConfig = false
    @State private var showMonthYearPicker = false
    @State private var netConfigSheetMonth = Date().startOfMonthLocal()
    @State private var holidayImportKeys: Set<String> = []
    @State private var now = Date()
    @State private var toolbarContainerWidth: CGFloat = 0
    @State private var isLoadingData = false
    @State private var pendingLoadAfterCurrentCycle = false
    @State private var showUnsyncedIndicator = false
    @State private var monthSelectionFeedbackTrigger = 0
    @State private var dayDeleteFeedbackTrigger = 0
    @State private var suppressCalendarCellAnimations = false
    @State private var monthChangeFollowUpTask: Task<Void, Never>?
    @State private var isTipCalendarDisplayActive = false
    @State private var showMonthMoneyPopover = false
    @State private var showMonthHoursPopover = false
    @State private var dayEntriesNotificationCancellable: AnyCancellable?
    @State private var tipEntriesNotificationCancellable: AnyCancellable?
    @State private var isInitialLoading = true
    @State private var initialLoadTask: Task<Void, Never>?
    @State private var backgroundCloudSyncWindow = CalendarTabView.initialBackgroundCloudSyncWindow()
    @State private var derivedSnapshot = CalendarDerivedSnapshot.empty
    @State private var derivedSnapshotTask: Task<Void, Never>?
    @State private var pendingDerivedSnapshotKey = ""
    @State private var calendarViewMode: CalendarViewMode = .month

    private let service = CalculationService()
    private let holidayImporter = HolidayImportService()
    private let previewRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let calendarContentHorizontalPadding: CGFloat = 16
    private let calendarCardSpacing: CGFloat = 9
    private let shiftListDayLabelWidth: CGFloat = 52
    private let shiftListVisibleHourCount: CGFloat = 8
    private let calendarColorAnimation = Animation.smooth(duration: 0.14, extraBounce: 0)
    private let monthChangeSettlingDelayNanoseconds: UInt64 = 180_000_000
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    private static let compactCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    private static let compactWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE"
        return formatter
    }()
    private let unsyncedIndicatorDebounce = RunLoop.SchedulerTimeType.Stride.milliseconds(900)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if calendarViewMode == .month {
                    weekdayHeader
                }
                calendarSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, calendarContentHorizontalPadding)
            .padding(.top)
            .padding(.bottom, 6)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                monthBottomSummaryBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarItemsCalendarView
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: CalendarTabToolbarWidthPreferenceKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(CalendarTabToolbarWidthPreferenceKey.self) { value in
                toolbarContainerWidth = value
            }
            .task(id: holidayImportTaskKey) {
                await importHolidaysIfNeededForDisplayedMonth()
            }
            .task(id: displayedMonth.startOfMonthLocal()) {
                await loadTipsForDisplayedMonth()
            }
            .task(id: calendarDerivedSnapshotKey) {
                scheduleCalendarDerivedSnapshotRecompute(key: calendarDerivedSnapshotKey)
            }
            .onChange(of: displayedMonth.startOfMonthLocal()) { _, _ in
                selectedPopoverDay = nil
            }
            .task {
                await runInitialLoadingSequence()
            }
            .onAppear {
                dayEntriesNotificationCancellable = NotificationCenter.default.publisher(for: .dayEntriesDidChange)
                    .sink { _ in
                        Task { await loadData(mode: .localOnly) }
                    }
                tipEntriesNotificationCancellable = NotificationCenter.default.publisher(for: .tipEntriesDidChange)
                    .sink { _ in
                        Task { await loadTipsForDisplayedMonth() }
                    }
            }
            .onDisappear {
                dayEntriesNotificationCancellable?.cancel()
                dayEntriesNotificationCancellable = nil
                tipEntriesNotificationCancellable?.cancel()
                tipEntriesNotificationCancellable = nil
                initialLoadTask?.cancel()
                initialLoadTask = nil
                monthChangeFollowUpTask?.cancel()
                monthChangeFollowUpTask = nil
                derivedSnapshotTask?.cancel()
                derivedSnapshotTask = nil
            }
            .onReceive(previewRefreshTimer) { value in
                now = value
            }
            .onReceive(
                cloudKitService.$isUnsynced
                    .removeDuplicates()
                    .debounce(for: unsyncedIndicatorDebounce, scheduler: RunLoop.main)
            ) { value in
                showUnsyncedIndicator = value
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(oldPhase, newPhase)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .today:
                    TodayFocusView(settings: settings)
                        .presentationDetents([.fraction(0.58)])
                        .presentationDragIndicator(.visible)
                case let .tips(month):
                    TipEntrySheet(month: month, settings: settings) {
                        Task { await loadTipsForDisplayedMonth() }
                    }
                    .environmentObject(cloudKitService)
                }
            }
            .sheet(item: $selectedEditorDay) { selection in
                let editorDate = selection.date.startOfDayLocal()
                DayEditorView(
                    date: editorDate,
                    settings: settings,
                    onDaySaved: applyDayEditorChange,
                    previewEntry: entry(for: editorDate),
                    seededEntries: entries,
                    seededHolidayDays: importedHolidays,
                    usesSeededContext: true
                )
            }
            .sheet(item: $selectedTipEditorState) { state in
                TipEntryEditorSheet(
                    title: state.title,
                    saveAccessibilityLabel: state.saveAccessibilityLabel,
                    dateRange: tipEditorDateRange(containing: state.initialDate),
                    initialDate: state.initialDate,
                    initialAmountCents: state.initialAmountCents
                ) { date, amountCents in
                    saveTipFromCalendar(
                        date: date,
                        amountCents: amountCents,
                        replacing: state.tip,
                        previousDate: state.initialDate,
                        isEditingExistingTip: state.isEditingExistingTip
                    )
                    selectedTipEditorState = nil
                }
            }
            .sheet(isPresented: $showMonthYearPicker) {
                MonthYearPickerSheet(
                    initialMonth: displayedMonth,
                    yearRange: monthYearPickerRange,
                    accent: settings.themeAccent.color
                ) { selectedMonth in
                    let targetMonth = selectedMonth.startOfMonthLocal()
                    beginDisplayedMonthChange(to: targetMonth)
                    displayedMonth = targetMonth
                    ensureBackgroundCloudSyncWindowCovers(month: targetMonth)
                    monthSelectionFeedbackTrigger += 1
                }
            }
            .sheet(isPresented: $showNetWageConfig) {
                NetWageConfigSheet(
                    selectedMonth: $netConfigSheetMonth,
                    config: netConfigBindingForSheet,
                    onSelectMonth: selectNetConfigSheetMonth
                )
                .environmentObject(cloudKitService)
            }
            .sensoryFeedback(.selection, trigger: monthSelectionFeedbackTrigger)
            .sensoryFeedback(.warning, trigger: dayDeleteFeedbackTrigger)
        }
        .payScopeBackground(accent: settings.themeAccent.color, intensity: 0.92)
        .overlay(
            Group {
                if isInitialLoading {
                    splashView
                }
            }
        )
    }

    @MainActor
    private func runInitialLoadingSequence() async {
        guard isInitialLoading else { return }

        initialLoadTask?.cancel()
        let localLoadTask = Task { @MainActor in
            await loadData(mode: .localOnly)
        }
        initialLoadTask = localLoadTask
        await localLoadTask.value

        guard !Task.isCancelled else { return }
        isInitialLoading = false

        let cloudLoadTask = Task { @MainActor in
            await loadData(mode: .fullSync)
        }
        initialLoadTask = cloudLoadTask
    }

    @MainActor
    private func handleScenePhaseChange(
        _ oldPhase: ScenePhase,
        _ newPhase: ScenePhase
    ) {
        guard newPhase == .active else { return }
        guard activeSheet == nil, selectedEditorDay == nil else { return }

        Task {
            await loadData(mode: .fullSync)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItemsCalendarView: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            MonthYearToolbarButton(
                month: monthYearParts.month,
                year: monthYearParts.year,
                accent: settings.themeAccent.color
            ) {
                showMonthYearPicker = true
            }
            .accessibilityLabel("Monat und Jahr auswählen")
            .accessibilityValue(germanMonthYear(displayedMonth))
        }

        ToolbarItem(placement: .topBarLeading) {
            
                calendarDisplayModeMenu
               
        }
        
        ToolbarSpacer(placement: .topBarLeading)
        
        ToolbarItem(placement: .topBarLeading)
        {
            calendarViewModeButton
        }

        if settings.effectiveShowTipsButton {
            ToolbarItem(placement: .topBarTrailing) {
                tipsToolbarButton
            }

        }

    }

    private var monthYearPickerRange: ClosedRange<Int> {
        let currentYear = Calendar.current.component(.year, from: Date())
        let displayedYear = Calendar.current.component(.year, from: displayedMonth)
        return min(currentYear, displayedYear) - 25...max(currentYear, displayedYear) + 25
    }

    private var calendarDerivedSnapshotKey: String {
        var hasher = Hasher()
        hasher.combine(displayedMonth.startOfMonthLocal().timeIntervalSinceReferenceDate)
        hasher.combine(dayEntriesSignature(entries))
        hasher.combine(tipEntriesSignature(tipEntries))
        hasher.combine(netConfigSignature(netConfigs))
        hasher.combine(holidaySignature(importedHolidays))
        hasher.combine(calendarCalculationSettingsSignature)
        return String(hasher.finalize())
    }

    private var calendarCalculationSettingsSignature: Int {
        var hasher = Hasher()
        hasher.combine(settings.payMode.rawValue)
        hasher.combine(settings.hourlyRateCents ?? -1)
        hasher.combine(settings.monthlySalaryCents ?? -1)
        hasher.combine(settings.weeklyTargetSeconds ?? -1)
        hasher.combine(settings.vacationLookbackCount)
        hasher.combine(settings.effectiveVacationCreditingMode.rawValue)
        hasher.combine(settings.effectiveVacationFixedSeconds)
        hasher.combine(settings.countMissingAsZero)
        hasher.combine(settings.strictHistoryRequired)
        hasher.combine(settings.effectiveCalculateBreaks)
        hasher.combine(settings.effectiveHolidayCreditingMode.rawValue)
        hasher.combine(settings.effectiveHolidayFixedSeconds)
        hasher.combine(settings.scheduledWorkdaysCount)
        hasher.combine(settings.effectiveShowCalendarWeekNumbers)
        hasher.combine(settings.effectiveShowCalendarWeekHours)
        hasher.combine(settings.effectiveShowCalendarWeekPay)
        hasher.combine(settings.effectiveShowTipsButton)
        hasher.combine(settings.effectiveCalendarSummaryDisplayMode.rawValue)
        hasher.combine(settings.netWageTaxPercent ?? -1)
        hasher.combine(settings.netPensionPercent ?? -1)
        hasher.combine(settings.netMonthlyAllowanceEuro ?? -1)
        hasher.combine(settings.netBonusesCSV ?? "")
        hasher.combine(normalizedHolidayCountryCode ?? "")
        hasher.combine(normalizedHolidaySubdivisionCode ?? "")
        return hasher.finalize()
    }

    @MainActor
    private func scheduleCalendarDerivedSnapshotRecompute(key: String) {
        guard key != derivedSnapshot.key || pendingDerivedSnapshotKey != key else { return }

        derivedSnapshotTask?.cancel()
        pendingDerivedSnapshotKey = key

        let entrySnapshots = entries.map(CalculationInputSnapshot.init)
        let settingsSnapshot = CalculationSettingsSnapshot(settings)
        let tipSnapshots = tipEntries
        let holidaySnapshots = importedHolidays.map(CalendarHolidaySnapshot.init)
        let options = CalendarDerivedOptions(
            displayedMonth: displayedMonth.startOfMonthLocal(),
            showsWeekNumbers: settings.effectiveShowCalendarWeekNumbers,
            showsWeekHours: settings.effectiveShowCalendarWeekHours,
            showsWeekPay: settings.effectiveShowCalendarWeekPay,
            holidayCountryCode: normalizedHolidayCountryCode,
            holidaySubdivisionCode: normalizedHolidaySubdivisionCode
        )

        derivedSnapshotTask = Task { @MainActor in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.makeCalendarDerivedSnapshot(
                    key: key,
                    entries: entrySnapshots,
                    tips: tipSnapshots,
                    holidays: holidaySnapshots,
                    settings: settingsSnapshot,
                    options: options
                )
            }.value

            guard !Task.isCancelled else { return }
            guard pendingDerivedSnapshotKey == key else { return }
            derivedSnapshot = snapshot
        }
    }

    nonisolated private static func makeCalendarDerivedSnapshot(
        key: String,
        entries: [CalculationInputSnapshot],
        tips: [TipEntry],
        holidays: [CalendarHolidaySnapshot],
        settings: CalculationSettingsSnapshot,
        options: CalendarDerivedOptions
    ) -> CalendarDerivedSnapshot {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        let monthStart = options.displayedMonth.startOfMonthLocal(calendar: calendar)
        let interval = calendar.dateInterval(of: .month, for: monthStart)
            ?? DateInterval(start: monthStart, duration: 24 * 60 * 60)
        let monthEnd = interval.end.addingTimeInterval(-1)

        var context = CalculationService(calendar: calendar).makeContext(
            entrySnapshots: entries,
            settingsSnapshot: settings,
            calendar: calendar
        )
        let monthSummary = context.periodSummary(from: interval.start, to: monthEnd)
        let dates = monthDates(for: monthStart, calendar: calendar)
        let tipCentsByDate = tipTotalsByDate(
            entries: entries,
            tips: tips,
            monthStart: interval.start,
            monthEnd: monthEnd,
            calendar: calendar
        )

        var dayResultsByDate: [Date: ComputationResult] = [:]
        for date in dates where calendar.isDate(date, equalTo: monthStart, toGranularity: .month) {
            let dayDate = date.startOfDayLocal(calendar: calendar)
            guard let entry = context.entriesByDate[dayDate], isVisibleInCalendarCell(entry) else {
                continue
            }
            dayResultsByDate[dayDate] = context.dayComputation(for: entry)
        }

        let monthWeekSummaries = monthWeekHourSummaries(
            monthStart: interval.start,
            monthEnd: monthEnd,
            context: &context,
            calendar: calendar
        )

        let weekBadgesByDate = weekBadgeLookup(
            for: dates,
            context: &context,
            options: options,
            calendar: calendar
        )

        let holidayDates = Set(
            holidays
                .filter {
                    normalizedCode($0.countryCode) == options.holidayCountryCode &&
                    normalizedCode($0.subdivisionCode) == options.holidaySubdivisionCode
                }
                .map { $0.date.startOfDayLocal(calendar: calendar) }
        )

        return CalendarDerivedSnapshot(
            key: key,
            displayedMonthSummary: monthSummary,
            monthWeekHourSummaries: monthWeekSummaries,
            dayResultsByDate: dayResultsByDate,
            weekBadgesByDate: weekBadgesByDate,
            displayedMonthTipTotalCents: tipCentsByDate.values.reduce(0, +),
            tipCentsByDate: tipCentsByDate,
            holidayDates: holidayDates
        )
    }

    nonisolated private static func monthDates(for displayedMonth: Date, calendar: Calendar) -> [Date] {
        let firstOfMonth = displayedMonth.startOfMonthLocal(calendar: calendar)
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingDayCount = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDayCount, to: firstOfMonth) else {
            return []
        }

        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    nonisolated private static func tipTotalsByDate(
        entries: [CalculationInputSnapshot],
        tips: [TipEntry],
        monthStart: Date,
        monthEnd: Date,
        calendar: Calendar
    ) -> [Date: Int] {
        var totalsByDay: [Date: Int] = [:]

        for entry in entries where entry.date >= monthStart && entry.date <= monthEnd {
            let amount = max(0, entry.tipAmountCents ?? 0)
            guard amount > 0 else { continue }
            let day = entry.date.startOfDayLocal(calendar: calendar)
            totalsByDay[day] = max(totalsByDay[day] ?? 0, amount)
        }

        for tip in tips where tip.date >= monthStart && tip.date <= monthEnd && tip.amountCents > 0 {
            let day = tip.date.startOfDayLocal(calendar: calendar)
            if totalsByDay[day] == nil {
                totalsByDay[day] = 0
            }
            totalsByDay[day]? += tip.amountCents
        }

        return totalsByDay
    }

    nonisolated private static func monthWeekHourSummaries(
        monthStart: Date,
        monthEnd: Date,
        context: inout CalculationContext,
        calendar: Calendar
    ) -> [MonthWeekHourSummary] {
        var cursor = monthStart.startOfDayLocal(calendar: calendar)
        var weeks: [MonthWeekHourSummary] = []
        var seenWeekStarts = Set<Date>()

        while cursor <= monthEnd {
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: cursor) else {
                break
            }

            let weekStart = weekInterval.start.startOfDayLocal(calendar: calendar)
            if !seenWeekStarts.contains(weekStart) {
                seenWeekStarts.insert(weekStart)
                let weekEnd = weekInterval.end.addingTimeInterval(-1)
                let rangeStart = max(weekInterval.start, monthStart)
                let rangeEnd = min(weekEnd, monthEnd)
                let summary = context.periodSummary(from: rangeStart, to: rangeEnd)
                weeks.append(
                    MonthWeekHourSummary(
                        id: weekStart,
                        weekNumber: calendar.component(.weekOfYear, from: weekStart),
                        seconds: summary.totalSeconds
                    )
                )
            }

            cursor = weekInterval.end
        }

        return weeks
    }

    nonisolated private static func weekBadgeLookup(
        for dates: [Date],
        context: inout CalculationContext,
        options: CalendarDerivedOptions,
        calendar: Calendar
    ) -> [Date: WeekBadgeData] {
        guard options.showsWeekNumbers || options.showsWeekHours || options.showsWeekPay else { return [:] }

        var lookup: [Date: WeekBadgeData] = [:]
        for index in stride(from: 0, to: dates.count, by: 7) {
            let dayDate = dates[index].startOfDayLocal(calendar: calendar)
            lookup[dayDate] = weekBadgeData(for: dayDate, context: &context, options: options, calendar: calendar)
        }
        return lookup
    }

    nonisolated private static func weekBadgeData(
        for date: Date,
        context: inout CalculationContext,
        options: CalendarDerivedOptions,
        calendar: Calendar
    ) -> WeekBadgeData {
        let day = date.startOfDayLocal(calendar: calendar)
        let weekStart = weekStartDate(for: day, calendar: calendar)
        let weekEnd = weekStart.addingDays(6, calendar: calendar)
        let summary = context.periodSummary(from: weekStart, to: weekEnd)

        let weekNumber = options.showsWeekNumbers
            ? calendarWeekNumber(for: weekStart, calendar: calendar)
            : nil

        var detailParts: [String] = []
        if options.showsWeekHours {
            detailParts.append("\(hhmmString(seconds: summary.totalSeconds)) h")
        }
        if options.showsWeekPay {
            detailParts.append(compactCurrencyString(cents: summary.totalCents))
        }

        return WeekBadgeData(
            weekNumber: weekNumber,
            detailText: detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")
        )
    }

    nonisolated private static func weekStartDate(for date: Date, calendar: Calendar) -> Date {
        let normalized = date.startOfDayLocal(calendar: calendar)
        let weekday = calendar.component(.weekday, from: normalized)
        let desired = 2
        let diff = (weekday - desired + 7) % 7
        return normalized.addingDays(-diff, calendar: calendar)
    }

    nonisolated private static func calendarWeekNumber(for date: Date, calendar: Calendar) -> Int {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar.component(.weekOfYear, from: date.startOfDayLocal(calendar: calendar))
    }

    nonisolated private static func isVisibleInCalendarCell(_ entry: CalculationInputSnapshot) -> Bool {
        if (entry.manualWorkedSeconds ?? 0) > 0 { return true }
        if (entry.creditedOverrideSeconds ?? 0) > 0 { return true }
        if entry.type != .work { return true }
        if let start = entry.shiftStart, let end = entry.shiftEnd, end > start { return true }
        return false
    }

    nonisolated private static func compactCurrencyString(cents: Int) -> String {
        let value = NSNumber(value: Double(cents) / 100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value) ?? "0"
    }

    nonisolated private static func hhmmString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    private static func monthAdding(
        _ value: Int,
        to month: Date,
        calendar: Calendar = .current
    ) -> Date {
        let normalizedMonth = month.startOfMonthLocal(calendar: calendar)
        return calendar.date(byAdding: .month, value: value, to: normalizedMonth)?
            .startOfMonthLocal(calendar: calendar) ?? normalizedMonth
    }

    private static func initialBackgroundCloudSyncWindow(
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthSyncWindow {
        let currentMonth = reference.startOfMonthLocal(calendar: calendar)
        return MonthSyncWindow(
            startMonth: monthAdding(-initialBackgroundCloudSyncRadiusMonths, to: currentMonth, calendar: calendar),
            endMonth: monthAdding(initialBackgroundCloudSyncRadiusMonths, to: currentMonth, calendar: calendar)
        )
    }

    private var backgroundCloudSyncInterval: DateInterval {
        backgroundCloudSyncWindow.dateInterval()
    }

    private func ensureBackgroundCloudSyncWindowCovers(month: Date) {
        let month = month.startOfMonthLocal()
        guard month < backgroundCloudSyncWindow.startMonth || month > backgroundCloudSyncWindow.endMonth else {
            return
        }
        backgroundCloudSyncWindow = Self.initialBackgroundCloudSyncWindow(reference: month)
    }

    private func expandBackgroundCloudSyncWindowAfterSwipe(delta: Int, targetMonth: Date) {
        guard delta != 0 else { return }

        var nextWindow = backgroundCloudSyncWindow
        let normalizedTarget = targetMonth.startOfMonthLocal()

        if delta > 0 {
            let expandedEnd = Self.monthAdding(1, to: nextWindow.endMonth)
            nextWindow.endMonth = max(expandedEnd, normalizedTarget)
        } else {
            let expandedStart = Self.monthAdding(-1, to: nextWindow.startMonth)
            nextWindow.startMonth = min(expandedStart, normalizedTarget)
        }

        if nextWindow != backgroundCloudSyncWindow {
            backgroundCloudSyncWindow = nextWindow
        }
    }

    private var displayedMonthBounds: (Date, Date) {
        guard let interval = Calendar.current.dateInterval(of: .month, for: displayedMonth) else {
            let now = Date().startOfDayLocal()
            return (now, now)
        }
        return (interval.start, interval.end.addingTimeInterval(-1))
    }

    private var displayedMonthTipInterval: DateInterval {
        let bounds = displayedMonthBounds
        return DateInterval(start: bounds.0, end: bounds.1)
    }

    private var displayedMonthTipTotalText: String {
        PayScopeFormatters.currencyString(cents: displayedMonthTipTotalCents)
    }

    private var displayedMonthTipTotalCents: Int {
        derivedSnapshot.displayedMonthTipTotalCents
    }

    private var monthHoursBottomBarSummary: some View {
        let summary = displayedMonthSummary
        let shape = Capsule(style: .continuous)

        return Button {
            showMonthHoursPopover = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "clock.fill")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(settings.themeAccent.color)

                Text(PayScopeFormatters.hhmmString(seconds: summary.totalSeconds) + "h")
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .payScopeNumericTransition(value: summary.totalSeconds)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .payScopePureGlassSurface(
            accent: settings.themeAccent.color,
            in: shape,
            tintOpacity: 0.075,
            shadowOpacity: 0.1,
            isInteractive: true
        )
        .popover(isPresented: $showMonthHoursPopover, arrowEdge: .bottom) {
            monthHoursSummaryPopover()
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monatsstunden")
        .accessibilityValue(PayScopeFormatters.hhmmString(seconds: summary.totalSeconds))
    }

    private var monthBottomSummaryBar: some View {
        return HStack(spacing: 0) {
            monthHoursBottomBarSummary

            Spacer(minLength: 24)

            monthPayBottomBarSummary
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    private var monthPayBottomBarSummary: some View {
        let summary = displayedMonthSummary
        let breakdown = monthMoneyBreakdown(for: summary)
        let wageValue = monthMoneyPillWageValue(for: breakdown)
        let includesTips = settings.effectiveShowTipsButton
        let tipValue = includesTips ? displayedMonthTipTotalCents : 0
        let totalValue = wageValue + tipValue
        let shape = Capsule(style: .continuous)

        return Button {
            showMonthMoneyPopover = true
        } label: {
            HStack(spacing: 7) {
                Text(PayScopeFormatters.currencyString(cents: totalValue))
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .payScopeNumericTransition(value: totalValue)

                Image(systemName: includesTips ? "arrow.up.right" : "eurosign.circle.fill")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(settings.themeAccent.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .payScopePureGlassSurface(
            accent: settings.themeAccent.color,
            in: shape,
            tintOpacity: 0.075,
            shadowOpacity: 0.1,
            isInteractive: true
        )
        .popover(isPresented: $showMonthMoneyPopover, arrowEdge: .bottom) {
            monthMoneySummaryPopover(summary: summary)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(monthMoneyPillAccessibilityLabel(includesTips: includesTips))
        .accessibilityValue(PayScopeFormatters.currencyString(cents: totalValue))
    }

    private func monthMoneyPillAccessibilityLabel(includesTips: Bool) -> String {
        guard !includesTips else { return "Monatssumme" }

        switch settings.effectiveCalendarSummaryDisplayMode {
        case .net:
            return "Monatslohn Netto"
        case .gross:
            return "Monatslohn Brutto"
        case .shiftPay:
            return "Monatlicher Schichtlohn"
        }
    }

    private func monthMoneyPillWageValue(
        for breakdown: (grossCents: Int, bonusCents: Int, pensionCents: Int, wageTaxCents: Int, netCents: Int)
    ) -> Int {
        switch settings.effectiveCalendarSummaryDisplayMode {
        case .net:
            return breakdown.netCents
        case .gross:
            return breakdown.grossCents + breakdown.bonusCents
        case .shiftPay:
            return breakdown.grossCents
        }
    }

private func monthHoursSummaryPopover() -> some View {
    let totalSeconds = displayedMonthSummary.totalSeconds

    return VStack(spacing: 10) {
        ForEach(monthWeekHourSummaries, id: \.id) { week in
            monthHoursPopoverRow(
                title: "KW \(week.weekNumber)",
                value: PayScopeFormatters.hhmmString(seconds: week.seconds) + " h"
            )
        }

        Divider()
            .padding(.vertical, 2)

        VStack(spacing: 4) {
            Text("Gesamt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(PayScopeFormatters.hhmmString(seconds: totalSeconds) + " h")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(settings.themeAccent.color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(settings.themeAccent.color.opacity(0.08))
        }
    }
    .padding(14)
    .frame(width: 210)
    .payScopePopoverSurface(accent: settings.themeAccent.color)
}

    private func monthHoursPopoverRow(title: String, value: String, isTotal: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: isTotal ? "sum" : "calendar")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(settings.themeAccent.color)
                .frame(width: 18)

            Text(title)
                .font(.caption.weight(isTotal ? .bold : .semibold))
                .foregroundStyle(isTotal ? .primary : .secondary)

            Spacer(minLength: 10)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(isTotal ? .black : .bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var monthWeekHourSummaries: [MonthWeekHourSummary] {
        derivedSnapshot.monthWeekHourSummaries
    }

private func monthMoneySummaryPopover(summary: TotalsSummary) -> some View {
    let breakdown = monthMoneyBreakdown(for: summary)
    let showsTips = settings.effectiveShowTipsButton
    let accent = settings.themeAccent.color

    return VStack(spacing: 12) {
        monthMoneyPopoverRow(
            title: breakdown.bonusCents > 0 ? "Schichtlohn" : "Bruttolohn",
            value: PayScopeFormatters.currencyString(cents: breakdown.grossCents),
            markerColor: accent.opacity(0.75)
        )

        if breakdown.bonusCents > 0 {
            monthMoneyPopoverRow(
                title: "Zuschläge",
                value: "+" + PayScopeFormatters.currencyString(cents: breakdown.bonusCents),
                valueColor: .green,
                markerColor: .green
            )
            monthMoneyPopoverRow(
                title: "Brutto",
                value: PayScopeFormatters.currencyString(cents: breakdown.grossCents + breakdown.bonusCents),
                markerColor: accent.opacity(0.75)
            )
        }

        if breakdown.pensionCents > 0 || breakdown.wageTaxCents > 0 {
            Divider()

            if breakdown.pensionCents > 0 {
                monthMoneyPopoverRow(
                    title: "RV Abzug",
                    value: deductionCurrencyString(cents: breakdown.pensionCents),
                    valueColor: .orange,
                    markerColor: .orange
                )
            }

            if breakdown.wageTaxCents > 0 {
                monthMoneyPopoverRow(
                    title: "LS Abzug",
                    value: deductionCurrencyString(cents: breakdown.wageTaxCents),
                    valueColor: .orange,
                    markerColor: .orange
                )
            }
        }

        Divider()
            .padding(.vertical, 2)

        VStack(spacing: 5) {
            Text("Netto")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(accent.opacity(0.82))

            Text(PayScopeFormatters.currencyString(cents: breakdown.netCents))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.24), lineWidth: 1)
                }
        }

        if showsTips {
            Divider()
                .padding(.vertical, 2)

            monthMoneyPopoverRow(
                title: "Trinkgeld",
                value: PayScopeFormatters.currencyString(cents: displayedMonthTipTotalCents),
                valueColor: .green,
                markerColor: .green
            )

            monthMoneyPopoverRow(
                title: "Gesamt",
                value: PayScopeFormatters.currencyString(cents: breakdown.netCents + displayedMonthTipTotalCents),
                isFinal: true,
                valueColor: accent,
                markerColor: accent
            )
        }
    }
    .padding(16)
    .frame(width: 268)
    .payScopePopoverSurface(accent: accent)
}

    private func monthMoneyPopoverRow(
        title: String,
        value: String,
        isFinal: Bool = false,
        valueColor: Color = .primary,
        markerColor: Color = .secondary
    ) -> some View {
        HStack(spacing: 10) {
            Capsule(style: .continuous)
                .fill(markerColor.opacity(isFinal ? 0.95 : 0.62))
                .frame(width: isFinal ? 5 : 4, height: isFinal ? 24 : 18)

            Text(title)
                .font(.system(size: isFinal ? 14 : 12, weight: isFinal ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isFinal ? .primary : .secondary)

            Spacer(minLength: 10)

            Text(value)
                .font(.system(size: isFinal ? 18 : 15, weight: isFinal ? .black : .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func monthMoneyBreakdown(for summary: TotalsSummary) -> (
        grossCents: Int,
        bonusCents: Int,
        pensionCents: Int,
        wageTaxCents: Int,
        netCents: Int
    ) {
        let effectiveConfig = effectiveNetConfig(for: displayedMonth.startOfMonthLocal())
        let grossEuro = Double(summary.totalCents) / 100.0
        let bonusEuro = bonuses(from: effectiveConfig.bonusesCSV).reduce(0, +)
        let grossMonthly = max(0, grossEuro + bonusEuro)
        let pensionRate = max(0, (effectiveConfig.pensionPercent ?? 0) / 100.0)
        let wageTaxRate = max(0, (effectiveConfig.wageTaxPercent ?? 0) / 100.0)
        let allowance = max(0, effectiveConfig.monthlyAllowanceEuro ?? 0)
        let deductionBase = max(0, grossMonthly - allowance)
        let pensionEuro = deductionBase * pensionRate
        let wageTaxEuro = deductionBase * wageTaxRate
        let netEuro = grossMonthly - pensionEuro - wageTaxEuro

        return (
            grossCents: summary.totalCents,
            bonusCents: Int((bonusEuro * 100).rounded()),
            pensionCents: Int((pensionEuro * 100).rounded()),
            wageTaxCents: Int((wageTaxEuro * 100).rounded()),
            netCents: Int((netEuro * 100).rounded())
        )
    }

    private func deductionCurrencyString(cents: Int) -> String {
        guard cents > 0 else { return PayScopeFormatters.currencyString(cents: 0) }
        return "-\(PayScopeFormatters.currencyString(cents: cents))"
    }

    private func monthToolbarPayValue(for summary: TotalsSummary) -> Int {
        switch settings.effectiveCalendarSummaryDisplayMode {
        case .net:
            return monthlyNetCents(for: summary)
        case .gross:
            let breakdown = monthMoneyBreakdown(for: summary)
            return breakdown.grossCents + breakdown.bonusCents
        case .shiftPay:
            return summary.totalCents
        }
    }

    private var tipsToolbarButton: some View {
        Button {
            withAnimation(calendarColorAnimation) {
                isTipCalendarDisplayActive.toggle()
            }
        } label: {
            let systemImage = isTipCalendarDisplayActive ? "eurosign.circle.fill" : "eurosign.circle"
            if settings.effectiveShowTipsButtonAmount {
                Label(displayedMonthTipTotalText, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: systemImage)
            }
        }
        .foregroundStyle(isTipCalendarDisplayActive ? settings.themeAccent.color : .primary)
        .id("\(settings.effectiveShowTipsButton)-\(settings.effectiveShowTipsButtonAmount)-\(displayedMonthTipTotalText)-\(isTipCalendarDisplayActive)")
        .accessibilityLabel("Trinkgeld im Kalender")
        .accessibilityValue(isTipCalendarDisplayActive ? "Aktiv" : "Inaktiv")
    }

    private var calendarDisplayModeMenu: some View {
        CalendarDisplayModeMenu(
            currentMode: settings.calendarCellDisplayMode ?? .dot,
            currentBreakMode: settings.effectiveCalendarHoursBreakMode,
            selectDisplayMode: updateCalendarDisplayMode,
            selectHoursBreakMode: updateCalendarHoursDisplayMode
        )
    }

    private var calendarViewModeButton: some View {
        Button {
            withAnimation(calendarColorAnimation) {
                selectedPopoverDay = nil
                calendarViewMode = calendarViewMode == .month ? .shiftList : .month
            }
        } label: {
            Image(systemName: calendarViewMode == .month ? "chart.bar.yaxis" : "calendar")
                .font(.headline.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendarViewMode == .month ? "Listenansicht anzeigen" : "Monatsansicht anzeigen")
        .accessibilityValue(calendarViewMode == .month ? "Monatsansicht aktiv" : "Listenansicht aktiv")
    }

    private func updateCalendarDisplayMode(_ mode: CalendarCellDisplayMode) {
        guard settings.calendarCellDisplayMode != mode else { return }
        settings.calendarCellDisplayMode = mode
        Task { try? await cloudKitService.saveSettings(settings) }
    }

    private func updateCalendarHoursDisplayMode(_ breakMode: CalendarHoursBreakMode) {
        settings.calendarCellDisplayMode = .hours
        settings.calendarHoursBreakMode = breakMode
        Task { try? await cloudKitService.saveSettings(settings) }
    }

    private var displayedMonthSummary: TotalsSummary {
        derivedSnapshot.displayedMonthSummary
    }

    private var monthSummaryBar: some View {
        let summary = displayedMonthSummary
        let monthlyNetCents = monthlyNetCents(for: summary)
        let breakdown = monthMoneyBreakdown(for: summary)

        return PayScopeGlassControlGroup(spacing: 8) {
            HStack(spacing: 8) {
                monthMetricChip(
                    title: "Stunden",
                    value: PayScopeFormatters.hhmmString(seconds: summary.totalSeconds)
                )
                monthMetricChip(
                    title: "Brutto",
                    value: PayScopeFormatters.currencyString(cents: breakdown.grossCents + breakdown.bonusCents)
                )

                Button {
                    openNetWageConfigForDisplayedMonth()
                } label: {
                    monthMetricChip(
                        title: "Netto",
                        value: PayScopeFormatters.currencyString(cents: monthlyNetCents)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func openNetWageConfigForDisplayedMonth() {
        netConfigSheetMonth = displayedMonth.startOfMonthLocal()
        ensureNetConfigExists(for: netConfigSheetMonth)
        showNetWageConfig = true
    }

    private func monthlyNetCents(for summary: TotalsSummary) -> Int {
        Int((monthlyNetEuro(for: summary) * 100).rounded())
    }

    private func monthlyNetEuro(for summary: TotalsSummary) -> Double {
        let gross = Double(summary.totalCents) / 100.0
        let effectiveConfig = effectiveNetConfig(for: displayedMonth.startOfMonthLocal())
        let bonusSum = bonuses(from: effectiveConfig.bonusesCSV).reduce(0, +)
        return service.monthlyNetEuro(
            grossEuro: gross,
            bonusesEuro: bonusSum,
            wageTaxPercent: effectiveConfig.wageTaxPercent,
            pensionPercent: effectiveConfig.pensionPercent,
            monthlyAllowanceEuro: effectiveConfig.monthlyAllowanceEuro
        )
    }

    private func bonuses(from csv: String) -> [Double] {
        csv
            .split(separator: ";")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func netConfig(for monthStart: Date) -> NetWageMonthConfig? {
        netConfigs.first(where: { $0.monthStart.isSameLocalDay(as: monthStart.startOfMonthLocal()) })
    }

    private func effectiveNetConfig(for monthStart: Date) -> (wageTaxPercent: Double?, pensionPercent: Double?, monthlyAllowanceEuro: Double?, bonusesCSV: String) {
        if let current = netConfig(for: monthStart) {
            return (current.wageTaxPercent, current.pensionPercent, current.monthlyAllowanceEuro, current.bonusesCSV)
        }
        return (
            settings.netWageTaxPercent,
            settings.netPensionPercent,
            settings.netMonthlyAllowanceEuro,
            settings.netBonusesCSV ?? ""
        )
    }

    private func ensureNetConfigExists(for monthStart: Date) {
        let normalizedMonth = monthStart.startOfMonthLocal()
        if netConfig(for: normalizedMonth) != nil {
            return
        }

        let seed = effectiveNetConfig(for: normalizedMonth)
        let config = NetWageMonthConfig(
            monthStart: normalizedMonth,
            wageTaxPercent: seed.wageTaxPercent,
            pensionPercent: seed.pensionPercent,
            monthlyAllowanceEuro: seed.monthlyAllowanceEuro,
            bonusesCSV: seed.bonusesCSV
        )
        // keep config locally and persist via CloudKit
        netConfigs.append(config)
        upsertLocalNetConfig(config)
        Task {
            do {
                try await cloudKitService.saveNetWageConfig(config)
            } catch {
                #if DEBUG
                print("Failed to save net config: \(error)")
                #endif
            }
        }
    }

    private var netConfigBindingForSheet: Binding<NetWageMonthConfig> {
        Binding(
            get: {
                netConfig(for: netConfigSheetMonth) ?? NetWageMonthConfig(monthStart: netConfigSheetMonth)
            },
            set: { updated in
                upsertNetConfig(updated)
            }
        )
    }

    private func selectNetConfigSheetMonth(_ month: Date) {
        let normalizedMonth = month.startOfMonthLocal()
        ensureNetConfigExists(for: normalizedMonth)
        netConfigSheetMonth = normalizedMonth
    }

    private func upsertNetConfig(_ config: NetWageMonthConfig) {
        let normalizedMonth = config.monthStart.startOfMonthLocal()
        if let index = netConfigs.firstIndex(where: { $0.monthStart.isSameLocalDay(as: normalizedMonth) }) {
            netConfigs[index] = config
        } else {
            netConfigs.append(config)
        }
        upsertLocalNetConfig(config)
    }

    @MainActor
    private func loadTipsForDisplayedMonth() async {
        let interval = displayedMonthTipInterval
        let localTips = LocalTipEntryStore.shared.loadAll(in: interval)
        let deletedTipsByID = Dictionary(
            LocalTipEntryStore.shared.loadDeletionTombstones().map { ($0.id, $0.lastModified) },
            uniquingKeysWith: max
        )
        let remoteTips = ((try? await cloudKitService.fetchTipEntries(in: interval)) ?? []).filter { tip in
            guard let deletedAt = deletedTipsByID[tip.id] else { return true }
            return deletedAt < tip.updatedAt
        }

        if !remoteTips.isEmpty {
            LocalTipEntryStore.shared.upsertMany(remoteTips)
        }

        let mergedTips = mergeTipEntriesKeepingNewest(local: localTips, remote: remoteTips)
        tipEntries = mergedTips
        applyEntriesIfChanged(entriesWithLegacyTipsApplied(to: entries, tips: mergedTips, persist: true))
    }

    private func mergeTipEntriesKeepingNewest(local: [TipEntry], remote: [TipEntry]) -> [TipEntry] {
        var merged: [String: TipEntry] = [:]

        for tip in local + remote {
            if let existing = merged[tip.id], existing.updatedAt >= tip.updatedAt {
                continue
            }
            merged[tip.id] = tip
        }

        return merged.values.sorted { $0.date > $1.date }
    }

    private func tipCents(for dayDate: Date, entry: DayEntry?) -> Int {
        let entryTip = max(0, entry?.tipAmountCents ?? 0)
        if entryTip > 0 {
            return entryTip
        }
        return tipEntries
            .filter { $0.date.isSameLocalDay(as: dayDate) }
            .reduce(0) { $0 + max(0, $1.amountCents) }
    }

    private func entriesWithLegacyTipsApplied(
        to sourceEntries: [DayEntry],
        tips: [TipEntry],
        persist: Bool
    ) -> [DayEntry] {
        let totalsByDay = legacyTipTotalsByDay(tips)
        var nextEntries: [DayEntry] = []

        for entry in sourceEntries {
            guard entry.isRealTrackedDay else { continue }
            let key = dayKey(entry.date)
            guard let payload = totalsByDay[key] else {
                nextEntries.append(entry)
                continue
            }

            let incomingAmount = max(0, payload.amountCents)
            guard incomingAmount > 0 else {
                nextEntries.append(entry)
                continue
            }

            if max(0, entry.tipAmountCents ?? 0) != incomingAmount {
                entry.tipAmountCents = incomingAmount
                if payload.updatedAt > entry.updatedAt {
                    entry.updatedAt = payload.updatedAt
                }
                if persist {
                    localStore.save(entry)
                }
            }
            nextEntries.append(entry)
        }

        return nextEntries.sorted { $0.date > $1.date }
    }

    private func deletionTombstonesByDay(in interval: DateInterval) -> [String: Date] {
        Dictionary(
            localStore.loadDeletionTombstones()
                .filter { interval.contains($0.date) }
                .map { (dayKey($0.date), $0.lastModified) },
            uniquingKeysWith: { current, incoming in
                incoming > current ? incoming : current
            }
        )
    }

    @MainActor
    private func cleanupTipOnlyDayPlaceholders(localEntries: [DayEntry], remoteEntries: [DayEntry]) async {
        let realDays = Set((localEntries + remoteEntries)
            .filter(\.isRealTrackedDay)
            .map { dayKey($0.date) })
        let deletedAt = Date()

        for entry in localEntries where entry.isTipOnlyPlaceholder {
            let hasRealSameDay = realDays.contains(dayKey(entry.date))
            localStore.delete(on: entry.date, markTombstone: !hasRealSameDay, deletedAt: deletedAt)
        }

        for entry in remoteEntries where entry.isTipOnlyPlaceholder && !realDays.contains(dayKey(entry.date)) {
            do {
                try await cloudKitService.deleteDayEntry(on: entry.date)
            } catch {
                #if DEBUG
                print("CloudKit cleanup failed for tip-only day placeholder \(entry.date): \(error)")
                #endif
            }
        }
    }

    private func legacyTipTotalsByDay(_ tips: [TipEntry]) -> [String: (date: Date, amountCents: Int, updatedAt: Date)] {
        var totals: [String: (date: Date, amountCents: Int, updatedAt: Date)] = [:]

        for tip in tips where tip.amountCents > 0 {
            let day = tip.date.startOfDayLocal()
            let key = dayKey(day)
            let existing = totals[key]
            totals[key] = (
                date: day,
                amountCents: (existing?.amountCents ?? 0) + tip.amountCents,
                updatedAt: max(existing?.updatedAt ?? .distantPast, tip.updatedAt)
            )
        }

        return totals
    }

    private func utcDate(forLocalDay date: Date) -> Date {
        let localDay = date.startOfDayLocal()
        let components = Calendar.current.dateComponents([.year, .month, .day], from: localDay)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: components) ?? localDay.startOfDayUTC()
    }

    private func monthMetricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .center)
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)
                .payScopeNumericTransition(value: value)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .payScopeGlassControl(accent: settings.themeAccent.color, cornerRadius: 16, tintOpacity: 0.14)
    }

    private var weekdayHeader: some View {
        var germanCalendar = Calendar.current
        germanCalendar.locale = Locale(identifier: "de_DE")
        let symbols = germanCalendar.shortWeekdaySymbols
        let ordered = Array(symbols[1...6] + [symbols[0]])

        return HStack {
            ForEach(ordered, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let dates = monthDates()
        let rowCount = max(1, Int(ceil(Double(dates.count) / 7.0)))
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        let dayResultsByDate = derivedSnapshot.dayResultsByDate
        let holidayDateSet = derivedSnapshot.holidayDates
        let weekBadgesByDate = derivedSnapshot.weekBadgesByDate
        let tipCentsByDate = derivedSnapshot.tipCentsByDate

        return GeometryReader { geo in
            let spacing = calendarCardSpacing
            let totalSpacing = spacing * CGFloat(max(0, rowCount - 1))
            let availableHeight = max(0, geo.size.height - totalSpacing)
            let cellHeight = max(1, availableHeight / CGFloat(rowCount))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7), spacing: spacing) {
                ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                    let dayDate = date.startOfDayLocal()
                    let entry = entriesByDate[dayDate]
                    let isHoliday = holidayDateSet.contains(dayDate) || entry?.type == .holiday
                    let weekBadgeData = shouldShowWeekBadge && index % 7 == 0
                        ? weekBadgesByDate[dayDate]
                        : nil
                    let displayedTipCents = settings.effectiveShowTipsButton
                        ? tipCentsByDate[dayDate] ?? 0
                        : 0
                    let rowIndex = index / 7
                    let popoverArrowEdge: Edge = rowIndex < rowCount / 2 ? .top : .bottom

                    dayCell(
                        for: dayDate,
                        height: cellHeight,
                        entry: entry,
                        result: dayResultsByDate[dayDate],
                        isHoliday: isHoliday,
                        displayedTipCents: displayedTipCents,
                        weekBadgeData: weekBadgeData,
                        popoverArrowEdge: popoverArrowEdge,
                        isInDisplayedMonth: Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calendarSurface: some View {
        ZStack {
            switch calendarViewMode {
            case .month:
                calendarGrid
                    .transaction { transaction in
                        if suppressCalendarCellAnimations {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
            case .shiftList:
                shiftBarListView
                    .transition(.opacity)
            }
        }
        .padding(.top, 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 52)
                .onEnded(handleMonthSwipe)
        )
    }

    private var shiftBarListView: some View {
        let days = displayedMonthDays()
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        let dayResultsByDate = derivedSnapshot.dayResultsByDate
        let tipCentsByDate = derivedSnapshot.tipCentsByDate
        let bounds = shiftListTimelineBounds()
        let rowSpacing = calendarCardSpacing

        return GeometryReader { geo in
            let rowHeight = max(54, (max(0, geo.size.height - rowSpacing * 6) / 7))
            let timelineViewportWidth = max(1, geo.size.width - shiftListDayLabelWidth - 8)
            let contentWidth = shiftListTimelineContentWidth(
                viewportWidth: timelineViewportWidth,
                bounds: bounds
            )

            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: rowSpacing) {
                        ForEach(days, id: \.timeIntervalSinceReferenceDate) { day in
                            shiftListDayLabel(day)
                                .frame(width: shiftListDayLabelWidth, height: rowHeight)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: rowSpacing) {
                            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                let dayDate = day.startOfDayLocal()
                                let entry = entriesByDate[dayDate].flatMap { isVisibleInCalendarCell($0) ? $0 : nil }
                                let visibleTipCents = settings.effectiveShowTipsButton ? tipCentsByDate[dayDate] ?? 0 : 0
                                let arrowEdge: Edge = index < days.count / 2 ? .top : .bottom

                                shiftListTimelineRow(
                                    dayDate: dayDate,
                                    entry: entry,
                                    result: dayResultsByDate[dayDate],
                                    tipCents: visibleTipCents,
                                    bounds: bounds,
                                    width: contentWidth,
                                    height: rowHeight,
                                    popoverArrowEdge: arrowEdge
                                )
                            }
                        }
                        .frame(width: contentWidth, alignment: .leading)
                    }
                }
                .padding(.bottom, 2)
            }
        }
    }

    private func shiftListDayLabel(_ date: Date) -> some View {
        let calendar = Calendar.current
        let dayNumber = calendar.component(.day, from: date)
        let weekday = Self.compactWeekdayFormatter.string(from: date)
        let isToday = calendar.isDateInToday(date)
        let isWeekend = calendar.isDateInWeekend(date)

        return VStack(spacing: 3) {
            Text("\(dayNumber)")
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(isToday ? settings.themeAccent.color : .primary)
                .monospacedDigit()

            Text(weekday)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isWeekend ? Color.secondary.opacity(0.78) : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .payScopeGlassControl(
            accent: isToday ? settings.themeAccent.color : Color.secondary,
            cornerRadius: 14,
            tintOpacity: isToday ? 0.12 : 0.06,
            isInteractive: false
        )
    }

    private func shiftListTimelineRow(
        dayDate: Date,
        entry: DayEntry?,
        result: ComputationResult?,
        tipCents: Int,
        bounds: ClosedRange<Int>,
        width: CGFloat,
        height: CGFloat,
        popoverArrowEdge: Edge
    ) -> some View {
        let accent = entry.map { categoryTintColor(for: $0.type, isHoliday: $0.type == .holiday) ?? settings.themeAccent.color } ?? settings.themeAccent.color
        let rowShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return ZStack(alignment: .leading) {
            rowShape
                .fill(Color.primary.opacity(colorScheme == .light ? 0.035 : 0.065))
                .overlay(
                    rowShape
                        .stroke(Color.primary.opacity(colorScheme == .light ? 0.065 : 0.12), lineWidth: 0.7)
                )

            shiftListTimelineGrid(bounds: bounds, width: width, height: height)

            if let entry,
               let range = shiftListRange(for: entry, on: dayDate),
               let barFrame = shiftListBarFrame(for: range, bounds: bounds, width: width) {
                shiftListShiftBar(
                    dayDate: dayDate,
                    entry: entry,
                    result: result,
                    tipCents: tipCents,
                    range: range,
                    frame: barFrame,
                    accent: accent,
                    height: height,
                    popoverArrowEdge: popoverArrowEdge
                )
            }
        }
        .frame(width: width, height: height)
    }

    private func shiftListTimelineGrid(
        bounds: ClosedRange<Int>,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            ForEach(shiftListTimelineTicks(bounds: bounds), id: \.self) { tick in
                Path { path in
                    let x = shiftListX(for: tick, bounds: bounds, width: width)
                    path.move(to: CGPoint(x: x, y: 6))
                    path.addLine(to: CGPoint(x: x, y: max(6, height - 6)))
                }
                .stroke(Color.primary.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
    }

    private func shiftListShiftBar(
        dayDate: Date,
        entry: DayEntry,
        result: ComputationResult?,
        tipCents: Int,
        range: ShiftTimeRange,
        frame: (x: CGFloat, width: CGFloat),
        accent: Color,
        height: CGFloat,
        popoverArrowEdge: Edge
    ) -> some View {
        let barHeight = max(44, height - 10)
        let shape = Capsule(style: .continuous)

        return Button {
            selectedPopoverDay = dayDate
        } label: {
            shiftListShiftBarLabel(entry: entry, range: range, width: frame.width)
                .frame(width: frame.width, height: barHeight)
                .background(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(colorScheme == .light ? 0.92 : 0.78),
                                    accent.opacity(colorScheme == .light ? 0.62 : 0.5)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .overlay(
                    shape
                        .stroke(.white.opacity(colorScheme == .light ? 0.34 : 0.18), lineWidth: 0.8)
                )
                .shadow(color: accent.opacity(0.14), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .offset(x: frame.x, y: (height - barHeight) / 2)
        .popover(
            isPresented: dayPopoverBinding(for: dayDate),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: popoverArrowEdge
        ) {
            ShiftViewPopover(
                date: dayDate,
                entry: entry,
                entries: entries,
                tipCents: tipCents,
                settings: settings,
                onEditTip: presentTipEditor,
                onDeleteTip: { deleteTipsFromCalendar(for: $0) },
                onEdit: presentDayEditor,
                onDelete: deleteDayFromPopover
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private func shiftListShiftBarLabel(
        entry: DayEntry,
        range: ShiftTimeRange,
        width: CGFloat
    ) -> some View {
        let durationText = PayScopeFormatters.hhmmString(seconds: range.durationSeconds)
        let startText = entry.shiftStart.map { PayScopeFormatters.time.string(from: $0) } ?? ShiftTimeRange.displayMinute(range.startMinute)
        let endText = entry.shiftEnd.map { PayScopeFormatters.time.string(from: $0) } ?? ShiftTimeRange.displayMinute(range.endMinuteOffset)

        return HStack(spacing: 5) {
            if width >= 132 {
                Text(startText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(durationText)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(endText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if width >= 72 {
                Text(durationText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .padding(.horizontal, width >= 132 ? 9 : 5)
    }

    private func shiftListBarFrame(
        for range: ShiftTimeRange,
        bounds: ClosedRange<Int>,
        width: CGFloat
    ) -> (x: CGFloat, width: CGFloat)? {
        let start = max(bounds.lowerBound, range.startMinute)
        let end = min(bounds.upperBound, range.endMinuteOffset)
        guard end > start else { return nil }
        let x = shiftListX(for: start, bounds: bounds, width: width)
        let endX = shiftListX(for: end, bounds: bounds, width: width)
        return (x: x, width: max(2, endX - x))
    }

    private func shiftListRange(for entry: DayEntry, on dayDate: Date) -> ShiftTimeRange? {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
            return nil
        }
        return ShiftTimeRange(anchorDate: dayDate, start: start, end: end)
    }

    private func shiftListTimelineBounds() -> ClosedRange<Int> {
        let configuredRanges = [settings.shiftShortcut1, settings.shiftShortcut2, settings.shiftShortcut3]
            .compactMap { shiftShortcutTimelineRange(raw: $0) }
        let lower = configuredRanges.map(\.lowerBound).min() ?? (6 * 60)
        let upper = configuredRanges.map(\.upperBound).max() ?? (22 * 60)
        let minimumUpper = lower + Int(shiftListVisibleHourCount * 60)
        return lower...max(upper, minimumUpper)
    }

    private func shiftShortcutTimelineRange(raw: String) -> ClosedRange<Int>? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(CalendarShiftShortcutBoundsPayload.self, from: data) {
            return shiftShortcutTimelineRange(startMinute: payload.startMinute, endMinute: payload.endMinute)
        }

        let parts = trimmed.split(separator: "-")
        guard parts.count == 2,
              let startMinute = Int(parts[0]),
              let endMinute = Int(parts[1]) else {
            return nil
        }
        return shiftShortcutTimelineRange(startMinute: startMinute, endMinute: endMinute)
    }

    private func shiftShortcutTimelineRange(startMinute: Int, endMinute: Int) -> ClosedRange<Int>? {
        let clampedStart = max(0, min(ShiftTimeRange.minutesPerDay - 1, startMinute))
        let normalizedEnd = endMinute <= clampedStart ? endMinute + ShiftTimeRange.minutesPerDay : endMinute
        let clampedEnd = max(clampedStart + 15, min(ShiftTimeRange.maxEndMinuteOffset, normalizedEnd))
        return clampedStart...clampedEnd
    }

    private func shiftListTimelineContentWidth(
        viewportWidth: CGFloat,
        bounds: ClosedRange<Int>
    ) -> CGFloat {
        let totalMinutes = max(1, bounds.upperBound - bounds.lowerBound)
        let visibleMinutes = max(1, Int(shiftListVisibleHourCount * 60))
        return max(viewportWidth, viewportWidth * CGFloat(totalMinutes) / CGFloat(visibleMinutes))
    }

    private func shiftListX(
        for minute: Int,
        bounds: ClosedRange<Int>,
        width: CGFloat
    ) -> CGFloat {
        let span = max(1, bounds.upperBound - bounds.lowerBound)
        let clamped = max(bounds.lowerBound, min(bounds.upperBound, minute))
        return width * CGFloat(clamped - bounds.lowerBound) / CGFloat(span)
    }

    private func shiftListTimelineTicks(bounds: ClosedRange<Int>) -> [Int] {
        let startHour = Int(floor(Double(bounds.lowerBound) / 60.0))
        let endHour = Int(ceil(Double(bounds.upperBound) / 60.0))
        return (startHour...endHour)
            .map { $0 * 60 }
            .filter { bounds.contains($0) }
    }

    private func displayedMonthDays() -> [Date] {
        let calendar = Calendar.current
        let monthStart = displayedMonth.startOfMonthLocal(calendar: calendar)
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)?.startOfDayLocal(calendar: calendar)
        }
    }

    private func handleMonthSwipe(_ gesture: DragGesture.Value) {
        guard calendarViewMode == .month else { return }
        let horizontal = gesture.translation.width
        let vertical = gesture.translation.height
        let horizontalDistance = abs(horizontal)
        let verticalDistance = abs(vertical)
        guard horizontalDistance >= 96, horizontalDistance > verticalDistance * 1.5 else {
            return
        }

        shiftDisplayedMonth(by: horizontal < 0 ? 1 : -1)
    }

    private func shiftDisplayedMonth(by delta: Int) {
        guard delta != 0 else { return }
        guard let targetMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth.startOfMonthLocal()) else {
            return
        }

        selectedPopoverDay = nil
        expandBackgroundCloudSyncWindowAfterSwipe(delta: delta, targetMonth: targetMonth)
        let normalizedTargetMonth = targetMonth.startOfMonthLocal()
        beginDisplayedMonthChange(to: normalizedTargetMonth)
        displayedMonth = normalizedTargetMonth
        monthSelectionFeedbackTrigger += 1
    }

    private func beginDisplayedMonthChange(to targetMonth: Date) {
        monthChangeFollowUpTask?.cancel()
        suppressCalendarCellAnimations = true
        monthChangeFollowUpTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: monthChangeSettlingDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard displayedMonth.startOfMonthLocal().isSameLocalDay(as: targetMonth.startOfMonthLocal()) else {
                return
            }
            await loadData(mode: .fullSync)
            suppressCalendarCellAnimations = false
        }
    }

    private func dayCell(
        for dayDate: Date,
        height: CGFloat,
        entry: DayEntry?,
        result: ComputationResult?,
        isHoliday: Bool,
        displayedTipCents: Int,
        weekBadgeData: WeekBadgeData?,
        popoverArrowEdge: Edge,
        isInDisplayedMonth: Bool
    ) -> some View {
        let visibleEntry = isInDisplayedMonth ? entry.flatMap { isVisibleInCalendarCell($0) ? $0 : nil } : nil
        let isToday = isInDisplayedMonth && Calendar.current.isDateInToday(dayDate)
        let isWeekend = Calendar.current.isDateInWeekend(dayDate)
        let visibleTipCents = isInDisplayedMonth ? displayedTipCents : 0
        let effectiveIsHoliday = isInDisplayedMonth && isHoliday
        let categoryTint = categoryTintColor(for: visibleEntry?.type, isHoliday: effectiveIsHoliday)
        let hasTipHighlight = isTipCalendarDisplayActive && visibleTipCents > 0
        let suppressShiftHighlightForTipFocus = isTipCalendarDisplayActive && visibleEntry != nil && !hasTipHighlight
        let displayedCategoryTint: Color? = {
            if hasTipHighlight {
                return settings.themeAccent.color
            }
            return suppressShiftHighlightForTipFocus ? nil : categoryTint
        }()
        let needsDarkRedContrast = isInDisplayedMonth && !isTipCalendarDisplayActive && needsDarkRedCalendarContrast(for: visibleEntry, isHoliday: effectiveIsHoliday)
        let todayHighlightColor = todayHighlightColor(for: visibleEntry)
        let hasSavedShift = hasSavedShift(in: visibleEntry)
        let usesShiftHighlight = hasSavedShift && !isTipCalendarDisplayActive
        let dayCardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let glassTint = dayCardGlassTint(
            isWeekend: isWeekend,
            isHoliday: effectiveIsHoliday,
            categoryTint: displayedCategoryTint,
            hasSavedShift: usesShiftHighlight,
            hasTipHighlight: hasTipHighlight
        )
        let renderedGlassTint = isInDisplayedMonth ? glassTint : Color.secondary
        let activeGlassTintOpacity = dayCardGlassTintOpacity(
            isWeekend: isWeekend,
            isHoliday: effectiveIsHoliday,
            isToday: isToday,
            hasSavedShift: usesShiftHighlight,
            hasTipHighlight: hasTipHighlight
        )
        let glassTintOpacity = isInDisplayedMonth
            ? activeGlassTintOpacity
            : (colorScheme == .light ? 0.075 : 0.052)
        let renderedGlassTintOpacity = colorScheme == .light
            ? min(0.28, glassTintOpacity * 1.45)
            : glassTintOpacity
        let dayCardFillOpacity = isInDisplayedMonth
            ? (colorScheme == .light
                ? max(0.22, renderedGlassTintOpacity * 1.25)
                : max(0.16, renderedGlassTintOpacity * 0.9))
            : (colorScheme == .light ? 0.11 : 0.075)
        let metricModel = calendarCellMetricModel(for: visibleEntry, result: isInDisplayedMonth ? result : nil, tipCents: visibleTipCents)
        let dayNumber = Calendar.current.component(.day, from: dayDate)
        let numberTopPadding = max(8, (height * 0.38) - 24)

        return Button {
            guard isInDisplayedMonth else { return }
            selectedPopoverDay = dayDate
        } label: {
            VStack(spacing: 0) {
                Text("\(dayNumber)")
                    .font(.system(size: isInDisplayedMonth ? 26 : 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        isInDisplayedMonth
                            ? dayNumberForegroundColor(
                                isWeekend: isWeekend,
                                isHoliday: effectiveIsHoliday,
                                categoryTint: displayedCategoryTint
                            )
                            : .secondary.opacity(0.28)
                    )
                    .padding(.top, numberTopPadding)

                Group {
                    if isToday {
                        Capsule(style: .continuous)
                            .fill(todayHighlightColor.opacity(0.72))
                            .frame(width: 30, height: 3)
                            .shadow(color: todayHighlightColor.opacity(0.18), radius: 6, x: 0, y: 2)
                    } else {
                        Color.clear
                    }
                }

                .frame(height: 6)
                .padding(.top, 2)

                Spacer(minLength: 2)

                CalendarCellMorphMetricView(model: metricModel)
                    .frame(maxWidth: .infinity)

                if isInDisplayedMonth, !isTipCalendarDisplayActive, let result {
                    switch result {
                    case .warning:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    case .error:
                        if !shouldHideCalendarErrorIcon(for: visibleEntry, result: result) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    case .ok:
                        EmptyView()
                    }
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                ZStack {
                    dayCardShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    renderedGlassTint.opacity(dayCardFillOpacity),
                                    renderedGlassTint.opacity(max(0.035, dayCardFillOpacity * 0.56))
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if isInDisplayedMonth, usesShiftHighlight, let shiftTint = categoryTint {
                        dayCardShape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        shiftTint.opacity(colorScheme == .light ? 0.34 : 0.28),
                                        shiftTint.opacity(colorScheme == .light ? 0.16 : 0.13),
                                        shiftTint.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            )
            .overlay(
                dayCardShape
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .light ? 0.16 : 0.07),
                                .white.opacity(colorScheme == .light ? 0.035 : 0.02),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            )
            .overlay(
                ZStack {
                    dayCardShape
                        .stroke(
                            isInDisplayedMonth
                                ? Color.primary.opacity(colorScheme == .light ? 0.07 : 0.12)
                                : Color.secondary.opacity(colorScheme == .light ? 0.11 : 0.08),
                            lineWidth: 0.75
                        )

                    dayCardShape
                        .stroke(.white.opacity(colorScheme == .light ? 0.38 : 0.12), lineWidth: 0.55)

                    if isToday {
                        dayCardShape
                            .stroke(todayHighlightColor.opacity(0.24), lineWidth: 0.9)
                    }

                    if needsDarkRedContrast {
                        dayCardShape
                            .stroke((categoryTint ?? .red).opacity(0.34), lineWidth: 1.1)
                    }
                }
            )
            .overlay(alignment: .topLeading) {
                if let weekBadgeData {
                    weekBadgeView(weekBadgeData, muted: !isInDisplayedMonth || (isWeekend && !effectiveIsHoliday))
                        .padding(.top, 7)
                        .padding(.leading, 7)
                }
            }
            .shadow(
                color: !isInDisplayedMonth
                    ? .clear
                    : (hasTipHighlight
                        ? settings.themeAccent.color.opacity(0.1)
                        : (isToday ? todayHighlightColor.opacity(0.07) : .black.opacity(colorScheme == .light ? 0.035 : 0.12))),
                radius: !isInDisplayedMonth ? 0 : ((hasTipHighlight || isToday) ? 5 : 3),
                x: 0,
                y: !isInDisplayedMonth ? 0 : ((hasTipHighlight || isToday) ? 3 : 2)
            )
        }
        .buttonStyle(.plain)
        .contentShape(dayCardShape)
        .accessibilityHidden(!isInDisplayedMonth)
        .popover(
            isPresented: dayPopoverBinding(for: dayDate),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: popoverArrowEdge
        ) {
            ShiftViewPopover(
                date: dayDate,
                entry: visibleEntry,
                entries: entries,
                tipCents: visibleTipCents,
                settings: settings,
                onEditTip: presentTipEditor,
                onDeleteTip: { deleteTipsFromCalendar(for: $0) },
                onEdit: presentDayEditor,
                onDelete: deleteDayFromPopover
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private func dayPopoverBinding(for dayDate: Date) -> Binding<Bool> {
        Binding(
            get: {
                selectedPopoverDay?.isSameLocalDay(as: dayDate) == true
            },
            set: { isPresented in
                if isPresented {
                    selectedPopoverDay = dayDate
                } else if selectedPopoverDay?.isSameLocalDay(as: dayDate) == true {
                    selectedPopoverDay = nil
                }
            }
        )
    }

    private func presentDayEditor(for date: Date) {
        let selection = CalendarDaySelection(date: date.startOfDayLocal())
        selectedPopoverDay = nil
        DispatchQueue.main.async {
            selectedEditorDay = selection
        }
    }

    private func presentTipEditor(for date: Date) {
        let localDay = date.startOfDayLocal()
        let existingTip = primaryTipEntry(for: localDay)
        let existingAmount = tipCents(for: localDay, entry: entry(for: localDay))
        guard settings.effectiveShowTipsButton || existingAmount > 0 else { return }
        selectedPopoverDay = nil
        DispatchQueue.main.async {
            selectedTipEditorState = TipEntryEditorState(
                tip: existingTip,
                initialDate: localDay,
                initialAmountCents: existingAmount > 0 ? existingAmount : nil
            )
        }
    }

    private func tipEditorDateRange(containing date: Date) -> ClosedRange<Date> {
        let month = date.startOfMonthLocal()
        let interval = Calendar.current.dateInterval(of: .month, for: month)
            ?? DateInterval(start: month, duration: 24 * 60 * 60)
        return interval.start...interval.end.addingTimeInterval(-1)
    }

    private func saveTipFromCalendar(
        date: Date,
        amountCents: Int,
        replacing existingTip: TipEntry?,
        previousDate: Date,
        isEditingExistingTip: Bool
    ) {
        guard amountCents > 0 else { return }
        let updatedAt = Date()
        let targetDate = date.startOfDayLocal()
        let previousDay = previousDate.startOfDayLocal()
        let replacementTip = existingTip ?? (isEditingExistingTip ? primaryTipEntry(for: previousDay) : nil)

        let tip = TipEntry(
            id: replacementTip?.id ?? UUID().uuidString,
            date: targetDate,
            amountCents: amountCents,
            updatedAt: updatedAt
        )
        LocalTipEntryStore.shared.save(tip)

        var tipsToDelete: [TipEntry] = []
        if isEditingExistingTip {
            tipsToDelete = supersededTipEntries(
                replacementID: tip.id,
                previousDay: previousDay,
                targetDay: targetDate
            )
            for oldTip in tipsToDelete {
                LocalTipEntryStore.shared.delete(oldTip)
                syncTipDeleteFromCalendar(oldTip)
            }
        }

        var nextTips = mergeTipEntriesKeepingNewest(local: tipEntries + [tip], remote: [])
        if !tipsToDelete.isEmpty {
            let deletedIDs = Set(tipsToDelete.map(\.id))
            nextTips.removeAll { deletedIDs.contains($0.id) }
        }
        tipEntries = nextTips.filter { displayedMonthTipInterval.contains($0.date) }

        persistDayTipAmountFromCalendar(amountCents, for: targetDate, updatedAt: updatedAt)
        if !previousDay.isSameLocalDay(as: targetDate) {
            persistDayTipAmountFromCalendar(0, for: previousDay, updatedAt: updatedAt)
        }

        syncTipFromCalendar(tip)
    }

    private func primaryTipEntry(for date: Date) -> TipEntry? {
        tipEntries(on: date)
            .sorted {
                if $0.updatedAt == $1.updatedAt {
                    return $0.id < $1.id
                }
                return $0.updatedAt > $1.updatedAt
            }
            .first
    }

    private func tipEntries(on date: Date) -> [TipEntry] {
        let localDay = date.startOfDayLocal()
        return mergeTipEntriesKeepingNewest(
            local: tipEntries + LocalTipEntryStore.shared.loadAll(),
            remote: []
        )
        .filter { $0.date.isSameLocalDay(as: localDay) }
    }

    private func supersededTipEntries(
        replacementID: String,
        previousDay: Date,
        targetDay: Date
    ) -> [TipEntry] {
        mergeTipEntriesKeepingNewest(
            local: tipEntries + LocalTipEntryStore.shared.loadAll(),
            remote: []
        )
        .filter { tip in
            tip.id != replacementID &&
            (
                tip.date.isSameLocalDay(as: previousDay) ||
                tip.date.isSameLocalDay(as: targetDay)
            )
        }
    }

    private func persistDayTipAmountFromCalendar(_ amountCents: Int, for date: Date, updatedAt: Date) {
        let day = date.startOfDayLocal()
        guard let target = localStore.load(on: day) ?? entry(for: day) else { return }

        if target.isTipOnlyPlaceholder {
            localStore.delete(on: day)
            entries.removeAll { $0.date.isSameLocalDay(as: day) }
            Task {
                do {
                    try await cloudKitService.deleteDayEntry(on: day)
                } catch {
                    #if DEBUG
                    print("CloudKit day tip cleanup failed, local tombstone kept for retry: \(error)")
                    #endif
                }
            }
            return
        }

        guard target.isRealTrackedDay else { return }

        let existingAmount = max(0, target.tipAmountCents ?? 0)
        let normalizedAmount = max(0, amountCents)
        guard normalizedAmount > 0 || existingAmount > 0 else { return }
        guard existingAmount != normalizedAmount else { return }

        target.date = utcDate(forLocalDay: day)
        target.updatedAt = max(target.updatedAt, updatedAt)
        target.tipAmountCents = normalizedAmount > 0 ? normalizedAmount : nil

        localStore.save(target)
        entries.removeAll { $0.date.isSameLocalDay(as: day) }
        entries.append(target)
        entries.sort { $0.date > $1.date }

        Task {
            do {
                try await cloudKitService.saveDayEntry(target)
                localStore.save(target)
            } catch {
                #if DEBUG
                print("CloudKit day tip save failed, persisted locally as fallback: \(error)")
                #endif
            }
        }
    }

    private func syncTipFromCalendar(_ tip: TipEntry) {
        Task {
            do {
                try await cloudKitService.saveTipEntry(tip)
                LocalTipEntryStore.shared.markSynced(tip)
            } catch {
                #if DEBUG
                print("Tip save from calendar failed, persisted locally as fallback: \(error)")
                #endif
            }
        }
    }

    private func syncTipDeleteFromCalendar(_ tip: TipEntry) {
        Task {
            do {
                try await cloudKitService.deleteTipEntry(tip)
            } catch {
                #if DEBUG
                print("Tip delete from calendar failed, persisted locally as fallback: \(error)")
                #endif
            }
        }
    }

    private func deleteTipsFromCalendar(for date: Date) {
        let day = date.startOfDayLocal()
        let deletedAt = Date()
        let tipsForDay = tipEntries(on: day)

        for tip in tipsForDay {
            LocalTipEntryStore.shared.delete(tip, deletedAt: deletedAt)
            syncTipDeleteFromCalendar(tip)
        }

        tipEntries.removeAll { $0.date.isSameLocalDay(as: day) }
        persistDayTipAmountFromCalendar(0, for: day, updatedAt: deletedAt)
        selectedPopoverDay = nil
    }

    private func deleteDayFromPopover(for date: Date) {
        dayDeleteFeedbackTrigger += 1
        deleteDayEntry(for: date.startOfDayLocal())
        selectedPopoverDay = nil
    }

    private func isVisibleInCalendarCell(_ entry: DayEntry) -> Bool {
        if (entry.manualWorkedSeconds ?? 0) > 0 { return true }
        if (entry.creditedOverrideSeconds ?? 0) > 0 { return true }
        if entry.type != .work { return true }
        if let s = entry.shiftStart, let e = entry.shiftEnd, e > s { return true }
        return false
    }

    private func needsDarkRedCalendarContrast(for entry: DayEntry?, isHoliday: Bool) -> Bool {
        guard colorScheme == .dark, let entry else { return false }

        if entry.type == .work {
            return settings.themeAccent == .red
        }

        if isHoliday {
            return isWarmRedCategory(settings.effectiveHolidayCategoryColor)
        }

        guard let categoryColor = settings.categoryColorSelection(for: entry.type) else {
            return false
        }
        return isWarmRedCategory(categoryColor)
    }

    private func isWarmRedCategory(_ color: ShiftCategoryColor) -> Bool {
        color == .blush || color == .coral
    }

    private func dayCardGlassTint(
        isWeekend: Bool,
        isHoliday: Bool,
        categoryTint: Color?,
        hasSavedShift: Bool,
        hasTipHighlight: Bool
    ) -> Color {
        if hasTipHighlight {
            return settings.themeAccent.color
        }
        if let categoryTint, hasSavedShift || isHoliday {
            return categoryTint
        }
        if isHoliday {
            return settings.categoryColor(for: .holiday)
        }
        if isWeekend {
            return colorScheme == .dark ? .black : settings.themeAccent.color.opacity(0.68)
        }
        return categoryTint ?? (colorScheme == .dark ? settings.themeAccent.color.opacity(0.68) : settings.themeAccent.color)
    }

    private func dayCardGlassTintOpacity(
        isWeekend: Bool,
        isHoliday: Bool,
        isToday: Bool,
        hasSavedShift: Bool,
        hasTipHighlight: Bool
    ) -> Double {
        if hasTipHighlight {
            return isToday ? 0.2 : 0.18
        }
        if isToday {
            return hasSavedShift ? 0.18 : 0.14
        }
        if hasSavedShift {
            return 0.16
        }
        if isHoliday {
            return 0.13
        }
        if colorScheme == .dark {
            return isWeekend ? 0.12 : 0.075
        }
        return isWeekend ? 0.075 : 0.095
    }

    private func hasSavedShift(in entry: DayEntry?) -> Bool {
        guard let entry else { return false }
        if let start = entry.shiftStart, let end = entry.shiftEnd, end > start {
            return true
        }
        return false
    }

    private func todayHighlightColor(for entry: DayEntry?) -> Color {
        guard let entry, entry.type != .work else {
            return settings.themeAccent.color
        }
        return settings.categoryColor(for: entry.type)
    }

    private func dayNumberForegroundColor(
        isWeekend: Bool,
        isHoliday: Bool,
        categoryTint: Color?
    ) -> Color {
        if isHoliday {
            return settings.categoryColor(for: .holiday)
        }
        if let categoryTint {
            return categoryTint
        }
        return isWeekend ? .secondary : .primary
    }

    private func categoryTintColor(for dayType: DayType?, isHoliday: Bool) -> Color? {
        if isHoliday {
            return settings.categoryColor(for: .holiday)
        }
        return dayType.map { settings.categoryColor(for: $0) }
    }

    private var monthYearParts: (month: String, year: String) {
        let value = germanMonthYear(displayedMonth)
        let parts = value.split(separator: " ")
        return (
            month: parts.first.map(String.init) ?? "",
            year: parts.dropFirst().joined(separator: " ")
        )
    }

    private func germanMonthYear(_ date: Date) -> String {
        Self.monthYearFormatter.string(from: date)
    }

    private var shouldShowWeekBadge: Bool {
        settings.effectiveShowCalendarWeekNumbers ||
        settings.effectiveShowCalendarWeekHours ||
        settings.effectiveShowCalendarWeekPay
    }

    private func weekBadgeView(_ data: WeekBadgeData, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let weekNumber = data.weekNumber {
                Text("KW \(weekNumber)")
            }
            if let detailText = data.detailText {
                Text(detailText)
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(muted ? .secondary : settings.themeAccent.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill((muted ? Color.secondary : settings.themeAccent.color).opacity(0.12))
        )
    }

    private func calendarCellMetricModel(
        for entry: DayEntry?,
        result: ComputationResult?,
        tipCents: Int
    ) -> CalendarCellMetricModel {
        let mode = settings.calendarCellDisplayMode ?? .dot
        let hasTips = tipCents > 0
        let tipTint: Color = isTipCalendarDisplayActive ? settings.themeAccent.color : .secondary
        let tipValueText = isTipCalendarDisplayActive && hasTips ? shortCurrency(cents: tipCents) : nil

        func emptyOrTipMetric(animationKey: String) -> CalendarCellMetricModel {
            guard hasTips else {
                return .empty(animationKey: animationKey)
            }
            return .tipsOnly(tint: tipTint, text: tipValueText, animationKey: animationKey)
        }

        if isTipCalendarDisplayActive {
            return emptyOrTipMetric(
                animationKey: "tips-only-\(mode.rawValue)-\(tipCents)-active-\(isTipCalendarDisplayActive)"
            )
        }

        guard let entry else {
            return emptyOrTipMetric(
                animationKey: "tips-only-\(mode.rawValue)-\(tipCents)-active-\(isTipCalendarDisplayActive)"
            )
        }

        let categoryTint = isTipCalendarDisplayActive ? Color.secondary : settings.categoryColor(for: entry.type)
        let metricTextTint: Color = isTipCalendarDisplayActive ? .secondary : .primary
        let hasShiftDeviation = entry.creditedOverrideSeconds != nil
        let animationKey = "\(mode.rawValue)-break-\(settings.effectiveCalendarHoursBreakMode.rawValue)-tipfocus-\(isTipCalendarDisplayActive)-\(metricAnimationKey(for: entry, result: result, tipCents: tipCents))"

        switch mode {
        case .dot:
            return .iconOnly(
                symbol: entry.type.icon,
                tint: categoryTint,
                showsTips: hasTips,
                tipTint: tipTint,
                showsDeviation: hasShiftDeviation,
                animationKey: animationKey
            )
        case .hours:
            let seconds = calendarCellHoursSeconds(for: entry, result: result)
            return .textMetric(
                symbol: entry.type.icon,
                tint: categoryTint,
                text: tipValueText ?? PayScopeFormatters.hhmmString(seconds: seconds),
                textTint: tipValueText == nil ? metricTextTint : tipTint,
                showsTips: hasTips,
                tipTint: tipTint,
                showsDeviation: hasShiftDeviation,
                animationKey: animationKey
            )
        case .pay:
            let cents: Int = {
                guard let result else { return 0 }
                switch result {
                case let .ok(_, valueCents), let .warning(_, valueCents, _):
                    return valueCents
                case .error:
                    return 0
                }
            }()
            return .textMetric(
                symbol: entry.type.icon,
                tint: categoryTint,
                text: tipValueText ?? shortCurrency(cents: cents),
                textTint: tipValueText == nil ? metricTextTint : tipTint,
                showsTips: hasTips,
                tipTint: tipTint,
                showsDeviation: hasShiftDeviation,
                animationKey: animationKey
            )
        case .startTime:
            if let tipValueText {
                return .textMetric(
                    symbol: entry.type.icon,
                    tint: categoryTint,
                    text: tipValueText,
                    textTint: tipTint,
                    showsTips: hasTips,
                    tipTint: tipTint,
                    showsDeviation: hasShiftDeviation,
                    animationKey: animationKey
                )
            }
            if isTipCalendarDisplayActive {
                return emptyOrTipMetric(animationKey: animationKey)
            }
            guard let text = calendarCellStartTimeText(for: entry) else {
                return emptyOrTipMetric(animationKey: animationKey)
            }
            return .textMetric(
                symbol: entry.type.icon,
                tint: categoryTint,
                text: text,
                textTint: metricTextTint,
                showsTips: hasTips,
                tipTint: tipTint,
                showsDeviation: hasShiftDeviation,
                animationKey: animationKey
            )
        case .endTime:
            if let tipValueText {
                return .textMetric(
                    symbol: entry.type.icon,
                    tint: categoryTint,
                    text: tipValueText,
                    textTint: tipTint,
                    showsTips: hasTips,
                    tipTint: tipTint,
                    showsDeviation: hasShiftDeviation,
                    animationKey: animationKey
                )
            }
            if isTipCalendarDisplayActive {
                return emptyOrTipMetric(animationKey: animationKey)
            }
            guard let text = calendarCellEndTimeText(for: entry) else {
                return emptyOrTipMetric(animationKey: animationKey)
            }
            return .textMetric(
                symbol: entry.type.icon,
                tint: categoryTint,
                text: text,
                textTint: metricTextTint,
                showsTips: hasTips,
                tipTint: tipTint,
                showsDeviation: hasShiftDeviation,
                animationKey: animationKey
            )
        case .startAndEndTime:
            if let tipValueText {
                return .textMetric(
                    symbol: entry.type.icon,
                    tint: categoryTint,
                    text: tipValueText,
                    textFontSize: 10,
                    textTint: tipTint,
                    showsTips: hasTips,
                    tipTint: tipTint,
                    showsDeviation: hasShiftDeviation,
                    animationKey: animationKey
                )
            }
            if isTipCalendarDisplayActive {
                return emptyOrTipMetric(animationKey: animationKey)
            }
            guard let text = calendarCellStartAndEndTimeRows(for: entry).first?.text else {
                return emptyOrTipMetric(animationKey: animationKey)
            }
            return .textMetric(
                symbol: entry.type.icon,
                tint: categoryTint,
                text: text,
                textFontSize: 10,
                textTint: metricTextTint,
                showsTips: hasTips,
                tipTint: tipTint,
                showsDeviation: hasShiftDeviation,
                animationKey: animationKey
            )
        }
    }

    private func calendarCellStartTimeText(for entry: DayEntry) -> String? {
        guard let start = entry.shiftStart else { return nil }
        return PayScopeFormatters.time.string(from: start)
    }

    private func calendarCellEndTimeText(for entry: DayEntry) -> String? {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
            return nil
        }
        let suffix = Calendar.current.isDate(start, inSameDayAs: end) ? "" : " +1"
        return "\(PayScopeFormatters.time.string(from: end))\(suffix)"
    }

    private func calendarCellStartAndEndTimeRows(for entry: DayEntry) -> [CalendarCellTimeRow] {
        guard
            let start = entry.shiftStart,
            let end = entry.shiftEnd,
            end > start
        else {
            return []
        }

        func roundedHourString(for date: Date) -> String {
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)

            var hour = components.hour ?? 0
            let minute = components.minute ?? 0

            if minute >= 30 {
                hour += 1
            }

            hour = hour % 24

            return String(format: "%02d", hour)
        }

        let startHour = roundedHourString(for: start)
        let endHour = roundedHourString(for: end)

        return [
            CalendarCellTimeRow(
                text: "\(startHour) → \(endHour)"
            )
        ]
    }

    private func shiftTimeRangeText(for entry: DayEntry) -> String? {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
            return nil
        }
        return "\(PayScopeFormatters.time.string(from: start))–\(PayScopeFormatters.time.string(from: end))"
    }

    private func metricAnimationKey(for entry: DayEntry?, result: ComputationResult?, tipCents: Int) -> String {
        guard let entry else { return "tips-\(tipCents)" }
        let resultKey: String = {
            guard let result else { return "nil" }
            switch result {
            case let .ok(seconds, cents):
                return "ok-\(seconds)-\(cents)"
            case let .warning(seconds, cents, reason):
                return "warn-\(seconds)-\(cents)-\(reason)"
            case .error:
                return "error"
            }
        }()
        let shiftKey: String = {
            guard let shift = shiftTimeRangeText(for: entry) else { return "no-shift" }
            return shift
        }()
        return "\(entry.type.rawValue)-\(entry.updatedAt.timeIntervalSinceReferenceDate)-\(shiftKey)-tips-\(tipCents)-\(resultKey)"
    }

    private func calendarCellHoursSeconds(for entry: DayEntry, result: ComputationResult?) -> Int {
        switch settings.effectiveCalendarHoursBreakMode {
        case .withoutBreak:
            return secondsFromResult(result)
        case .withBreak:
            if let manual = entry.manualWorkedSeconds {
                return max(0, manual)
            }
            if let start = entry.shiftStart, let end = entry.shiftEnd, end > start {
                return max(0, Int(end.timeIntervalSince(start)))
            }
            return secondsFromResult(result)
        }
    }

    private func secondsFromResult(_ result: ComputationResult?) -> Int {
        guard let result else { return 0 }
        switch result {
        case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
            return valueSeconds
        case .error:
            return 0
        }
    }

    private func shouldHideCalendarErrorIcon(for entry: DayEntry?, result: ComputationResult) -> Bool {
        guard case .error = result else { return false }
        guard let entry else { return false }
        guard entry.type == .vacation || entry.type == .holiday || entry.type == .sick else { return false }
        guard entry.creditedOverrideSeconds == nil else { return false }
        switch entry.type {
        case .vacation:
            guard settings.effectiveVacationCreditingMode == .lookback13Weeks else { return false }
        case .holiday:
            guard settings.effectiveHolidayCreditingMode == .lookback13Weeks else { return false }
        case .sick:
            break
        case .work, .manual:
            return false
        }
        return secondsFromResult(result) == 0
    }

    private func shortCurrency(cents: Int) -> String {
        let value = NSNumber(value: Double(cents) / 100)
        return Self.compactCurrencyFormatter.string(from: value) ?? "0"
    }

    private func monthDates() -> [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        let firstOfMonth = displayedMonth.startOfMonthLocal(calendar: calendar)
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingDayCount = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDayCount, to: firstOfMonth) else {
            return []
        }

        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    private func deleteDayEntry(for date: Date) {
        // Optimistic UI update: remove the local entry immediately so the calendar reflects the change
        entries.removeAll { $0.date.isSameLocalDay(as: date) }
        deleteLegacyTips(on: date)
        localStore.delete(on: date)

        Task { @MainActor in
            await AppleCalendarSyncService.shared.deleteEvent(for: date)
            do {
                try await cloudKitService.deleteDayEntry(on: date)
            } catch {
                #if DEBUG
                print("Failed to delete day entry for \(date), local tombstone kept for retry: \(error)")
                #endif
            }
        }
    }

    private func deleteLegacyTips(on date: Date) {
        let tipsForDay = LocalTipEntryStore.shared
            .loadAll()
            .filter { $0.date.isSameLocalDay(as: date) }
        guard !tipsForDay.isEmpty else { return }

        tipEntries.removeAll { $0.date.isSameLocalDay(as: date) }
        for tip in tipsForDay {
            LocalTipEntryStore.shared.delete(tip)
            Task {
                do {
                    try await cloudKitService.deleteTipEntry(tip)
                } catch {
                    #if DEBUG
                    print("Failed to delete legacy tip entry for \(date): \(error)")
                    #endif
                }
            }
        }
    }

    private func applyDayEditorChange(_ dayDate: Date, _ entry: DayEntry?) {
        let localDay = dayDate.startOfDayLocal()
        entries.removeAll { $0.date.isSameLocalDay(as: localDay) }

        guard let entry else { return }
        entries.append(entry)
        entries.sort { $0.date > $1.date }
    }

    private var holidayImportTaskKey: String {
        let year = Calendar.current.component(.year, from: displayedMonth)
        let country = normalizedHolidayCountryCode ?? "NONE"
        let subdivision = normalizedHolidaySubdivisionCode ?? "ALL"
        return "\(year)-\(country)-\(subdivision)"
    }

    private var normalizedHolidayCountryCode: String? {
        normalizeCode(settings.holidayCountryCode) ?? "DE"
    }

    private var normalizedHolidaySubdivisionCode: String? {
        normalizeCode(settings.holidaySubdivisionCode)
    }

    @MainActor
    private func loadData(mode: DataLoadMode = .fullSync) async {
        if isLoadingData {
            if mode == .fullSync {
                pendingLoadAfterCurrentCycle = true
            }
            return
        }
        isLoadingData = true
        defer {
            isLoadingData = false
            if pendingLoadAfterCurrentCycle {
                pendingLoadAfterCurrentCycle = false
                Task { await loadData(mode: .fullSync) }
            }
        }

        ensureBackgroundCloudSyncWindowCovers(month: displayedMonth)
        let interval = backgroundCloudSyncInterval

        let localTips = LocalTipEntryStore.shared.loadAll(in: interval)
        let localRawEntries = localStore.loadAll(in: interval)
        let localEntries = entriesWithLegacyTipsApplied(
            to: localRawEntries,
            tips: localTips,
            persist: true
        )
        let localSnapshot = deduplicateEntriesByLocalDayKeepingNewest(localEntries)
        let localNetConfigs = fetchLocalNetConfigs()
        if mode == .localOnly || entries.isEmpty {
            // Cold start: show persisted data immediately, then refresh from cloud.
            applyEntriesIfChanged(localSnapshot)
        }
        if mode == .localOnly || netConfigs.isEmpty {
            applyNetConfigsIfChanged(localNetConfigs)
        }
        guard mode == .fullSync else { return }

        do {
            // Cloud-first: prefer iCloud data when reachable.
            var cloudEntries = deduplicateEntriesByLocalDayKeepingNewest(
                try await cloudKitService.fetchDayEntries(in: interval)
            )

            await cleanupTipOnlyDayPlaceholders(localEntries: localRawEntries, remoteEntries: cloudEntries)
            var tombstonesByDay = deletionTombstonesByDay(in: interval)
            cloudEntries = cloudEntries.filter(\.isRealTrackedDay)

            // Sync local deletions to cloud first (LWW).
            let didSyncDeletes = await syncPendingLocalDeletionsToCloud(
                cloudEntries: cloudEntries,
                interval: interval
            )
            if didSyncDeletes {
                cloudEntries = deduplicateEntriesByLocalDayKeepingNewest(
                    try await cloudKitService.fetchDayEntries(in: interval)
                )
                await cleanupTipOnlyDayPlaceholders(localEntries: localRawEntries, remoteEntries: cloudEntries)
                tombstonesByDay = deletionTombstonesByDay(in: interval)
                cloudEntries = cloudEntries.filter(\.isRealTrackedDay)
            }

            // If local fallback entries exist, sync newer local versions back to iCloud.
            if !localSnapshot.isEmpty {
                let didSyncPending = await syncPendingLocalEntriesToCloud(localEntries: localSnapshot, cloudEntries: cloudEntries)
                if didSyncPending {
                    cloudEntries = deduplicateEntriesByLocalDayKeepingNewest(
                        try await cloudKitService.fetchDayEntries(in: interval)
                    )
                    cloudEntries = cloudEntries.filter(\.isRealTrackedDay)
                }
            }

            let cloudEntriesWithoutLocallyDeleted = cloudEntries.filter { cloudEntry in
                guard let deletedAt = tombstonesByDay[dayKey(cloudEntry.date)] else { return true }
                return deletedAt < cloudEntry.updatedAt
            }
            localStore.upsertMany(cloudEntriesWithoutLocallyDeleted, notify: false)

            // UI should reflect newest known state immediately, even if CloudKit query is briefly stale.
            let mergedForUI = entriesWithLegacyTipsApplied(
                to: mergeEntriesByLocalDayKeepingNewest(
                    local: localSnapshot,
                    remote: cloudEntriesWithoutLocallyDeleted
                ),
                tips: localTips,
                persist: true
            )

            applyEntriesIfChanged(mergedForUI)

            // load persisted net wage configurations
            let cloudNetConfigs = try await cloudKitService.fetchNetWageConfigs()
            for config in cloudNetConfigs {
                upsertLocalNetConfig(config)
            }
            applyNetConfigsIfChanged(mergedNetConfigs(local: fetchLocalNetConfigs(), remote: cloudNetConfigs))

            // load holiday data for the displayed year
            let year = Calendar.current.component(.year, from: displayedMonth)
            let country = normalizedHolidayCountryCode
            let subdivision = normalizedHolidaySubdivisionCode
            applyImportedHolidaysIfChanged(
                try await cloudKitService.fetchHolidayDays(
                    countryCode: country,
                    subdivisionCode: subdivision,
                    year: year
                )
            )
        } catch {
            #if DEBUG
            print("Calendar loadData failed: \(error)")
            #endif
            // Fallback: keep app usable offline/unreachable.
            applyEntriesIfChanged(deduplicateEntriesByLocalDayKeepingNewest(localEntries))
            applyNetConfigsIfChanged(fetchLocalNetConfigs())
        }
    }

    private func applyEntriesIfChanged(_ newEntries: [DayEntry]) {
        guard dayEntriesSignature(newEntries) != dayEntriesSignature(entries) else { return }
        entries = newEntries
    }

    private func applyNetConfigsIfChanged(_ newConfigs: [NetWageMonthConfig]) {
        guard netConfigSignature(newConfigs) != netConfigSignature(netConfigs) else { return }
        netConfigs = newConfigs
    }

    private func fetchLocalNetConfigs() -> [NetWageMonthConfig] {
        let descriptor = FetchDescriptor<NetWageMonthConfig>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func upsertLocalNetConfig(_ source: NetWageMonthConfig) {
        let normalizedMonth = source.monthStart.startOfMonthUTC()
        let existing = fetchLocalNetConfigs().first {
            netConfigMonthKey($0.monthStart) == netConfigMonthKey(normalizedMonth)
        }

        if let existing {
            existing.monthStart = normalizedMonth
            existing.wageTaxPercent = source.wageTaxPercent
            existing.pensionPercent = source.pensionPercent
            existing.monthlyAllowanceEuro = source.monthlyAllowanceEuro
            existing.bonusesCSV = source.bonusesCSV
        } else {
            modelContext.insert(
                NetWageMonthConfig(
                    monthStart: normalizedMonth,
                    wageTaxPercent: source.wageTaxPercent,
                    pensionPercent: source.pensionPercent,
                    monthlyAllowanceEuro: source.monthlyAllowanceEuro,
                    bonusesCSV: source.bonusesCSV
                )
            )
        }
        try? modelContext.save()
    }

    private func mergedNetConfigs(local: [NetWageMonthConfig], remote: [NetWageMonthConfig]) -> [NetWageMonthConfig] {
        var byMonth: [String: NetWageMonthConfig] = [:]
        for config in local {
            byMonth[netConfigMonthKey(config.monthStart)] = config
        }
        for config in remote {
            byMonth[netConfigMonthKey(config.monthStart)] = config
        }
        return byMonth.values.sorted { $0.monthStart < $1.monthStart }
    }

    private func netConfigMonthKey(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month], from: date.startOfMonthUTC())
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    private func applyImportedHolidaysIfChanged(_ newHolidays: [HolidayCalendarDay]) {
        guard holidaySignature(newHolidays) != holidaySignature(importedHolidays) else { return }
        importedHolidays = newHolidays
    }

    private func dayEntriesSignature(_ values: [DayEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(values.count)
        for value in values.sorted(by: { $0.date < $1.date }) {
            hasher.combine(value.date.timeIntervalSinceReferenceDate)
            hasher.combine(value.updatedAt.timeIntervalSinceReferenceDate)
            hasher.combine(value.type.rawValue)
            hasher.combine(value.manualWorkedSeconds ?? -1)
            hasher.combine(value.creditedOverrideSeconds ?? -1)
            hasher.combine(value.shiftStart?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(value.shiftEnd?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(value.breakSeconds ?? -1)
            hasher.combine(value.alwaysApplyFifteenMinuteBuffer ?? false)
            hasher.combine(value.tipAmountCents ?? -1)
            hasher.combine(value.segments.count)
            for segment in value.segments.sorted(by: { $0.start < $1.start }) {
                hasher.combine(segment.start.timeIntervalSinceReferenceDate)
                hasher.combine(segment.end.timeIntervalSinceReferenceDate)
                hasher.combine(segment.breakSeconds)
            }
        }
        return hasher.finalize()
    }

    private func netConfigSignature(_ values: [NetWageMonthConfig]) -> Int {
        var hasher = Hasher()
        hasher.combine(values.count)
        for value in values.sorted(by: { $0.monthStart < $1.monthStart }) {
            hasher.combine(value.monthStart.timeIntervalSinceReferenceDate)
            hasher.combine(value.wageTaxPercent ?? -1)
            hasher.combine(value.pensionPercent ?? -1)
            hasher.combine(value.monthlyAllowanceEuro ?? -1)
            hasher.combine(value.bonusesCSV)
        }
        return hasher.finalize()
    }

    private func tipEntriesSignature(_ values: [TipEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(values.count)
        for value in values.sorted(by: { $0.id < $1.id }) {
            hasher.combine(value.id)
            hasher.combine(value.date.timeIntervalSinceReferenceDate)
            hasher.combine(value.amountCents)
            hasher.combine(value.updatedAt.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    private func holidaySignature(_ values: [HolidayCalendarDay]) -> Int {
        var hasher = Hasher()
        hasher.combine(values.count)
        for value in values.sorted(by: { $0.key < $1.key }) {
            hasher.combine(value.key)
            hasher.combine(value.date.timeIntervalSinceReferenceDate)
            hasher.combine(value.localName)
            hasher.combine(value.countryCode)
            hasher.combine(value.subdivisionCode ?? "")
            hasher.combine(value.sourceYear)
        }
        return hasher.finalize()
    }

    private func syncPendingLocalEntriesToCloud(localEntries: [DayEntry], cloudEntries: [DayEntry]) async -> Bool {
        let localNewestByDay = deduplicateEntriesByLocalDayKeepingNewest(localEntries)
        let cloudByDay = Dictionary(
            cloudEntries.map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        let pending = localNewestByDay.filter { local in
            guard let cloud = cloudByDay[dayKey(local.date)] else { return true }
            if local.isRealTrackedDay && cloud.isTipOnlyPlaceholder {
                return true
            }
            if local.updatedAt > cloud.updatedAt {
                return true
            }
            if local.updatedAt == cloud.updatedAt && !isEquivalentEntry(local, cloud) {
                return true
            }
            return false
        }
        guard !pending.isEmpty else { return false }

        var syncedAny = false
        for entry in pending {
            do {
                try await cloudKitService.saveDayEntry(entry)
                syncedAny = true
            } catch {
                #if DEBUG
                print("Pending local entry sync failed for \(entry.date): \(error)")
                #endif
            }
        }
        return syncedAny
    }

    private func syncPendingLocalDeletionsToCloud(
        cloudEntries: [DayEntry],
        interval: DateInterval
    ) async -> Bool {
        let cloudByDay = Dictionary(
            cloudEntries.map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        let tombstones = localStore.loadDeletionTombstones()
            .filter { interval.contains($0.date) }
        guard !tombstones.isEmpty else { return false }

        var changedAny = false
        for tombstone in tombstones {
            let key = dayKey(tombstone.date)
            guard let cloud = cloudByDay[key] else {
                continue
            }

            if tombstone.lastModified >= cloud.updatedAt {
                do {
                    try await cloudKitService.deleteDayEntry(on: tombstone.date)
                    changedAny = true
                } catch {
                    #if DEBUG
                    print("Pending tombstone sync failed for \(tombstone.date): \(error)")
                    #endif
                }
            } else {
                // Cloud entry is newer than local deletion.
                localStore.clearDeletionTombstone(on: tombstone.date)
                changedAny = true
            }
        }
        return changedAny
    }

    private func isEquivalentEntry(_ lhs: DayEntry, _ rhs: DayEntry) -> Bool {
        lhs.type == rhs.type &&
        lhs.breakSeconds == rhs.breakSeconds &&
        lhs.manualWorkedSeconds == rhs.manualWorkedSeconds &&
        lhs.creditedOverrideSeconds == rhs.creditedOverrideSeconds &&
        lhs.shiftStart == rhs.shiftStart &&
        lhs.shiftEnd == rhs.shiftEnd &&
        lhs.tipAmountCents == rhs.tipAmountCents
    }

    private func dayKey(_ date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    private func deduplicateEntriesByLocalDayKeepingNewest(_ source: [DayEntry]) -> [DayEntry] {
        let byDay = Dictionary(
            source.map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                preferredEntryForSameDay(existing: existing, candidate: candidate)
            }
        )

        return byDay.values.sorted { $0.date > $1.date }
    }

    private func mergeEntriesByLocalDayKeepingNewest(local: [DayEntry], remote: [DayEntry]) -> [DayEntry] {
        let byDay = Dictionary(
            (local + remote).map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                preferredEntryForSameDay(existing: existing, candidate: candidate)
            }
        )
        return byDay.values.sorted { $0.date > $1.date }
    }

    private func preferredEntryForSameDay(existing: DayEntry, candidate: DayEntry) -> DayEntry {
        if existing.isRealTrackedDay != candidate.isRealTrackedDay {
            return candidate.isRealTrackedDay ? candidate : existing
        }
        return candidate.updatedAt > existing.updatedAt ? candidate : existing
    }

    @MainActor
    private func importHolidaysIfNeededForDisplayedMonth() async {
        let year = Calendar.current.component(.year, from: displayedMonth)
        guard let countryCode = normalizedHolidayCountryCode else { return }
        let subdivisionCode = normalizedHolidaySubdivisionCode

        let importKey = holidayImportTaskKey
        if holidayImportKeys.contains(importKey) {
            return
        }
        let hasHolidaysForYear = importedHolidays.contains {
            $0.sourceYear == year &&
            normalizeCode($0.countryCode) == countryCode &&
            normalizeCode($0.subdivisionCode) == subdivisionCode
        }
        if hasHolidaysForYear {
            holidayImportKeys.insert(importKey)
            return
        }

        do {
            let cloudHolidays = try await cloudKitService.fetchHolidayDays(
                countryCode: countryCode,
                subdivisionCode: subdivisionCode,
                year: year
            )
            if !cloudHolidays.isEmpty {
                applyImportedHolidaysIfChanged(cloudHolidays)
                holidayImportKeys.insert(importKey)
                return
            }

            let days = try await holidayImporter.fetchHolidayCalendarDays(
                year: year,
                countryCode: countryCode,
                subdivisionCode: subdivisionCode
            )
            try await cloudKitService.replaceHolidayDays(
                days,
                countryCode: countryCode,
                subdivisionCode: subdivisionCode,
                year: year
            )
            let validHolidayDates = Set(days.map { $0.date.startOfDayLocal() })
            let cleanedMarkers = try await cloudKitService.clearStaleHolidayMarkers(
                validHolidayDates: validHolidayDates,
                year: year
            )
            holidayImportKeys.insert(importKey)
            // refresh local state
            importedHolidays = try await cloudKitService.fetchHolidayDays(countryCode: countryCode, subdivisionCode: subdivisionCode, year: year)
            if cleanedMarkers > 0 {
                await loadData()
            }
        } catch {
            // Non-blocking: calendar still works without imported holidays.
        }
    }

    private func normalizeCode(_ value: String?) -> String? {
        Self.normalizedCode(value)
    }

    nonisolated private static func normalizedCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private var todayBottomBarWidth: CGFloat {
        let baseWidth = toolbarContainerWidth > 0 ? toolbarContainerWidth : 390
        let proposedWidth = baseWidth * 0.9
        return min(max(proposedWidth, 276), 388)
    }

    private var todayBottomBarHeight: CGFloat {
        let scaledHeight = todayBottomBarWidth * 0.17
        return min(max(scaledHeight, 54), 68)
    }

    private var todayBottomBarPill: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {

                Text(todayWorkedDisplay)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .payScopeNumericTransition(value: todayWorkedDisplay)

                Text("Heute • \(PayScopeFormatters.day.string(from: todayStart))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(width: todayBottomBarWidth, height: todayBottomBarHeight, alignment: .leading)
        .payScopePureGlassSurface(
            accent: todayEntry.map { settings.categoryColor(for: $0.type) } ?? settings.themeAccent.color,
            in: Capsule(style: .continuous),
            tintOpacity: 0.105,
            shadowOpacity: 0.07,
            isInteractive: true
        )
        //.shadow(color: .black.opacity(0.28), radius: 9, x: 0, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heute Vorschau")
        .accessibilityValue(todayWorkedDisplay)
    }

    private var todayStart: Date {
        now.startOfDayLocal()
    }

    private var todayEntry: DayEntry? {
        entries.first(where: { $0.date.isSameLocalDay(as: todayStart) })
    }

    private func entry(for date: Date) -> DayEntry? {
        entries.first { $0.date.isSameLocalDay(as: date) }
    }

    private var todayWorkedDisplay: String {
        "\(PayScopeFormatters.hhmmString(seconds: todayWorkedSeconds)) h"
    }

    private var todayWorkedSeconds: Int {
        workedSeconds(until: now, for: todayEntry)
    }

    private func workedSeconds(until now: Date, for day: DayEntry?) -> Int {
        guard let day else { return 0 }
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }

        if let start = day.shiftStart, let end = day.shiftEnd, end > start {
            guard now > start else { return 0 }
            let effectiveEnd = min(now, end)
            let elapsedSeconds = max(0, Int(effectiveEnd.timeIntervalSince(start)))
            guard settings.effectiveCalculateBreaks else { return elapsedSeconds }
            let totalShiftSeconds = max(1, Int(end.timeIntervalSince(start)))
            let breakSeconds = max(0, day.breakSeconds ?? 0)
            let elapsedBreak = Int((Double(breakSeconds) * Double(elapsedSeconds) / Double(totalShiftSeconds)).rounded())
            return max(0, elapsedSeconds - elapsedBreak)
        }

        return 0
    }

    private var splashView: some View {
        ZStack {
            Color.clear
                .payScopeBackground(accent: settings.themeAccent.color, intensity: 1.08)

            VStack(spacing: 16) {
                // Replace with your app icon asset name if available
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)

                Text("PayScope wird vorbereitet…")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PayScope wird vorbereitet")
    }
}

private struct WeekBadgeData: Sendable {
    let weekNumber: Int?
    let detailText: String?
}

private struct CalendarCellTimeRow: Identifiable {
    let text: String

    var id: String {
        "-\(text)"
    }
}

private struct CalendarCellMetricModel {
    let primarySymbol: String?
    let primaryTint: Color
    let primaryIconSize: CGFloat
    let primaryIconWeight: Font.Weight
    let secondaryIconSize: CGFloat
    let secondaryIconWeight: Font.Weight
    let usesHierarchicalSymbol: Bool
    let showsTips: Bool
    let tipTint: Color
    let showsDeviation: Bool
    let text: String?
    let textTint: Color
    let textFontSize: CGFloat
    let textWeight: Font.Weight
    let iconSpacing: CGFloat
    let iconRowHeight: CGFloat
    let textHeight: CGFloat
    let rowSpacing: CGFloat
    let animationKey: String

    var hasPrimarySymbol: Bool {
        primarySymbol != nil
    }

    var hasText: Bool {
        text?.isEmpty == false
    }

    var hasAnyIcon: Bool {
        hasPrimarySymbol || showsTips || showsDeviation
    }

    var hasAnyContent: Bool {
        hasAnyIcon || hasText
    }

    var totalHeight: CGFloat {
        guard hasAnyContent else { return 0 }
        return iconRowHeight + (hasText ? rowSpacing + textHeight : 0)
    }

    static func empty(animationKey: String) -> CalendarCellMetricModel {
        CalendarCellMetricModel(
            primarySymbol: nil,
            primaryTint: .clear,
            primaryIconSize: 0,
            primaryIconWeight: .regular,
            secondaryIconSize: 0,
            secondaryIconWeight: .regular,
            usesHierarchicalSymbol: false,
            showsTips: false,
            tipTint: .secondary,
            showsDeviation: false,
            text: nil,
            textTint: .primary,
            textFontSize: 11,
            textWeight: .bold,
            iconSpacing: 0,
            iconRowHeight: 0,
            textHeight: 0,
            rowSpacing: 0,
            animationKey: animationKey
        )
    }

    static func tipsOnly(tint: Color, text: String?, animationKey: String) -> CalendarCellMetricModel {
        CalendarCellMetricModel(
            primarySymbol: "eurosign.circle.fill",
            primaryTint: tint,
            primaryIconSize: 13,
            primaryIconWeight: .bold,
            secondaryIconSize: 0,
            secondaryIconWeight: .bold,
            usesHierarchicalSymbol: false,
            showsTips: false,
            tipTint: tint,
            showsDeviation: false,
            text: text,
            textTint: tint,
            textFontSize: 11,
            textWeight: .bold,
            iconSpacing: 0,
            iconRowHeight: 16,
            textHeight: text == nil ? 0 : 12,
            rowSpacing: text == nil ? 0 : 2,
            animationKey: animationKey
        )
    }

    static func iconOnly(
        symbol: String,
        tint: Color,
        showsTips: Bool,
        tipTint: Color,
        showsDeviation: Bool,
        animationKey: String
    ) -> CalendarCellMetricModel {
        CalendarCellMetricModel(
            primarySymbol: symbol,
            primaryTint: tint,
            primaryIconSize: 19,
            primaryIconWeight: .semibold,
            secondaryIconSize: 13,
            secondaryIconWeight: .bold,
            usesHierarchicalSymbol: true,
            showsTips: showsTips,
            tipTint: tipTint,
            showsDeviation: showsDeviation,
            text: nil,
            textTint: .primary,
            textFontSize: 11,
            textWeight: .bold,
            iconSpacing: 5,
            iconRowHeight: 22,
            textHeight: 0,
            rowSpacing: 0,
            animationKey: animationKey
        )
    }

    static func textMetric(
        symbol: String,
        tint: Color,
        text: String,
        textFontSize: CGFloat = 11,
        textTint: Color = .primary,
        showsTips: Bool,
        tipTint: Color,
        showsDeviation: Bool,
        animationKey: String
    ) -> CalendarCellMetricModel {
        CalendarCellMetricModel(
            primarySymbol: symbol,
            primaryTint: tint,
            primaryIconSize: 11,
            primaryIconWeight: .regular,
            secondaryIconSize: 11,
            secondaryIconWeight: .bold,
            usesHierarchicalSymbol: false,
            showsTips: showsTips,
            tipTint: tipTint,
            showsDeviation: showsDeviation,
            text: text,
            textTint: textTint,
            textFontSize: textFontSize,
            textWeight: .bold,
            iconSpacing: 4,
            iconRowHeight: 13,
            textHeight: 12,
            rowSpacing: textFontSize < 11 ? 1 : 2,
            animationKey: animationKey
        )
    }
}

private struct CalendarCellMorphMetricView: View {
    let model: CalendarCellMetricModel

    var body: some View {
        VStack(spacing: model.hasText ? model.rowSpacing : 0) {
            iconRow
            .frame(height: model.hasAnyIcon ? model.iconRowHeight : 0)
            .frame(maxWidth: .infinity, alignment: .center)
            .scaleEffect(model.hasAnyIcon ? 1 : 0.72)
            .clipped()

            Text(model.text ?? "")
                .font(.system(size: model.textFontSize, weight: model.textWeight, design: .rounded))
                .foregroundStyle(model.textTint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .frame(height: model.hasText ? model.textHeight : 0)
                .scaleEffect(model.hasText ? 1 : 0.78, anchor: .top)
                .clipped()
        }
        .frame(height: model.totalHeight)
        .scaleEffect(model.hasAnyContent ? 1 : 0.84)
        .clipped()
        .accessibilityHidden(!model.hasAnyContent)
    }

    @ViewBuilder
    private var iconRow: some View {
        HStack(spacing: model.iconSpacing) {
            if let primarySymbol = model.primarySymbol {
                metricSymbol(
                    systemName: primarySymbol,
                    tint: model.primaryTint,
                    size: model.primaryIconSize,
                    weight: model.primaryIconWeight,
                    usesHierarchicalSymbol: model.usesHierarchicalSymbol
                )
            }

            if model.showsTips {
                metricSymbol(
                    systemName: "eurosign.circle.fill",
                    tint: model.tipTint,
                    size: model.secondaryIconSize,
                    weight: .bold,
                    usesHierarchicalSymbol: false
                )
            }

            if model.showsDeviation {
                metricSymbol(
                    systemName: "pencil",
                    tint: .secondary,
                    size: model.secondaryIconSize,
                    weight: model.secondaryIconWeight,
                    usesHierarchicalSymbol: false
                )
            }
        }
    }

    private func metricSymbol(
        systemName: String,
        tint: Color,
        size: CGFloat,
        weight: Font.Weight,
        usesHierarchicalSymbol: Bool
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: max(size, 1), weight: weight))
            .symbolRenderingMode(usesHierarchicalSymbol ? .hierarchical : .monochrome)
            .foregroundStyle(tint)
            .contentTransition(.opacity)
            .frame(width: size + 4, height: size + 4, alignment: .center)
    }
}

private struct CalendarDaySelection: Identifiable {
    let date: Date

    var id: String {
        "day-editor-\(date.startOfDayLocal().timeIntervalSinceReferenceDate)"
    }
}

private struct CalendarShiftShortcutBoundsPayload: Codable {
    let startMinute: Int
    let endMinute: Int
}

private enum CalendarSheet: Identifiable {
    case today
    case tips(Date)

    var id: String {
        switch self {
        case .today:
            return "today"
        case let .tips(month):
            return "tips-\(month.timeIntervalSinceReferenceDate)"
        }
    }
}

private struct MonthYearToolbarButton: View {
    let month: String
    let year: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(month)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(year)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(accent.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarDisplayModeMenu: View {
    let currentMode: CalendarCellDisplayMode
    let currentBreakMode: CalendarHoursBreakMode
    let selectDisplayMode: (CalendarCellDisplayMode) -> Void
    let selectHoursBreakMode: (CalendarHoursBreakMode) -> Void

    @State private var selectedMode: CalendarCellDisplayMode
    @State private var selectedBreakMode: CalendarHoursBreakMode

    init(
        currentMode: CalendarCellDisplayMode,
        currentBreakMode: CalendarHoursBreakMode,
        selectDisplayMode: @escaping (CalendarCellDisplayMode) -> Void,
        selectHoursBreakMode: @escaping (CalendarHoursBreakMode) -> Void
    ) {
        self.currentMode = currentMode
        self.currentBreakMode = currentBreakMode
        self.selectDisplayMode = selectDisplayMode
        self.selectHoursBreakMode = selectHoursBreakMode
        _selectedMode = State(initialValue: currentMode)
        _selectedBreakMode = State(initialValue: currentBreakMode)
    }

    var body: some View {
        Menu {
            ForEach(CalendarCellDisplayMode.allCases.filter { $0 != .pay }) { mode in
                if mode == .hours {
                    Menu {
                        ForEach(CalendarHoursBreakMode.allCases) { breakMode in
                            Button {
                                selectedMode = .hours
                                selectedBreakMode = breakMode
                                selectHoursBreakMode(breakMode)
                            } label: {
                                CalendarMenuItemLabel(
                                    title: breakMode.label,
                                    systemImage: Self.hoursBreakModeSystemImage(for: breakMode),
                                    isSelected: selectedMode == .hours && selectedBreakMode == breakMode
                                )
                            }
                        }
                    } label: {
                        CalendarMenuItemLabel(
                            title: mode.label,
                            systemImage: Self.displayModeSystemImage(for: mode),
                            isSelected: selectedMode == .hours
                        )
                    }
                } else {
                    Button {
                        selectedMode = mode
                        selectDisplayMode(mode)
                    } label: {
                        CalendarMenuItemLabel(
                            title: mode.label,
                            systemImage: Self.displayModeSystemImage(for: mode),
                            isSelected: selectedMode == mode
                        )
                    }
                }
            }
        } label: {
            Image(systemName: Self.displayModeSystemImage(for: toolbarDisplayMode))
                .font(.headline.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .id("calendar-display-mode-menu")
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityLabel("Kalenderansicht")
        .accessibilityValue(accessibilityValue)
        .onChange(of: currentMode) { _, newValue in
            selectedMode = newValue
        }
        .onChange(of: currentBreakMode) { _, newValue in
            selectedBreakMode = newValue
        }
    }

    private var accessibilityValue: String {
        guard selectedMode != .pay else { return "Lohnansicht aktiv" }
        guard selectedMode == .hours else { return selectedMode.label }
        return "\(selectedMode.label), \(selectedBreakMode.label)"
    }

    private var toolbarDisplayMode: CalendarCellDisplayMode {
        selectedMode == .pay ? .dot : selectedMode
    }

    private static func displayModeSystemImage(for mode: CalendarCellDisplayMode) -> String {
        switch mode {
        case .dot:
            return "circle.grid.2x2.fill"
        case .hours:
            return "clock.fill"
        case .pay:
            return "eurosign.circle.fill"
        case .startTime:
            return "play.circle.fill"
        case .endTime:
            return "stop.circle.fill"
        case .startAndEndTime:
            return "arrow.up.arrow.down.circle.fill"
        }
    }

    private static func hoursBreakModeSystemImage(for mode: CalendarHoursBreakMode) -> String {
        switch mode {
        case .withoutBreak:
            return "minus.circle"
        case .withBreak:
            return "plus.circle"
        }
    }
}

private struct CalendarMenuItemLabel: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Label(title, systemImage: isSelected ? "checkmark" : systemImage)
    }
}

struct MonthYearPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialMonth: Date
    let yearRange: ClosedRange<Int>
    let accent: Color
    let onSelect: (Date) -> Void

    @State private var selectedMonth: Int
    @State private var selectedYear: Int

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    init(
        initialMonth: Date,
        yearRange: ClosedRange<Int>,
        accent: Color,
        onSelect: @escaping (Date) -> Void
    ) {
        let normalizedMonth = initialMonth.startOfMonthLocal()
        let components = Calendar.current.dateComponents([.month, .year], from: normalizedMonth)
        self.initialMonth = normalizedMonth
        self.yearRange = yearRange
        self.accent = accent
        self.onSelect = onSelect
        _selectedMonth = State(initialValue: components.month ?? 1)
        _selectedYear = State(initialValue: components.year ?? Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(spacing: 0) {
                    Picker("Monat", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Self.monthName(for: month))
                                .tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Jahr", selection: $selectedYear) {
                        ForEach(yearRange, id: \.self) { year in
                            Text(String(year))
                                .monospacedDigit()
                                .tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: 216)

                Button {
                    selectCurrentMonth()
                } label: {
                    Label("Aktueller Monat", systemImage: "calendar.badge.clock")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(accent)
                        .payScopeGlassControl(accent: accent, cornerRadius: 15, tintOpacity: 0.115)
                        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .navigationTitle("Monat wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Schließen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        commitSelection()
                    } label:{
                        Image(systemName: "checkmark")
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .tint(accent)
    }

    private var selectedDate: Date {
        DateComponents(calendar: Calendar.current, year: selectedYear, month: selectedMonth, day: 1)
            .date?
            .startOfMonthLocal() ?? initialMonth
    }

    private func commitSelection() {
        onSelect(selectedDate)
        dismiss()
    }

    private func selectCurrentMonth() {
        let current = Date().startOfMonthLocal()
        selectedMonth = Calendar.current.component(.month, from: current)
        selectedYear = Calendar.current.component(.year, from: current)
    }

    private static func monthName(for month: Int) -> String {
        let date = DateComponents(calendar: Calendar.current, year: 2024, month: month, day: 1).date ?? Date()
        return monthFormatter.string(from: date)
    }
}

private struct CalendarTabToolbarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ShiftSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ShiftViewPopover: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private enum PopoverColumnAlignment {
        case leading
        case center
        case trailing

        var horizontal: HorizontalAlignment {
            switch self {
            case .leading:
                return .leading
            case .center:
                return .center
            case .trailing:
                return .trailing
            }
        }

        var frame: Alignment {
            switch self {
            case .leading:
                return .leading
            case .center:
                return .center
            case .trailing:
                return .trailing
            }
        }
    }

    let date: Date
    let entry: DayEntry?
    let entries: [DayEntry]
    let tipCents: Int
    @Bindable var settings: Settings
    let onEditTip: (Date) -> Void
    let onDeleteTip: (Date) -> Void
    let onEdit: (Date) -> Void
    let onDelete: (Date) -> Void

    @State private var showDeleteConfirm = false
    @State private var showDeleteTipConfirm = false
    @State private var sharePayload: ShiftSharePayload?

    private let service = CalculationService()
    private let popoverWidth: CGFloat = 320
    private var popoverContentWidth: CGFloat {
        popoverWidth - (PayScopeModalGeometry.popover.edgePadding * 2)
    }

    private var dayStart: Date {
        date.startOfDayLocal()
    }

    private var accent: Color {
        entry.map { settings.categoryColor(for: $0.type) } ?? settings.themeAccent.color
    }

    private var computation: ComputationResult? {
        guard let entry else { return nil }
        return service.dayComputation(for: entry, allEntries: entries, settings: settings)
    }

    private var workedSeconds: Int {
        computation?.valueSecondsOrZero ?? 0
    }

    private var payCents: Int {
        computation?.valueCentsOrZero ?? 0
    }

    private var hasTip: Bool {
        tipCents > 0
    }

    private var bodyTitle: String {
        entry?.type.label ?? "Keine Schicht"
    }

    private var bodyIcon: String {
        entry?.type.icon ?? "square"
    }

    private var dateText: String {
        PayScopeFormatters.day.string(from: dayStart)
    }

    private var contentMaxHeight: CGFloat {
        280
    }

    var body: some View {
        popoverShell(includeActions: true, limitContentHeight: true)
            .alert("Tag löschen?", isPresented: $showDeleteConfirm) {
                Button("Löschen", role: .destructive) {
                    onDelete(dayStart)
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Dieser Tageseintrag wird gelöscht.")
            }
            .alert("Trinkgeld löschen?", isPresented: $showDeleteTipConfirm) {
                Button("Löschen", role: .destructive) {
                    onDeleteTip(dayStart)
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Das Trinkgeld für diesen Tag wird gelöscht.")
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
                    .presentationBackground(Color.clear)
            }
    }

    private func popoverShell(includeActions: Bool, limitContentHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(includeActions: includeActions)

            if entry != nil || hasTip {
                Group {
                    content
                        .padding(.vertical, 0)
                }
                .if(limitContentHeight) { view in
                    HStack {
                        view
                    }
                    .frame(maxHeight: contentMaxHeight)
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(width: popoverContentWidth)
    }

    private func header(includeActions: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: bodyIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(colorScheme == .light ? 0.2 : 0.16))
                )
                .glassEffect(
                    .regular
                        .tint(accent.opacity(colorScheme == .light ? 0.16 : 0.12))
                        .interactive(false),
                    in: .rect(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.65)
                        .blendMode(.softLight)
                        .allowsHitTesting(false)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(bodyTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(dateText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(entry == nil ? Color.secondary : accent)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if includeActions, entry != nil {
                headerActionGroup {
                    headerIconButton(
                        systemImage: "trash",
                        tint: .red
                    ) {
                        showDeleteConfirm = true
                    }
                    .accessibilityLabel("Tag löschen")

                    shareMenu

                    headerIconButton(
                        systemImage: "pencil",
                        tint: accent
                    ) {
                        onEdit(dayStart)
                    }
                    .accessibilityLabel("Bearbeiten")
                }
            } else if includeActions {
                headerActionGroup {
                    if !hasTip, settings.effectiveShowTipsButton {
                        headerIconButton(
                            systemImage: "eurosign.circle",
                            tint: accent
                        ) {
                            onEditTip(dayStart)
                        }
                        .accessibilityLabel("Trinkgeld hinzufügen")
                    }

                    headerIconButton(
                        systemImage: "plus",
                        tint: accent
                    ) {
                        onEdit(dayStart)
                    }
                    .accessibilityLabel("Schicht hinzufügen")
                }
            }
        }
        .padding(.horizontal, 15)
        .frame(width: popoverContentWidth, height: 58)
        .overlay(alignment: .bottom) {
            if entry != nil || hasTip {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 0.5)
            }
        }
    }

    private func headerActionGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) {
            content()
        }
    }

    private var shareMenu: some View {
        let buttonShape = RoundedRectangle(cornerRadius: 13, style: .continuous)

        return Menu {
            Button {
                shareInlineText()
            } label: {
                Label("Als Inline-Text", systemImage: "text.alignleft")
            }

            Button {
                sharePopoverImage()
            } label: {
                Label("Als Bild", systemImage: "photo")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white.opacity(0.34)).interactive(), in: .rect(cornerRadius: 13))
                .overlay(
                    buttonShape
                        .stroke(.white.opacity(0.18), lineWidth: 0.65)
                        .blendMode(.softLight)
                        .allowsHitTesting(false)
                )
                .contentShape(buttonShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Teilen")
    }

    private func headerIconButton(
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white.opacity(0.34)).interactive(), in: .rect(cornerRadius: 13))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.65)
                        .blendMode(.softLight)
                        .allowsHitTesting(false)
                )
                .contentShape(shape)
        }
        .buttonStyle(
            PayScopeLiquidGlassPressButtonStyle(
                accent: tint,
                shape: shape,
                tintOpacity: 0.04,
                pressedScale: 0.94
            )
        )
    }

    private func shareInlineText() {
        sharePayload = ShiftSharePayload(items: [shareText])
    }

    @MainActor
    private func sharePopoverImage() {
        if let image = renderedShareImage() {
            sharePayload = ShiftSharePayload(items: [image])
        } else {
            sharePayload = ShiftSharePayload(items: [shareText])
        }
    }

    @MainActor
    private func renderedShareImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: shareImageView
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = displayScale
        renderer.proposedSize = ProposedViewSize(width: popoverWidth, height: nil)
        return renderer.uiImage
    }

    private var shareImageView: some View {
        popoverShell(includeActions: false, limitContentHeight: false)
            .payScopePureGlassSurface(
                accent: accent,
                cornerRadius: PayScopeModalGeometry.popover.innerCornerRadius,
                tintOpacity: 0.045,
                shadowOpacity: 0.06,
                isInteractive: false
            )
    }

    private var shareText: String {
        guard let entry else {
            var lines = [bodyTitle, dateText]
            if hasTip {
                lines.append("Trinkgeld: \(PayScopeFormatters.currencyString(cents: tipCents))")
            }
            return lines.joined(separator: "\n")
        }

        var lines = [
            "\(entry.type.label) - \(dateText)",
            "Start: \(startTimeText(for: entry))",
            "Ende: \(endTimeTextForSharing(for: entry))",
            "Dauer: \(durationValueText(for: entry)) h",
            "Pause: \(breakValueText(for: entry)) h",
            "Lohn: \(PayScopeFormatters.currencyString(cents: payCents))"
        ]

        if hasTip {
            lines.append("Trinkgeld: \(PayScopeFormatters.currencyString(cents: tipCents))")
        }

        if let statusMessage {
            lines.append("\(statusMessage.title): \(statusMessage.text)")
        }

        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var content: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 10) {
                shiftSummaryCard(for: entry)

                if let status = statusMessage {
                    infoPanel(systemImage: status.icon, title: status.title, text: status.text, tint: status.tint)
                        .padding(.horizontal, 15)
                }

            }
            .padding(.bottom, statusMessage == nil ? 0 : 13)
        } else if hasTip {
            tipOnlySummaryCard
        }
    }

    private func shiftSummaryCard(for entry: DayEntry) -> some View {
        let endText = endTimeText(for: entry)
        let durationText = durationValueText(for: entry)

        return VStack(alignment: .leading, spacing: 12) {

            timeRangeRow(
                start: startTimeText(for: entry),
                end: endText.time,
                endSuffix: endText.suffix,
                duration: durationText
            )

            LazyVGrid(columns: metricColumns, spacing: 7) {

                compactMetric(
                    label: "Pause",
                    value: breakValueText(for: entry),
                    suffix: "h",
                    systemImage: "pause.fill",
                    columnAlignment: .leading
                )

                if hasTip {
                    compactTipEditButton(columnAlignment: .center)
                } else if settings.effectiveShowTipsButton {
                    compactTipAddButton()
                }

                compactMetric(
                    label: "Lohn",
                    value: payValueText(),
                    systemImage: "eurosign",
                    valueTint: payCents > 0 ? accent : .secondary,
                    isTinted: payCents > 0,
                    columnAlignment: .trailing
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    private var tipOnlySummaryCard: some View {
        let actionHeight: CGFloat = 52

        return HStack(spacing: 8) {
            compactTipMetricTile(columnAlignment: .leading, isGlassInteractive: false)
                .frame(maxWidth: .infinity)
                .frame(height: actionHeight)

            tipOnlyActionButton(
                systemImage: "pencil",
                tint: accent,
                accessibilityLabel: "Trinkgeld bearbeiten"
            ) {
                onEditTip(dayStart)
            }
            .frame(height: actionHeight)

            tipOnlyActionButton(
                systemImage: "trash",
                tint: .red,
                accessibilityLabel: "Trinkgeld löschen"
            ) {
                showDeleteTipConfirm = true
            }
            .frame(height: actionHeight)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: hasTip || settings.effectiveShowTipsButton ? 3 : 2)
    }

    private func timeRangeRow(start: String, end: String, endSuffix: String?, duration: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            timeEndpoint(label: "Start", value: start, systemImage: "play.fill", columnAlignment: .leading)

            durationBridge(value: duration)

            timeEndpoint(label: "Ende", value: end, suffix: endSuffix, systemImage: "stop.fill", columnAlignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .shiftViewPanel(accent: accent)
    }

    private func durationBridge(value: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(value == "-" ? .secondary : accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .payScopeNumericTransition(value: value)

                if value != "-" {
                    Text("h")
                        .font(.system(size: 7, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(accent)
                .frame(height: 14)
        }
        .frame(width: 64)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func timeEndpoint(
        label: String,
        value: String,
        suffix: String? = nil,
        systemImage: String,
        columnAlignment: PopoverColumnAlignment
    ) -> some View {
        VStack(alignment: columnAlignment.horizontal, spacing: 3) {

            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: columnAlignment.frame)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .payScopeNumericTransition(value: value)

                if let suffix {
                    Text(suffix)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: columnAlignment.frame)
        }
        .frame(maxWidth: .infinity, alignment: columnAlignment.frame)
    }

    private func compactTipAddButton() -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return Button {
            onEditTip(dayStart)
        } label: {
            VStack(alignment: .center, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "eurosign.circle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Trinkgeld")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Hinzufügen")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .payScopeContentSurface(
                accent: accent,
                in: shape,
                emphasis: 0.18,
                shadowOpacity: 0.015
            )
            .contentShape(shape)
        }
        .buttonStyle(
            PayScopeLiquidGlassPressButtonStyle(
                accent: accent,
                shape: shape,
                tintOpacity: 0.052,
                pressedScale: 0.99
            )
        )
        .accessibilityLabel("Trinkgeld hinzufügen")
    }

    private func compactTipEditButton(columnAlignment: PopoverColumnAlignment) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return Button {
            onEditTip(dayStart)
        } label: {
            compactTipMetricTile(
                columnAlignment: columnAlignment,
                systemImage: "pencil",
                isGlassInteractive: true
            )
            .contentShape(shape)
        }
        .buttonStyle(
            PayScopeLiquidGlassPressButtonStyle(
                accent: accent,
                shape: shape,
                tintOpacity: 0.052,
                pressedScale: 0.99
            )
        )
        .accessibilityLabel("Trinkgeld bearbeiten")
        .accessibilityValue(PayScopeFormatters.currencyString(cents: tipCents))
    }

    private func compactTipMetricTile(
        columnAlignment: PopoverColumnAlignment,
        systemImage: String = "eurosign.circle.fill",
        isGlassInteractive: Bool = true
    ) -> some View {
        compactMetric(
            label: "Trinkgeld",
            value: moneyTileValueText(cents: tipCents),
            systemImage: systemImage,
            valueTint: .orange,
            isTinted: true,
            isGlassInteractive: isGlassInteractive,
            columnAlignment: columnAlignment
        )
    }

    private func tipOnlyActionButton(
        systemImage: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 42)
                .frame(maxHeight: .infinity)
                .payScopeContentSurface(
                    accent: tint,
                    in: shape,
                    emphasis: 0.18,
                    shadowOpacity: 0.015
                )
                .glassEffect(
                    .regular
                        .tint(tint.opacity(colorScheme == .light ? 0.18 : 0.13))
                        .interactive(),
                    in: .rect(cornerRadius: 10)
                )
                .overlay(
                    shape
                        .stroke(.white.opacity(0.18), lineWidth: 0.65)
                        .blendMode(.softLight)
                        .allowsHitTesting(false)
                )
                .contentShape(shape)
        }
        .buttonStyle(
            PayScopeLiquidGlassPressButtonStyle(
                accent: tint,
                shape: shape,
                tintOpacity: 0.06,
                pressedScale: 0.98
            )
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private func compactMetric(
        label: String,
        value: String,
        suffix: String? = nil,
        systemImage: String,
        valueTint: Color = .primary,
        isTinted: Bool = false,
        isGlassInteractive: Bool = false,
        columnAlignment: PopoverColumnAlignment
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return VStack(alignment: columnAlignment.horizontal, spacing: 4) {

            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: columnAlignment.frame)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(valueTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                    .payScopeNumericTransition(value: value)

                if let suffix {
                    Text(suffix)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: columnAlignment.frame)
        }
        .frame(maxWidth: .infinity, alignment: columnAlignment.frame)
        .padding(8)
        .payScopeContentSurface(
            accent: accent,
            in: shape,
            emphasis: isTinted ? 0.24 : 0.16,
            shadowOpacity: 0.015
        )
    }

    private func infoPanel(systemImage: String, title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .shiftViewPanel(accent: accent)
    }

    private var statusMessage: (icon: String, title: String, text: String, tint: Color)? {
        guard let computation else { return nil }
        switch computation {
        case .ok:
            return nil
        case let .warning(_, _, message):
            return ("exclamationmark.triangle.fill", "Hinweis", localizedComputationMessage(message), .orange)
        case let .error(message, missingDates):
            let details = missingDates.isEmpty
                ? localizedComputationMessage(message)
                : "\(localizedComputationMessage(message)) \(missingDatesText(missingDates))"
            return ("xmark.octagon.fill", "Fehlt", details, .red)
        }
    }

    private func startTimeText(for entry: DayEntry) -> String {
        guard let start = entry.shiftStart else { return "-" }
        return PayScopeFormatters.time.string(from: start)
    }

    private func endTimeText(for entry: DayEntry) -> (time: String, suffix: String?) {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
            return ("-", nil)
        }

        let suffix = Calendar.current.isDate(start, inSameDayAs: end) ? nil : "+1"
        return (PayScopeFormatters.time.string(from: end), suffix)
    }

    private func endTimeTextForSharing(for entry: DayEntry) -> String {
        let endText = endTimeText(for: entry)
        guard let suffix = endText.suffix else { return endText.time }
        return "\(endText.time) \(suffix)"
    }

    private func durationValueText(for entry: DayEntry) -> String {
        let seconds = totalDurationSeconds(for: entry)
        if seconds > 0 || entry.manualWorkedSeconds != nil || entry.type != .work {
            return PayScopeFormatters.hhmmString(seconds: seconds)
        }
        return "-"
    }

    private func totalDurationSeconds(for entry: DayEntry) -> Int {
        if let start = entry.shiftStart, let end = entry.shiftEnd, end > start {
            return max(0, Int(end.timeIntervalSince(start)))
        }

        if !entry.segments.isEmpty {
            return entry.segments.reduce(0) { total, segment in
                total + max(0, Int(segment.end.timeIntervalSince(segment.start)))
            }
        }

        if let manual = entry.manualWorkedSeconds {
            return max(0, manual)
        }

        return max(0, workedSeconds)
    }

    private func breakValueText(for entry: DayEntry) -> String {
        PayScopeFormatters.hhmmString(seconds: max(0, entry.breakSeconds ?? 0))
    }

    private func payValueText() -> String {
        payCents > 0 ? moneyTileValueText(cents: payCents) : "-"
    }

    private func moneyTileValueText(cents: Int) -> String {
        let amount = Decimal(max(0, cents)) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "-"
    }

    private func missingDatesText(_ dates: [Date]) -> String {
        let formatted = dates
            .prefix(3)
            .map { PayScopeFormatters.day.string(from: $0) }
            .joined(separator: ", ")
        if dates.count > 3 {
            return "Referenzen: \(formatted) +\(dates.count - 3)."
        }
        return "Referenzen: \(formatted)."
    }

    private func localizedComputationMessage(_ message: String) -> String {
        if message.contains("Not enough history") {
            return "Nicht genug Verlauf für die Berechnung."
        }
        if message.contains("All") && message.contains("lookback values are 0") {
            return "Alle Referenzwerte sind 0."
        }
        if message.contains("Reference day has invalid data") {
            return "Ein Referenztag enthält ungültige Daten."
        }
        return message
    }
}

private struct ShiftViewPanelStyle: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        content
            .payScopeContentSurface(
                accent: accent,
                in: shape,
                emphasis: 0.2,
                shadowOpacity: 0.02
            )
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transformed: View>(
        _ condition: Bool,
        transform: (Self) -> Transformed
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func shiftViewPanel(accent: Color) -> some View {
        modifier(ShiftViewPanelStyle(accent: accent))
    }
}

private struct TipEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudKitService: CloudKitService

    let month: Date
    let settings: Settings
    let onTipsChanged: () -> Void

    @State private var tips: [TipEntry] = []
    @State private var editorState: TipEntryEditorState?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .medium
        return formatter
    }()

    init(month: Date, settings: Settings, onTipsChanged: @escaping () -> Void) {
        let normalizedMonth = month.startOfMonthLocal()
        self.month = normalizedMonth
        self.settings = settings
        self.onTipsChanged = onTipsChanged
    }

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: month)
            ?? DateInterval(start: month, duration: 24 * 60 * 60)
    }

    private var dateRange: ClosedRange<Date> {
        monthInterval.start...monthInterval.end.addingTimeInterval(-1)
    }

    private var totalCents: Int {
        tips.reduce(0) { $0 + $1.amountCents }
    }

    private var sortedTips: [TipEntry] {
        tips.sorted {
            if $0.date == $1.date {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.date > $1.date
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                totalHeader

                List {
                    if isLoading && tips.isEmpty {
                        Section {
                            ProgressView("Trinkgeld wird geladen...")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } else if sortedTips.isEmpty {
                        Section {
                            Text("Noch kein Trinkgeld in diesem Monat.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            ForEach(sortedTips) { tip in
                                tipRow(tip)
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            presentEditTip(tip)
                                        } label: {
                                            Label("Bearbeiten", systemImage: "pencil")
                                        }
                                        .tint(settings.themeAccent.color)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteTip(tip)
                                        } label: {
                                            Label("Löschen", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(.systemBackground).opacity(0.86))
                }
            }
            .navigationTitle("Trinkgeld")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Schließen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentAddTip()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Trinkgeld hinzufügen")
                    .glassEffect()
                }
            }
            .task {
                await loadTips()
            }
            .sheet(item: $editorState) { state in
                TipEntryEditorSheet(
                    title: state.title,
                    saveAccessibilityLabel: state.saveAccessibilityLabel,
                    dateRange: dateRange,
                    initialDate: state.initialDate,
                    initialAmountCents: state.initialAmountCents
                ) { date, amountCents in
                    saveTip(date: date, amountCents: amountCents, replacing: state.tip)
                    editorState = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var totalHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summe")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(PayScopeFormatters.currencyString(cents: totalCents))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 12)

                Text(Self.monthFormatter.string(from: month))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.86))
    }

    private func tipRow(_ tip: TipEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "eurosign.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dayFormatter.string(from: tip.date))
                    .font(.body.weight(.semibold))
                Text("Trinkgeld")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(PayScopeFormatters.currencyString(cents: tip.amountCents))
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .payScopeNumericTransition(value: tip.amountCents)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var defaultTipDate: Date {
        let today = Date().startOfDayLocal()
        if monthInterval.contains(today) {
            return today
        }
        return month
    }

    private func presentAddTip() {
        editorState = TipEntryEditorState(
            tip: nil,
            initialDate: defaultTipDate,
            initialAmountCents: nil
        )
    }

    private func presentEditTip(_ tip: TipEntry) {
        editorState = TipEntryEditorState(
            tip: tip,
            initialDate: tip.date,
            initialAmountCents: tip.amountCents
        )
    }

    @MainActor
    private func loadTips() async {
        isLoading = true
        errorMessage = nil

        let localTips = LocalTipEntryStore.shared.loadAll(in: monthInterval)
        let deletedTipsByID = Dictionary(
            LocalTipEntryStore.shared.loadDeletionTombstones().map { ($0.id, $0.lastModified) },
            uniquingKeysWith: max
        )

        do {
            let remoteTips = try await cloudKitService.fetchTipEntries(in: monthInterval).filter { tip in
                guard let deletedAt = deletedTipsByID[tip.id] else { return true }
                return deletedAt < tip.updatedAt
            }
            if !remoteTips.isEmpty {
                LocalTipEntryStore.shared.upsertMany(remoteTips)
            }
            tips = mergeTipEntriesKeepingNewest(local: localTips, remote: remoteTips)
            persistTipTotalsForLoadedTips()
        } catch {
            tips = localTips
            persistTipTotalsForLoadedTips()
            errorMessage = "iCloud konnte nicht geladen werden. Lokale Einträge bleiben verfügbar."
        }

        isLoading = false
        onTipsChanged()
    }

    private func saveTip(date: Date, amountCents: Int, replacing existingTip: TipEntry?) {
        guard amountCents > 0 else { return }
        let tip = TipEntry(
            id: existingTip?.id ?? UUID().uuidString,
            date: date.startOfDayLocal(),
            amountCents: amountCents,
            updatedAt: Date()
        )
        LocalTipEntryStore.shared.save(tip)

        var nextTips = tips.filter { $0.id != tip.id }
        nextTips.append(tip)
        tips = mergeTipEntriesKeepingNewest(local: nextTips, remote: [])
        persistTipTotal(for: tip.date, updatedAt: tip.updatedAt)
        if let previousDate = existingTip?.date,
           !previousDate.isSameLocalDay(as: tip.date) {
            persistTipTotal(for: previousDate, updatedAt: tip.updatedAt)
        }
        errorMessage = nil
        onTipsChanged()

        syncTipSave(
            tip,
            offlineMessage: existingTip == nil
                ? "Trinkgeld wurde lokal gespeichert und später synchronisiert."
                : "Trinkgeld wurde lokal geändert und später synchronisiert."
        )
    }

    private func syncTipSave(_ tip: TipEntry, offlineMessage: String) {
        Task {
            do {
                try await cloudKitService.saveTipEntry(tip)
                LocalTipEntryStore.shared.markSynced(tip)
            } catch {
                await MainActor.run {
                    errorMessage = offlineMessage
                }
            }
        }
    }

    private func deleteTip(_ tip: TipEntry) {
        LocalTipEntryStore.shared.delete(tip)
        tips.removeAll { $0.id == tip.id }
        persistTipTotal(for: tip.date, updatedAt: Date())
        errorMessage = nil
        Task {
            do {
                try await cloudKitService.deleteTipEntry(tip)
            } catch {
                await MainActor.run {
                    errorMessage = "Eintrag wurde lokal gelöscht und später synchronisiert."
                }
            }
        }
        onTipsChanged()
    }

    private func persistTipTotalsForLoadedTips() {
        let dates = Set(tips.map { dayKey($0.date) })
        for key in dates {
            guard let tip = tips.first(where: { dayKey($0.date) == key }) else { continue }
            let latestUpdate = tips
                .filter { dayKey($0.date) == key }
                .map(\.updatedAt)
                .max() ?? Date()
            persistTipTotal(for: tip.date, updatedAt: latestUpdate)
        }
    }

    private func persistTipTotal(for date: Date, updatedAt: Date) {
        let total = tips
            .filter { $0.date.isSameLocalDay(as: date) }
            .reduce(0) { $0 + max(0, $1.amountCents) }
        persistDayTipAmount(total, for: date, updatedAt: updatedAt)
    }

    private func persistDayTipAmount(_ amountCents: Int, for date: Date, updatedAt: Date) {
        let day = date.startOfDayLocal()
        guard let target = LocalDayEntryStore.shared.load(on: day) else { return }
        if target.isTipOnlyPlaceholder {
            LocalDayEntryStore.shared.delete(on: day)
            Task {
                do {
                    try await cloudKitService.deleteDayEntry(on: day)
                } catch {
                    #if DEBUG
                    print("CloudKit day tip cleanup failed, local tombstone kept for retry: \(error)")
                    #endif
                }
            }
            return
        }
        guard target.isRealTrackedDay else { return }

        let existingAmount = max(0, target.tipAmountCents ?? 0)
        let normalizedAmount = max(0, amountCents)

        guard normalizedAmount > 0 || existingAmount > 0 else { return }
        guard existingAmount != normalizedAmount else { return }

        target.date = Self.utcDate(forLocalDay: day)
        target.updatedAt = max(target.updatedAt, updatedAt)
        target.tipAmountCents = normalizedAmount > 0 ? normalizedAmount : nil

        LocalDayEntryStore.shared.save(target)
        Task {
            do {
                try await cloudKitService.saveDayEntry(target)
                LocalDayEntryStore.shared.save(target)
            } catch {
                #if DEBUG
                print("CloudKit day tip save failed, persisted locally as fallback: \(error)")
                #endif
            }
        }
    }

    private func dayKey(_ date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    private static func utcDate(forLocalDay date: Date) -> Date {
        let localDay = date.startOfDayLocal()
        let components = Calendar.current.dateComponents([.year, .month, .day], from: localDay)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: components) ?? localDay.startOfDayUTC()
    }

    private func mergeTipEntriesKeepingNewest(local: [TipEntry], remote: [TipEntry]) -> [TipEntry] {
        var merged: [String: TipEntry] = [:]

        for tip in local + remote {
            if let existing = merged[tip.id], existing.updatedAt >= tip.updatedAt {
                continue
            }
            merged[tip.id] = tip
        }

        return Array(merged.values)
    }
}

private struct TipEntryEditorState: Identifiable {
    let id = UUID()
    let tip: TipEntry?
    let initialDate: Date
    let initialAmountCents: Int?

    var isEditingExistingTip: Bool {
        tip != nil || max(0, initialAmountCents ?? 0) > 0
    }

    var title: String {
        isEditingExistingTip ? "Trinkgeld bearbeiten" : "Trinkgeld hinzufügen"
    }

    var saveAccessibilityLabel: String {
        isEditingExistingTip ? "Speichern" : "Hinzufügen"
    }
}

private struct TipEntryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    let title: String
    let saveAccessibilityLabel: String
    let dateRange: ClosedRange<Date>
    let onSave: (Date, Int) -> Void

    @State private var selectedDate: Date
    @State private var amountText: String
    @State private var isDatePickerExpanded = false
    private let accent = Color.green

    init(
        title: String,
        saveAccessibilityLabel: String,
        dateRange: ClosedRange<Date>,
        initialDate: Date,
        initialAmountCents: Int?,
        onSave: @escaping (Date, Int) -> Void
    ) {
        self.title = title
        self.saveAccessibilityLabel = saveAccessibilityLabel
        self.dateRange = dateRange
        self.onSave = onSave
        _selectedDate = State(initialValue: initialDate.startOfDayLocal())
        _amountText = State(initialValue: initialAmountCents.map(Self.amountText) ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    amountEditor
                    datePickerPanel
                }
                .padding(.horizontal, PayScopeModalGeometry.sheet.edgePadding)
                .padding(.top, PayScopeModalGeometry.sheet.edgePadding)
                .padding(.bottom, 24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Schließen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let amountCents = parsedAmountCents else { return }
                        onSave(selectedDate, amountCents)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(parsedAmountCents == nil)
                    .accessibilityLabel(saveAccessibilityLabel)
                }
            }
        }
        .payScopeSheetSurface(accent: accent)
        .onAppear {
            isAmountFocused = amountText.isEmpty
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var amountEditor: some View {
        VStack(spacing: 10) {
            Image(systemName: "eurosign.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .payScopeLiquidGlassIcon(accent: accent, tintOpacity: 0.14)

            Text("Trinkgeld")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0,00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($isAmountFocused)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .frame(minWidth: 120, maxWidth: 230)
                    .submitLabel(.done)

                Text("EUR")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .payScopeNumericTransition(value: amountText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .payScopeGlassSurface(accent: accent, cornerRadius: PayScopeModalGeometry.sheet.innerCornerRadius, tintOpacity: 0.055, shadowOpacity: 0.075)
        .contentShape(RoundedRectangle(cornerRadius: PayScopeModalGeometry.sheet.innerCornerRadius, style: .continuous))
        .onTapGesture {
            isAmountFocused = true
        }
        .accessibilityLabel("Betrag")
        .accessibilityValue(amountText.isEmpty ? "Leer" : "\(amountText) Euro")
    }

    private var datePickerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isDatePickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                        .frame(width: 30, height: 30)
                        .payScopeLiquidGlassIcon(accent: accent, tintOpacity: 0.1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Datum")
                            .font(.headline.weight(.semibold))
                        Text(Self.selectedDateFormatter.string(from: selectedDate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .payScopeTextTransition(value: selectedDate)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isDatePickerExpanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kalender")
            .accessibilityValue(isDatePickerExpanded ? "Geöffnet" : "Eingeklappt")

            if isDatePickerExpanded {
                DatePicker("Datum", selection: $selectedDate, in: dateRange, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(accent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .payScopeGlassSurface(accent: accent, cornerRadius: PayScopeModalGeometry.sheet.innerCornerRadius, tintOpacity: 0.045, shadowOpacity: 0.065)
    }

    private var parsedAmountCents: Int? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else { return nil }
        return Int((amount * 100).rounded())
    }

    private static let selectedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .full
        return formatter
    }()

    private nonisolated static func amountText(cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
            .replacingOccurrences(of: ".", with: ",")
    }
}

private struct NetWageConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var selectedMonth: Date
    @Binding var config: NetWageMonthConfig
    let onSelectMonth: (Date) -> Void

    @State private var wageTaxText = ""
    @State private var pensionText = ""
    @State private var allowanceText = ""
    @State private var bonusTexts: [String] = []
    @State private var newBonusText = ""
    @State private var showMonthPicker = false
    @State private var saveFeedbackTrigger = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Monat") {
                    Button {
                        showMonthPicker = true
                    } label: {
                        HStack {
                            Text("Gültig für")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(Self.monthYearFormatter.string(from: selectedMonth))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                FormAusgabenSection(
                    wageTaxText: $wageTaxText,
                    pensionText: $pensionText,
                    allowanceText: $allowanceText
                )

                Section("Zuschläge (€)") {
                    if bonusTexts.isEmpty {
                        Text("Noch keine Zuschläge.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(bonusTexts.enumerated()), id: \.offset) { idx, value in
                            HStack {
                                TextField("Zuschlag \(idx + 1)", text: bindingForBonus(at: idx))
                                    .keyboardType(.decimalPad)
                                Text("€")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    bonusTexts.remove(at: idx)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack {
                        TextField("Neuer Zuschlag", text: $newBonusText)
                            .keyboardType(.decimalPad)
                        Text("€")
                            .foregroundStyle(.secondary)
                        Button("Hinzufügen") {
                            guard !newBonusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            let formatted = formatForDisplay(from: newBonusText)
                            bonusTexts.append(formatted ?? newBonusText)
                            newBonusText = ""
                        }
                    }
                }
            }
            .navigationTitle("Lohn Netto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Abbrechen")
                }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                save()
                                dismiss()
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .accessibilityLabel("Speichern")
                        }
            }
            .onAppear {
                selectedMonth = config.monthStart.startOfMonthLocal()
                loadFields(from: config)
            }
            .onChange(of: config.monthStart) { _, _ in
                selectedMonth = config.monthStart.startOfMonthLocal()
                loadFields(from: config)
            }
            .sensoryFeedback(.success, trigger: saveFeedbackTrigger)
            .sheet(isPresented: $showMonthPicker) {
                MonthYearPickerSheet(
                    initialMonth: selectedMonth,
                    yearRange: monthYearPickerRange,
                    accent: .accentColor
                ) { month in
                    monthPickerBinding.wrappedValue = month
                }
            }
        }
    }

    private var monthYearPickerRange: ClosedRange<Int> {
        let currentYear = Calendar.current.component(.year, from: Date())
        let selectedYear = Calendar.current.component(.year, from: selectedMonth)
        return min(currentYear, selectedYear) - 25...max(currentYear, selectedYear) + 25
    }

    private var monthPickerBinding: Binding<Date> {
        Binding(
            get: { selectedMonth },
            set: { newValue in
                let normalizedMonth = newValue.startOfMonthLocal()
                selectedMonth = normalizedMonth
                onSelectMonth(normalizedMonth)
            }
        )
    }

    private func loadFields(from config: NetWageMonthConfig) {
        wageTaxText = formattedPercent(config.wageTaxPercent)
        pensionText = formattedPercent(config.pensionPercent)
        allowanceText = config.monthlyAllowanceEuro
            .map { formatForDisplay(from: String($0)) ?? "" } ?? ""
        bonusTexts = config.bonusesCSV
            .split(separator: ";")
            .map { formatForDisplay(from: String($0)) ?? String($0) }
    }

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private func bindingForBonus(at index: Int) -> Binding<String> {
        Binding(
            get: { bonusTexts[index] },
            set: { bonusTexts[index] = $0 }
        )
    }

    private struct FormAusgabenSection: View {
        @Binding var wageTaxText: String
        @Binding var pensionText: String
        @Binding var allowanceText: String

        var body: some View {
            Section("Abgaben (%)") {
                HStack {
                    TextField("Lohnsteuer", text: $wageTaxText)
                        .keyboardType(.decimalPad)
                    Text("%")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Rentenversicherung", text: $pensionText)
                        .keyboardType(.decimalPad)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Freibetrag (€ / Monat)") {
                HStack {
                    TextField("Monatlicher Freibetrag", text: $allowanceText)
                        .keyboardType(.decimalPad)
                    Text("€")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedPercent(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func normalizedDouble(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func formatForDisplay(from text: String) -> String? {
        guard let value = normalizedDouble(from: text) else { return nil }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func save() {
        let wageTax = normalizedDouble(from: wageTaxText)
        let pension = normalizedDouble(from: pensionText)
        let allowance = normalizedDouble(from: allowanceText)
        let bonusesCSV = bonusTexts
            .compactMap { normalizedDouble(from: $0) }
            .map { String(format: "%.2f", $0) }
            .joined(separator: ";")
        config.wageTaxPercent = wageTax
        config.pensionPercent = pension
        config.monthlyAllowanceEuro = allowance
        config.bonusesCSV = bonusesCSV
        config.monthStart = selectedMonth.startOfMonthUTC()
        upsertLocalNetConfig(config)
        wageTaxText = formatForDisplay(from: wageTaxText) ?? ""
        pensionText = formatForDisplay(from: pensionText) ?? ""
        allowanceText = formatForDisplay(from: allowanceText) ?? ""
        bonusTexts = bonusTexts.map { formatForDisplay(from: $0) ?? $0 }
        saveFeedbackTrigger += 1
        Task {
            do {
                try await cloudKitService.saveNetWageConfig(config)
            } catch {
                #if DEBUG
                print("Failed saving net config: \(error)")
                #endif
            }
        }
    }

    private func upsertLocalNetConfig(_ source: NetWageMonthConfig) {
        let normalizedMonth = source.monthStart.startOfMonthUTC()
        let existing = fetchLocalNetConfigs().first {
            netConfigMonthKey($0.monthStart) == netConfigMonthKey(normalizedMonth)
        }

        if let existing {
            existing.monthStart = normalizedMonth
            existing.wageTaxPercent = source.wageTaxPercent
            existing.pensionPercent = source.pensionPercent
            existing.monthlyAllowanceEuro = source.monthlyAllowanceEuro
            existing.bonusesCSV = source.bonusesCSV
        } else {
            modelContext.insert(
                NetWageMonthConfig(
                    monthStart: normalizedMonth,
                    wageTaxPercent: source.wageTaxPercent,
                    pensionPercent: source.pensionPercent,
                    monthlyAllowanceEuro: source.monthlyAllowanceEuro,
                    bonusesCSV: source.bonusesCSV
                )
            )
        }
        try? modelContext.save()
    }

    private func fetchLocalNetConfigs() -> [NetWageMonthConfig] {
        let descriptor = FetchDescriptor<NetWageMonthConfig>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func netConfigMonthKey(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month], from: date.startOfMonthUTC())
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }
}

private enum CalendarTabViewPreviewData {
    static var todayFocusSettings: Settings {
        Settings(
            hasCompletedOnboarding: true,
            payMode: .hourly,
            hourlyRateCents: 1650,
            weeklyTargetSeconds: 30 * 3600,
            calculateBreaks: true,
            holidayFixedSeconds: 8 * 3600,
            scheduledWorkdaysCount: 5,
            themeAccent: .teal,
            manualCategoryColor: .lavender,
            vacationCategoryColor: .mint,
            holidayCategoryColor: .peach,
            sickCategoryColor: .blush
        )
    }

    static var todayFocusEntries: [DayEntry] {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = now.startOfDayLocal()

        let today = DayEntry(date: now, type: .work, notes: "Preview-Schicht")
        today.shiftStart = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: todayStart)
            ?? todayStart.addingTimeInterval(8.5 * 3600)
        today.shiftEnd = calendar.date(bySettingHour: 17, minute: 15, second: 0, of: todayStart)
            ?? todayStart.addingTimeInterval(17.25 * 3600)
        today.breakSeconds = 30 * 60

        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterday = DayEntry(
            date: yesterdayDate,
            type: .manual,
            notes: "Preview-Ausgleich",
            manualWorkedSeconds: 4 * 3600 + 30 * 60
        )

        return [yesterday, today]
    }
}

#Preview("Calendar") {
    @Previewable @State var displayedMonth = Date()
    let settings = CalendarTabViewPreviewData.todayFocusSettings

    CalendarTabView(
        displayedMonth: $displayedMonth,
        settings: settings,
        isOffline: false
    )
    .environmentObject(CloudKitService.shared)
    .modelContainer(
        for: [
            Settings.self,
            DayEntry.self,
            HolidayCalendarDay.self,
            NetWageMonthConfig.self,
            TimeSegment.self
        ],
        inMemory: true
    )
}

#Preview("Shift Edit Sheet") {
    let settings = CalendarTabViewPreviewData.todayFocusSettings
    let entry = CalendarTabViewPreviewData.todayFocusEntries.last!
    let day = entry.date.startOfDayLocal()

    NavigationStack {
        Color.clear
            .ignoresSafeArea()
    }
    .sheet(isPresented: .constant(true)) {
        DayEditorView(
            date: day,
            settings: settings,
            onDaySaved: nil,
            previewEntry: entry,
            calendarPreview: AnyView(
                CalendarSheetPreviewCard(
                    date: day,
                    entry: entry,
                    settings: settings
                )
            )
        )
        .environmentObject(CloudKitService.shared)
        .modelContainer(
            for: [
                Settings.self,
                DayEntry.self,
                HolidayCalendarDay.self,
                NetWageMonthConfig.self,
                TimeSegment.self
            ],
            inMemory: true
        )
    }
}

#Preview("Today Focus Sheet") {
    let settings = CalendarTabViewPreviewData.todayFocusSettings

    NavigationStack {
        Text("Hello")
    }
    .sheet(isPresented: .constant(true)) {
        TodayFocusView(
            settings: settings,
            entriesOverride: CalendarTabViewPreviewData.todayFocusEntries
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .modelContainer(
            for: [
                Settings.self,
                DayEntry.self,
                HolidayCalendarDay.self,
                NetWageMonthConfig.self,
                TimeSegment.self
            ],
            inMemory: true
        )
    }
}

private struct CalendarSheetPreviewCard: View {
    let date: Date
    let entry: DayEntry
    let settings: Settings

    private var accent: Color {
        settings.categoryColor(for: entry.type)
    }

    var body: some View {
        HStack(spacing: 14) {
            dayTile

            VStack(alignment: .leading, spacing: 7) {
                Label(entry.type.label, systemImage: entry.type.icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Text(PayScopeFormatters.day.string(from: date.startOfDayLocal()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    previewChip(title: "Dauer", value: "08:15")
                    previewChip(title: "Zeit", value: "08:30-17:15")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .payScopeLiquidGlass(accent: accent, cornerRadius: 24, tintOpacity: 0.08)
    }

    private var dayTile: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(accent.opacity(0.105))
            .frame(width: 112, height: 112)
            .overlay(
                VStack(spacing: 6) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)

                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: entry.type.icon)
                            Text("08:15")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent.opacity(0.24), lineWidth: 1)
            )
            .payScopeLiquidGlass(accent: accent, cornerRadius: 22, tintOpacity: 0.085)
    }

    private func previewChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .payScopeGlassControl(accent: accent, cornerRadius: 11, tintOpacity: 0.075, isInteractive: false)
    }
}
