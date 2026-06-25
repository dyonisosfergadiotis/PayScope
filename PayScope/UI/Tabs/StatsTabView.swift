import SwiftUI
import Combine
#if canImport(Charts)
import Charts
#endif

struct StatsTabView: View {
    private enum DataLoadMode {
        case localOnly
        case fullSync
    }

    private enum StatsContentMode: String, CaseIterable, Identifiable {
        case pay
        case timeAccount

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pay:
                return "Lohn"
            case .timeAccount:
                return "Zeitkonto"
            }
        }

        var icon: String {
            switch self {
            case .pay:
                return "eurosign.circle.fill"
            case .timeAccount:
                return "plusminus.circle.fill"
            }
        }
    }

    private enum MonthSelectorStyle {
        case largeTitle
        case subtitle
    }

    private struct StatsBestDay: Sendable {
        let date: Date
        let seconds: Int
    }

    private struct StatsDayTypeBreakdownValue: Sendable {
        let type: DayType
        let count: Int
        let seconds: Int
    }

    private struct StatsDerivedSnapshot: Sendable {
        var key: String
        var monthSummary: TotalsSummary
        var activeDaysCount: Int
        var bestDay: StatsBestDay?
        var yearPayPoints: [MonthPayPoint]
        var yearAverageMonthlyCents: Int
        var dayTypeBreakdown: [StatsDayTypeBreakdownValue]
        var monthDailyPoints: [MonthDailyPoint]

        static let empty = StatsDerivedSnapshot(
            key: "",
            monthSummary: TotalsSummary(),
            activeDaysCount: 0,
            bestDay: nil,
            yearPayPoints: [],
            yearAverageMonthlyCents: 0,
            dayTypeBreakdown: [],
            monthDailyPoints: []
        )
    }

    @EnvironmentObject private var cloudKitService: CloudKitService
    @Bindable var settings: Settings
    @Binding var referenceMonth: Date
    var includesTimeAccount: Bool = true
    var isActive: Bool = true

    @State private var entries: [DayEntry] = []
    @State private var isLoadingData = false
    @State private var showMonthYearPicker = false
    @State private var selectedContentMode: StatsContentMode = .pay
    @State private var modeSelectionFeedbackTrigger = 0
    @State private var derivedSnapshot = StatsDerivedSnapshot.empty
    @State private var derivedSnapshotTask: Task<Void, Never>?
    @State private var pendingDerivedSnapshotKey = ""
    @Namespace private var statsModeNamespace

    private let localStore = LocalDayEntryStore.shared
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if includesTimeAccount {
                        statsModeRail
                    }

                    statsContent
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .navigationTitle("Statistik")
            .toolbarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    statsLargeTitle
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
        .sensoryFeedback(.selection, trigger: modeSelectionFeedbackTrigger)
        .task(id: dataLoadTaskKey) {
            guard isActive else { return }
            await loadData()
        }
        .task(id: statsDerivedSnapshotKey) {
            scheduleStatsDerivedSnapshotRecompute(key: statsDerivedSnapshotKey)
        }
        .onChange(of: includesTimeAccount) { _, includesTimeAccount in
            guard !includesTimeAccount, selectedContentMode == .timeAccount else { return }
            selectedContentMode = .pay
        }
        .onDisappear {
            derivedSnapshotTask?.cancel()
            derivedSnapshotTask = nil
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .dayEntriesDidChange)
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
        ) { _ in
            guard isActive else { return }
            Task { await loadData(mode: .localOnly) }
        }
    }

    private var dataLoadTaskKey: String {
        "\(referenceMonth.startOfMonthLocal().timeIntervalSinceReferenceDate)-active-\(isActive)"
    }

    private var statsDerivedSnapshotKey: String {
        var hasher = Hasher()
        hasher.combine(referenceMonth.startOfMonthLocal().timeIntervalSinceReferenceDate)
        hasher.combine(dayEntriesSignature(entries))
        hasher.combine(statsCalculationSettingsSignature)
        return String(hasher.finalize())
    }

    private var statsCalculationSettingsSignature: Int {
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
        return hasher.finalize()
    }

    @MainActor
    private func scheduleStatsDerivedSnapshotRecompute(key: String) {
        guard key != derivedSnapshot.key || pendingDerivedSnapshotKey != key else { return }

        derivedSnapshotTask?.cancel()
        pendingDerivedSnapshotKey = key

        let entrySnapshots = entries.map(CalculationInputSnapshot.init)
        let settingsSnapshot = CalculationSettingsSnapshot(settings)
        let referenceMonthStart = referenceMonth.startOfMonthLocal()

        derivedSnapshotTask = Task { @MainActor in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.makeStatsDerivedSnapshot(
                    key: key,
                    entries: entrySnapshots,
                    settings: settingsSnapshot,
                    referenceMonth: referenceMonthStart
                )
            }.value

            guard !Task.isCancelled else { return }
            guard pendingDerivedSnapshotKey == key else { return }
            derivedSnapshot = snapshot
        }
    }

    nonisolated private static func makeStatsDerivedSnapshot(
        key: String,
        entries: [CalculationInputSnapshot],
        settings: CalculationSettingsSnapshot,
        referenceMonth: Date
    ) -> StatsDerivedSnapshot {
        let calendar = Calendar.current
        let monthRange = calendar.dateInterval(of: .month, for: referenceMonth)
            ?? DateInterval(start: referenceMonth, duration: 24 * 60 * 60)
        let monthEnd = monthRange.end.addingTimeInterval(-1)
        let monthEntries = entries
            .filter(\.isRealTrackedDay)
            .filter { $0.date >= monthRange.start && $0.date < monthRange.end }
            .sorted { $0.date < $1.date }

        var context = CalculationService(calendar: calendar).makeContext(
            entrySnapshots: entries,
            settingsSnapshot: settings,
            calendar: calendar
        )

        let monthSummary = context.periodSummary(from: monthRange.start, to: monthEnd)
        let monthSecondsByDate = monthEntrySecondsByDate(monthEntries, context: &context, calendar: calendar)
        let activeDaysCount = monthSecondsByDate.values.filter { $0 > 0 }.count
        let bestDay = monthSecondsByDate
            .filter { $0.value > 0 }
            .max { $0.value < $1.value }
            .map { StatsBestDay(date: $0.key, seconds: $0.value) }

        let yearPayPoints = yearPayPoints(
            referenceMonth: referenceMonth,
            context: &context,
            calendar: calendar
        )
        let yearAverageMonthlyCents: Int = {
            guard !yearPayPoints.isEmpty else { return 0 }
            let total = yearPayPoints.reduce(0) { $0 + $1.cents }
            return Int((Double(total) / Double(yearPayPoints.count)).rounded())
        }()

        let dayTypeBreakdown = DayType.allCases.compactMap { type -> StatsDayTypeBreakdownValue? in
            let typedEntries = monthEntries.filter { $0.type == type }
            let seconds = typedEntries.reduce(0) { total, entry in
                let day = entry.date.startOfDayLocal(calendar: calendar)
                return total + max(0, monthSecondsByDate[day] ?? 0)
            }
            guard !typedEntries.isEmpty || seconds > 0 else { return nil }
            return StatsDayTypeBreakdownValue(type: type, count: typedEntries.count, seconds: seconds)
        }

        let monthDailyPoints = monthEntries.compactMap { entry -> MonthDailyPoint? in
            let day = entry.date.startOfDayLocal(calendar: calendar)
            guard let seconds = monthSecondsByDate[day] else { return nil }
            return MonthDailyPoint(date: entry.date, hours: Double(seconds) / 3600.0)
        }

        return StatsDerivedSnapshot(
            key: key,
            monthSummary: monthSummary,
            activeDaysCount: activeDaysCount,
            bestDay: bestDay,
            yearPayPoints: yearPayPoints,
            yearAverageMonthlyCents: yearAverageMonthlyCents,
            dayTypeBreakdown: dayTypeBreakdown,
            monthDailyPoints: monthDailyPoints
        )
    }

    nonisolated private static func monthEntrySecondsByDate(
        _ monthEntries: [CalculationInputSnapshot],
        context: inout CalculationContext,
        calendar: Calendar
    ) -> [Date: Int] {
        var values: [Date: Int] = [:]
        for entry in monthEntries {
            let result = context.dayComputation(for: entry)
            switch result {
            case let .ok(seconds, _), let .warning(seconds, _, _):
                values[entry.date.startOfDayLocal(calendar: calendar)] = seconds
            case .error:
                continue
            }
        }
        return values
    }

    nonisolated private static func yearPayPoints(
        referenceMonth: Date,
        context: inout CalculationContext,
        calendar: Calendar
    ) -> [MonthPayPoint] {
        guard let yearInterval = calendar.dateInterval(of: .year, for: referenceMonth) else {
            return []
        }

        return (0..<12).compactMap { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: yearInterval.start) else {
                return nil
            }
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let summary = context.periodSummary(from: monthStart, to: monthEnd.addingTimeInterval(-1))
            return MonthPayPoint(
                monthStart: monthStart,
                cents: summary.totalCents,
                isHighlighted: calendar.isDate(monthStart, equalTo: referenceMonth, toGranularity: .month)
            )
        }
    }

    @ViewBuilder
    private var statsContent: some View {
        switch effectiveContentMode {
        case .pay:
            VStack(spacing: 18) {
                monthFocusCard
                statsCards
                dayTypeBreakdownCard
                yearPayChartCard
                monthDailyChartCard
            }
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
        case .timeAccount:
            HoursAccountTabView(
                settings: settings,
                referenceMonth: $referenceMonth,
                presentation: .embedded
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
        }
    }

    private var effectiveContentMode: StatsContentMode {
        includesTimeAccount ? selectedContentMode : .pay
    }

    private var statsModeRail: some View {
        HStack(spacing: 5) {
            ForEach(StatsContentMode.allCases) { mode in
                statsModeButton(mode)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity)
        .payScopeGlassControl(
            accent: settings.themeAccent.color,
            cornerRadius: 25,
            tintOpacity: 0.055,
            isInteractive: false
        )
    }

    private func statsModeButton(_ mode: StatsContentMode) -> some View {
        let isSelected = effectiveContentMode == mode

        return Button {
            guard selectedContentMode != mode else { return }
            withAnimation(.smooth(duration: 0.28, extraBounce: 0.12)) {
                selectedContentMode = mode
            }
            modeSelectionFeedbackTrigger += 1
        } label: {
            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color(.tertiarySystemFill).opacity(0.76))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(settings.themeAccent.color.opacity(0.16), lineWidth: 0.8)
                        )
                        .matchedGeometryEffect(id: "stats-mode-selection", in: statsModeNamespace)
                }

                HStack(spacing: 7) {
                    Image(systemName: mode.icon)
                        .font(.system(.caption, design: .rounded).weight(.black))
                    Text(mode.title)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
                .foregroundStyle(isSelected ? settings.themeAccent.color : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(
            PayScopeLiquidGlassPressButtonStyle(
                accent: settings.themeAccent.color,
                shape: Capsule(style: .continuous),
                tintOpacity: 0.04,
                pressedScale: 0.975
            )
        )
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var monthRange: DateInterval {
        Calendar.current.dateInterval(of: .month, for: referenceMonth) ?? DateInterval(start: referenceMonth, end: referenceMonth)
    }

    private var statsLoadInterval: DateInterval {
        guard let yearInterval = Calendar.current.dateInterval(of: .year, for: referenceMonth) else {
            return monthRange
        }
        return DateInterval(
            start: yearInterval.start.addingDays(-7 * settings.vacationLookbackCount),
            end: yearInterval.end
        )
    }

    private var monthSummary: TotalsSummary {
        derivedSnapshot.monthSummary
    }

    private var monthDays: Int {
        max(1, Calendar.current.range(of: .day, in: .month, for: referenceMonth)?.count ?? 30)
    }

    private var averageSecondsPerDay: Int {
        Int((Double(monthSummary.totalSeconds) / Double(monthDays)).rounded())
    }

    private var averageSecondsPerWeek: Int {
        Int((Double(monthSummary.totalSeconds) / Double(monthDays) * 7.0).rounded())
    }

    private var averageSecondsPerActiveDay: Int {
        guard activeDaysCount > 0 else { return 0 }
        return Int((Double(monthSummary.totalSeconds) / Double(activeDaysCount)).rounded())
    }

    private var averageCentsPerActiveDay: Int {
        guard activeDaysCount > 0 else { return 0 }
        return Int((Double(monthSummary.totalCents) / Double(activeDaysCount)).rounded())
    }

    private var activeDaysCount: Int {
        derivedSnapshot.activeDaysCount
    }

    private var monthTargetSeconds: Int? {
        guard let weeklyTarget = settings.weeklyTargetSeconds, weeklyTarget > 0 else { return nil }
        return Int((Double(weeklyTarget) / 7.0 * Double(monthDays)).rounded())
    }

    private var monthTargetProgress: Double? {
        guard let target = monthTargetSeconds, target > 0 else { return nil }
        return min(1, Double(monthSummary.totalSeconds) / Double(target))
    }

    private var bestDay: (date: Date, seconds: Int)? {
        derivedSnapshot.bestDay.map { (date: $0.date, seconds: $0.seconds) }
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

    private var yearPayPoints: [MonthPayPoint] {
        derivedSnapshot.yearPayPoints
    }

    private var yearAverageMonthlyCents: Int {
        derivedSnapshot.yearAverageMonthlyCents
    }

    private var monthFocusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Monatssumme")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(PayScopeFormatters.currencyString(cents: monthSummary.totalCents))
                        .font(.system(.largeTitle, design: .rounded).weight(.black))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .payScopeNumericTransition(value: monthSummary.totalCents)
                }

                Spacer(minLength: 8)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(settings.themeAccent.color)
                    .frame(width: 48, height: 48)
                    .payScopeLiquidGlassIcon(
                        accent: settings.themeAccent.color,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                        tintOpacity: 0.12,
                        shadowOpacity: 0.06
                    )
            }

            HStack(spacing: 10) {
                focusPill(
                    icon: "clock.fill",
                    value: PayScopeFormatters.hoursString(seconds: monthSummary.totalSeconds),
                    label: "Stunden"
                )
                focusPill(
                    icon: "calendar.badge.checkmark",
                    value: "\(activeDaysCount)",
                    label: "Tage"
                )
            }

            if let monthTargetSeconds, let monthTargetProgress {
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
                                .fill(settings.themeAccent.color)
                                .frame(width: max(10, proxy.size.width * monthTargetProgress))
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .padding(20)
        .payScopePureGlassSurface(
            accent: settings.themeAccent.color,
            cornerRadius: 28,
            tintOpacity: 0.07,
            shadowOpacity: 0.09,
            isInteractive: false
        )
    }

    private var statsLargeTitle: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Statistik")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            VStack{
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
        .payScopePureGlassSurface(
            accent: settings.themeAccent.color,
            cornerRadius: 18,
            tintOpacity: 0.045,
            shadowOpacity: 0.025,
            isInteractive: false
        )
    }

    private var statsCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            metricCard(
                title: PayScopeFormatters.currencyString(cents: averageCentsPerActiveDay),
                value: PayScopeFormatters.hoursString(seconds: averageSecondsPerActiveDay),
                footnote: "Ø pro Schicht",
                icon: "timer",
                tint: settings.themeAccent.color
            )
            metricCard(
                title: PayScopeFormatters.hoursString(seconds: averageSecondsPerWeek),
                value: PayScopeFormatters.hoursString(seconds: averageSecondsPerDay),
                footnote: "Ø pro Woche",
                icon: "calendar",
                tint: .teal
            )
            metricCard(
                title: "",
                value: PayScopeFormatters.currencyString(cents: yearAverageMonthlyCents),
                footnote: "Jahresschnitt",
                icon: "chart.bar.fill",
                tint: .indigo
            )
            if let bestDay {
                metricCard(
                    title: PayScopeFormatters.day.string(from: bestDay.date),
                    value: PayScopeFormatters.hoursString(seconds: bestDay.seconds),
                    footnote: "Stärkster Tag",
                    icon: "sparkles",
                    tint: .orange
                )
            } else {
                metricCard(
                    title: "Stärkster Tag",
                    value: "-",
                    footnote: "Noch keine Daten",
                    icon: "sparkles",
                    tint: .orange
                )
            }
        }
    }

    private func metricCard(title: String, value: String, footnote: String, icon: String, tint: Color) -> some View {
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
                .minimumScaleFactor(0.58)
                .payScopeNumericTransition(value: value)
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(footnote)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .payScopePureGlassSurface(
            accent: settings.themeAccent.color,
            cornerRadius: 22,
            tintOpacity: 0.052,
            shadowOpacity: 0.07,
            isInteractive: false
        )
    }

    private var dayTypeBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(title: "Aufteilung", subtitle: "")

            if dayTypeBreakdown.isEmpty {
                Text("Noch keine Daten.")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(dayTypeBreakdown) { item in
                        breakdownRow(item)
                    }
                }
            }
        }
        .padding(16)
        .payScopePureGlassSurface(
            accent: settings.themeAccent.color,
            cornerRadius: PayScopeModalGeometry.sheet.innerCornerRadius,
            tintOpacity: 0.055,
            shadowOpacity: 0.075,
            isInteractive: false
        )
    }

    private var dayTypeBreakdown: [DayTypeBreakdownItem] {
        derivedSnapshot.dayTypeBreakdown.map { value in
            return DayTypeBreakdownItem(
                type: value.type,
                count: value.count,
                seconds: value.seconds,
                tint: settings.categoryColor(for: value.type)
            )
        }
    }

    private func breakdownRow(_ item: DayTypeBreakdownItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.icon)
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundStyle(item.tint)
                .frame(width: 30, height: 30)
                .payScopeLiquidGlassIcon(accent: item.tint, tintOpacity: 0.13, shadowOpacity: 0.06)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.type.label)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text("\(item.count) \(item.count == 1 ? "Tag" : "Tage")")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .payScopeNumericTransition(value: item.count)
            }

            Spacer()

            Text(PayScopeFormatters.hoursString(seconds: item.seconds))
                .font(.system(.subheadline, design: .rounded).weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .payScopeNumericTransition(value: item.seconds)
        }
        .padding(12)
        .payScopePureGlassSurface(
            accent: item.tint,
            cornerRadius: 16,
            tintOpacity: 0.042,
            shadowOpacity: 0.02,
            isInteractive: false
        )
    }

    private func cardHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.black))
                if subtitle != "" {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var yearPayChartCard: some View {
        YearPayChartCard(
            points: yearPayPoints,
            averageMonthlyCents: yearAverageMonthlyCents,
            referenceMonthStart: referenceMonth.startOfMonthLocal(),
            accent: settings.themeAccent.color
        )
    }

    private var monthDailyChartCard: some View {
        MonthDailyChartCard(
            points: monthDailyPoints,
            referenceMonthStart: referenceMonth.startOfMonthLocal(),
            accent: settings.themeAccent.color
        )
    }

    private var monthDailyPoints: [MonthDailyPoint] {
        derivedSnapshot.monthDailyPoints
    }

    @MainActor
    private func loadData(mode: DataLoadMode = .fullSync) async {
        guard !isLoadingData else { return }
        isLoadingData = true
        defer { isLoadingData = false }

        let interval = statsLoadInterval
        let localEntries = localStore.loadAll(in: interval)
        let localSnapshot = deduplicateEntriesByLocalDayKeepingNewest(localEntries)
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
                try await cloudKitService.fetchDayEntries(in: interval)
            )
            let cloudEntriesWithoutLocallyDeleted = cloudEntries.filter { cloudEntry in
                guard let deletedAt = tombstonesByDay[dayKey(cloudEntry.date)] else { return true }
                return deletedAt < cloudEntry.updatedAt
            }
            let mergedEntries = mergeEntriesByLocalDayKeepingNewest(
                local: localSnapshot,
                remote: cloudEntriesWithoutLocallyDeleted
            )

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
            hasher.combine(value.updatedAt.timeIntervalSinceReferenceDate)
            hasher.combine(value.type.rawValue)
            hasher.combine(value.manualWorkedSeconds ?? -1)
            hasher.combine(value.creditedOverrideSeconds ?? -1)
            hasher.combine(value.shiftStart?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(value.shiftEnd?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(value.breakSeconds ?? -1)
            hasher.combine(value.alwaysApplyFifteenMinuteBuffer ?? false)
            hasher.combine(value.segments.count)
            for segment in value.segments.sorted(by: { $0.start < $1.start }) {
                hasher.combine(segment.start.timeIntervalSinceReferenceDate)
                hasher.combine(segment.end.timeIntervalSinceReferenceDate)
                hasher.combine(segment.breakSeconds)
            }
        }
        return hasher.finalize()
    }

    private func deduplicateEntriesByLocalDayKeepingNewest(_ source: [DayEntry]) -> [DayEntry] {
        let byDay = Dictionary(
            source.map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        return byDay.values.sorted { $0.date < $1.date }
    }

    private func mergeEntriesByLocalDayKeepingNewest(local: [DayEntry], remote: [DayEntry]) -> [DayEntry] {
        deduplicateEntriesByLocalDayKeepingNewest(local + remote)
    }

    private func dayKey(_ date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }
}

private struct MonthPayPoint: Sendable {
    let monthStart: Date
    let cents: Int
    let isHighlighted: Bool
}

private struct MonthDailyPoint: Sendable {
    let date: Date
    let hours: Double
}

private struct YearPayChartCard: View {
    let points: [MonthPayPoint]
    let averageMonthlyCents: Int
    let referenceMonthStart: Date
    let accent: Color

    @State private var selectedMonth: Date?

    private static let compactMonthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsChartCardHeader(title: "Lohnverlauf")

            if points.isEmpty {
                Text("Noch keine Daten.")
                    .foregroundStyle(.secondary)
            } else {
#if canImport(Charts)
                let selectedPoint = selectedPayPoint(for: selectedMonth)

                StaticYearPayChart(
                    points: points,
                    averageMonthlyCents: averageMonthlyCents,
                    yDomain: chartYDomain,
                    accent: accent
                )
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateSelection(at: value.location.x, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
                .overlay(alignment: .top) {
                    ChartSelectionOverlay(
                        title: selectedPoint.map { Self.compactMonthTitleFormatter.string(from: $0.monthStart) },
                        value: selectedPoint.map { PayScopeFormatters.currencyString(cents: $0.cents) },
                        accent: accent
                    )
                }
#else
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(points, id: \.monthStart) { point in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(point.isHighlighted ? accent : .secondary.opacity(0.35))
                            .frame(width: 10, height: max(4, (Double(point.cents) / 100.0) * 0.02))
                    }
                }
                .frame(height: 220, alignment: .bottom)
#endif
            }
        }
        .padding(16)
        .payScopePureGlassSurface(
            accent: accent,
            cornerRadius: PayScopeModalGeometry.sheet.innerCornerRadius,
            tintOpacity: 0.055,
            shadowOpacity: 0.075,
            isInteractive: false
        )
        .onChange(of: referenceMonthStart) { _, _ in
            selectedMonth = nil
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        let maxPay = points.map { Double($0.cents) / 100.0 }.max() ?? 0
        let averagePay = Double(averageMonthlyCents) / 100.0
        return stableChartYDomain(maxValue: max(maxPay, averagePay))
    }

    private func selectedPayPoint(for date: Date?) -> MonthPayPoint? {
        guard let date else { return nil }
        return points.first { Calendar.current.isDate($0.monthStart, equalTo: date, toGranularity: .month) }
    }

    private func updateSelection(at xPosition: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            selectedMonth = nil
            return
        }
        let plotFrame = geometry[plotFrameAnchor]
        let plotX = xPosition - plotFrame.origin.x
        guard plotX >= 0, plotX <= plotFrame.width else {
            selectedMonth = nil
            return
        }
        guard let date: Date = proxy.value(atX: plotX) else { return }
        let monthStart = selectedPayPoint(for: date)?.monthStart
        guard selectedMonth != monthStart else { return }
        selectedMonth = monthStart
    }
}

private struct MonthDailyChartCard: View {
    let points: [MonthDailyPoint]
    let referenceMonthStart: Date
    let accent: Color

    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsChartCardHeader(title: "Stundenverlauf")

            if points.isEmpty {
                Text("Noch keine Daten.")
                    .foregroundStyle(.secondary)
            } else {
#if canImport(Charts)
                let selectedPoint = selectedDailyPoint(for: selectedDate)

                StaticMonthDailyChart(
                    points: points,
                    yDomain: chartYDomain,
                    accent: accent
                )
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateSelection(at: value.location.x, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
                .overlay(alignment: .top) {
                    ChartSelectionOverlay(
                        title: selectedPoint.map { PayScopeFormatters.day.string(from: $0.date) },
                        value: selectedPoint.map {
                            "\(PayScopeFormatters.hhmmString(seconds: Int(($0.hours * 3600).rounded()))) h"
                        },
                        accent: accent
                    )
                }
#else
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(points, id: \.date) { point in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accent)
                            .frame(width: 8, height: max(4, point.hours * 16))
                    }
                }
                .frame(height: 220, alignment: .bottom)
#endif
            }
        }
        .padding(16)
        .payScopePureGlassSurface(
            accent: accent,
            cornerRadius: PayScopeModalGeometry.sheet.innerCornerRadius,
            tintOpacity: 0.055,
            shadowOpacity: 0.075,
            isInteractive: false
        )
        .onChange(of: referenceMonthStart) { _, _ in
            selectedDate = nil
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        stableChartYDomain(maxValue: points.map(\.hours).max() ?? 0)
    }

    private func selectedDailyPoint(for date: Date?) -> MonthDailyPoint? {
        guard let date else { return nil }
        return points.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func updateSelection(at xPosition: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            selectedDate = nil
            return
        }
        let plotFrame = geometry[plotFrameAnchor]
        let plotX = xPosition - plotFrame.origin.x
        guard plotX >= 0, plotX <= plotFrame.width else {
            selectedDate = nil
            return
        }
        guard let date: Date = proxy.value(atX: plotX) else { return }
        let day = selectedDailyPoint(for: date)?.date
        guard selectedDate != day else { return }
        selectedDate = day
    }
}

#if canImport(Charts)
private struct StaticYearPayChart: View {
    let points: [MonthPayPoint]
    let averageMonthlyCents: Int
    let yDomain: ClosedRange<Double>
    let accent: Color

    var body: some View {
        Chart {
            ForEach(points, id: \.monthStart) { point in
                BarMark(
                    x: .value("Monat", point.monthStart, unit: .month),
                    y: .value("Lohn", Double(point.cents) / 100.0)
                )
                .cornerRadius(5)
                .foregroundStyle(point.isHighlighted ? accent : .secondary.opacity(0.35))
            }

            RuleMark(y: .value("Ø", Double(averageMonthlyCents) / 100.0))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 220)
        .chartYScale(domain: yDomain)
    }
}

private struct StaticMonthDailyChart: View {
    let points: [MonthDailyPoint]
    let yDomain: ClosedRange<Double>
    let accent: Color

    var body: some View {
        Chart(points, id: \.date) { point in
            BarMark(
                x: .value("Tag", point.date, unit: .day),
                y: .value("Stunden", point.hours)
            )
            .cornerRadius(4)
            .foregroundStyle(accent)
        }
        .frame(height: 220)
        .chartYScale(domain: yDomain)
    }
}
#endif

private struct StatsChartCardHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.black))
            Spacer()
        }
    }
}

private struct ChartSelectionOverlay: View {
    let title: String?
    let value: String?
    let accent: Color

    var body: some View {
        if let title, let value {
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.black))
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .payScopeGlassControl(
                accent: accent,
                cornerRadius: 12,
                tintOpacity: 0.065,
                isInteractive: false
            )
            .padding(.top, 8)
            .allowsHitTesting(false)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
}

private func stableChartYDomain(maxValue: Double) -> ClosedRange<Double> {
    0...max(maxValue * 1.12, 1)
}

private struct DayTypeBreakdownItem: Identifiable {
    var id: DayType { type }

    let type: DayType
    let count: Int
    let seconds: Int
    let tint: Color
}
