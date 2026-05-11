import SwiftUI
import Combine
import SwiftData

struct CalendarTabView: View {
    private enum DataLoadMode: Equatable {
        case localOnly
        case fullSync
    }

    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.scenePhase) private var scenePhase
    private let localStore = LocalDayEntryStore.shared
    @State private var entries: [DayEntry] = []
    @State private var tipEntries: [TipEntry] = []
    @State private var netConfigs: [NetWageMonthConfig] = []
    @State private var importedHolidays: [HolidayCalendarDay] = []
    @Bindable var settings: Settings
    let isOffline: Bool

    @State private var displayedMonth = Date()
    @State private var activeSheet: CalendarSheet?
    @State private var showNetWageConfig = false
    @State private var netConfigSheetMonth = Date().startOfMonthLocal()
    @State private var deleteCandidateDate: Date?
    @State private var longPressTriggeredDate: Date?
    @State private var holidayImportKeys: Set<String> = []
    @State private var now = Date()
    @State private var dayColumnsVisible = true
    @State private var dayFlipDirection: DayFlipDirection = .fromRightToLeft
    @State private var toolbarContainerWidth: CGFloat = 0
    @State private var isLoadingData = false
    @State private var pendingLoadAfterCurrentCycle = false
    @State private var showUnsyncedIndicator = false

    @State private var notificationCancellable: AnyCancellable?
    @State private var isInitialLoading = true
    @State private var initialLoadTask: Task<Void, Never>?

    private let service = CalculationService()
    private let holidayImporter = HolidayImportService()
    private let previewRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let calendarContentHorizontalPadding: CGFloat = 16
    private let calendarBottomToolbarSpacerHeight: CGFloat = 12
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "yyyy"
        return formatter
    }()
    private static let compactCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    private let dayColumnFlipDuration: Double = 0.3
    private let unsyncedIndicatorDebounce = RunLoop.SchedulerTimeType.Stride.milliseconds(900)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                monthHeader
                monthSummaryBar
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("PayScope")
                            .font(.headline.weight(.semibold))
                        if showUnsyncedIndicator {
                            Text("Nicht Synchronisiert")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Einstellungen öffnen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if settings.effectiveShowTipsButton {
                        Button {
                            activeSheet = .tips(displayedMonth.startOfMonthLocal())
                        } label: {
                            if settings.effectiveShowTipsButtonAmount {
                                Label(displayedMonthTipTotalText, systemImage: "eurosign.circle")
                            } else {
                                Image(systemName: "eurosign.circle")
                            }
                        }
                        .accessibilityLabel("Trinkgeld öffnen")
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            jumpToCurrentMonth()
                            activeSheet = .today
                        } label: {
                            todayBottomBarPill
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
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
            .task {
                await runInitialLoadingSequence()
            }
            .onAppear {
                notificationCancellable = NotificationCenter.default.publisher(for: .dayEntriesDidChange)
                    .sink { _ in
                        Task { await loadData(mode: .localOnly) }
                    }
            }
            .onDisappear {
                notificationCancellable?.cancel()
                notificationCancellable = nil
                initialLoadTask?.cancel()
                initialLoadTask = nil
                withTransaction(Transaction(animation: nil)) {
                    dayColumnsVisible = true
                }
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
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                guard activeSheet == nil else { return }
                Task { await loadData(mode: .fullSync) }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case let .day(date):
                    ShiftViewSheet(
                        date: date.startOfDayLocal(),
                        entry: entry(for: date),
                        entries: entries,
                        settings: settings,
                        onDaySaved: applyDayEditorChange
                    )
                case .today:
                    TodayFocusView(settings: settings)
                        .presentationDetents([.fraction(0.68), .large])
                        .presentationDragIndicator(.visible)
                        .payScopeSheetSurface(accent: settings.themeAccent.color)
                case .settings:
                    SettingsTabView(settings: settings)
                case let .tips(month):
                    TipEntrySheet(month: month, settings: settings) {
                        Task { await loadTipsForDisplayedMonth() }
                    }
                    .environmentObject(cloudKitService)
                    .payScopeSheetSurface(accent: settings.themeAccent.color)
                }
            }
            .sheet(isPresented: $showNetWageConfig) {
                if let idx = netConfigs.firstIndex(where: { $0.monthStart.isSameLocalDay(as: netConfigSheetMonth) }) {
                    NetWageConfigSheet(
                        config: $netConfigs[idx],
                        onPersistDefaults: persistNetDefaultsToSettings
                    )
                        .environmentObject(cloudKitService)
                        .payScopeSheetSurface(accent: settings.themeAccent.color)
                } else {
                    VStack(spacing: 12) {
                        ProgressView("Netto-Konfiguration wird geladen...")
                        Button("Erneut laden") {
                            ensureNetConfigExists(for: netConfigSheetMonth)
                        }
                    }
                    .task {
                        ensureNetConfigExists(for: netConfigSheetMonth)
                    }
                    .payScopeSheetSurface(accent: settings.themeAccent.color)
                }
            }
            .confirmationDialog(
                "Tag löschen?",
                isPresented: Binding(
                    get: { deleteCandidateDate != nil },
                    set: { if !$0 { deleteCandidateDate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Bestätigen", role: .destructive) {
                    if let deleteCandidateDate {
                        deleteDayEntry(for: deleteCandidateDate)
                    }
                    deleteCandidateDate = nil
                }
                Button("Abbrechen", role: .cancel) {
                    deleteCandidateDate = nil
                }
            } message: {
                Text("Der komplette Tageseintrag wird gelöscht.")
            }
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

    private var monthHeader: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(germanMonth(displayedMonth))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .id(displayedMonth.startOfMonthLocal())

                Text(yearString(displayedMonth))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .id(Calendar.current.component(.year, from: displayedMonth))
            }

            HStack(spacing: 12) {
                calendarControlButton(systemImage: "chevron.left") {
                    shiftDisplayedMonth(by: -1, flipDirection: .fromLeftToRight)
                }
                Spacer()
                calendarControlButton(systemImage: "chevron.right") {
                    shiftDisplayedMonth(by: 1, flipDirection: .fromRightToLeft)
                }
            }
        }
    }

    private func germanMonth(_ date: Date) -> String {
        Self.monthFormatter.string(from: date)
    }

    private func yearString(_ date: Date) -> String {
        Self.yearFormatter.string(from: date)
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
        PayScopeFormatters.currencyString(cents: tipEntries.reduce(0) { $0 + $1.amountCents })
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

        return HStack(spacing: 8) {
            monthMetricChip(
                title: "Stunden",
                value: PayScopeFormatters.hhmmString(seconds: summary.totalSeconds)
            )
            monthMetricChip(
                title: "Brutto",
                value: PayScopeFormatters.currencyString(cents: summary.totalCents)
            )

            Button {
                netConfigSheetMonth = displayedMonth.startOfMonthLocal()
                ensureNetConfigExists(for: netConfigSheetMonth)
                showNetWageConfig = true
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

        tipEntries = mergeTipEntriesKeepingNewest(local: localTips, remote: remoteTips)
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
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 16, emphasis: 0.22)
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
            let spacing: CGFloat = 8
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
                    let hiddenAngle = dayFlipDirection.hiddenAngle

                    Group {
                        if Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
                            dayCell(
                                for: dayDate,
                                height: cellHeight,
                                entry: entry,
                                result: dayResultsByDate[dayDate],
                                isHoliday: isHoliday,
                                weekBadgeData: weekBadgeData
                            )
                        } else if date > displayedMonthBounds.1 {
                            adjacentMonthCell(for: dayDate, height: cellHeight, isNextMonth: true, weekBadgeData: weekBadgeData)
                        } else {
                            adjacentMonthCell(for: dayDate, height: cellHeight, isNextMonth: false, weekBadgeData: weekBadgeData)
                        }
                    }
                    .rotation3DEffect(
                        .degrees(dayColumnsVisible ? 0 : hiddenAngle),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: dayFlipDirection.flipAnchor,
                        perspective: 0.72
                    )
                    .offset(x: dayColumnsVisible ? 0 : dayFlipDirection.hiddenOffset)
                    .opacity(dayColumnsVisible ? 1 : 0)
                    .animation(
                        .easeOut(duration: dayColumnFlipDuration),
                        value: dayColumnsVisible
                    )
                }
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
                DragGesture(minimumDistance: 24)
                    .onEnded { gesture in
                        handleMonthSwipe(gesture)
                    }
            )
    }

    private func dayCell(
        for dayDate: Date,
        height: CGFloat,
        entry: DayEntry?,
        result: ComputationResult?,
        isHoliday: Bool,
        weekBadgeData: WeekBadgeData?
    ) -> some View {
        let visibleEntry = entry.flatMap { isVisibleInCalendarCell($0) ? $0 : nil }
        let isToday = Calendar.current.isDateInToday(dayDate)
        let isWeekend = Calendar.current.isDateInWeekend(dayDate)
        let categoryTint = categoryTintColor(for: visibleEntry?.type, isHoliday: isHoliday)
        let hasSavedShift = hasSavedShift(in: visibleEntry)
        let dayBackgroundColors = dayCellBackgroundColors(
            isWeekend: isWeekend,
            isHoliday: isHoliday,
            categoryTint: hasSavedShift ? nil : categoryTint
        )
        let dayCardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let numberTopPadding = max(8, (height * 0.38) - 24)

        return Button {
            if let longPressTriggeredDate, longPressTriggeredDate.isSameLocalDay(as: dayDate) {
                self.longPressTriggeredDate = nil
                return
            }
            activeSheet = .day(dayDate)
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
                        cellMetric(for: visibleEntry, result: result)
                            .id(metricIdentity(for: visibleEntry, result: result))
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                )
                            )
                    }
                }
                .animation(.easeOut(duration: 0.22), value: metricAnimationKey(for: visibleEntry, result: result))

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
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                    }
                }
                .clipShape(dayCardShape)
            )
            .animation(.easeOut(duration: 0.22), value: hasSavedShift)
            .overlay(
                dayCardShape
                    .stroke(.white.opacity(0.2), lineWidth: 0.9)
            )
            .overlay(alignment: .topLeading) {
                if let weekBadgeData {
                    weekBadgeView(weekBadgeData, muted: isWeekend && !isHoliday)
                        .padding(.top, 7)
                        .padding(.leading, 7)
                }
            }
            .overlay(
                dayCardShape
                    .stroke(
                        isToday ? settings.themeAccent.color.opacity(0.52) : settings.themeAccent.color.opacity(0.2),
                        lineWidth: isToday ? 1.4 : 1
                    )
            )
            .shadow(
                color: isToday ? settings.themeAccent.color.opacity(0.18) : .black.opacity(0.04),
                radius: isToday ? 9 : 5,
                x: 0,
                y: isToday ? 6 : 3
            )
        }
        .buttonStyle(.plain)
        .contentShape(dayCardShape)
        .onLongPressGesture(minimumDuration: 0.6) {
            guard entry != nil else { return }
            longPressTriggeredDate = dayDate
            deleteCandidateDate = dayDate
        }
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
        return !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func dayCellBackgroundColors(
        isWeekend: Bool,
        isHoliday: Bool,
        categoryTint: Color?
    ) -> [Color] {
        if isWeekend && isHoliday {
            return [
                Color(.tertiarySystemFill).opacity(0.84),
                Color.orange.opacity(0.18),
                Color(.secondarySystemFill).opacity(0.72)
            ]
        }

        if isHoliday {
            return [
                Color.orange.opacity(0.2),
                Color.orange.opacity(0.09),
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

    private func hasSavedShift(in entry: DayEntry?) -> Bool {
        guard let entry else { return false }
        if let start = entry.shiftStart, let end = entry.shiftEnd, end > start {
            return true
        }
        return false
    }

    private func dayNumberForegroundColor(
        isWeekend: Bool,
        isHoliday: Bool,
        categoryTint: Color?
    ) -> Color {
        if isHoliday {
            return DayType.holiday.tint(for: settings.themeAccent)
        }
        if let categoryTint {
            return categoryTint
        }
        return isWeekend ? .secondary : .primary
    }

    private func categoryTintColor(for dayType: DayType?, isHoliday: Bool) -> Color? {
        if isHoliday {
            return DayType.holiday.tint(for: settings.themeAccent)
        }
        return dayType?.tint(for: settings.themeAccent)
    }

    private func adjacentMonthCell(for date: Date, height: CGFloat, isNextMonth: Bool, weekBadgeData: WeekBadgeData?) -> some View {
        let dayDate = date.startOfDayLocal()
        let fillOpacity: Double = isNextMonth ? 0.38 : 0.24
        let textOpacity: Double = isNextMonth ? 0.34 : 0.5

        return VStack(spacing: 0) {
            Text("\(Calendar.current.component(.day, from: dayDate))")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary.opacity(textOpacity))
                .padding(.top, max(8, (height * 0.38) - 24))
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        )
        .overlay(alignment: .topLeading) {
            if let weekBadgeData {
                weekBadgeView(weekBadgeData, muted: true)
                    .padding(.top, 7)
                    .padding(.leading, 7)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.gray.opacity(isNextMonth ? 0.22 : 0.14), lineWidth: 1)
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
        let weekStart = service.weekStartDate(for: day, weekStart: .monday)
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
    private func cellMetric(for entry: DayEntry, result: ComputationResult?) -> some View {
        let hasShiftDeviation = entry.creditedOverrideSeconds != nil
        let typeIcon = Image(systemName: entry.type.icon)
            .font(.caption2)
            .foregroundStyle(entry.type.tint(for: settings.themeAccent))
        let categoryIconRow = HStack(spacing: 4) {
            typeIcon
            if hasShiftDeviation {
                Image(systemName: "pencil")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }

        switch settings.calendarCellDisplayMode ?? .dot {
        case .dot:
            if let shiftTime = shiftTimeRangeText(for: entry) {
                HStack(spacing: 4) {
                    categoryIconRow
                    Text(shiftTime)
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            } else {
                categoryIconRow
            }
        case .hours:
            let seconds = calendarCellHoursSeconds(for: entry, result: result)
            VStack(spacing: 2) {
                categoryIconRow
                Text(PayScopeFormatters.hhmmString(seconds: seconds))
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
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
            VStack(spacing: 2) {
                categoryIconRow
                Text(shortCurrency(cents: cents))
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }

    private func shiftTimeRangeText(for entry: DayEntry) -> String? {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
            return nil
        }
        return "\(PayScopeFormatters.time.string(from: start))–\(PayScopeFormatters.time.string(from: end))"
    }

    private func metricIdentity(for entry: DayEntry, result: ComputationResult?) -> String {
        "\(entry.updatedAt.timeIntervalSinceReferenceDate)-\(metricAnimationKey(for: entry, result: result))"
    }

    private func metricAnimationKey(for entry: DayEntry?, result: ComputationResult?) -> String {
        guard let entry else { return "none" }
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
        return "\(entry.type.rawValue)-\(entry.updatedAt.timeIntervalSinceReferenceDate)-\(shiftKey)-\(resultKey)"
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
        localStore.delete(on: date)

        Task { @MainActor in
            do {
                try await cloudKitService.deleteDayEntry(on: date)
            } catch {
                #if DEBUG
                print("Failed to delete day entry for \(date), local tombstone kept for retry: \(error)")
                #endif
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

        let start = Date().addingDays(-365)
        let end = Date().addingDays(365)
        let interval = DateInterval(start: start, end: end)

        let localEntries = localStore.loadAll(in: interval)
        let localSnapshot = deduplicateEntriesByLocalDayKeepingNewest(localEntries)
        if mode == .localOnly || entries.isEmpty {
            // Cold start: show persisted data immediately, then refresh from cloud.
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
            // Cloud-first: prefer iCloud data when reachable.
            var cloudEntries = deduplicateEntriesByLocalDayKeepingNewest(
                try await cloudKitService.fetchDayEntries(in: interval)
            )

            // Sync local deletions to cloud first (LWW).
            let didSyncDeletes = await syncPendingLocalDeletionsToCloud(cloudEntries: cloudEntries)
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

            // UI should reflect newest known state immediately, even if CloudKit query is briefly stale.
            let mergedForUI = mergeEntriesByLocalDayKeepingNewest(
                local: localSnapshot,
                remote: cloudEntriesWithoutLocallyDeleted
            )

            applyEntriesIfChanged(mergedForUI)
            localStore.upsertMany(cloudEntriesWithoutLocallyDeleted, notify: false)

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
            hasher.combine(value.notes)
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

    private func syncPendingLocalDeletionsToCloud(cloudEntries: [DayEntry]) async -> Bool {
        let cloudByDay = Dictionary(
            cloudEntries.map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        let tombstones = localStore.loadDeletionTombstones()
        guard !tombstones.isEmpty else { return false }

        var changedAny = false
        for tombstone in tombstones {
            let key = dayKey(tombstone.date)
            guard let cloud = cloudByDay[key] else {
                localStore.clearDeletionTombstone(on: tombstone.date)
                changedAny = true
                continue
            }

            if tombstone.lastModified >= cloud.updatedAt {
                do {
                    try await cloudKitService.deleteDayEntry(on: tombstone.date)
                    localStore.clearDeletionTombstone(on: tombstone.date)
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
        lhs.notes == rhs.notes &&
        lhs.breakSeconds == rhs.breakSeconds &&
        lhs.manualWorkedSeconds == rhs.manualWorkedSeconds &&
        lhs.creditedOverrideSeconds == rhs.creditedOverrideSeconds &&
        lhs.shiftStart == rhs.shiftStart &&
        lhs.shiftEnd == rhs.shiftEnd
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

    private func calendarControlButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: 40, height: 40)
                .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 14, emphasis: 0.26)
        }
        .buttonStyle(.plain)
    }

    private func handleMonthSwipe(_ gesture: DragGesture.Value) {
        let horizontal = gesture.translation.width
        let vertical = gesture.translation.height
        guard abs(horizontal) > abs(vertical), abs(horizontal) >= 48 else {
            return
        }

        if horizontal < 0 {
            shiftDisplayedMonth(by: 1, flipDirection: .fromRightToLeft)
        } else {
            shiftDisplayedMonth(by: -1, flipDirection: .fromLeftToRight)
        }
    }

    private func shiftDisplayedMonth(by delta: Int, flipDirection: DayFlipDirection) {
        guard delta != 0 else { return }
        triggerDayCardColumnFlip(direction: flipDirection)
        displayedMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    }

    private func triggerDayCardColumnFlip(direction: DayFlipDirection) {
        dayFlipDirection = direction

        withTransaction(Transaction(animation: nil)) {
            dayColumnsVisible = false
        }
        DispatchQueue.main.async {
            dayColumnsVisible = true
        }
    }

    private func jumpToCurrentMonth() {
        let currentMonth = displayedMonth.startOfMonthLocal()
        let targetMonth = Date().startOfMonthLocal()
        guard !currentMonth.isSameLocalDay(as: targetMonth) else {
            displayedMonth = Date()
            return
        }

        displayedMonth = targetMonth
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

private enum DayFlipDirection {
    case fromRightToLeft
    case fromLeftToRight

    var hiddenAngle: Double {
        switch self {
        case .fromRightToLeft:
            return -78
        case .fromLeftToRight:
            return 78
        }
    }

    var flipAnchor: UnitPoint {
        switch self {
        case .fromRightToLeft:
            return .trailing
        case .fromLeftToRight:
            return .leading
        }
    }

    var hiddenOffset: CGFloat {
        switch self {
        case .fromRightToLeft:
            return 22
        case .fromLeftToRight:
            return -22
        }
    }
}

private enum CalendarSheet: Identifiable {
    case day(Date)
    case today
    case settings
    case tips(Date)

    var id: String {
        switch self {
        case let .day(date):
            return "day-\(date.timeIntervalSinceReferenceDate)"
        case .today:
            return "today"
        case .settings:
            return "settings"
        case let .tips(month):
            return "tips-\(month.timeIntervalSinceReferenceDate)"
        }
    }
}

private struct CalendarTabToolbarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ShiftViewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let entry: DayEntry?
    let entries: [DayEntry]
    @Bindable var settings: Settings
    let onDaySaved: (Date, DayEntry?) -> Void

    @State private var showEditor = false

    private let service = CalculationService()
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private var dayStart: Date {
        date.startOfDayLocal()
    }

    private var accent: Color {
        entry?.type.tint(for: settings.themeAccent) ?? settings.themeAccent.color
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

    private var bodyTitle: String {
        entry?.type.label ?? "Kein Eintrag"
    }

    private var dateText: String {
        PayScopeFormatters.day.string(from: dayStart)
    }

    private var weekdayText: String {
        Self.weekdayFormatter.string(from: dayStart)
    }

    private var notesText: String? {
        let trimmed = entry?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let entry {
                        if hasFocusedMetrics(for: entry) {
                            focusedMetrics(for: entry)
                        }

                        if let status = statusMessage {
                            infoPanel(systemImage: status.icon, title: status.title, text: status.text, tint: status.tint)
                        }

                        if let notesText {
                            infoPanel(systemImage: "note.text", title: "Notizen", text: notesText, tint: .secondary)
                        }
                    } else {
                        emptyPanel
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
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

                ToolbarItem(placement: .principal) {
                    Text(dateText)
                        .font(.headline.weight(.semibold))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Bearbeiten")
                }
            }
            .sheet(isPresented: $showEditor) {
                DayEditorView(
                    date: dayStart,
                    settings: settings,
                    onDaySaved: onDaySaved
                )
            }
        }
        .presentationDetents([.fraction(entry == nil ? 0.38 : 0.58), .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.14))
                Image(systemName: entry?.type.icon ?? "calendar")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(bodyTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(weekdayText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .shiftViewPanel(accent: accent)
    }

    @ViewBuilder
    private func focusedMetrics(for entry: DayEntry) -> some View {
        VStack(spacing: 10) {
            if let timeText = timeRangeText(for: entry) {
                metricRow(icon: "clock.fill", title: "Schicht", value: timeText, tint: accent)
            }

            if shouldShowBreak(for: entry) {
                metricRow(
                    icon: "cup.and.saucer.fill",
                    title: "Pause",
                    value: PayScopeFormatters.hhmmString(seconds: max(0, entry.breakSeconds ?? 0)),
                    tint: .secondary
                )
            }

            if workedSeconds > 0 || entry.manualWorkedSeconds != nil || entry.type != .work {
                metricRow(
                    icon: "timer",
                    title: durationTitle(for: entry),
                    value: "\(PayScopeFormatters.hhmmString(seconds: workedSeconds)) h",
                    tint: accent
                )
            }

            if payCents > 0 {
                metricRow(
                    icon: "banknote.fill",
                    title: "Lohn",
                    value: PayScopeFormatters.currencyString(cents: payCents),
                    tint: .green
                )
            }

            if entry.creditedOverrideSeconds != nil {
                metricRow(
                    icon: "pencil.line",
                    title: "Wert",
                    value: "Manuell überschrieben",
                    tint: .secondary
                )
            }
        }
        .padding(14)
        .shiftViewPanel(accent: accent)
    }

    private var emptyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kein Eintrag")
                .font(.headline.weight(.semibold))
            Text("Für diesen Tag sind noch keine Schichtdaten gespeichert.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .shiftViewPanel(accent: settings.themeAccent.color)
    }

    private func metricRow(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .padding(.vertical, 4)
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

    private func timeRangeText(for entry: DayEntry) -> String? {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else { return nil }
        return ShiftTimeRange.displayRange(start: start, end: end)
    }

    private func shouldShowBreak(for entry: DayEntry) -> Bool {
        guard entry.type == .work else { return false }
        return (entry.breakSeconds ?? 0) > 0
    }

    private func hasFocusedMetrics(for entry: DayEntry) -> Bool {
        timeRangeText(for: entry) != nil ||
        shouldShowBreak(for: entry) ||
        workedSeconds > 0 ||
        entry.manualWorkedSeconds != nil ||
        entry.type != .work ||
        payCents > 0 ||
        entry.creditedOverrideSeconds != nil
    }

    private func durationTitle(for entry: DayEntry) -> String {
        if entry.type == .work, shouldShowBreak(for: entry) {
            return "Netto"
        }
        if entry.type == .manual {
            return "Dauer"
        }
        if entry.type == .vacation || entry.type == .holiday || entry.type == .sick {
            return "Anrechnung"
        }
        return "Dauer"
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
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accent.opacity(0.14), lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

private extension View {
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
    @State private var selectedDate: Date
    @State private var amountText = ""
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
        _selectedDate = State(initialValue: normalizedMonth)
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
            Form {
                Section {
                    LabeledContent("Monat", value: Self.monthFormatter.string(from: month))
                    LabeledContent("Summe", value: PayScopeFormatters.currencyString(cents: totalCents))
                }

                Section("Eintragen") {
                    DatePicker("Datum", selection: $selectedDate, in: dateRange, displayedComponents: .date)

                    HStack {
                        TextField("Betrag", text: $amountText)
                            .keyboardType(.decimalPad)
                        Text("EUR")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        addTip()
                    } label: {
                        Label("Trinkgeld hinzufügen", systemImage: "plus.circle.fill")
                    }
                    .disabled(parsedAmountCents() == nil)
                }

                Section("Einträge") {
                    if isLoading && tips.isEmpty {
                        ProgressView("Trinkgeld wird geladen...")
                    } else if sortedTips.isEmpty {
                        Text("Noch kein Trinkgeld in diesem Monat.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedTips) { tip in
                            HStack {
                                Text(Self.dayFormatter.string(from: tip.date))
                                Spacer(minLength: 12)
                                Text(PayScopeFormatters.currencyString(cents: tip.amountCents))
                                    .fontWeight(.semibold)
                            }
                        }
                        .onDelete(perform: deleteTips)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
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
            }
            .task {
                await loadTips()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
        } catch {
            tips = localTips
            errorMessage = "iCloud konnte nicht geladen werden. Lokale Einträge bleiben verfügbar."
        }

        isLoading = false
        onTipsChanged()
    }

    private func addTip() {
        guard let amountCents = parsedAmountCents() else { return }

        let tip = TipEntry(
            date: selectedDate.startOfDayLocal(),
            amountCents: amountCents,
            updatedAt: Date()
        )
        LocalTipEntryStore.shared.save(tip)
        tips = mergeTipEntriesKeepingNewest(local: tips + [tip], remote: [])
        amountText = ""
        errorMessage = nil
        onTipsChanged()

        Task {
            do {
                try await cloudKitService.saveTipEntry(tip)
                LocalTipEntryStore.shared.markSynced(tip)
            } catch {
                await MainActor.run {
                    errorMessage = "Trinkgeld wurde lokal gespeichert und später synchronisiert."
                }
            }
        }
    }

    private func deleteTips(at offsets: IndexSet) {
        let visibleTips = sortedTips
        for offset in offsets {
            let tip = visibleTips[offset]
            LocalTipEntryStore.shared.delete(tip)
            tips.removeAll { $0.id == tip.id }
            Task {
                do {
                    try await cloudKitService.deleteTipEntry(tip)
                } catch {
                    await MainActor.run {
                        errorMessage = "Eintrag wurde lokal gelöscht und später synchronisiert."
                    }
                }
            }
        }
        onTipsChanged()
    }

    private func parsedAmountCents() -> Int? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else { return nil }
        return Int((amount * 100).rounded())
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
