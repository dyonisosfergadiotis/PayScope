import SwiftUI

struct CalendarMonthView: View {
    let settings: Settings?
    let entries: [DayEntry]
    let netConfigs: [NetWageMonthConfig]
    let holidays: [HolidayCalendarDay]
    var onSelectionChange: ((Bool) -> Void)?

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date?
    @State private var monthColumnReveal: Double = 1
    @State private var monthTransitionDirection: CGFloat = 1

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = settings?.weekStart == .sunday ? 1 : 2
        return c
    }

    private var accentColor: Color {
        settings?.themeAccent.color ?? .accentColor
    }

    private var selectedDetailEntry: (date: Date, entry: DayEntry, computedSeconds: Int?)? {
        guard let selectedDate else { return nil }
        guard let entry = selectedEntry(for: selectedDate), shouldShowDetail(for: entry) else { return nil }
        return (selectedDate, entry, detailSeconds(for: entry))
    }

    private var selectedDayShowsDetail: Bool {
        selectedDetailEntry != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if let settings {
                monthSummaryBar(for: summaryReferenceDate, settings: settings)
            }

            VStack(spacing: 8) {
                header
                weekdayHeader
                monthGrid
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            if let detail = selectedDetailEntry {
                DayDetailView(
                    date: detail.date,
                    entry: detail.entry,
                    accentColor: accentColor,
                    computedSeconds: detail.computedSeconds
                )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(10)
        .animation(.easeInOut(duration: 0.22), value: selectedDayShowsDetail)
        .onAppear {
            if selectedDate == nil {
                selectedDate = calendar.startOfDay(for: Date())
            }
            onSelectionChange?(selectedDayShowsDetail)
        }
        .onChange(of: selectedDayShowsDetail) { _, newValue in
            onSelectionChange?(newValue)
        }
    }

    private func selectedEntry(for date: Date) -> DayEntry? {
        let selectedKey = date.localDayKey(calendar: calendar)
        return entries.first { $0.date.localDayKey(calendar: calendar) == selectedKey }
    }

    private var summaryReferenceDate: Date {
        selectedDate?.startOfDayLocal(calendar: calendar) ?? calendar.startOfDay(for: Date())
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(monthString(for: displayedMonth))
                    .font(.title3.weight(.semibold))
                Text(yearString(for: displayedMonth))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                monthNavigationButton(systemImage: "chevron.left", accessibilityLabel: "Vorheriger Monat") {
                    navigateMonth(by: -1)
                }
                Spacer()
                monthNavigationButton(systemImage: "chevron.right", accessibilityLabel: "Nächster Monat") {
                    navigateMonth(by: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private func monthNavigationButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
    }

    private func navigateMonth(by delta: Int) {
        guard delta != 0 else { return }
        guard let targetMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }

        monthTransitionDirection = delta > 0 ? 1 : -1
        displayedMonth = targetMonth
        selectedDate = normalizedSelectedDate(for: targetMonth)

        monthColumnReveal = 0
        withAnimation(.easeOut(duration: 0.24)) {
            monthColumnReveal = 1
        }
    }

    private func normalizedSelectedDate(for month: Date) -> Date {
        let preferredDay = selectedDate.map { calendar.component(.day, from: $0) } ?? 1
        let monthRange = calendar.range(of: .day, in: .month, for: month) ?? 1..<2
        let targetDay = min(max(preferredDay, monthRange.lowerBound), monthRange.upperBound - 1)
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = targetDay

        if let alignedDate = calendar.date(from: components) {
            return calendar.startOfDay(for: alignedDate)
        }
        return month.startOfMonthLocal(calendar: calendar)
    }

    private var weekdayHeader: some View {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return HStack(spacing: 4) {
            ForEach(shiftedWeekdaySymbols(symbols), id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
    }

    private var monthGrid: some View {
        let days = daysForMonthGrid(containing: displayedMonth)
        let entriesByDate = Dictionary(entries.map { ($0.date.localDayKey(calendar: calendar), $0) }, uniquingKeysWith: { current, _ in current })
        // Holiday dates are stored as UTC civil days; compare against their UTC day keys.
        let holidaySet = Set(holidays.map { $0.date.utcDayKey })
        let dayResults = buildDayResultsLookup(days: days, entriesByDate: entriesByDate)
        let dayCellHeight: CGFloat = 60

        return VStack(spacing: 4) {
            ForEach(0..<days.count / 7, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        let day = days[row * 7 + col]
                        let dayKey = day.date.localDayKey(calendar: calendar)
                        let entry = day.isInDisplayedMonth ? entriesByDate[dayKey] : nil
                        let result = dayResults[dayKey]
                        let isHoliday = holidaySet.contains(dayKey)
                        let isSelected = selectedDate?.startOfDayLocal(calendar: calendar).isSameLocalDay(as: day.date.startOfDayLocal(calendar: calendar), calendar: calendar) ?? false
                        let revealProgress = columnRevealProgress(for: col)

                        MonthDayCell(
                            day: day.date,
                            isInMonth: day.isInDisplayedMonth,
                            isToday: calendar.isDateInToday(day.date),
                            entry: entry,
                            isHoliday: isHoliday,
                            isSelected: isSelected,
                            result: result,
                            settings: settings,
                            accentColor: accentColor
                        )
                        .onTapGesture {
                            guard day.isInDisplayedMonth else { return }
                            let isSameDay = selectedDate?.startOfDayLocal(calendar: calendar).isSameLocalDay(as: day.date.startOfDayLocal(calendar: calendar), calendar: calendar) ?? false
                            if isSameDay {
                                selectedDate = calendar.startOfDay(for: Date())
                            } else {
                                selectedDate = day.date.startOfDayLocal(calendar: calendar)
                            }
                        }
                        .opacity(0.9 + (0.1 * revealProgress))
                        .offset(x: monthTransitionDirection * (1 - revealProgress) * 8)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: dayCellHeight)
                    }
                }
            }
        }
    }

    private func monthSummaryBar(for date: Date, settings: Settings) -> some View {
        let summary = monthlySummary(for: date, settings: settings)
        let grossValue = summary.grossCents.map { cents in
            Formatters.currencyString(cents: cents)
        } ?? "-"
        let netValue = summary.netCents.map { cents in
            Formatters.currencyString(cents: cents)
        } ?? "-"

        return HStack(spacing: 12) {
            summaryMetric(title: "Monatsstunden", value: Formatters.hoursString(seconds: summary.totalSeconds), icon: "clock.fill")
            summaryMetric(title: "Monats-Brutto", value: grossValue, icon: "eurosign.circle.fill")
            summaryMetric(title: "Monats-Netto", value: netValue, icon: "banknote.fill")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func summaryMetric(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func monthlySummary(for date: Date, settings: Settings) -> (totalSeconds: Int, grossCents: Int?, netCents: Int?) {
        let entriesByDate = buildEntriesLookup()
        let monthStart = date.startOfMonthLocal(calendar: calendar)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return (0, nil, nil)
        }

        let monthEntries = entries.filter { entry in
            let localDay = entry.date.startOfDayLocal(calendar: calendar)
            return localDay >= monthStart && localDay < monthEnd
        }

        var totalSeconds = 0
        var grossCents = 0

        for entry in monthEntries {
            let result = dayComputation(for: entry, entriesByDate: entriesByDate, settings: settings)
            switch result {
            case let .ok(seconds, cents), let .warning(seconds, cents, _):
                totalSeconds += seconds
                grossCents += cents
            case .error:
                break
            }
        }

        let netCents = netMonthlyCents(grossCents: grossCents, date: monthStart, settings: settings)

        return (totalSeconds, grossCents, netCents)
    }

    private func buildEntriesLookup() -> [String: DayEntry] {
        Dictionary(entries.map { ($0.date.localDayKey(calendar: calendar), $0) }, uniquingKeysWith: { current, _ in current })
    }

    private func buildDayResultsLookup(days: [DayInfo], entriesByDate: [String: DayEntry]) -> [String: DayComputationResult] {
        guard let settings else { return [:] }

        var lookup: [String: DayComputationResult] = [:]
        for day in days where day.isInDisplayedMonth {
            let dayKey = day.date.localDayKey(calendar: calendar)
            guard let entry = entriesByDate[dayKey] else { continue }
            lookup[dayKey] = dayComputation(for: entry, entriesByDate: entriesByDate, settings: settings)
        }
        return lookup
    }

    private func dayComputation(
        for day: DayEntry,
        entriesByDate: [String: DayEntry],
        settings: Settings
    ) -> DayComputationResult {
        switch day.type {
        case .work, .manual:
            let seconds = workedSeconds(for: day)
            return .ok(seconds: seconds, cents: payCents(for: seconds, settings: settings))
        case .vacation:
            if let overrideSeconds = day.creditedOverrideSeconds {
                let seconds = max(0, overrideSeconds)
                return .ok(seconds: seconds, cents: payCents(for: seconds, settings: settings))
            }
            if settings.effectiveVacationCreditingMode == .fixedValue {
                let seconds = settings.effectiveVacationFixedSeconds
                return .ok(seconds: seconds, cents: payCents(for: seconds, settings: settings))
            }
            return creditedResult(for: day, entriesByDate: entriesByDate, settings: settings)
        case .holiday:
            if let overrideSeconds = day.creditedOverrideSeconds {
                let seconds = max(0, overrideSeconds)
                return .ok(seconds: seconds, cents: payCents(for: seconds, settings: settings))
            }
            if settings.effectiveHolidayCreditingMode == .fixedValue {
                let seconds = settings.effectiveHolidayFixedSeconds
                return .ok(seconds: seconds, cents: payCents(for: seconds, settings: settings))
            }
            return creditedResult(for: day, entriesByDate: entriesByDate, settings: settings)
        case .sick:
            if let overrideSeconds = day.creditedOverrideSeconds {
                let seconds = max(0, overrideSeconds)
                return .ok(seconds: seconds, cents: payCents(for: seconds, settings: settings))
            }
            return creditedResult(for: day, entriesByDate: entriesByDate, settings: settings)
        }
    }

    private func creditedResult(
        for day: DayEntry,
        entriesByDate: [String: DayEntry],
        settings: Settings
    ) -> DayComputationResult {
        let normalizedDate = day.date.startOfDayLocal(calendar: calendar)
        let lookback = max(1, settings.vacationLookbackCount)
        var values: [Int] = []

        for index in 1...lookback {
            let referenceDate = normalizedDate.addingDays(index * -7, calendar: calendar).startOfDayLocal(calendar: calendar)
            let referenceKey = referenceDate.localDayKey(calendar: calendar)

            guard let refEntry = entriesByDate[referenceKey] else {
                if settings.strictHistoryRequired && !settings.countMissingAsZero {
                    return .error(message: "Fehlende Referenztage für Lookback-Berechnung")
                }
                values.append(0)
                continue
            }

            values.append(referenceSeconds(for: refEntry, settings: settings))
        }

        guard !values.isEmpty else {
            return .error(message: "Nicht genug Verlauf für die Lookback-Berechnung")
        }

        let total = values.reduce(0, +)
        let averageRaw = Double(total) / Double(values.count)
        let roundedToMinute = Int(ceil(averageRaw / 60.0) * 60.0)
        let seconds = max(0, roundedToMinute)
        let cents = payCents(for: seconds, settings: settings)

        if values.allSatisfy({ $0 == 0 }) {
            return .warning(seconds: 0, cents: 0, message: "Lookback enthält nur Nullwerte")
        }
        return .ok(seconds: seconds, cents: cents)
    }

    private func referenceSeconds(for day: DayEntry, settings: Settings) -> Int {
        if let overrideSeconds = day.creditedOverrideSeconds {
            return max(0, overrideSeconds)
        }

        if day.type == .vacation, settings.effectiveVacationCreditingMode == .fixedValue {
            return settings.effectiveVacationFixedSeconds
        }

        if day.type == .holiday, settings.effectiveHolidayCreditingMode == .fixedValue {
            return settings.effectiveHolidayFixedSeconds
        }

        return workedSeconds(for: day)
    }

    private func workedSeconds(for entry: DayEntry) -> Int {
        if let manual = entry.manualWorkedSeconds, manual > 0 {
            return manual
        }

        let includeBreak = settings?.effectiveCalendarHoursBreakMode == .withBreak
        let fromSegments = entry.segments.reduce(0) { sum, segment in
            let rawSeconds = Int(segment.end.timeIntervalSince(segment.start))
            let value = includeBreak ? rawSeconds : rawSeconds - segment.breakSeconds
            return sum + max(0, value)
        }

        return max(0, fromSegments)
    }

    private func payCents(for seconds: Int, settings: Settings) -> Int {
        switch settings.payMode {
        case .hourly:
            guard let hourlyRateCents = settings.hourlyRateCents else { return 0 }
            return Int((Double(seconds) / 3600.0 * Double(hourlyRateCents)).rounded())
        case .monthly:
            guard
                let monthlySalaryCents = settings.monthlySalaryCents,
                let weeklyTargetSeconds = settings.weeklyTargetSeconds,
                weeklyTargetSeconds > 0
            else {
                return 0
            }
            let monthlyTargetSeconds = Double(weeklyTargetSeconds) * 52.0 / 12.0
            let hourlyRateCents = Double(monthlySalaryCents) / (monthlyTargetSeconds / 3600.0)
            return Int((Double(seconds) / 3600.0 * hourlyRateCents).rounded())
        }
    }

    private func netMonthlyCents(grossCents: Int, date: Date, settings: Settings) -> Int {
        let monthConfig = netConfig(for: date)

        let taxPercent = max(0, monthConfig?.wageTaxPercent ?? settings.netWageTaxPercent ?? 0)
        let pensionPercent = max(0, monthConfig?.pensionPercent ?? settings.netPensionPercent ?? 0)
        let combinedDeduction = min(max((taxPercent + pensionPercent) / 100.0, 0), 0.95)

        let monthlyAllowanceEuro = monthConfig?.monthlyAllowanceEuro ?? settings.netMonthlyAllowanceEuro ?? 0
        let bonusesEuro = parseBonusCSV(monthConfig?.bonusesCSV ?? settings.netBonusesCSV ?? "")
        let monthlyExtrasCents = Int(((monthlyAllowanceEuro + bonusesEuro) * 100).rounded())

        let baseNet = Int((Double(grossCents) * (1.0 - combinedDeduction)).rounded())
        return max(0, baseNet + monthlyExtrasCents)
    }

    private func netConfig(for date: Date) -> NetWageMonthConfig? {
        netConfigs.first { config in
            calendar.isDate(config.monthStart, equalTo: date, toGranularity: .month)
        }
    }

    private func parseBonusCSV(_ raw: String) -> Double {
        raw
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(0.0) { partialResult, token in
                partialResult + parseLocalizedDouble(token)
            }
    }

    private func parseLocalizedDouble(_ token: String) -> Double {
        var normalized = token.replacingOccurrences(of: " ", with: "")

        if normalized.contains(",") && normalized.contains(".") {
            normalized = normalized.replacingOccurrences(of: ".", with: "")
        }

        normalized = normalized.replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }

    private func columnRevealProgress(for column: Int) -> CGFloat {
        let stagger = 0.09
        let start = Double(column) * stagger
        let span = max(0.01, 1.0 - (Double(6) * stagger))
        let raw = (monthColumnReveal - start) / span
        let clamped = min(max(raw, 0), 1)
        return CGFloat(clamped)
    }

    private func shouldShowDetail(for entry: DayEntry) -> Bool {
        if entry.type != .work {
            return true
        }
        if let manualSeconds = entry.manualWorkedSeconds, manualSeconds > 0 {
            return true
        }
        if let overrideSeconds = entry.creditedOverrideSeconds, overrideSeconds > 0 {
            return true
        }
        return entry.segments.contains(where: { $0.end > $0.start })
    }

    private func detailSeconds(for entry: DayEntry) -> Int? {
        guard let settings else { return nil }
        let entriesByDate = buildEntriesLookup()
        let result = dayComputation(for: entry, entriesByDate: entriesByDate, settings: settings)
        switch result {
        case let .ok(seconds, _), let .warning(seconds, _, _):
            return seconds > 0 ? seconds : nil
        case .error:
            return nil
        }
    }

    private func monthString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    private func yearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private func shiftedWeekdaySymbols(_ symbols: [String]) -> [String] {
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private struct DayInfo: Identifiable {
        let id = UUID()
        let date: Date
        let isInDisplayedMonth: Bool
    }

    enum DayComputationResult {
        case ok(seconds: Int, cents: Int)
        case warning(seconds: Int, cents: Int, message: String)
        case error(message: String)

        var secondsOrZero: Int {
            switch self {
            case let .ok(seconds, _), let .warning(seconds, _, _):
                return seconds
            case .error:
                return 0
            }
        }
    }

    private func daysForMonthGrid(containing date: Date) -> [DayInfo] {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let firstOfMonth = calendar.date(from: comps) else { return [] }

        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let diff = (weekday - calendar.firstWeekday + 7) % 7

        guard let gridStart = calendar.date(byAdding: .day, value: -diff, to: firstOfMonth) else { return [] }

        let total = 42
        return (0..<total).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let inMonth = calendar.isDate(d, equalTo: firstOfMonth, toGranularity: .month)
            return DayInfo(date: d, isInDisplayedMonth: inMonth)
        }
    }
}

private struct MonthDayCell: View {
    let day: Date
    let isInMonth: Bool
    let isToday: Bool
    let entry: DayEntry?
    let isHoliday: Bool
    let isSelected: Bool
    let result: CalendarMonthView.DayComputationResult?
    let settings: Settings?
    let accentColor: Color

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: day))
    }

    private var displaySeconds: Int {
        if let result {
            return result.secondsOrZero
        }

        guard let entry else { return 0 }

        if let seconds = entry.manualWorkedSeconds, seconds > 0 {
            return seconds
        }

        let includeBreak = settings?.effectiveCalendarHoursBreakMode == .withBreak
        return entry.segments.reduce(0) { sum, segment in
            let rawSeconds = Int(segment.end.timeIntervalSince(segment.start))
            let worked = includeBreak ? rawSeconds : rawSeconds - segment.breakSeconds
            return sum + max(0, worked)
        }
    }

    private var displayMode: CalendarCellDisplayMode {
        settings?.calendarCellDisplayMode ?? .dot
    }

    private var metricText: String? {
        guard entry != nil else { return nil }

        switch displayMode {
        case .dot:
            return nil
        case .hours:
            guard displaySeconds > 0 else { return nil }
            return Formatters.hhmmString(seconds: displaySeconds)
        case .pay:
            guard let result else { return nil }
            let cents: Int
            switch result {
            case let .ok(_, valueCents), let .warning(_, valueCents, _):
                cents = valueCents
            case .error:
                return nil
            }
            guard cents > 0 else { return nil }
            return Formatters.currencyString(cents: cents)
        }
    }

    private var iconSymbol: String {
        if let entry {
            return entry.type.icon
        }
        if isHoliday {
            return "flag.fill"
        }
        return "circle.dashed"
    }

    private var iconColor: Color {
        if let entry {
            return entry.type == .work ? accentColor : entry.type.tint
        }
        if isHoliday {
            return .orange
        }
        return .secondary.opacity(0.35)
    }

    private var iconOpacity: Double {
        (entry != nil || isHoliday) ? 1 : 0
    }

    private var metricPlaceholder: String {
        switch displayMode {
        case .pay:
            return "--,--"
        case .dot, .hours:
            return "--:--"
        }
    }

    private var metricOpacity: Double {
        metricText == nil ? 0 : 1
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)

            VStack(spacing: 0) {
                Text(dayNumber)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isInMonth ? .primary : .tertiary)
                    .padding(.top, 5)

                Spacer(minLength: 0)

                Image(systemName: iconSymbol)
                    .foregroundStyle(iconColor)
                    .font(.callout.weight(.semibold))
                    .opacity(iconOpacity)

                Spacer(minLength: 0)

                Text(metricText ?? metricPlaceholder)
                    .font(.caption2)
                    .foregroundStyle(metricText == nil ? .tertiary : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(metricOpacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 4)
            .padding(.bottom, 5)

            if isToday {
                Circle()
                    .fill(todayMarkerColor)
                    .frame(width: 7, height: 7)
                    .padding(6)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, style: borderStrokeStyle)
        )
    }

    private var backgroundColor: Color {
        if isSelected {
            return accentColor.opacity(0.24)
        }
        if isToday {
            return Color.orange.opacity(0.08)
        }
        if isHoliday {
            return Color.orange.opacity(0.12)
        }
        if entry != nil {
            return accentColor.opacity(0.08)
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    private var borderColor: Color {
        if isSelected {
            return accentColor
        }
        if isToday {
            return .orange.opacity(0.9)
        }
        return Color.primary.opacity(0.05)
    }

    private var borderStrokeStyle: StrokeStyle {
        if isSelected {
            return StrokeStyle(lineWidth: 1.8)
        }
        if isToday {
            return StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        }
        return StrokeStyle(lineWidth: 1)
    }

    private var todayMarkerColor: Color {
        isSelected ? .white : .orange
    }
}

#Preview {
    CalendarMonthView(
        settings: Settings(),
        entries: [],
        netConfigs: [],
        holidays: []
    )
    .frame(minWidth: 460, minHeight: 620)
    .padding()
}
