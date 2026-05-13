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

    @EnvironmentObject private var cloudKitService: CloudKitService
    @Bindable var settings: Settings
    @Binding var referenceMonth: Date

    @State private var entries: [DayEntry] = []
    @State private var isLoadingData = false

    private let localStore = LocalDayEntryStore.shared
    private let service = CalculationService()
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthFocusCard
                    statsCards
                    dayTypeBreakdownCard
                    yearPayChartCard
                    monthDailyChartCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .navigationTitle("Statistik")
        }
        .payScopeBackground(accent: settings.themeAccent.color)
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

    private var monthEntries: [DayEntry] {
        entries
            .filter { $0.date >= monthRange.start && $0.date < monthRange.end }
            .sorted { $0.date < $1.date }
    }

    private var monthSummary: TotalsSummary {
        service.periodSummary(
            entries: entries,
            from: monthRange.start,
            to: monthRange.end.addingTimeInterval(-1),
            settings: settings
        )
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
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        return monthEntries
            .compactMap { workedSeconds(for: $0, entriesByDate: entriesByDate) }
            .filter { $0 > 0 }
            .count
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
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        return monthEntries.compactMap { day -> (date: Date, seconds: Int)? in
            guard let seconds = workedSeconds(for: day, entriesByDate: entriesByDate), seconds > 0 else { return nil }
            return (day.date, seconds)
        }
        .max { $0.seconds < $1.seconds }
    }

    private var monthTitle: String {
        Self.monthTitleFormatter.string(from: referenceMonth)
    }

    private var yearPayPoints: [MonthPayPoint] {
        guard let yearInterval = Calendar.current.dateInterval(of: .year, for: referenceMonth) else {
            return []
        }

        let months = (0..<12).compactMap { Calendar.current.date(byAdding: .month, value: $0, to: yearInterval.start) }
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)

        return months.map { monthStart in
            let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let summary = service.periodSummary(
                entries: entries,
                entriesByDate: entriesByDate,
                from: monthStart,
                to: monthEnd.addingTimeInterval(-1),
                settings: settings
            )
            return MonthPayPoint(
                monthStart: monthStart,
                cents: summary.totalCents,
                isHighlighted: Calendar.current.isDate(monthStart, equalTo: referenceMonth, toGranularity: .month)
            )
        }
    }

    private var yearAverageMonthlyCents: Int {
        let points = yearPayPoints
        guard !points.isEmpty else { return 0 }
        let total = points.reduce(0) { $0 + $1.cents }
        return Int((Double(total) / Double(points.count)).rounded())
    }

    private var monthFocusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(monthTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(PayScopeFormatters.currencyString(cents: monthSummary.totalCents))
                        .font(.system(.largeTitle, design: .rounded).weight(.black))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 8)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(settings.themeAccent.color)
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
        .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 28, emphasis: 0.75)
    }

    private func focusPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundStyle(settings.themeAccent.color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(settings.themeAccent.color.opacity(0.14)))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
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

    private var statsCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricCard(
                title: "Ø aktiver Tag",
                value: PayScopeFormatters.hoursString(seconds: averageSecondsPerActiveDay),
                footnote: PayScopeFormatters.currencyString(cents: averageCentsPerActiveDay),
                icon: "timer",
                tint: settings.themeAccent.color
            )
            metricCard(
                title: "Ø Kalendertag",
                value: PayScopeFormatters.hoursString(seconds: averageSecondsPerDay),
                footnote: "\(PayScopeFormatters.hoursString(seconds: averageSecondsPerWeek)) / Woche",
                icon: "calendar",
                tint: .teal
            )
            metricCard(
                title: "Jahresschnitt",
                value: PayScopeFormatters.currencyString(cents: yearAverageMonthlyCents),
                footnote: "Monatslohn",
                icon: "chart.bar.fill",
                tint: .indigo
            )
            if let bestDay {
                metricCard(
                    title: "Stärkster Tag",
                    value: PayScopeFormatters.hoursString(seconds: bestDay.seconds),
                    footnote: PayScopeFormatters.day.string(from: bestDay.date),
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
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.14))
                )

            Spacer(minLength: 0)

            Text(value)
                .font(.system(.title3, design: .rounded).weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
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
        .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 22, emphasis: 0.38)
    }

    private var dayTypeBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(title: "Aufteilung", subtitle: "Tage und Stunden nach Art")

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
        .payScopeCard(accent: settings.themeAccent.color)
    }

    private var dayTypeBreakdown: [DayTypeBreakdownItem] {
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        return DayType.allCases.compactMap { type in
            let typedEntries = monthEntries.filter { $0.type == type }
            let seconds = typedEntries.reduce(0) { total, entry in
                total + max(0, workedSeconds(for: entry, entriesByDate: entriesByDate) ?? 0)
            }
            guard !typedEntries.isEmpty || seconds > 0 else { return nil }
            return DayTypeBreakdownItem(
                type: type,
                count: typedEntries.count,
                seconds: seconds,
                tint: type.tint(for: settings.themeAccent)
            )
        }
    }

    private func breakdownRow(_ item: DayTypeBreakdownItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.icon)
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundStyle(item.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(item.tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.type.label)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text("\(item.count) \(item.count == 1 ? "Tag" : "Tage")")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(PayScopeFormatters.hoursString(seconds: item.seconds))
                .font(.system(.subheadline, design: .rounded).weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.62))
        )
    }

    private func cardHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.black))
                Text(subtitle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var yearPayChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(title: "Lohnverlauf", subtitle: "Jahr mit Monatsdurchschnitt")

            let points = yearPayPoints

            if points.isEmpty {
                Text("Noch keine Daten.")
                    .foregroundStyle(.secondary)
            } else {
#if canImport(Charts)
                Chart {
                    ForEach(points, id: \.monthStart) { point in
                        BarMark(
                            x: .value("Monat", point.monthStart, unit: .month),
                            y: .value("Lohn", Double(point.cents) / 100.0)
                        )
                        .cornerRadius(5)
                        .foregroundStyle(point.isHighlighted ? settings.themeAccent.color : .secondary.opacity(0.35))
                    }

                    RuleMark(y: .value("Ø", Double(yearAverageMonthlyCents) / 100.0))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 220)
#else
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(points, id: \.monthStart) { point in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(point.isHighlighted ? settings.themeAccent.color : .secondary.opacity(0.35))
                            .frame(width: 10, height: max(4, (Double(point.cents) / 100.0) * 0.02))
                    }
                }
                .frame(height: 220, alignment: .bottom)
#endif
            }
        }
        .payScopeCard(accent: settings.themeAccent.color)
    }

    private var monthDailyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(title: "Tagesverlauf", subtitle: "Gearbeitete Stunden im Monat")

            let points = monthDailyPoints

            if points.isEmpty {
                Text("Noch keine Daten.")
                    .foregroundStyle(.secondary)
            } else {
#if canImport(Charts)
                Chart(points, id: \.date) { point in
                    BarMark(
                        x: .value("Tag", point.date, unit: .day),
                        y: .value("Stunden", point.hours)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(settings.themeAccent.color)
                }
                .frame(height: 220)
#else
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(points, id: \.date) { point in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(settings.themeAccent.color)
                            .frame(width: 8, height: max(4, point.hours * 16))
                    }
                }
                .frame(height: 220, alignment: .bottom)
#endif
            }
        }
        .payScopeCard(accent: settings.themeAccent.color)
    }

    private var monthDailyPoints: [(date: Date, hours: Double)] {
        let entriesByDate = service.makeEntriesByDateLookup(from: entries)
        return monthEntries.compactMap { day -> (date: Date, hours: Double)? in
            guard let seconds = workedSeconds(for: day, entriesByDate: entriesByDate) else { return nil }
            return (day.date, Double(seconds) / 3600.0)
        }
    }

    private func workedSeconds(for day: DayEntry, entriesByDate: [Date: DayEntry]) -> Int? {
        let result = service.dayComputation(for: day, entriesByDate: entriesByDate, settings: settings)
        switch result {
        case let .ok(seconds, _), let .warning(seconds, _, _):
            return seconds
        case .error:
            return nil
        }
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

private struct MonthPayPoint {
    let monthStart: Date
    let cents: Int
    let isHighlighted: Bool
}

private struct DayTypeBreakdownItem: Identifiable {
    var id: DayType { type }

    let type: DayType
    let count: Int
    let seconds: Int
    let tint: Color
}
