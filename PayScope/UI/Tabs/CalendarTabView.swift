import SwiftUI
import Combine
import SwiftData
import UIKit

struct CalendarTabView: View {
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

    private static let initialBackgroundCloudSyncRadiusMonths = 3

    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.scenePhase) private var scenePhase
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
    @Namespace private var calendarGridGlassNamespace

    @State private var dayEntriesNotificationCancellable: AnyCancellable?
    @State private var tipEntriesNotificationCancellable: AnyCancellable?
    @State private var isInitialLoading = true
    @State private var initialLoadTask: Task<Void, Never>?
    @State private var backgroundCloudSyncWindow = CalendarTabView.initialBackgroundCloudSyncWindow()

    private let service = CalculationService()
    private let holidayImporter = HolidayImportService()
    private let previewRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let calendarContentHorizontalPadding: CGFloat = 16
    private let calendarBottomToolbarSpacerHeight: CGFloat = 12
    private let calendarCardSpacing: CGFloat = 9
    private let calendarGlassBlendSpacing: CGFloat = 6
    private let calendarGlassAnimation = Animation.smooth(duration: 0.34, extraBounce: 0)
    private let calendarContentAnimation = Animation.smooth(duration: 0.24, extraBounce: 0)
    private let calendarContentTransition = AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .center))
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
    private let unsyncedIndicatorDebounce = RunLoop.SchedulerTimeType.Stride.milliseconds(900)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                weekdayHeader
                calendarSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Color.clear
                    .frame(height: calendarBottomToolbarSpacerHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, calendarContentHorizontalPadding)
            .padding(.top)
            .padding(.bottom, 6)
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
                        .payScopeSheetSurface(accent: settings.themeAccent.color)
                case .settings:
                    SettingsTabView(settings: settings)
                        .payScopeSheetSurface(accent: settings.themeAccent.color)
                case let .tips(month):
                    TipEntrySheet(month: month, settings: settings) {
                        Task { await loadTipsForDisplayedMonth() }
                    }
                    .environmentObject(cloudKitService)
                    .payScopeSheetSurface(accent: settings.themeAccent.color)
                }
            }
            .sheet(item: $selectedEditorDay) { selection in
                DayEditorView(
                    date: selection.date,
                    settings: settings,
                    onDaySaved: applyDayEditorChange
                )
            }
            .sheet(isPresented: $showMonthYearPicker) {
                MonthYearPickerSheet(
                    initialMonth: displayedMonth,
                    yearRange: monthYearPickerRange,
                    accent: settings.themeAccent.color
                ) { selectedMonth in
                    displayedMonth = selectedMonth
                    ensureBackgroundCloudSyncWindowCovers(month: selectedMonth)
                    monthSelectionFeedbackTrigger += 1
                    Task { await loadData(mode: .fullSync) }
                }
                .payScopeSheetSurface(accent: settings.themeAccent.color)
            }
            .sensoryFeedback(.selection, trigger: monthSelectionFeedbackTrigger)
            .sensoryFeedback(.warning, trigger: dayDeleteFeedbackTrigger)
        }
        .background(
            LinearGradient(
                colors: [settings.themeAccent.color, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
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
            monthHoursToolbarSummary
        }

        ToolbarItem(placement: .topBarTrailing) {
            calendarDisplayModeMenu
        }

        if settings.effectiveShowTipsButton {
            ToolbarSpacer(placement: .topBarTrailing)
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
        let monthStart = displayedMonthBounds.0
        let monthEnd = displayedMonthBounds.1
        var totalsByDay: [String: Int] = [:]

        for entry in entries where entry.date >= monthStart && entry.date <= monthEnd {
            let amount = max(0, entry.tipAmountCents ?? 0)
            guard amount > 0 else { continue }
            totalsByDay[dayKey(entry.date)] = max(totalsByDay[dayKey(entry.date)] ?? 0, amount)
        }

        for tip in tipEntries where tip.date >= monthStart && tip.date <= monthEnd && tip.amountCents > 0 {
            let key = dayKey(tip.date)
            if totalsByDay[key] == nil {
                totalsByDay[key] = 0
            }
            totalsByDay[key]? += tip.amountCents
        }

        return totalsByDay.values.reduce(0, +)
    }

    private var monthHoursToolbarSummary: some View {
        let summary = displayedMonthSummary
        let monthlyValue = monthToolbarPayValue(for: summary)

        return Button {
            openNetWageConfigForDisplayedMonth()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(PayScopeFormatters.hhmmString(seconds: summary.totalSeconds) + "h")
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .payScopeNumericTransition(value: summary.totalSeconds)

                Text(PayScopeFormatters.currencyString(cents: monthlyValue))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(settings.themeAccent.color).opacity(0.6)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .payScopeNumericTransition(value: monthlyValue)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 96, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monatsübersicht")
        .accessibilityValue("\(PayScopeFormatters.hhmmString(seconds: summary.totalSeconds)), \(PayScopeFormatters.currencyString(cents: monthlyValue))")
    }

    private func monthToolbarPayValue(for summary: TotalsSummary) -> Int {
        switch settings.effectiveCalendarSummaryDisplayMode {
        case .net:
            return monthlyNetCents(for: summary)
        case .gross:
            return summary.totalCents
        }
    }

    private var tipsToolbarButton: some View {
        Button {
            activeSheet = .tips(displayedMonth.startOfMonthLocal())
        } label: {
            if settings.effectiveShowTipsButtonAmount {
                Label(displayedMonthTipTotalText, systemImage: "eurosign.circle")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "eurosign.circle")
            }
        }
        .id("\(settings.effectiveShowTipsButton)-\(settings.effectiveShowTipsButtonAmount)-\(displayedMonthTipTotalText)")
        .accessibilityLabel("Trinkgeld öffnen")
    }

    private var calendarDisplayModeMenu: some View {
        CalendarDisplayModeMenu(
            currentMode: settings.calendarCellDisplayMode ?? .dot,
            currentBreakMode: settings.effectiveCalendarHoursBreakMode,
            selectDisplayMode: updateCalendarDisplayMode,
            selectHoursBreakMode: updateCalendarHoursDisplayMode
        )
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
        service.periodSummary(
            entries: entries,
            from: displayedMonthBounds.0,
            to: displayedMonthBounds.1,
            settings: settings
        )
    }

    private var monthSummaryBar: some View {
        let summary = displayedMonthSummary
        let monthlyNetCents = monthlyNetCents(for: summary)

        return PayScopeGlassControlGroup(spacing: 8) {
            HStack(spacing: 8) {
                monthMetricChip(
                    title: "Stunden",
                    value: PayScopeFormatters.hhmmString(seconds: summary.totalSeconds)
                )
                monthMetricChip(
                    title: "Brutto",
                    value: PayScopeFormatters.currencyString(cents: summary.totalCents)
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

    private func previousMonthConfig(for monthStart: Date) -> NetWageMonthConfig? {
        guard let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: monthStart.startOfMonthLocal()) else {
            return nil
        }
        return netConfig(for: previousMonth.startOfMonthLocal())
    }

    private func effectiveNetConfig(for monthStart: Date) -> (wageTaxPercent: Double?, pensionPercent: Double?, monthlyAllowanceEuro: Double?, bonusesCSV: String) {
        if let current = netConfig(for: monthStart) {
            return (current.wageTaxPercent, current.pensionPercent, current.monthlyAllowanceEuro, current.bonusesCSV)
        }
        if let previous = previousMonthConfig(for: monthStart) {
            return (previous.wageTaxPercent, previous.pensionPercent, previous.monthlyAllowanceEuro, previous.bonusesCSV)
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

    private func persistNetDefaultsToSettings(
        wageTaxPercent: Double?,
        pensionPercent: Double?,
        monthlyAllowanceEuro: Double?,
        bonusesCSV: String
    ) {
        settings.netWageTaxPercent = wageTaxPercent
        settings.netPensionPercent = pensionPercent
        settings.netMonthlyAllowanceEuro = monthlyAllowanceEuro
        settings.netBonusesCSV = bonusesCSV.isEmpty ? nil : bonusesCSV

        Task {
            do {
                try await cloudKitService.saveSettings(settings)
            } catch {
                #if DEBUG
                print("Failed saving net defaults in settings: \(error)")
                #endif
            }
        }
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
        guard !totalsByDay.isEmpty else { return sourceEntries }

        var entriesByDay = Dictionary(
            sourceEntries.map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )

        for (key, payload) in totalsByDay {
            let entry = entriesByDay[key] ?? DayEntry(
                date: utcDate(forLocalDay: payload.date),
                updatedAt: payload.updatedAt
            )
            let incomingAmount = max(0, payload.amountCents)
            guard incomingAmount > 0 else { continue }

            if max(0, entry.tipAmountCents ?? 0) != incomingAmount {
                entry.tipAmountCents = incomingAmount
                if payload.updatedAt > entry.updatedAt {
                    entry.updatedAt = payload.updatedAt
                }
                if persist {
                    localStore.save(entry)
                }
            }
            entriesByDay[key] = entry
        }

        return entriesByDay.values.sorted { $0.date > $1.date }
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
        let dayResultsByDate = dayResultLookup(for: dates, entriesByDate: entriesByDate)
        let holidayDateSet = holidayDates
        let weekBadgesByDate = weekBadgeLookup(for: dates, entriesByDate: entriesByDate)

        return GeometryReader { geo in
            let spacing = calendarCardSpacing
            let totalSpacing = spacing * CGFloat(max(0, rowCount - 1))
            let availableHeight = max(0, geo.size.height - totalSpacing)
            let cellHeight = max(1, availableHeight / CGFloat(rowCount))

            GlassEffectContainer(spacing: calendarGlassBlendSpacing) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7), spacing: spacing) {
                    ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                        let dayDate = date.startOfDayLocal()
                        let entry = entriesByDate[dayDate]
                        let isHoliday = holidayDateSet.contains(dayDate) || entry?.type == .holiday
                        let weekBadgeData = shouldShowWeekBadge && index % 7 == 0
                            ? weekBadgesByDate[dayDate]
                            : nil
                        let hasTips = tipCents(for: dayDate, entry: entry) > 0
                        let rowIndex = index / 7
                        let popoverArrowEdge: Edge = rowIndex < rowCount / 2 ? .top : .bottom

                        Group {
                            if Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
                                dayCell(
                                    for: dayDate,
                                    height: cellHeight,
                                    entry: entry,
                                    result: dayResultsByDate[dayDate],
                                    isHoliday: isHoliday,
                                    hasTips: hasTips,
                                    weekBadgeData: weekBadgeData,
                                    popoverArrowEdge: popoverArrowEdge,
                                    glassEffectID: index
                                )
                            } else if date > displayedMonthBounds.1 {
                                adjacentMonthCell(for: dayDate, height: cellHeight, isNextMonth: true, weekBadgeData: weekBadgeData, glassEffectID: index)
                            } else {
                                adjacentMonthCell(for: dayDate, height: cellHeight, isNextMonth: false, weekBadgeData: weekBadgeData, glassEffectID: index)
                            }
                        }
                    }
                }
                .animation(calendarGlassAnimation, value: displayedMonth.startOfMonthLocal())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calendarSurface: some View {
        ZStack {
            calendarGrid
        }
            .clipped()
            .padding(.top, 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 52)
                    .onEnded(handleMonthSwipe)
            )
    }

    private func handleMonthSwipe(_ gesture: DragGesture.Value) {
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
        withAnimation(calendarGlassAnimation) {
            displayedMonth = targetMonth.startOfMonthLocal()
        }
        monthSelectionFeedbackTrigger += 1
        Task { await loadData(mode: .fullSync) }
    }

    private func dayCell(
        for dayDate: Date,
        height: CGFloat,
        entry: DayEntry?,
        result: ComputationResult?,
        isHoliday: Bool,
        hasTips: Bool,
        weekBadgeData: WeekBadgeData?,
        popoverArrowEdge: Edge,
        glassEffectID: Int
    ) -> some View {
        let visibleEntry = entry.flatMap { isVisibleInCalendarCell($0) ? $0 : nil }
        let isToday = Calendar.current.isDateInToday(dayDate)
        let isWeekend = Calendar.current.isDateInWeekend(dayDate)
        let categoryTint = categoryTintColor(for: visibleEntry?.type, isHoliday: isHoliday)
        let todayHighlightColor = todayHighlightColor(for: visibleEntry)
        let hasSavedShift = hasSavedShift(in: visibleEntry)
        let dayBackgroundColors = dayCellBackgroundColors(
            isWeekend: isWeekend,
            isHoliday: isHoliday,
            categoryTint: hasSavedShift ? nil : categoryTint
        )
        let dayCardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let glassTint = dayCardGlassTint(
            isWeekend: isWeekend,
            isHoliday: isHoliday,
            categoryTint: categoryTint,
            hasSavedShift: hasSavedShift
        )
        let glassTintOpacity = dayCardGlassTintOpacity(
            isWeekend: isWeekend,
            isHoliday: isHoliday,
            isToday: isToday,
            hasSavedShift: hasSavedShift
        )
        let numberTopPadding = max(8, (height * 0.38) - 24)

        return Button {
            selectedPopoverDay = dayDate
        } label: {
            VStack(spacing: 0) {
                Text("\(Calendar.current.component(.day, from: dayDate))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        dayNumberForegroundColor(
                            isWeekend: isWeekend,
                            isHoliday: isHoliday,
                            categoryTint: categoryTint
                        )
                    )
                    .padding(.top, numberTopPadding)

                Spacer(minLength: 2)

                ZStack {
                    if let visibleEntry {
                        cellMetric(for: visibleEntry, result: result, hasTips: hasTips)
                            .id(metricIdentity(for: visibleEntry, result: result, hasTips: hasTips))
                            .transition(calendarContentTransition)
                    } else if hasTips {
                        Image(systemName: "eurosign.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .accessibilityLabel("Trinkgeld")
                            .transition(calendarContentTransition)
                    }
                }
                .animation(calendarContentAnimation, value: metricAnimationKey(for: visibleEntry, result: result, hasTips: hasTips))

                if let result {
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
                                colors: dayBackgroundColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    if hasSavedShift {
                        dayCardShape
                            .fill(
                                LinearGradient(
                                    colors: shiftHighlightColors(categoryTint: categoryTint),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .transition(.opacity)
                    }
                }
                .clipShape(dayCardShape)
            )
            .glassEffect(
                .regular
                    .tint(glassTint.opacity(glassTintOpacity))
                    .interactive(true),
                in: dayCardShape
            )
            .glassEffectID(glassEffectID, in: calendarGridGlassNamespace)
            .animation(calendarGlassAnimation, value: hasSavedShift)
            .overlay(alignment: .topLeading) {
                if let weekBadgeData {
                    weekBadgeView(weekBadgeData, muted: isWeekend && !isHoliday)
                        .padding(.top, 7)
                        .padding(.leading, 7)
                }
            }
            .overlay(
                ZStack {
                    dayCardShape
                        .stroke(.white.opacity(isToday ? 0.18 : 0.12), lineWidth: 0.75)
                        .blendMode(.softLight)
                    
                    if isToday {
                        dayCardShape
                            .stroke(todayHighlightColor.opacity(0.52), lineWidth: 1.4)
                    }
                }
            )
            .shadow(
                color: isToday ? todayHighlightColor.opacity(0.18) : .black.opacity(0.04),
                radius: isToday ? 9 : 5,
                x: 0,
                y: isToday ? 6 : 3
            )
        }
        .buttonStyle(.plain)
        .contentShape(dayCardShape)
        .popover(
            isPresented: dayPopoverBinding(for: dayDate),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: popoverArrowEdge
        ) {
            ShiftViewPopover(
                date: dayDate,
                entry: self.entry(for: dayDate),
                entries: entries,
                tipCents: tipCents(for: dayDate, entry: self.entry(for: dayDate)),
                settings: settings,
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

    private func deleteDayFromPopover(for date: Date) {
        dayDeleteFeedbackTrigger += 1
        deleteDayEntry(for: date.startOfDayLocal())
        selectedPopoverDay = nil
    }

    private func dayResultLookup(
        for dates: [Date],
        entriesByDate: [Date: DayEntry]
    ) -> [Date: ComputationResult] {
        var lookup: [Date: ComputationResult] = [:]

        for date in dates where Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
            let dayDate = date.startOfDayLocal()
            guard let entry = entriesByDate[dayDate], isVisibleInCalendarCell(entry) else {
                continue
            }
            lookup[dayDate] = service.dayComputation(
                for: entry,
                entriesByDate: entriesByDate,
                settings: settings
            )
        }

        return lookup
    }

    private func weekBadgeLookup(
        for dates: [Date],
        entriesByDate: [Date: DayEntry]
    ) -> [Date: WeekBadgeData] {
        guard shouldShowWeekBadge else { return [:] }
        var lookup: [Date: WeekBadgeData] = [:]

        for index in stride(from: 0, to: dates.count, by: 7) {
            let dayDate = dates[index].startOfDayLocal()
            lookup[dayDate] = weekBadgeData(for: dayDate, entriesByDate: entriesByDate)
        }

        return lookup
    }

    private func isVisibleInCalendarCell(_ entry: DayEntry) -> Bool {
        if (entry.manualWorkedSeconds ?? 0) > 0 { return true }
        if (entry.creditedOverrideSeconds ?? 0) > 0 { return true }
        if entry.type != .work { return true }
        if let s = entry.shiftStart, let e = entry.shiftEnd, e > s { return true }
        return false
    }

    private func dayCellBackgroundColors(
        isWeekend: Bool,
        isHoliday: Bool,
        categoryTint: Color?
    ) -> [Color] {
        let holidayTint = categoryTint ?? settings.categoryColor(for: .holiday)

        if isWeekend && isHoliday {
            return [
                Color(.tertiarySystemFill).opacity(0.84),
                holidayTint.opacity(0.18),
                Color(.secondarySystemFill).opacity(0.72)
            ]
        }

        if isHoliday {
            return [
                holidayTint.opacity(0.2),
                holidayTint.opacity(0.09),
                Color(.secondarySystemBackground).opacity(0.94)
            ]
        }

        if let categoryTint {
            if isWeekend {
                return [
                    Color(.tertiarySystemFill).opacity(0.84),
                    categoryTint.opacity(0.16),
                    Color(.secondarySystemFill).opacity(0.74)
                ]
            }

            return [
                categoryTint.opacity(0.2),
                categoryTint.opacity(0.09),
                Color(.secondarySystemBackground).opacity(0.94)
            ]
        }

        if isWeekend {
            return [
                Color(.tertiarySystemFill).opacity(0.86),
                Color(.secondarySystemFill).opacity(0.76)
            ]
        }

        return [
            Color(.secondarySystemBackground).opacity(0.95),
            settings.themeAccent.color.opacity(0.06),
            Color(.systemBackground).opacity(0.98)
        ]
    }

    private func shiftHighlightColors(categoryTint: Color?) -> [Color] {
        let tint = categoryTint ?? settings.themeAccent.color
        return [
            tint.opacity(0.2),
            tint.opacity(0.09),
            Color(.secondarySystemBackground).opacity(0.94)
        ]
    }

    private func dayCardGlassTint(
        isWeekend: Bool,
        isHoliday: Bool,
        categoryTint: Color?,
        hasSavedShift: Bool
    ) -> Color {
        if let categoryTint, hasSavedShift || isHoliday {
            return categoryTint
        }
        if isHoliday {
            return settings.categoryColor(for: .holiday)
        }
        if isWeekend {
            return settings.themeAccent.color.opacity(0.68)
        }
        return categoryTint ?? settings.themeAccent.color
    }

    private func dayCardGlassTintOpacity(
        isWeekend: Bool,
        isHoliday: Bool,
        isToday: Bool,
        hasSavedShift: Bool
    ) -> Double {
        if isToday {
            return hasSavedShift ? 0.18 : 0.14
        }
        if hasSavedShift {
            return 0.16
        }
        if isHoliday {
            return 0.13
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

    private func adjacentMonthCell(for date: Date, height: CGFloat, isNextMonth: Bool, weekBadgeData: WeekBadgeData?, glassEffectID: Int) -> some View {
        let dayDate = date.startOfDayLocal()
        let fillOpacity: Double = isNextMonth ? 0.38 : 0.24
        let textOpacity: Double = isNextMonth ? 0.34 : 0.5
        let dayCardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let glassTintOpacity: Double = isNextMonth ? 0.045 : 0.06

        return VStack(spacing: 0) {
            Text("\(Calendar.current.component(.day, from: dayDate))")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary.opacity(textOpacity))
                .padding(.top, max(8, (height * 0.38) - 24))
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(
            dayCardShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.tertiarySystemFill).opacity(fillOpacity),
                            Color(.secondarySystemFill).opacity(fillOpacity + 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .glassEffect(
            .regular.tint(settings.themeAccent.color.opacity(glassTintOpacity)),
            in: dayCardShape
        )
        .glassEffectID(glassEffectID, in: calendarGridGlassNamespace)
        .overlay(
            dayCardShape
                .stroke(.white.opacity(0.08), lineWidth: 0.7)
                .blendMode(.softLight)
        )
        .overlay(alignment: .topLeading) {
            if let weekBadgeData {
                weekBadgeView(weekBadgeData, muted: true)
                    .padding(.top, 7)
                    .padding(.leading, 7)
            }
        }
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

    private func weekBadgeData(
        for date: Date,
        entriesByDate: [Date: DayEntry]
    ) -> WeekBadgeData {
        let day = date.startOfDayLocal()
        let weekStart = service.weekStartDate(for: day)
        let weekEnd = weekStart.addingDays(6)
        let summary = service.periodSummary(
            entries: entries,
            entriesByDate: entriesByDate,
            from: weekStart,
            to: weekEnd,
            settings: settings
        )

        let weekNumber = settings.effectiveShowCalendarWeekNumbers
            ? calendarWeekNumber(for: weekStart)
            : nil

        var detailParts: [String] = []
        if settings.effectiveShowCalendarWeekHours {
            detailParts.append("\(PayScopeFormatters.hhmmString(seconds: summary.totalSeconds)) h")
        }
        if settings.effectiveShowCalendarWeekPay {
            detailParts.append(shortCurrency(cents: summary.totalCents))
        }

        return WeekBadgeData(
            weekNumber: weekNumber,
            detailText: detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")
        )
    }

    private func calendarWeekNumber(for date: Date) -> Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.component(.weekOfYear, from: date.startOfDayLocal(calendar: calendar))
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

    @ViewBuilder
    private func cellMetric(for entry: DayEntry, result: ComputationResult?, hasTips: Bool) -> some View {
        let hasShiftDeviation = entry.creditedOverrideSeconds != nil
        let categoryTint = settings.categoryColor(for: entry.type)
        let typeIcon = Image(systemName: entry.type.icon)
            .font(.caption2)
            .foregroundStyle(categoryTint)
        let categoryIconRow = HStack(spacing: 4) {
            typeIcon
            if hasTips {
                Image(systemName: "eurosign.circle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Trinkgeld")
            }
            if hasShiftDeviation {
                Image(systemName: "pencil")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        let iconsOnlyCategoryIconRow = HStack(spacing: 5) {
            Image(systemName: entry.type.icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(categoryTint)
                .symbolRenderingMode(.hierarchical)
            if hasTips {
                Image(systemName: "eurosign.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Trinkgeld")
            }
            if hasShiftDeviation {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }

        switch settings.calendarCellDisplayMode ?? .dot {
        case .dot:
            iconsOnlyCategoryIconRow
        case .hours:
            let seconds = calendarCellHoursSeconds(for: entry, result: result)
            calendarCellMetricStack(
                categoryIconRow: categoryIconRow,
                texts: [PayScopeFormatters.hhmmString(seconds: seconds)]
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
            calendarCellMetricStack(
                categoryIconRow: categoryIconRow,
                texts: [shortCurrency(cents: cents)]
            )
        case .startTime:
            calendarCellMetricStack(
                categoryIconRow: categoryIconRow,
                texts: calendarCellStartTimeText(for: entry).map { [$0] } ?? [],
                showsIconWhenEmpty: false
            )
        case .endTime:
            calendarCellMetricStack(
                categoryIconRow: categoryIconRow,
                texts: calendarCellEndTimeText(for: entry).map { [$0] } ?? [],
                showsIconWhenEmpty: false
            )
        case .startAndEndTime:
            calendarCellStartAndEndTimeStack(
                categoryIconRow: categoryIconRow,
                rows: calendarCellStartAndEndTimeRows(for: entry),
                tint: settings.categoryColor(for: entry.type),
                showsIconWhenEmpty: false
            )
        }
    }

    @ViewBuilder
    private func calendarCellMetricStack<Icon: View>(
        categoryIconRow: Icon,
        texts: [String],
        showsIconWhenEmpty: Bool = true
    ) -> some View {
        if texts.isEmpty {
            if showsIconWhenEmpty {
                categoryIconRow
            } else {
                EmptyView()
            }
        } else {
            VStack(spacing: texts.count > 1 ? 1 : 2) {
                categoryIconRow
                ForEach(texts.indices, id: \.self) { index in
                    Text(texts[index])
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    @ViewBuilder
    private func calendarCellStartAndEndTimeStack<Icon: View>(
        categoryIconRow: Icon,
        rows: [CalendarCellTimeRow],
        tint: Color,
        showsIconWhenEmpty: Bool = true
    ) -> some View {
        if rows.isEmpty {
            if showsIconWhenEmpty {
                categoryIconRow
            } else {
                EmptyView()
            }
        } else {
            VStack(spacing: 1) {
                categoryIconRow
                    .offset(y: -2)
                ForEach(rows) { row in
                    HStack(spacing: 3) {
                        Text(row.text)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
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

    private func metricIdentity(for entry: DayEntry, result: ComputationResult?, hasTips: Bool) -> String {
        "\(entry.updatedAt.timeIntervalSinceReferenceDate)-\(metricAnimationKey(for: entry, result: result, hasTips: hasTips))"
    }

    private func metricAnimationKey(for entry: DayEntry?, result: ComputationResult?, hasTips: Bool) -> String {
        guard let entry else { return "tips-\(hasTips)" }
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
        return "\(entry.type.rawValue)-\(entry.updatedAt.timeIntervalSinceReferenceDate)-\(shiftKey)-tips-\(hasTips)-\(resultKey)"
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
        // Determine the month interval for the currently displayed month
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }

        // Find the week that contains the first day of the month
        guard let firstWeek = Calendar.current.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        // We always want to show exactly 6 full weeks (42 days)
        let sixWeeksEnd = Calendar.current.date(byAdding: .day, value: 42, to: firstWeek.start) ?? firstWeek.end

        var dates: [Date] = []
        var current = firstWeek.start
        while current < sixWeeksEnd {
            dates.append(current)
            current = current.addingDays(1)
        }
        return dates
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

    private var holidayDates: Set<Date> {
        let country = normalizedHolidayCountryCode
        let subdivision = normalizedHolidaySubdivisionCode
        return Set(
            importedHolidays
                .filter {
                    normalizeCode($0.countryCode) == country &&
                    normalizeCode($0.subdivisionCode) == subdivision
                }
                .map { $0.date.startOfDayLocal() }
        )
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
        let localEntries = entriesWithLegacyTipsApplied(
            to: localStore.loadAll(in: interval),
            tips: localTips,
            persist: true
        )
        let localSnapshot = deduplicateEntriesByLocalDayKeepingNewest(localEntries)
        if mode == .localOnly || entries.isEmpty {
            // Cold start: show persisted data immediately, then refresh from cloud.
            applyEntriesIfChanged(localSnapshot)
        }
        guard mode == .fullSync else { return }

        let tombstonesByDay = Dictionary(
            localStore.loadDeletionTombstones()
                .filter { interval.contains($0.date) }
                .map { (dayKey($0.date), $0.lastModified) },
            uniquingKeysWith: { current, incoming in
                incoming > current ? incoming : current
            }
        )

        do {
            // Cloud-first: prefer iCloud data when reachable.
            var cloudEntries = deduplicateEntriesByLocalDayKeepingNewest(
                try await cloudKitService.fetchDayEntries(in: interval)
            )

            // Sync local deletions to cloud first (LWW).
            let didSyncDeletes = await syncPendingLocalDeletionsToCloud(
                cloudEntries: cloudEntries,
                interval: interval
            )
            if didSyncDeletes {
                cloudEntries = deduplicateEntriesByLocalDayKeepingNewest(
                    try await cloudKitService.fetchDayEntries(in: interval)
                )
            }

            // If local fallback entries exist, sync newer local versions back to iCloud.
            if !localSnapshot.isEmpty {
                let didSyncPending = await syncPendingLocalEntriesToCloud(localEntries: localSnapshot, cloudEntries: cloudEntries)
                if didSyncPending {
                    cloudEntries = deduplicateEntriesByLocalDayKeepingNewest(
                        try await cloudKitService.fetchDayEntries(in: interval)
                    )
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
            applyNetConfigsIfChanged(try await cloudKitService.fetchNetWageConfigs())

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
            hasher.combine(value.tipAmountCents ?? -1)
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
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )

        return byDay.values.sorted { $0.date > $1.date }
    }

    private func mergeEntriesByLocalDayKeepingNewest(local: [DayEntry], remote: [DayEntry]) -> [DayEntry] {
        let byDay = Dictionary(
            (local + remote).map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        return byDay.values.sorted { $0.date > $1.date }
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
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            settings.themeAccent.color.opacity(0.3),
                            settings.themeAccent.color.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.8)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(settings.themeAccent.color.opacity(0.34), lineWidth: 1.1)
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
            LinearGradient(
                colors: [settings.themeAccent.color, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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

private struct WeekBadgeData {
    let weekNumber: Int?
    let detailText: String?
}

private struct CalendarCellTimeRow: Identifiable {
    let text: String

    var id: String {
        "-\(text)"
    }
}

private struct CalendarDaySelection: Identifiable {
    let date: Date

    var id: String {
        "day-editor-\(date.startOfDayLocal().timeIntervalSinceReferenceDate)"
    }
}

private enum CalendarSheet: Identifiable {
    case today
    case settings
    case tips(Date)

    var id: String {
        switch self {
        case .today:
            return "today"
        case .settings:
            return "settings"
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
            ForEach(CalendarCellDisplayMode.allCases) { mode in
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
            Image(systemName: Self.displayModeSystemImage(for: selectedMode))
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
        guard selectedMode == .hours else { return selectedMode.label }
        return "\(selectedMode.label), \(selectedBreakMode.label)"
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
    let onEdit: (Date) -> Void
    let onDelete: (Date) -> Void

    @State private var showDeleteConfirm = false
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
            //.payScopeGlassSurface(accent: accent, cornerRadius: PayScopeModalGeometry.popover.innerCornerRadius, tintOpacity: 0.045, shadowOpacity: 0.06)
            //.payScopePopoverSurface(accent: accent)
            .alert("Tag löschen?", isPresented: $showDeleteConfirm) {
                Button("Löschen", role: .destructive) {
                    onDelete(dayStart)
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Dieser Tageseintrag wird gelöscht.")
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
            }
    }

    private func popoverShell(includeActions: Bool, limitContentHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(includeActions: includeActions)

            if entry != nil {
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
        HStack(spacing: 14) {
            Image(systemName: bodyIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(entry == nil ? Color.secondary.opacity(0.72) : accent)
                .frame(width: 32, height: 32)
                .payScopeLiquidGlassIcon(
                    accent: entry == nil ? Color.secondary.opacity(0.54) : accent,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    tintOpacity: entry == nil ? 0.07 : 0.12,
                    shadowOpacity: entry == nil ? 0.03 : 0.06
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(bodyTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(dateText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(entry == nil ? Color.secondary : accent)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if includeActions, entry != nil {
                HStack(spacing: 7) {
                    headerIconButton(
                        systemImage: "trash",
                        tint: .red,
                        backgroundTint: .red
                    ) {
                        showDeleteConfirm = true
                    }
                    .accessibilityLabel("Tag löschen")

                    shareMenu



                    headerIconButton(
                        systemImage: "pencil",
                        tint: accent,
                        backgroundTint: accent
                    ) {
                        onEdit(dayStart)
                    }
                    .accessibilityLabel("Bearbeiten")
                }
            } else if includeActions {
                headerIconButton(
                    systemImage: "plus",
                    tint: accent,
                    backgroundTint: accent
                ) {
                    onEdit(dayStart)
                }
                .accessibilityLabel("Schicht hinzufügen")
            }
        }
        .padding(.horizontal, 15)
        .frame(width: popoverContentWidth, height: 58)
        .overlay(alignment: .bottom) {
            if entry != nil {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 0.5)
            }
        }
    }

    private var shareMenu: some View {
        Menu {
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
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .payScopeGlassControl(accent: accent, cornerRadius: 13, tintOpacity: 0.095)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Teilen")
    }

    private func headerIconButton(
        systemImage: String,
        tint: Color,
        backgroundTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .payScopeGlassControl(accent: backgroundTint, cornerRadius: 13, tintOpacity: 0.095)
        }
        .buttonStyle(.plain)
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
            //.payScopeGlassSurface(accent: accent, cornerRadius: PayScopeModalGeometry.popover.innerCornerRadius, tintOpacity: 0.045, shadowOpacity: 0.06)
            //.payScopePopoverSurface(accent: accent)
    }

    private var shareText: String {
        guard let entry else {
            return "\(bodyTitle)\n\(dateText)"
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
        }
    }

    private func shiftSummaryCard(for entry: DayEntry) -> some View {
        let endText = endTimeText(for: entry)

        return VStack(alignment: .leading, spacing: 12) {

            timeRangeRow(
                start: startTimeText(for: entry),
                end: endText.time,
                endSuffix: endText.suffix
            )

            LazyVGrid(columns: metricColumns, spacing: 7) {

                compactMetric(
                    label: "Dauer",
                    value: durationValueText(for: entry),
                    suffix: durationValueText(for: entry) == "-" ? nil : "h",
                    systemImage: "clock.fill",
                    valueTint: accent,
                    columnAlignment: .leading
                )

                compactMetric(
                    label: "Pause",
                    value: breakValueText(for: entry),
                    suffix: "h",
                    systemImage: "pause.fill",
                    columnAlignment: .center
                )

                if hasTip {
                    compactMetric(
                        label: "Trinkgeld",
                        value: moneyTileValueText(cents: tipCents),
                        systemImage: "eurosign.circle.fill",
                        valueTint: .orange,
                        columnAlignment: .center
                    )
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

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 7), count: hasTip ? 4 : 3)
    }

    private func timeRangeRow(start: String, end: String, endSuffix: String?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            timeEndpoint(label: "Start", value: start, systemImage: "play.fill", columnAlignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 22)

            timeEndpoint(label: "Ende", value: end, suffix: endSuffix, systemImage: "stop.fill", columnAlignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .shiftViewPanel(accent: accent)
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

    private func compactMetric(
        label: String,
        value: String,
        suffix: String? = nil,
        systemImage: String,
        valueTint: Color = .primary,
        isTinted: Bool = false,
        columnAlignment: PopoverColumnAlignment
    ) -> some View {

        VStack(alignment: columnAlignment.horizontal, spacing: 4) {

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
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isTinted ? accent.opacity(0.26) : .white.opacity(0.12), lineWidth: 0.8)
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
        if workedSeconds > 0 || entry.manualWorkedSeconds != nil || entry.type != .work {
            return PayScopeFormatters.hhmmString(seconds: workedSeconds)
        }
        return "-"
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
            .background(
                shape
                    .fill(accent.opacity(0.035))
            )
            .glassEffect(
                .regular
                    .tint(accent.opacity(0.055))
                    .interactive(true),
                in: shape
            )
            .payScopeLiquidGlassTapFeedback(accent: accent, in: shape, tintOpacity: 0.052, pressedScale: 0.99)
            .overlay(
                shape
                    .stroke(accent.opacity(0.14), lineWidth: 1)
                    .allowsHitTesting(false)
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
                .payScopeSheetSurface(accent: settings.themeAccent.color)
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
        let existing = LocalDayEntryStore.shared.load(on: day)
        let existingAmount = max(0, existing?.tipAmountCents ?? 0)
        let normalizedAmount = max(0, amountCents)

        guard normalizedAmount > 0 || existingAmount > 0 else { return }
        guard existingAmount != normalizedAmount || existing == nil else { return }

        let target = existing ?? DayEntry(date: Self.utcDate(forLocalDay: day), updatedAt: updatedAt)
        target.date = Self.utcDate(forLocalDay: day)
        target.updatedAt = max(target.updatedAt, updatedAt)
        target.tipAmountCents = normalizedAmount > 0 ? normalizedAmount : nil

        if normalizedAmount == 0, Self.isTipOnlyEntry(target) {
            LocalDayEntryStore.shared.delete(on: day)
            Task {
                do {
                    try await cloudKitService.deleteDayEntry(on: day)
                } catch {
                    #if DEBUG
                    print("CloudKit day tip delete failed, local tombstone kept for retry: \(error)")
                    #endif
                }
            }
            return
        }

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

    private static func isTipOnlyEntry(_ entry: DayEntry) -> Bool {
        guard entry.type == .work else { return false }
        guard (entry.tipAmountCents ?? 0) == 0 else { return false }
        guard entry.manualWorkedSeconds == nil else { return false }
        guard entry.creditedOverrideSeconds == nil else { return false }
        if let start = entry.shiftStart, let end = entry.shiftEnd, end > start {
            return false
        }
        return true
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

    var title: String {
        tip == nil ? "Trinkgeld hinzufügen" : "Trinkgeld bearbeiten"
    }

    var saveAccessibilityLabel: String {
        tip == nil ? "Hinzufügen" : "Speichern"
    }
}

private struct TipEntryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let saveAccessibilityLabel: String
    let dateRange: ClosedRange<Date>
    let onSave: (Date, Int) -> Void

    @State private var selectedDate: Date
    @State private var amountText: String

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
            Form {
                Section {
                    DatePicker("Datum", selection: $selectedDate, in: dateRange, displayedComponents: .date)

                    HStack {
                        TextField("Betrag", text: $amountText)
                            .keyboardType(.decimalPad)
                        Text("EUR")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var parsedAmountCents: Int? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else { return nil }
        return Int((amount * 100).rounded())
    }

    private nonisolated static func amountText(cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
            .replacingOccurrences(of: ".", with: ",")
    }
}

private struct NetWageConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var config: NetWageMonthConfig
    let onPersistDefaults: (Double?, Double?, Double?, String) -> Void

    @State private var wageTaxText = ""
    @State private var pensionText = ""
    @State private var allowanceText = ""
    @State private var bonusTexts: [String] = []
    @State private var newBonusText = ""

    var body: some View {
        NavigationStack {
            Form {

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
                wageTaxText = formattedPercent(config.wageTaxPercent)
                pensionText = formattedPercent(config.pensionPercent)
                allowanceText = formatForDisplay(from: String(config.monthlyAllowanceEuro ?? 0)) ?? ""
                if config.monthlyAllowanceEuro == nil {
                    allowanceText = ""
                }
                bonusTexts = config.bonusesCSV
                    .split(separator: ";")
                    .map { formatForDisplay(from: String($0)) ?? String($0) }
            }
        }
    }

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
        wageTaxText = formatForDisplay(from: wageTaxText) ?? ""
        pensionText = formatForDisplay(from: pensionText) ?? ""
        allowanceText = formatForDisplay(from: allowanceText) ?? ""
        bonusTexts = bonusTexts.map { formatForDisplay(from: $0) ?? $0 }
        onPersistDefaults(wageTax, pension, allowance, bonusesCSV)
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
        .payScopeSheetSurface(accent: settings.themeAccent.color)
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
            .fill(
                LinearGradient(
                    colors: [
                        accent.opacity(0.2),
                        accent.opacity(0.09),
                        Color(.secondarySystemBackground).opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
                    .stroke(settings.themeAccent.color.opacity(0.2), lineWidth: 1)
            )
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
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(settings.themeAccent.color.opacity(0.08))
        )
    }
}
