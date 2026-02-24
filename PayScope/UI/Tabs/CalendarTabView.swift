import SwiftUI
import SwiftData
import Combine
import UIKit

struct CalendarTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]
    @Query(sort: \NetWageMonthConfig.monthStart) private var netConfigs: [NetWageMonthConfig]
    @Query(sort: \HolidayCalendarDay.date) private var importedHolidays: [HolidayCalendarDay]
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
    @State private var monthChangeDirection: MonthChangeDirection = .next
    @State private var weekdayColumnsVisible = true
    @State private var dayColumnsVisible = true

    private let service = CalculationService()
    private let holidayImporter = HolidayImportService()
    private let previewRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let calendarContentHorizontalPadding: CGFloat = 16
    private let todayPreviewEdgePadding: CGFloat = 5
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
    private let monthChangeAnimation = Animation.easeInOut(duration: 0.24)
    private let weekdayColumnAnimationDuration: Double = 0.18
    private let weekdayColumnAnimationStagger: Double = 0.035

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                monthHeader
                monthSummaryBar
                weekdayHeader
                calendarSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        if isOffline {
                            Text("offline")
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
                    Button {
                        activeSheet = .stats
                    } label: {
                        Image(systemName: "chart.bar")
                    }
                    .accessibilityLabel("Statistik öffnen")
                }
            }
            .task(id: holidayImportTaskKey) {
                await importHolidaysIfNeededForDisplayedMonth()
            }
            .onReceive(previewRefreshTimer) { value in
                now = value
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    jumpToCurrentMonth()
                    activeSheet = .today
                } label: {
                    todayPreviewCard
                }
                .buttonStyle(.plain)
                .padding(.horizontal, todayPreviewEdgePadding)
                .padding(.top, todayPreviewEdgePadding)
                .padding(.bottom, todayPreviewBottomInsetCompensation)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case let .day(date):
                    DayEditorView(date: date.startOfDayLocal(), settings: settings)
                case .today:
                    TodayFocusView(settings: settings)
                        .presentationDetents([.fraction(0.65)])
                        .presentationDragIndicator(.visible)
                        .payScopeSheetSurface(accent: settings.themeAccent.color)
                case .stats:
                    StatsTabView(settings: settings, referenceMonth: displayedMonth)
                        .payScopeSheetSurface(accent: settings.themeAccent.color)
                case .settings:
                    SettingsTabView(settings: settings)
                }
            }
            .sheet(isPresented: $showNetWageConfig) {
                if let config = netConfig(for: netConfigSheetMonth) {
                    NetWageConfigSheet(config: config)
                        .payScopeSheetSurface(accent: settings.themeAccent.color)
                } else {
                    ProgressView("Netto-Konfiguration wird geladen...")
                        .payScopeSheetSurface(accent: settings.themeAccent.color)
                }
            }
            .confirmationDialog(
                "Segmente löschen?",
                isPresented: Binding(
                    get: { deleteCandidateDate != nil },
                    set: { if !$0 { deleteCandidateDate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Bestätigen", role: .destructive) {
                    if let deleteCandidateDate {
                        deleteSegments(for: deleteCandidateDate)
                    }
                    deleteCandidateDate = nil
                }
                Button("Abbrechen", role: .cancel) {
                    deleteCandidateDate = nil
                }
            } message: {
                Text("Alle Segmente dieses Tages werden gelöscht.")
            }
        }
    }

    private var monthHeader: some View {
        ZStack {
            Text(germanMonthYear(displayedMonth))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .id(displayedMonth.startOfMonthLocal())
                .transition(
                    .asymmetric(
                        insertion: .move(edge: monthChangeDirection.monthInsertionEdge).combined(with: .opacity),
                        removal: .move(edge: monthChangeDirection.monthRemovalEdge).combined(with: .opacity)
                    )
                )

            HStack(spacing: 12) {
                calendarControlButton(systemImage: "chevron.left") {
                    shiftDisplayedMonth(by: -1)
                }
                Spacer()
                calendarControlButton(systemImage: "chevron.right") {
                    shiftDisplayedMonth(by: 1)
                }
            }
        }
    }

    private var displayedMonthBounds: (Date, Date) {
        guard let interval = Calendar.current.dateInterval(of: .month, for: displayedMonth) else {
            let now = Date().startOfDayLocal()
            return (now, now)
        }
        return (interval.start, interval.end.addingTimeInterval(-1))
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
                title: "Lohn Brutto",
                value: PayScopeFormatters.currencyString(cents: summary.totalCents)
            )

            Button {
                netConfigSheetMonth = displayedMonth.startOfMonthLocal()
                ensureNetConfigExists(for: netConfigSheetMonth)
                showNetWageConfig = true
            } label: {
                monthMetricChip(
                    title: "Lohn Netto",
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
        modelContext.insert(config)
        modelContext.persistIfPossible()
    }

    private func monthMetricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.9))
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 16, emphasis: 0.22)
    }

    private var weekdayHeader: some View {
        var germanCalendar = Calendar.current
        germanCalendar.locale = Locale(identifier: "de_DE")
        let symbols = germanCalendar.shortWeekdaySymbols
        let ordered = settings.weekStart == .monday ? Array(symbols[1...6] + [symbols[0]]) : symbols

        return HStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .opacity(weekdayColumnsVisible ? 1 : 0)
                    .offset(x: weekdayColumnsVisible ? 0 : monthChangeDirection.weekdayColumnOffset)
                    .animation(
                        .easeOut(duration: weekdayColumnAnimationDuration)
                            .delay(Double(monthChangeDirection.weekdayAnimationRank(for: index, total: ordered.count)) * weekdayColumnAnimationStagger),
                        value: weekdayColumnsVisible
                    )
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
                ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                    let dayDate = date.startOfDayLocal()
                    let entry = entriesByDate[dayDate]
                    let isHoliday = holidayDateSet.contains(dayDate) || entry?.type == .holiday
                    let weekBadgeData = shouldShowWeekBadge && index % 7 == 0
                        ? weekBadgesByDate[dayDate]
                        : nil
                    let columnIndex = index % 7

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
                    .opacity(dayColumnsVisible ? 1 : 0)
                    .offset(x: dayColumnsVisible ? 0 : monthChangeDirection.weekdayColumnOffset)
                    .animation(
                        .easeOut(duration: weekdayColumnAnimationDuration)
                            .delay(Double(monthChangeDirection.weekdayAnimationRank(for: columnIndex, total: 7)) * weekdayColumnAnimationStagger),
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
        let hasSegments = (entry?.segments.isEmpty == false)
        let isToday = Calendar.current.isDateInToday(dayDate)
        let isWeekend = Calendar.current.isDateInWeekend(dayDate)
        let categoryTint = categoryTintColor(for: visibleEntry?.type, isHoliday: isHoliday)
        let dayBackgroundColors = dayCellBackgroundColors(
            isWeekend: isWeekend,
            isHoliday: isHoliday,
            hasEntry: visibleEntry != nil,
            categoryTint: categoryTint
        )
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

                if let visibleEntry {
                    cellMetric(for: visibleEntry, result: result)
                }

                if let result {
                    switch result {
                    case .warning:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    case .error:
                        Image(systemName: "xmark.octagon.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    case .ok:
                        EmptyView()
                    }
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: dayBackgroundColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.6) {
            guard hasSegments else { return }
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
        if !entry.segments.isEmpty { return true }
        if (entry.manualWorkedSeconds ?? 0) > 0 { return true }
        if (entry.creditedOverrideSeconds ?? 0) > 0 { return true }
        if entry.type != .work { return true }
        return !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func dayCellBackgroundColors(
        isWeekend: Bool,
        isHoliday: Bool,
        hasEntry: Bool,
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
            settings.themeAccent.color.opacity(hasEntry ? 0.14 : 0.06),
            Color(.systemBackground).opacity(0.98)
        ]
    }

    private func dayNumberForegroundColor(
        isWeekend: Bool,
        isHoliday: Bool,
        categoryTint: Color?
    ) -> Color {
        if isHoliday {
            return .orange
        }
        if let categoryTint {
            return categoryTint
        }
        return isWeekend ? .secondary : .primary
    }

    private func categoryTintColor(for dayType: DayType?, isHoliday: Bool) -> Color? {
        if isHoliday {
            return .orange
        }
        return dayType?.tint
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
        let weekStart = service.weekStartDate(for: day, weekStart: settings.weekStart)
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
        calendar.firstWeekday = settings.weekStart == .sunday ? 1 : 2
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
            .foregroundStyle(entry.type.tint)
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
            categoryIconRow
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

    private func calendarCellHoursSeconds(for entry: DayEntry, result: ComputationResult?) -> Int {
        switch settings.effectiveCalendarHoursBreakMode {
        case .withoutBreak:
            return secondsFromResult(result)
        case .withBreak:
            let grossFromSegments = entry.segments.reduce(0) { partial, segment in
                partial + max(0, Int(segment.end.timeIntervalSince(segment.start)))
            }
            if grossFromSegments > 0 {
                return grossFromSegments
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

    private func shortCurrency(cents: Int) -> String {
        let value = NSNumber(value: Double(cents) / 100)
        return Self.compactCurrencyFormatter.string(from: value) ?? "0"
    }

    private func monthDates() -> [Date] {
        guard
            let interval = Calendar.current.dateInterval(of: .month, for: displayedMonth),
            let monthFirstWeek = Calendar.current.dateInterval(of: .weekOfMonth, for: interval.start),
            let monthLastWeek = Calendar.current.dateInterval(of: .weekOfMonth, for: interval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var dates: [Date] = []
        var current = monthFirstWeek.start
        while current < monthLastWeek.end {
            dates.append(current)
            current = current.addingDays(1)
        }
        return dates
    }

    private func deleteSegments(for date: Date) {
        guard let existing = entries.first(where: { $0.date.isSameLocalDay(as: date.startOfDayLocal()) }) else { return }
        existing.segments.removeAll()
        modelContext.persistIfPossible()
        exportICloudSnapshot()
    }

    private func exportICloudSnapshot() {
        ICloudSettingsSync.export(
            settings: settings,
            entries: entries,
            netWageConfigs: netConfigs,
            holidayDays: importedHolidays
        )
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
            _ = try await holidayImporter.importHolidays(
                year: year,
                countryCode: countryCode,
                subdivisionCode: subdivisionCode,
                modelContext: modelContext
            )
            holidayImportKeys.insert(importKey)
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
            shiftDisplayedMonth(by: 1)
        } else {
            shiftDisplayedMonth(by: -1)
        }
    }

    private func shiftDisplayedMonth(by delta: Int) {
        guard delta != 0 else { return }
        monthChangeDirection = delta > 0 ? .next : .previous

        withAnimation(monthChangeAnimation) {
            displayedMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        }
        triggerMonthChangeAnimations()
    }

    private func jumpToCurrentMonth() {
        let currentMonth = displayedMonth.startOfMonthLocal()
        let targetMonth = Date().startOfMonthLocal()
        guard !currentMonth.isSameLocalDay(as: targetMonth) else {
            displayedMonth = Date()
            return
        }

        monthChangeDirection = targetMonth > currentMonth ? .next : .previous
        withAnimation(monthChangeAnimation) {
            displayedMonth = targetMonth
        }
        triggerMonthChangeAnimations()
    }

    private func triggerMonthChangeAnimations() {
        withTransaction(Transaction(animation: nil)) {
            weekdayColumnsVisible = false
            dayColumnsVisible = false
        }
        DispatchQueue.main.async {
            weekdayColumnsVisible = true
            dayColumnsVisible = true
        }
    }

    private var todayPreviewCard: some View {
        let cardCornerRadius = todayPreviewCornerRadius

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Text("Heute • ")
                        .foregroundStyle(settings.themeAccent.color.opacity(0.94))

                    Text(PayScopeFormatters.day.string(from: todayStart))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: todayShiftIcon)
                            .font(.subheadline.weight(.bold))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(settings.themeAccent.color)
                            .background(
                                settings.themeAccent.color.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                        if todayHasShiftDeviation {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(todayWorkedDisplay)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 10)

            CompletionRing(
                progress: todayShiftCompletionFraction,
                accent: settings.themeAccent.color
            )
            .frame(width: 30, height: 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: cardCornerRadius, emphasis: 0.36)
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(settings.themeAccent.color.opacity(0.34), lineWidth: 1.2)
        )
        .shadow(color: settings.themeAccent.color.opacity(0.18), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heute Vorschau")
        .accessibilityValue("\(todayWorkedDisplay), \(todayShiftCompletionPercent)% der Schichtlänge")
    }

    private var todayPreviewCornerRadius: CGFloat {
        deviceDisplayCornerRadius + todayPreviewEdgePadding
    }

    private var todayPreviewBottomInsetCompensation: CGFloat {
        todayPreviewEdgePadding - deviceBottomSafeAreaInset
    }

    private var deviceDisplayCornerRadius: CGFloat {
        guard let keyWindow else {
            return 0
        }

        let windowCornerRadius = keyWindow.layer.cornerRadius
        if windowCornerRadius > 0 {
            return windowCornerRadius
        }
        return max(0, deviceBottomSafeAreaInset)
    }

    private var deviceBottomSafeAreaInset: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 0
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private var todayStart: Date {
        now.startOfDayLocal()
    }

    private var todayEntry: DayEntry? {
        entries.first(where: { $0.date.isSameLocalDay(as: todayStart) })
    }

    private var todayShiftIcon: String {
        todayEntry?.type.icon ?? "calendar.badge.clock"
    }

    private var todayHasShiftDeviation: Bool {
        todayEntry?.creditedOverrideSeconds != nil
    }

    private var todayWorkedDisplay: String {
        "\(PayScopeFormatters.hhmmString(seconds: todayWorkedSeconds)) h"
    }

    private var todayWorkedSeconds: Int {
        workedSeconds(until: now, for: todayEntry)
    }

    private var todayShiftCompletionFraction: Double {
        guard todayShiftLengthSeconds > 0 else { return 0 }
        let fraction = Double(todayWorkedSeconds) / Double(todayShiftLengthSeconds)
        return min(max(fraction, 0), 1)
    }

    private var todayShiftCompletionPercent: Int {
        Int((todayShiftCompletionFraction * 100).rounded())
    }

    private var todayShiftLengthSeconds: Int {
        shiftLengthSeconds(for: todayEntry)
    }

    private var plannedDaySeconds: Int? {
        guard let weeklyTarget = settings.weeklyTargetSeconds else { return nil }
        let days = max(1, settings.scheduledWorkdaysCount)
        return max(0, Int((Double(weeklyTarget) / Double(days)).rounded()))
    }

    private func shiftLengthSeconds(for day: DayEntry?) -> Int {
        guard let day else {
            return max(0, plannedDaySeconds ?? 0)
        }
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }

        let totalFromSegments = day.segments.reduce(0) { partial, segment in
            let segmentSeconds = max(0, Int(segment.end.timeIntervalSince(segment.start)) - max(0, segment.breakSeconds))
            return partial + segmentSeconds
        }
        if totalFromSegments > 0 {
            return totalFromSegments
        }
        return max(0, plannedDaySeconds ?? 0)
    }

    private func workedSeconds(until now: Date, for day: DayEntry?) -> Int {
        guard let day else { return 0 }
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }

        return day.segments.reduce(0) { partial, segment in
            guard now > segment.start else { return partial }
            let effectiveEnd = min(now, segment.end)
            let elapsedSeconds = max(0, Int(effectiveEnd.timeIntervalSince(segment.start)))
            let totalSegmentSeconds = max(1, Int(segment.end.timeIntervalSince(segment.start)))
            let breakSeconds = max(0, segment.breakSeconds)
            let elapsedBreak = Int((Double(breakSeconds) * Double(elapsedSeconds) / Double(totalSegmentSeconds)).rounded())
            return partial + max(0, elapsedSeconds - elapsedBreak)
        }
    }
}

private enum MonthChangeDirection {
    case next
    case previous

    var monthInsertionEdge: Edge {
        switch self {
        case .next:
            return .trailing
        case .previous:
            return .leading
        }
    }

    var monthRemovalEdge: Edge {
        switch self {
        case .next:
            return .leading
        case .previous:
            return .trailing
        }
    }

    var weekdayColumnOffset: CGFloat {
        switch self {
        case .next:
            return 12
        case .previous:
            return -12
        }
    }

    func weekdayAnimationRank(for index: Int, total: Int) -> Int {
        switch self {
        case .next:
            return max(0, total - index - 1)
        case .previous:
            return index
        }
    }
}

private struct WeekBadgeData {
    let weekNumber: Int?
    let detailText: String?
}

private enum CalendarSheet: Identifiable {
    case day(Date)
    case today
    case stats
    case settings

    var id: String {
        switch self {
        case let .day(date):
            return "day-\(date.timeIntervalSinceReferenceDate)"
        case .today:
            return "today"
        case .stats:
            return "stats"
        case .settings:
            return "settings"
        }
    }
}

private struct CompletionRing: View {
    let progress: Double
    let accent: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    accent.opacity(0.2),
                    lineWidth: 6
                )

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    accent,
                    style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

private struct TodayCompletionPieIcon: View {
    let progress: Double
    let accent: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: side / 2, y: side / 2)
            let radius = side / 2

            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))

                if clampedProgress > 0 {
                    Path { path in
                        path.move(to: center)
                        path.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + (clampedProgress * 360)),
                            clockwise: false
                        )
                        path.closeSubpath()
                    }
                    .fill(.white.opacity(0.9))
                }

                Circle()
                    .fill(accent.opacity(0.56))
                    .padding(side * 0.26)

                Circle()
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct NetWageConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var config: NetWageMonthConfig

    @State private var wageTaxText = ""
    @State private var pensionText = ""
    @State private var allowanceText = ""
    @State private var bonusTexts: [String] = []
    @State private var newBonusText = ""

    var body: some View {
        NavigationStack {
            Form {
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
        config.wageTaxPercent = wageTax
        config.pensionPercent = pension
        config.monthlyAllowanceEuro = allowance
        config.bonusesCSV = bonusTexts
            .compactMap { normalizedDouble(from: $0) }
            .map { String(format: "%.2f", $0) }
            .joined(separator: ";")
        wageTaxText = formatForDisplay(from: wageTaxText) ?? ""
        pensionText = formatForDisplay(from: pensionText) ?? ""
        allowanceText = formatForDisplay(from: allowanceText) ?? ""
        bonusTexts = bonusTexts.map { formatForDisplay(from: $0) ?? $0 }
        modelContext.persistIfPossible()
    }
}
