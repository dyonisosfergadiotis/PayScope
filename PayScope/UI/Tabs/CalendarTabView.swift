import SwiftUI
import SwiftData

struct CalendarTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]
    @Query(sort: \NetWageMonthConfig.monthStart) private var netConfigs: [NetWageMonthConfig]
    @Query(sort: \HolidayCalendarDay.date) private var importedHolidays: [HolidayCalendarDay]
    @Bindable var settings: Settings

    @State private var displayedMonth = Date()
    @State private var activeSheet: CalendarSheet?
    @State private var showNetWageConfig = false
    @State private var netConfigSheetMonth = Date().startOfMonthLocal()
    @State private var deleteCandidateDate: Date?
    @State private var longPressTriggeredDate: Date?
    @State private var holidayImportKeys: Set<String> = []

    private let service = CalculationService()
    private let holidayImporter = HolidayImportService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                monthHeader
                monthSummaryBar
                weekdayHeader
                calendarSurface
            }
            .padding()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PayScope")
                        .font(.headline.weight(.semibold))
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
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        displayedMonth = Date()
                        activeSheet = .day(Date().startOfDayLocal())
                    } label: {
                        bottomActionButton(systemImage: "sun.max.fill")
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        addAutomaticSegmentForToday()
                    } label: {
                        bottomActionButton(systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case let .day(date):
                    DayEditorView(date: date.startOfDayLocal(), settings: settings)
                        .presentationDetents([.fraction(0.65), .large])
                        .wageWiseSheetSurface(accent: settings.themeAccent.color)
                case .stats:
                    StatsTabView(settings: settings, referenceMonth: displayedMonth)
                        .wageWiseSheetSurface(accent: settings.themeAccent.color)
                case .settings:
                    SettingsTabView(settings: settings)
                        .wageWiseSheetSurface(accent: settings.themeAccent.color)
                }
            }
            .sheet(isPresented: $showNetWageConfig) {
                if let config = netConfig(for: netConfigSheetMonth) {
                    NetWageConfigSheet(config: config)
                        .wageWiseSheetSurface(accent: settings.themeAccent.color)
                } else {
                    ProgressView("Netto-Konfiguration wird geladen...")
                        .wageWiseSheetSurface(accent: settings.themeAccent.color)
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

        return HStack(spacing: 8) {
            monthMetricChip(
                title: "Stunden",
                value: WageWiseFormatters.hhmmString(seconds: summary.totalSeconds)
            )
            monthMetricChip(
                title: "Lohn Brutto",
                value: WageWiseFormatters.currencyString(cents: summary.totalCents)
            )

            Button {
                netConfigSheetMonth = displayedMonth.startOfMonthLocal()
                ensureNetConfigExists(for: netConfigSheetMonth)
                showNetWageConfig = true
            } label: {
                monthMetricChip(
                    title: "Lohn Netto",
                    value: WageWiseFormatters.currencyString(cents: monthlyNetCents)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private var monthlyNetCents: Int {
        Int((monthlyNetEuro * 100).rounded())
    }

    private var monthlyNetEuro: Double {
        let gross = Double(displayedMonthSummary.totalCents) / 100.0
        let effectiveConfig = effectiveNetConfig(for: displayedMonth.startOfMonthLocal())
        let bonusSum = bonuses(from: effectiveConfig.bonusesCSV).reduce(0, +)
        let grossPlusBonuses = gross + bonusSum
        let wageTax = (effectiveConfig.wageTaxPercent ?? 0) / 100.0
        let pension = (effectiveConfig.pensionPercent ?? 0) / 100.0

        // Net = gross + bonuses - tax share - pension share.
        return grossPlusBonuses
            - grossPlusBonuses * wageTax
            - grossPlusBonuses * pension
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

    private func effectiveNetConfig(for monthStart: Date) -> (wageTaxPercent: Double?, pensionPercent: Double?, bonusesCSV: String) {
        if let current = netConfig(for: monthStart) {
            return (current.wageTaxPercent, current.pensionPercent, current.bonusesCSV)
        }
        if let previous = previousMonthConfig(for: monthStart) {
            return (previous.wageTaxPercent, previous.pensionPercent, previous.bonusesCSV)
        }
        return (
            settings.netWageTaxPercent,
            settings.netPensionPercent,
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(settings.themeAccent.color.opacity(0.18), lineWidth: 1)
        )
    }

    private var weekdayHeader: some View {
        var germanCalendar = Calendar.current
        germanCalendar.locale = Locale(identifier: "de_DE")
        let symbols = germanCalendar.shortWeekdaySymbols
        let ordered = settings.weekStart == .monday ? Array(symbols[1...6] + [symbols[0]]) : symbols

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

        return GeometryReader { geo in
            let spacing: CGFloat = 8
            let totalSpacing = spacing * CGFloat(max(0, rowCount - 1))
            let cellHeight = max(86, (geo.size.height - totalSpacing) / CGFloat(rowCount))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7), spacing: spacing) {
                ForEach(dates, id: \.self) { date in
                    if Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
                        dayCell(for: date, height: cellHeight)
                    } else if date > displayedMonthBounds.1 {
                        adjacentMonthCell(for: date, height: cellHeight, isNextMonth: true)
                    } else {
                        adjacentMonthCell(for: date, height: cellHeight, isNextMonth: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calendarSurface: some View {
        ZStack {
            calendarGrid
                .id(displayedMonth.startOfMonthLocal())
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.985)), removal: .opacity))
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

    private func dayCell(for date: Date, height: CGFloat) -> some View {
        let dayDate = date.startOfDayLocal()
        let entry = entries.first(where: { $0.date.isSameLocalDay(as: dayDate) })
        let visibleEntry = entry.flatMap { $0.segments.isEmpty ? nil : $0 }
        let result = visibleEntry.map { service.dayComputation(for: $0, allEntries: entries, settings: settings) }
        let isToday = Calendar.current.isDateInToday(dayDate)
        let isWeekend = Calendar.current.isDateInWeekend(dayDate)
        let isHoliday = holidayDates.contains(dayDate)
        let isMutedDay = isWeekend || isHoliday
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
                    .foregroundStyle(isMutedDay ? .secondary : .primary)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isMutedDay
                        ? AnyShapeStyle(Color.gray.opacity(0.2))
                        : AnyShapeStyle(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(visibleEntry == nil ? .clear : settings.themeAccent.color.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isToday ? settings.themeAccent.color.opacity(0.52) : settings.themeAccent.color.opacity(0.2),
                        lineWidth: isToday ? 1.3 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.6) {
            guard visibleEntry != nil else { return }
            longPressTriggeredDate = dayDate
            deleteCandidateDate = dayDate
        }
    }

    private func adjacentMonthCell(for date: Date, height: CGFloat, isNextMonth: Bool) -> some View {
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(fillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.gray.opacity(isNextMonth ? 0.22 : 0.14), lineWidth: 1)
        )
    }

    private func germanMonthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func cellMetric(for entry: DayEntry, result: ComputationResult?) -> some View {
        let typeIcon = Image(systemName: entry.type.icon)
            .font(.caption2)
            .foregroundStyle(entry.type.tint)

        switch settings.calendarCellDisplayMode ?? .dot {
        case .dot:
            typeIcon
        case .hours:
            let seconds: Int = {
                guard let result else { return 0 }
                switch result {
                case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
                    return valueSeconds
                case .error:
                    return 0
                }
            }()
            VStack(spacing: 2) {
                Text(WageWiseFormatters.hhmmString(seconds: seconds))
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                typeIcon
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
                Text(shortCurrency(cents: cents))
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                typeIcon
            }
        }
    }

    private func shortCurrency(cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        let value = NSNumber(value: Double(cents) / 100)
        return formatter.string(from: value) ?? "0"
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

    private func addAutomaticSegmentForToday() {
        let today = Date().startOfDayLocal()
        let day = entries.first(where: { $0.date.isSameLocalDay(as: today) }) ?? {
            let newDay = DayEntry(date: today, type: .work)
            modelContext.insert(newDay)
            return newDay
        }()

        let start = automaticSegmentStart(for: day, on: today)
        let dayEnd = today.addingTimeInterval(24 * 3600)
        let end = min(dayEnd, start.addingTimeInterval(3600))
        guard end > start else { return }

        day.segments.append(TimeSegment(start: start, end: end, breakSeconds: 0))
        modelContext.persistIfPossible()
    }

    private func automaticSegmentStart(for day: DayEntry, on dayStart: Date) -> Date {
        let roundedNow = roundedNowDate(on: dayStart)
        if let lastEnd = day.segments.map(\.end).max() {
            return max(lastEnd, roundedNow)
        }
        return roundedNow
    }

    private func roundedNowDate(on dayStart: Date) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let roundedMinuteOfDay = min(24 * 60, ((hour * 60 + minute + 14) / 15) * 15)
        return dateAtMinute(roundedMinuteOfDay, on: dayStart)
    }

    private func dateAtMinute(_ minute: Int, on dayStart: Date) -> Date {
        if minute >= 24 * 60 {
            return dayStart.addingTimeInterval(24 * 3600)
        }
        let h = max(0, minute / 60)
        let m = max(0, minute % 60)
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: dayStart) ?? dayStart
    }

    private func deleteSegments(for date: Date) {
        guard let existing = entries.first(where: { $0.date.isSameLocalDay(as: date.startOfDayLocal()) }) else { return }
        existing.segments.removeAll()
        modelContext.persistIfPossible()
    }

    private var holidayImportTaskKey: String {
        let year = Calendar.current.component(.year, from: displayedMonth)
        let country = normalizedHolidayCountryCode ?? "NONE"
        let subdivision = normalizedHolidaySubdivisionCode ?? "ALL"
        return "\(year)-\(country)-\(subdivision)"
    }

    private var normalizedHolidayCountryCode: String? {
        normalizeCode(settings.holidayCountryCode)
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
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(settings.themeAccent.color.opacity(0.2), lineWidth: 1)
                )
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
        withAnimation(.easeInOut(duration: 0.22)) {
            displayedMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        }
    }

    private func bottomActionButton(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [settings.themeAccent.color, settings.themeAccent.color.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
}

private enum CalendarSheet: Identifiable {
    case day(Date)
    case stats
    case settings

    var id: String {
        switch self {
        case let .day(date):
            return "day-\(date.timeIntervalSinceReferenceDate)"
        case .stats:
            return "stats"
        case .settings:
            return "settings"
        }
    }
}

private struct NetWageConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var config: NetWageMonthConfig

    @State private var wageTaxText = ""
    @State private var pensionText = ""
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
        config.wageTaxPercent = wageTax
        config.pensionPercent = pension
        config.bonusesCSV = bonusTexts
            .compactMap { normalizedDouble(from: $0) }
            .map { String(format: "%.2f", $0) }
            .joined(separator: ";")
        wageTaxText = formatForDisplay(from: wageTaxText) ?? ""
        pensionText = formatForDisplay(from: pensionText) ?? ""
        bonusTexts = bonusTexts.map { formatForDisplay(from: $0) ?? $0 }
        modelContext.persistIfPossible()
    }
}
