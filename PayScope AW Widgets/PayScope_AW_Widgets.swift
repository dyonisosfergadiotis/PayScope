import SwiftUI
import WidgetKit

private enum WatchWidgetStore {
    static let appGroupIdentifier = "group.DyonisosFergadiotis.PayScope"
    static let snapshotKey = "payscope.watch.snapshot.data.v1"

    static func loadSnapshot() -> WatchWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(WatchWidgetSnapshot.self, from: data)
    }
}

private struct PayScopeWatchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PayScopeWatchWidgetEntry {
        PayScopeWatchWidgetEntry(
            date: .now,
            snapshot: .preview,
            focusDay: .previewActive,
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PayScopeWatchWidgetEntry) -> Void) {
        completion(entry(at: .now, isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PayScopeWatchWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WatchWidgetStore.loadSnapshot()
        let dates = refreshDates(from: snapshot, now: now)
        let entries = dates.map { date in
            PayScopeWatchWidgetEntry(
                date: date,
                snapshot: snapshot,
                focusDay: snapshot?.focusDay(at: date),
                isPlaceholder: false
            )
        }

        completion(Timeline(entries: entries, policy: .after(nextReloadDate(from: dates, now: now))))
    }

    private func entry(at date: Date, isPlaceholder: Bool) -> PayScopeWatchWidgetEntry {
        let snapshot = WatchWidgetStore.loadSnapshot() ?? (isPlaceholder ? .preview : nil)
        return PayScopeWatchWidgetEntry(
            date: date,
            snapshot: snapshot,
            focusDay: snapshot?.focusDay(at: date),
            isPlaceholder: isPlaceholder
        )
    }

    private func refreshDates(from snapshot: WatchWidgetSnapshot?, now: Date) -> [Date] {
        var candidates: Set<Date> = [now]
        if let focus = snapshot?.focusDay(at: now) {
            if let start = focus.shiftStart, start > now {
                candidates.insert(start)
            }
            if let end = focus.shiftEnd, end > now {
                candidates.insert(end)
            }
        }
        if let next = snapshot?.nextTimedShift(after: now)?.shiftStart, next > now {
            candidates.insert(next)
        }
        if let nextMinute = Calendar.current.date(byAdding: .minute, value: 15, to: now) {
            candidates.insert(nextMinute)
        }
        return candidates.sorted()
    }

    private func nextReloadDate(from dates: [Date], now: Date) -> Date {
        dates.first(where: { $0 > now.addingTimeInterval(1) })
            ?? Calendar.current.date(byAdding: .minute, value: 15, to: now)
            ?? now.addingTimeInterval(15 * 60)
    }
}

private struct PayScopeWatchWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchWidgetSnapshot?
    let focusDay: WatchWidgetDay?
    let isPlaceholder: Bool
}

struct PayScope_AW_Widgets: Widget {
    let kind = "PayScope_AW_Widgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PayScopeWatchWidgetProvider()) { entry in
            PayScopeWatchWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("PayScope Schicht")
        .description("Zeigt die aktive oder nächste Schicht im Smart Stack und auf Zifferblättern.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

private struct PayScopeWatchWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PayScopeWatchWidgetEntry

    private var accent: Color {
        entry.focusDay?.categoryColor ?? entry.snapshot?.themeAccent ?? .green
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                cornerView
            case .accessoryCircular:
                circularView
            case .accessoryInline:
                inlineView
            default:
                rectangularView
            }
        }
        .widgetAccentable()
    }

    private var rectangularView: some View {
        Group {
            if let day = entry.focusDay {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: day.iconName)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(accent)

                        Text(title(for: day))
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Spacer(minLength: 2)

                        Text(payText(for: day))
                            .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(timeRangeText(for: day))
                            .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Spacer(minLength: 2)

                        Text(durationText(for: day))
                            .font(.system(size: 10, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }

                    Text(statusText(for: day))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            } else {
                emptyRectangularView
            }
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let day = entry.focusDay {
                Gauge(value: day.progress(at: entry.date)) {
                    Image(systemName: day.iconName)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(accent)
            } else {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
    }

    private var cornerView: some View {
        Gauge(value: entry.focusDay?.progress(at: entry.date) ?? 0) {
            Image(systemName: entry.focusDay?.iconName ?? "calendar.badge.clock")
        } currentValueLabel: {
            Text(cornerValueText)
                .font(.system(size: 11, weight: .black, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.58)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(accent)
    }

    private var inlineView: some View {
        if let day = entry.focusDay {
            Text("\(day.dayTypeLabel) \(timeRangeText(for: day))")
        } else {
            Text("PayScope keine Schicht")
        }
    }

    private var cornerValueText: String {
        guard let day = entry.focusDay else { return "--" }
        if day.isActive(at: entry.date), let end = day.shiftEnd {
            let remaining = max(0, Int(end.timeIntervalSince(entry.date)))
            return Self.compactHoursString(seconds: remaining)
        }
        guard let start = day.shiftStart else { return day.dayTypeLabel }
        return Self.timeFormatter.string(from: start)
    }

    private var emptyRectangularView: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Keine Schicht")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .lineLimit(1)

                Text(entry.isPlaceholder ? "PayScope" : "Öffne die App zum Laden")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func title(for day: WatchWidgetDay) -> String {
        day.isActive(at: entry.date) ? "\(day.dayTypeLabel) läuft" : day.dayTypeLabel
    }

    private func statusText(for day: WatchWidgetDay) -> String {
        if day.isActive(at: entry.date), let end = day.shiftEnd {
            return "noch \(Self.hoursString(seconds: max(0, Int(end.timeIntervalSince(entry.date)))))"
        }

        if day.isUpcoming(at: entry.date) {
            return day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }

        return "Heute"
    }

    private func timeRangeText(for day: WatchWidgetDay) -> String {
        guard let start = day.shiftStart, let end = day.shiftEnd else {
            return "Ganztägig"
        }
        return "\(Self.timeFormatter.string(from: start))-\(Self.timeFormatter.string(from: end))"
    }

    private func durationText(for day: WatchWidgetDay) -> String {
        Self.hoursString(seconds: day.displayedSeconds)
    }

    private func payText(for day: WatchWidgetDay) -> String {
        let cents = day.isActive(at: entry.date) ? day.earnedSoFarPayCents : day.payCents
        return Self.currencyFormatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "0,00 €"
    }

    private static func hoursString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d h", clamped / 3600, (clamped % 3600) / 60)
    }

    private static func compactHoursString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

private struct WatchWidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var themeAccentRawValue: String
    var calendarSummaryDisplayModeRawValue: String
    var calendarHoursBreakModeRawValue: String
    var showTipsAmount: Bool
    var days: [WatchWidgetDay]

    var themeAccent: Color {
        WatchWidgetColorPalette.color(for: themeAccentRawValue)
    }

    var displayDays: [WatchWidgetDay] {
        days.sorted { $0.date < $1.date }
    }

    func focusDay(at now: Date) -> WatchWidgetDay? {
        if let active = displayDays.first(where: { $0.isActive(at: now) }) {
            return active
        }

        let today = Calendar.current.startOfDay(for: now)
        if let todayDay = displayDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            if let end = todayDay.shiftEnd,
               now >= end.addingTimeInterval(15 * 60),
               let next = nextTimedShift(after: now) {
                return next
            }
            return todayDay
        }

        return nextTimedShift(after: now)
    }

    func nextTimedShift(after now: Date) -> WatchWidgetDay? {
        displayDays
            .filter { day in
                guard let start = day.shiftStart, let end = day.shiftEnd, end > start else { return false }
                return start > now
            }
            .min { ($0.shiftStart ?? .distantFuture) < ($1.shiftStart ?? .distantFuture) }
    }
}

private struct WatchWidgetDay: Codable, Equatable {
    var date: Date
    var dayTypeRawValue: String
    var dayTypeLabel: String
    var iconName: String
    var categoryColorRawValue: String
    var workedSeconds: Int
    var payCents: Int
    var earnedSoFarSeconds: Int
    var earnedSoFarPayCents: Int
    var shiftStart: Date?
    var shiftEnd: Date?
    var breakSeconds: Int
    var tipAmountCents: Int
    var updatedAt: Date

    var categoryColor: Color {
        WatchWidgetColorPalette.color(for: categoryColorRawValue)
    }

    var displayedSeconds: Int {
        guard let start = shiftStart, let end = shiftEnd, end > start else {
            return workedSeconds
        }
        return max(0, Int(end.timeIntervalSince(start)))
    }

    func isActive(at now: Date) -> Bool {
        guard let start = shiftStart, let end = shiftEnd, end > start else { return false }
        return now >= start && now < end
    }

    func isUpcoming(at now: Date) -> Bool {
        guard let start = shiftStart, let end = shiftEnd, end > start else { return false }
        return start > now
    }

    func progress(at now: Date) -> Double {
        guard let start = shiftStart, let end = shiftEnd, end > start else { return 0 }
        let total = max(1, end.timeIntervalSince(start))
        let elapsed = min(max(now.timeIntervalSince(start), 0), total)
        return min(max(elapsed / total, 0), 1)
    }
}

private enum WatchWidgetColorPalette {
    static func color(for rawValue: String) -> Color {
        switch rawValue {
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "pink": return Color(red: 1.0, green: 0.36, blue: 0.64)
        case "teal": return .teal
        case "red": return .red
        case "indigo": return .indigo
        case "mint": return Color(red: 0.22, green: 0.78, blue: 0.56)
        case "sage": return Color(red: 0.46, green: 0.72, blue: 0.30)
        case "sky": return Color(red: 0.24, green: 0.58, blue: 0.92)
        case "aqua": return Color(red: 0.16, green: 0.72, blue: 0.78)
        case "lavender": return Color(red: 0.52, green: 0.42, blue: 0.88)
        case "lilac": return Color(red: 0.70, green: 0.38, blue: 0.86)
        case "blush": return Color(red: 0.90, green: 0.32, blue: 0.54)
        case "peach": return Color(red: 0.94, green: 0.52, blue: 0.30)
        case "butter": return Color(red: 0.88, green: 0.70, blue: 0.16)
        case "coral": return Color(red: 0.90, green: 0.34, blue: 0.30)
        default: return .blue
        }
    }
}

#if DEBUG
extension WatchWidgetSnapshot {
    static let preview = WatchWidgetSnapshot(
        generatedAt: .now,
        themeAccentRawValue: "green",
        calendarSummaryDisplayModeRawValue: "grossNet",
        calendarHoursBreakModeRawValue: "withBreak",
        showTipsAmount: true,
        days: [.previewActive]
    )
}

extension WatchWidgetDay {
    static let previewActive = WatchWidgetDay(
        date: .now,
        dayTypeRawValue: "work",
        dayTypeLabel: "Arbeit",
        iconName: "briefcase.fill",
        categoryColorRawValue: "green",
        workedSeconds: 7 * 3600,
        payCents: 10801,
        earnedSoFarSeconds: 5 * 3600 + 20 * 60,
        earnedSoFarPayCents: 8245,
        shiftStart: Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: .now),
        shiftEnd: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now),
        breakSeconds: 0,
        tipAmountCents: 0,
        updatedAt: .now
    )
}

#Preview(as: .accessoryRectangular) {
    PayScope_AW_Widgets()
} timeline: {
    PayScopeWatchWidgetEntry(date: .now, snapshot: .preview, focusDay: .previewActive, isPlaceholder: true)
}

#Preview(as: .accessoryCircular) {
    PayScope_AW_Widgets()
} timeline: {
    PayScopeWatchWidgetEntry(date: .now, snapshot: .preview, focusDay: .previewActive, isPlaceholder: true)
}

#Preview(as: .accessoryCorner) {
    PayScope_AW_Widgets()
} timeline: {
    PayScopeWatchWidgetEntry(date: .now, snapshot: .preview, focusDay: .previewActive, isPlaceholder: true)
}
#endif
