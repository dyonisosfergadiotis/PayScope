import SwiftUI
import WidgetKit

private enum WatchWidgetStore {
    static let appGroupIdentifier = "group.DyonisosFergadiotis.PayScope"
    static let snapshotKey = "payscope.watch.snapshot.data.v1"
    static let fileName = "WatchShiftSnapshot.json"

    static func loadSnapshot() -> WatchWidgetSnapshot? {
        let decoder = JSONDecoder()

        if let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: snapshotKey),
           let snapshot = try? decoder.decode(WatchWidgetSnapshot.self, from: data) {
            return snapshot
        }

        guard let data = try? Data(contentsOf: snapshotFileURL) else {
            return nil
        }
        return try? decoder.decode(WatchWidgetSnapshot.self, from: data)
    }

    private static var snapshotFileURL: URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("PayScope", isDirectory: true)
            .appendingPathComponent(fileName)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}

private struct PayScopeWatchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PayScopeWatchWidgetEntry {
        PayScopeWatchWidgetEntry(
            date: .now,
            snapshot: WatchWidgetSnapshot.preview,
            focusDay: WatchWidgetDay.previewActive,
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
        let snapshot = WatchWidgetStore.loadSnapshot() ?? (isPlaceholder ? WatchWidgetSnapshot.preview : nil)
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
        .description("Zeigt die aktive oder nächste Schicht im Smart Stack.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct PayScope_AW_Complications: Widget {
    let kind = "PayScope_AW_Complications"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PayScopeWatchWidgetProvider()) { entry in
            PayScopeWatchWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("PayScope Komplikation")
        .description("Zeigt Schichtstatus, Restzeit oder Startzeit direkt auf dem Zifferblatt.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

private struct PayScopeWatchWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PayScopeWatchWidgetEntry

    private func accent(at now: Date) -> Color {
        currentDay(at: now)?.categoryColor ?? entry.snapshot?.themeAccent ?? .green
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
            TimelineView(.periodic(from: entry.date, by: 1)) { timeline in
                if let day = currentDay(at: timeline.date) {
                    rectangularShiftView(day: day, now: timeline.date)
                } else {
                    emptyRectangularView
                }
            }
        }
    }

    private func rectangularShiftView(day: WatchWidgetDay, now: Date) -> some View {
        let currentAccent = day.categoryColor

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: day.iconName)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(currentAccent)
                    .frame(width: 15, height: 15)

                Text(title(for: day, now: now))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 2)

                Text(payText(for: day, now: now))
                    .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(currentAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }

            Text(statusText(for: day, now: now))
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            HStack(alignment: .center, spacing: 5) {
                bottomMetric(label: "Start", value: startTimeText(for: day), alignment: .leading, frameAlignment: .leading)

                Spacer(minLength: 0)

                Text(durationText(for: day))
                    .font(.system(size: 10, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(currentAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(currentAccent.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                Spacer(minLength: 0)

                bottomMetric(label: "Ende", value: endTimeText(for: day), alignment: .trailing, frameAlignment: .trailing)
            }
        }
    }

    private func bottomMetric(label: String, value: String, alignment: HorizontalAlignment, frameAlignment: Alignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: 34, alignment: frameAlignment)
    }

    private func currentDay(at now: Date) -> WatchWidgetDay? {
        entry.snapshot?.focusDay(at: now) ?? entry.focusDay
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let day = entry.focusDay {
                Gauge(value: day.progress(at: entry.date)) {
                    Image(systemName: day.iconName)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(accent(at: entry.date))
            } else {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accent(at: entry.date))
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
        .tint(accent(at: entry.date))
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
                .foregroundStyle(accent(at: entry.date))

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

    private func title(for day: WatchWidgetDay, now: Date) -> String {
        day.isActive(at: now) ? "\(day.dayTypeLabel) läuft" : day.dayTypeLabel
    }

    private func statusText(for day: WatchWidgetDay, now: Date) -> String {
        if day.isActive(at: now), let end = day.shiftEnd {
            return "noch \(Self.countdownString(seconds: max(0, Int(end.timeIntervalSince(now)))))"
        }

        if day.isUpcoming(at: now), let start = day.shiftStart {
            return "in \(Self.countdownString(seconds: max(0, Int(start.timeIntervalSince(now)))))"
        }

        return "Heute"
    }

    private func startTimeText(for day: WatchWidgetDay) -> String {
        guard let start = day.shiftStart else { return "Ganzt." }
        return Self.timeFormatter.string(from: start)
    }

    private func endTimeText(for day: WatchWidgetDay) -> String {
        guard let end = day.shiftEnd else { return "-" }
        return Self.timeFormatter.string(from: end)
    }

    private func timeRangeText(for day: WatchWidgetDay) -> String {
        "\(startTimeText(for: day))-\(endTimeText(for: day))"
    }

    private func durationText(for day: WatchWidgetDay) -> String {
        Self.hoursString(seconds: day.displayedSeconds)
    }

    private func payText(for day: WatchWidgetDay, now: Date) -> String {
        let cents = day.isActive(at: now) ? day.earnedSoFarPayCents : day.payCents
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

    private static func countdownString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d h", hours, minutes, seconds)
        }
        return String(format: "%d:%02d min", minutes, seconds)
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

    init(
        generatedAt: Date,
        themeAccentRawValue: String,
        calendarSummaryDisplayModeRawValue: String,
        calendarHoursBreakModeRawValue: String,
        showTipsAmount: Bool,
        days: [WatchWidgetDay]
    ) {
        self.generatedAt = generatedAt
        self.themeAccentRawValue = themeAccentRawValue
        self.calendarSummaryDisplayModeRawValue = calendarSummaryDisplayModeRawValue
        self.calendarHoursBreakModeRawValue = calendarHoursBreakModeRawValue
        self.showTipsAmount = showTipsAmount
        self.days = days.sorted { $0.date < $1.date }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .distantPast
        themeAccentRawValue = try container.decodeIfPresent(String.self, forKey: .themeAccentRawValue) ?? "blue"
        calendarSummaryDisplayModeRawValue = try container.decodeIfPresent(String.self, forKey: .calendarSummaryDisplayModeRawValue) ?? "grossNet"
        calendarHoursBreakModeRawValue = try container.decodeIfPresent(String.self, forKey: .calendarHoursBreakModeRawValue) ?? "withoutBreak"
        showTipsAmount = try container.decodeIfPresent(Bool.self, forKey: .showTipsAmount) ?? true
        days = (try container.decodeIfPresent([WatchWidgetDay].self, forKey: .days) ?? [])
            .sorted { $0.date < $1.date }
    }

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

    init(
        date: Date,
        dayTypeRawValue: String,
        dayTypeLabel: String,
        iconName: String,
        categoryColorRawValue: String,
        workedSeconds: Int,
        payCents: Int,
        earnedSoFarSeconds: Int,
        earnedSoFarPayCents: Int,
        shiftStart: Date?,
        shiftEnd: Date?,
        breakSeconds: Int,
        tipAmountCents: Int,
        updatedAt: Date
    ) {
        self.date = date
        self.dayTypeRawValue = dayTypeRawValue
        self.dayTypeLabel = dayTypeLabel
        self.iconName = iconName
        self.categoryColorRawValue = categoryColorRawValue
        self.workedSeconds = workedSeconds
        self.payCents = payCents
        self.earnedSoFarSeconds = earnedSoFarSeconds
        self.earnedSoFarPayCents = earnedSoFarPayCents
        self.shiftStart = shiftStart
        self.shiftEnd = shiftEnd
        self.breakSeconds = breakSeconds
        self.tipAmountCents = tipAmountCents
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        dayTypeRawValue = try container.decodeIfPresent(String.self, forKey: .dayTypeRawValue) ?? "work"
        dayTypeLabel = try container.decodeIfPresent(String.self, forKey: .dayTypeLabel) ?? "Arbeit"
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "briefcase.fill"
        categoryColorRawValue = try container.decodeIfPresent(String.self, forKey: .categoryColorRawValue) ?? "blue"
        workedSeconds = try container.decodeIfPresent(Int.self, forKey: .workedSeconds) ?? 0
        payCents = try container.decodeIfPresent(Int.self, forKey: .payCents) ?? 0
        earnedSoFarSeconds = try container.decodeIfPresent(Int.self, forKey: .earnedSoFarSeconds) ?? workedSeconds
        earnedSoFarPayCents = try container.decodeIfPresent(Int.self, forKey: .earnedSoFarPayCents) ?? payCents
        shiftStart = try container.decodeIfPresent(Date.self, forKey: .shiftStart)
        shiftEnd = try container.decodeIfPresent(Date.self, forKey: .shiftEnd)
        breakSeconds = try container.decodeIfPresent(Int.self, forKey: .breakSeconds) ?? 0
        tipAmountCents = try container.decodeIfPresent(Int.self, forKey: .tipAmountCents) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
    }

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
        case "monochrome": return .primary
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

#if DEBUG
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
