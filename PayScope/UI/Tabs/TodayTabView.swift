import SwiftUI
import SwiftData

struct TodayTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]
    @Bindable var settings: Settings

    @State private var showEditor = false

    private let service = CalculationService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let today = todayEntry {
                        todayCard(for: today)
                        todayEntriesCard(for: today)
                    } else {
                        emptyTodayCard
                    }

                    quickActions

                    weekMonthCards
                }
                .padding()
            }
            .navigationTitle("Heute")
            .sheet(isPresented: $showEditor) {
                DayEditorView(date: Date().startOfDayLocal(), settings: settings)
                    .presentationDetents([.fraction(0.65), .large])
            }
        }
        .wageWiseBackground(accent: settings.themeAccent.color)
    }

    private var todayEntry: DayEntry? {
        let today = Date().startOfDayLocal()
        return entries.first(where: { $0.date.isSameLocalDay(as: today) })
    }

    private var weekBounds: (Date, Date) {
        let start = service.weekStartDate(for: Date(), weekStart: settings.weekStart)
        let end = start.addingDays(6)
        return (start, end)
    }

    private var monthBounds: (Date, Date) {
        guard let interval = Calendar.current.dateInterval(of: .month, for: Date()) else {
            let now = Date().startOfDayLocal()
            return (now, now)
        }
        return (interval.start, interval.end.addingTimeInterval(-1))
    }

    private var weekSummary: TotalsSummary {
        service.periodSummary(entries: entries, from: weekBounds.0, to: weekBounds.1, settings: settings)
    }

    private var monthSummary: TotalsSummary {
        service.periodSummary(entries: entries, from: monthBounds.0, to: monthBounds.1, settings: settings)
    }

    private func todayCard(for day: DayEntry) -> some View {
        let result = service.dayComputation(for: day, allEntries: entries, settings: settings)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Tagesübersicht")
                .font(.headline)
            Label(day.type.label, systemImage: day.type.icon)
                .font(.subheadline)
                .foregroundStyle(day.type.tint)

            switch result {
            case let .ok(seconds, cents):
                Text(WageWiseFormatters.hoursString(seconds: seconds))
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text(WageWiseFormatters.currencyString(cents: cents))
                    .font(.title3.bold())
            case let .warning(seconds, cents, message):
                Text(WageWiseFormatters.hoursString(seconds: seconds))
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text(WageWiseFormatters.currencyString(cents: cents))
                    .font(.title3.bold())
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            case let .error(message, _):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text("Dieser Tag ist von den Summen ausgeschlossen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wageWiseCard(accent: settings.themeAccent.color)
    }

    private var emptyTodayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kein Eintrag für heute")
                .font(.headline)
            Text("Erstelle dein erstes Segment oder setze den Tagestyp.")
                .foregroundStyle(.secondary)
            Button("Heutigen Eintrag erstellen") {
                let day = DayEntry(date: Date(), type: .work)
                modelContext.insert(day)
                modelContext.persistIfPossible()
                showEditor = true
            }
            .buttonStyle(.wageWisePrimary(accent: settings.themeAccent.color))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wageWiseCard(accent: settings.themeAccent.color)
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            Button {
                if todayEntry == nil {
                    modelContext.insert(DayEntry(date: Date(), type: .work))
                    modelContext.persistIfPossible()
                }
                showEditor = true
            } label: {
                Label("Segment hinzufügen", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.wageWisePrimary(accent: settings.themeAccent.color))

            Button {
                // Timer mode intentionally omitted for reliability in 1.x baseline.
            } label: {
                Label("Timer", systemImage: "timer")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.wageWiseSecondary(accent: settings.themeAccent.color))
            .disabled(true)
            .accessibilityLabel("Timer-Modus nicht aktiviert")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wageWiseCard(accent: settings.themeAccent.color)
    }

    private var weekMonthCards: some View {
        VStack(spacing: 12) {
            summaryCard(title: "Diese Woche", summary: weekSummary)
            summaryCard(title: "Dieser Monat", summary: monthSummary)
        }
    }

    private func summaryCard(title: String, summary: TotalsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(WageWiseFormatters.hoursString(seconds: summary.totalSeconds))
                .font(.title2.bold())
            Text(WageWiseFormatters.currencyString(cents: summary.totalCents))
                .foregroundStyle(.secondary)
            if let weeklyTarget = settings.weeklyTargetSeconds, title == "Diese Woche" {
                let delta = summary.totalSeconds - weeklyTarget
                Text("Überstunden: \(WageWiseFormatters.hoursString(seconds: max(0, delta)))")
                    .font(.footnote)
                    .foregroundStyle(delta >= 0 ? .green : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wageWiseCard(accent: settings.themeAccent.color)
    }

    private func todayEntriesCard(for day: DayEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Eintraege heute")
                .font(.headline)

            if let manual = day.manualWorkedSeconds {
                HStack {
                    Text("Manuell erfasst")
                    Spacer()
                    Text(WageWiseFormatters.hoursString(seconds: manual))
                        .font(.subheadline.bold())
                }
                .padding(.vertical, 6)
            } else if day.segments.isEmpty {
                Text("Keine Segmente vorhanden.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(day.segments.enumerated()), id: \.offset) { idx, segment in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Segment \(idx + 1)")
                                .font(.subheadline.bold())
                            Text("\(WageWiseFormatters.time.string(from: segment.start)) - \(WageWiseFormatters.time.string(from: segment.end))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let duration = max(0, Int(segment.end.timeIntervalSince(segment.start)) - segment.breakSeconds)
                        Text(WageWiseFormatters.hoursString(seconds: duration))
                            .font(.footnote.bold())
                    }
                    .padding(.vertical, 6)
                    if idx < day.segments.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wageWiseCard(accent: settings.themeAccent.color)
    }
}
