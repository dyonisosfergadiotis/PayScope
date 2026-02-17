import SwiftUI
import SwiftData
#if canImport(Charts)
import Charts
#endif

struct StatsTabView: View {
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]
    @Bindable var settings: Settings
    let referenceMonth: Date

    private let service = CalculationService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    statsCards
                    yearPayChartCard
                    monthDailyChartCard
                }
                .padding()
            }
            .navigationTitle("Statistik")
        }
        .wageWiseBackground(accent: settings.themeAccent.color)
    }

    private var monthRange: DateInterval {
        Calendar.current.dateInterval(of: .month, for: referenceMonth) ?? DateInterval(start: referenceMonth, end: referenceMonth)
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

    private var activeDaysCount: Int {
        monthEntries.compactMap { workedSeconds(for: $0) }.filter { $0 > 0 }.count
    }

    private var bestDay: (date: Date, seconds: Int)? {
        monthEntries.compactMap { day in
            guard let seconds = workedSeconds(for: day), seconds > 0 else { return nil }
            return (day.date, seconds)
        }
        .max { $0.seconds < $1.seconds }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: referenceMonth)
    }

    private var yearPayPoints: [MonthPayPoint] {
        guard let yearInterval = Calendar.current.dateInterval(of: .year, for: referenceMonth) else {
            return []
        }

        let months = (0..<12).compactMap { Calendar.current.date(byAdding: .month, value: $0, to: yearInterval.start) }

        return months.map { monthStart in
            let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let summary = service.periodSummary(
                entries: entries,
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

    private var statsCards: some View {
        VStack(spacing: 10) {
            keyCard(label: "Monat", value: monthTitle)
            keyCard(label: "Gesamtstunden", value: WageWiseFormatters.hoursString(seconds: monthSummary.totalSeconds))
            keyCard(label: "Gesamtlohn", value: WageWiseFormatters.currencyString(cents: monthSummary.totalCents))
            keyCard(label: "Ø Stunden / Tag", value: WageWiseFormatters.hoursString(seconds: averageSecondsPerDay))
            keyCard(label: "Ø Stunden / Woche", value: WageWiseFormatters.hoursString(seconds: averageSecondsPerWeek))
            keyCard(label: "Arbeitstage", value: "\(activeDaysCount)")
            keyCard(label: "Ø Monatslohn (Jahr)", value: WageWiseFormatters.currencyString(cents: yearAverageMonthlyCents))
            if let bestDay {
                keyCard(
                    label: "Bester Tag",
                    value: "\(WageWiseFormatters.day.string(from: bestDay.date)) · \(WageWiseFormatters.hoursString(seconds: bestDay.seconds))"
                )
            }
        }
    }

    private func keyCard(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(WageWiseTypography.section)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .wageWiseCard(accent: settings.themeAccent.color)
    }

    private var yearPayChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lohnverlauf Jahr")
                .font(.headline)

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
                        .foregroundStyle(point.isHighlighted ? settings.themeAccent.color : .secondary.opacity(0.35))
                    }

                    RuleMark(y: .value("Ø", Double(yearAverageMonthlyCents) / 100.0))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 180)
#else
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(points, id: \.monthStart) { point in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(point.isHighlighted ? settings.themeAccent.color : .secondary.opacity(0.35))
                            .frame(width: 10, height: max(4, (Double(point.cents) / 100.0) * 0.02))
                    }
                }
                .frame(height: 180, alignment: .bottom)
#endif
            }
        }
        .wageWiseCard(accent: settings.themeAccent.color)
    }

    private var monthDailyChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tagesverlauf im Monat")
                .font(.headline)

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
                    .foregroundStyle(settings.themeAccent.color)
                }
                .frame(height: 180)
#else
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(points, id: \.date) { point in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(settings.themeAccent.color)
                            .frame(width: 8, height: max(4, point.hours * 16))
                    }
                }
                .frame(height: 180, alignment: .bottom)
#endif
            }
        }
        .wageWiseCard(accent: settings.themeAccent.color)
    }

    private var monthDailyPoints: [(date: Date, hours: Double)] {
        monthEntries.compactMap { day in
            guard let seconds = workedSeconds(for: day) else { return nil }
            return (day.date, Double(seconds) / 3600.0)
        }
    }

    private func workedSeconds(for day: DayEntry) -> Int? {
        let result = service.dayComputation(for: day, allEntries: entries, settings: settings)
        switch result {
        case let .ok(seconds, _), let .warning(seconds, _, _):
            return seconds
        case .error:
            return nil
        }
    }
}

private struct MonthPayPoint {
    let monthStart: Date
    let cents: Int
    let isHighlighted: Bool
}
