//
//  PayScope_WidgetsLiveActivity.swift
//  PayScope Widgets
//
//  Created by Dyonisos Fergadiotis on 18.02.26.
//

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct PayScope_WidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var workedTodaySeconds: Int
        var workedReferenceStart: Date
        var shiftCategoryIcon: String
        var themeAccentRawValue: String
        var shiftCategoryColorRawValue: String? = nil
        var isTimedShift: Bool? = true
        var isCompleted: Bool
        var completedPayCents: Int
        var nextShiftStart: Date?
        var nextShiftDurationSeconds: Int
        var isPaused: Bool
        var pauseStartedAt: Date?
    }

    var title: String
    var timelineStart: Date
    var timelineEnd: Date
}

struct PayScope_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PayScope_WidgetsAttributes.self) { context in
            PayScopeLiveActivityLockScreenContent(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    PayScopeLiveActivityExpandedContent(context: context)
                }
            } compactLeading: {
                if liveActivityPhase(for: context) == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(liveActivityAccent(for: context.state))
                } else {
                    switch liveActivityPhase(for: context) {
                    case .active:
                        PayScopeLiveActivityProgressRing(context: context)
                    case .upcoming:
                        Image(systemName: context.state.shiftCategoryIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(liveActivityAccent(for: context.state))
                    case .completed:
                        EmptyView()
                    }
                }
            } compactTrailing: {
                switch liveActivityPhase(for: context) {
                case .completed:
                    Text(Self.nextShiftCompactString(context.state.nextShiftStart))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(liveActivityAccent(for: context.state))
                case .upcoming:
                    Text(Self.nextShiftCompactString(context.attributes.timelineStart))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(liveActivityAccent(for: context.state))
                case .active:
                    Text(Self.activeCompactTrailingText(context))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(liveActivityAccent(for: context.state))
                }
            } minimal: {
                Image(systemName: liveActivityPhase(for: context) == .completed ? "checkmark.circle.fill" : (context.state.isPaused ? "pause.circle.fill" : context.state.shiftCategoryIcon))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(liveActivityAccent(for: context.state))
            }
            .keylineTint(liveActivityAccent(for: context.state))
        }
        .supplementalActivityFamilies([.small, .medium])
    }

    private static func nextShiftCompactString(_ start: Date?) -> String {
        guard let start else { return "--:--" }

        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now),
           calendar.isDate(start, inSameDayAs: tomorrow) {
            return "M \(compactTimeString(start))"
        }

        return compactTimeString(start)
    }

    private static func activeCompactTrailingText(_ context: ActivityViewContext<PayScope_WidgetsAttributes>) -> String {
        if context.state.isTimedShift == false {
            return currencyString(cents: context.state.completedPayCents)
        }

        return context.state.isPaused
            ? "Pause"
            : endTimeString(
                start: context.attributes.timelineStart,
                end: context.attributes.timelineEnd,
                fallback: context.attributes.timelineEnd
            )
    }

    private static func compactTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct PayScope_WidgetsRectangularLockScreen: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "PayScopeRectangularLockScreenWidget",
            provider: PayScopeRectangularProvider()
        ) { entry in
            PayScopeRectangularLockScreenContent(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("PayScope Live Rechteck")
        .description("Lock-Screen-Widget im Stil der Live Activity.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct PayScope_WidgetsInlineLockScreen: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "PayScopeInlineLockScreenWidget",
            provider: PayScopeRectangularProvider()
        ) { entry in
            PayScopeInlineLockScreenContent(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("PayScope Live Inline")
        .description("Inline-Lock-Screen-Widget mit Schichtstatus.")
        .supportedFamilies([.accessoryInline])
    }
}

struct PayScope_CurrentShiftCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "PayScopeCurrentShiftCardWidget",
            provider: PayScopeRectangularProvider()
        ) { entry in
            PayScopeCurrentShiftCardContent(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Aktuelle Schicht")
        .description("Zeigt deine aktuelle oder nächste Schicht als kompakte PayScope-Karte.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private enum PayScopeRectangularSharedStore {
    static let appGroupIdentifier = "group.DyonisosFergadiotis.PayScope"
    static let snapshotKey = "payscope.rectangularWidgetSnapshot.v1"
}

struct PayScopeRectangularSnapshot: Codable {
    let themeAccentRawValue: String
    let isShiftActive: Bool
    let shiftCategoryTitle: String?
    let shiftCategoryIcon: String?
    let shiftStart: Date?
    let shiftEnd: Date?
    let shiftDurationSeconds: Int
    let workedReferenceStart: Date?
    let workedTodaySeconds: Int?
    let completedPayCents: Int?
    let nextShiftStart: Date?
    let isAllDayStatus: Bool?
    let allDayYear: Int?
    let allDayMonth: Int?
    let allDayDay: Int?
}

extension PayScopeRectangularSnapshot {
    var hasAllDayStatus: Bool {
        isAllDayStatus == true && shiftCategoryTitle != nil
    }

    var allDayDisplayDate: Date? {
        guard
            let allDayYear,
            let allDayMonth,
            let allDayDay
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        components.year = allDayYear
        components.month = allDayMonth
        components.day = allDayDay
        components.hour = 12
        return components.date
    }
}

struct PayScopeRectangularProvider: TimelineProvider {
    func placeholder(in context: Context) -> PayScopeRectangularEntry {
        .previewActive(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PayScopeRectangularEntry) -> Void) {
        completion(Self.entry(for: .now, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PayScopeRectangularEntry>) -> Void) {
        let now = Date()
        let entry = Self.entry(for: now, isPreview: context.isPreview)
        let entries = Self.timelineEntries(for: entry, now: now)
        let reloadAnchor = entries.last?.date ?? now
        let nextRefresh = Self.nextRefreshDate(for: entry.snapshot, now: reloadAnchor)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private static func entry(for now: Date, isPreview: Bool) -> PayScopeRectangularEntry {
        if let snapshot = loadSnapshot() {
            return PayScopeRectangularEntry(date: now, snapshot: snapshot)
        }

        if isPreview {
            return .previewActive(date: now)
        }

        return .previewEmpty(date: now)
    }

    private static func loadSnapshot() -> PayScopeRectangularSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: PayScopeRectangularSharedStore.appGroupIdentifier),
            let data = defaults.data(forKey: PayScopeRectangularSharedStore.snapshotKey)
        else {
            return nil
        }

        return try? JSONDecoder().decode(PayScopeRectangularSnapshot.self, from: data)
    }

    private static func timelineEntries(for entry: PayScopeRectangularEntry, now: Date) -> [PayScopeRectangularEntry] {
        let futureDates = transitionDates(for: entry.snapshot, now: now)
        let uniqueSortedDates = Array(Set(futureDates))
            .filter { $0 > now }
            .sorted()

        return [entry] + uniqueSortedDates.map { PayScopeRectangularEntry(date: $0, snapshot: entry.snapshot) }
    }

    private static func nextRefreshDate(for snapshot: PayScopeRectangularSnapshot, now: Date) -> Date {
        let fallbackRefresh = now.addingTimeInterval(30 * 60)
        var refreshCandidates = transitionDates(for: snapshot, now: now)

        if let nextShiftStart = snapshot.nextShiftStart, nextShiftStart > now {
            refreshCandidates.append(nextShiftStart)
        }

        return refreshCandidates
            .filter { $0 > now }
            .min() ?? fallbackRefresh
    }

    private static func transitionDates(for snapshot: PayScopeRectangularSnapshot, now: Date) -> [Date] {
        let calendar = Calendar.current
        var transitionDates: [Date] = []

        if snapshot.hasAllDayStatus,
           let allDayDisplayDate = snapshot.allDayDisplayDate
        {
            let startOfDay = calendar.startOfDay(for: allDayDisplayDate)
            if let nextDayStart = calendar.date(byAdding: .day, value: 1, to: startOfDay),
               now < nextDayStart {
                transitionDates.append(nextDayStart)
            }
        }

        if
            let shiftStart = snapshot.shiftStart,
            let shiftEnd = snapshot.shiftEnd,
            shiftEnd > shiftStart
        {
            if now < shiftStart {
                if let nextDayStart = nextDayBoundary(after: now, calendar: calendar),
                   nextDayStart < shiftStart {
                    transitionDates.append(nextDayStart)
                }

                transitionDates.append(shiftStart)
            }

            if now < shiftEnd {
                transitionDates.append(shiftEnd)
            }
        }

        if let nextShiftStart = snapshot.nextShiftStart, nextShiftStart > now {
            if let nextDayStart = nextDayBoundary(after: now, calendar: calendar),
               nextDayStart < nextShiftStart {
                transitionDates.append(nextDayStart)
            }
        }

        return transitionDates
    }

    private static func nextDayBoundary(after date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }
}

struct PayScopeRectangularEntry: TimelineEntry {
    let date: Date
    let snapshot: PayScopeRectangularSnapshot
}

extension PayScopeRectangularEntry {
    static func previewActive(date: Date) -> PayScopeRectangularEntry {
        let start = date.addingTimeInterval(-2 * 3600)
        let end = date.addingTimeInterval(6 * 3600)
        return PayScopeRectangularEntry(
            date: date,
            snapshot: PayScopeRectangularSnapshot(
                themeAccentRawValue: "blue",
                isShiftActive: true,
                shiftCategoryTitle: "Arbeit",
                shiftCategoryIcon: "briefcase.fill",
                shiftStart: start,
                shiftEnd: end,
                shiftDurationSeconds: 8 * 3600,
                workedReferenceStart: start,
                workedTodaySeconds: 2 * 3600,
                completedPayCents: 3400,
                nextShiftStart: nil,
                isAllDayStatus: nil,
                allDayYear: nil,
                allDayMonth: nil,
                allDayDay: nil
            )
        )
    }

    static func previewNextShift(date: Date) -> PayScopeRectangularEntry {
        let nextShift = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        let nextShiftEnd = nextShift.addingTimeInterval(8 * 3600)
        let followingShift = Calendar.current.date(byAdding: .day, value: 1, to: nextShift) ?? nextShift
        return PayScopeRectangularEntry(
            date: date,
            snapshot: PayScopeRectangularSnapshot(
                themeAccentRawValue: "green",
                isShiftActive: false,
                shiftCategoryTitle: "Arbeit",
                shiftCategoryIcon: "briefcase.fill",
                shiftStart: nextShift,
                shiftEnd: nextShiftEnd,
                shiftDurationSeconds: 8 * 3600,
                workedReferenceStart: nil,
                workedTodaySeconds: nil,
                completedPayCents: nil,
                nextShiftStart: followingShift,
                isAllDayStatus: nil,
                allDayYear: nil,
                allDayMonth: nil,
                allDayDay: nil
            )
        )
    }

    static func previewEmpty(date: Date) -> PayScopeRectangularEntry {
        PayScopeRectangularEntry(
            date: date,
            snapshot: PayScopeRectangularSnapshot(
                themeAccentRawValue: "blue",
                isShiftActive: false,
                shiftCategoryTitle: nil,
                shiftCategoryIcon: nil,
                shiftStart: nil,
                shiftEnd: nil,
                shiftDurationSeconds: 0,
                workedReferenceStart: nil,
                workedTodaySeconds: nil,
                completedPayCents: nil,
                nextShiftStart: nil,
                isAllDayStatus: nil,
                allDayYear: nil,
                allDayMonth: nil,
                allDayDay: nil
            )
        )
    }

    static func previewAllDay(date: Date) -> PayScopeRectangularEntry {
        let dayComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return PayScopeRectangularEntry(
            date: date,
            snapshot: PayScopeRectangularSnapshot(
                themeAccentRawValue: "green",
                isShiftActive: false,
                shiftCategoryTitle: "Urlaub",
                shiftCategoryIcon: "sun.max.fill",
                shiftStart: nil,
                shiftEnd: nil,
                shiftDurationSeconds: 0,
                workedReferenceStart: nil,
                workedTodaySeconds: nil,
                completedPayCents: nil,
                nextShiftStart: Calendar.current.date(byAdding: .day, value: 1, to: date),
                isAllDayStatus: true,
                allDayYear: dayComponents.year,
                allDayMonth: dayComponents.month,
                allDayDay: dayComponents.day
            )
        )
    }

    static func previewLongDuration(date: Date) -> PayScopeRectangularEntry {
        let start = date.addingTimeInterval(-(123 * 3600 + 45 * 60))
        let end = date.addingTimeInterval(30 * 60)
        return PayScopeRectangularEntry(
            date: date,
            snapshot: PayScopeRectangularSnapshot(
                themeAccentRawValue: "orange",
                isShiftActive: true,
                shiftCategoryTitle: "Lange Schicht",
                shiftCategoryIcon: "clock.fill",
                shiftStart: start,
                shiftEnd: end,
                shiftDurationSeconds: 123 * 3600 + 45 * 60,
                workedReferenceStart: start,
                workedTodaySeconds: 123 * 3600 + 15 * 60,
                completedPayCents: 209525,
                nextShiftStart: nil,
                isAllDayStatus: nil,
                allDayYear: nil,
                allDayMonth: nil,
                allDayDay: nil
            )
        )
    }
}

private struct PayScopeRectangularLockScreenContent: View {
    let entry: PayScopeRectangularEntry

    private var accent: Color {
        liveAccentColor(from: entry.snapshot.themeAccentRawValue)
    }

    private var displayedShiftCategoryIcon: String {
        entry.snapshot.shiftCategoryIcon ?? "briefcase.fill"
    }

    private var displayedShiftCategoryTitle: String {
        entry.snapshot.shiftCategoryTitle ?? "Arbeit"
    }

    private var isShiftActive: Bool {
        guard
            let shiftStart = entry.snapshot.shiftStart,
            let shiftEnd = entry.snapshot.shiftEnd,
            shiftEnd > shiftStart
        else {
            return false
        }

        return entry.date >= shiftStart && entry.date < shiftEnd
    }

    private var isAllDayStatus: Bool {
        guard
            entry.snapshot.hasAllDayStatus,
            let allDayDisplayDate
        else {
            return false
        }

        return Calendar.current.isDate(allDayDisplayDate, inSameDayAs: entry.date)
    }

    private var allDayDisplayDate: Date? {
        entry.snapshot.allDayDisplayDate
    }

    private var nextShiftStartForDisplay: Date? {
        if
            let shiftStart = entry.snapshot.shiftStart,
            let shiftEnd = entry.snapshot.shiftEnd,
            shiftEnd > shiftStart,
            entry.date < shiftStart
        {
            return shiftStart
        }

        if let nextShiftStart = entry.snapshot.nextShiftStart, nextShiftStart > entry.date {
            return nextShiftStart
        }

        return nil
    }

    var body: some View {
        if isShiftActive {
            activeShiftView
        } else if isAllDayStatus {
            allDayStatusView
        } else {
            nextShiftView
        }
    }

    private var activeShiftView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: displayedShiftCategoryIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)

                Text(displayedShiftCategoryTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let shiftEnd = entry.snapshot.shiftEnd {
                RemainingTimerText(end: shiftEnd)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("00:00:00")
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(timeString(entry.snapshot.shiftStart ?? entry.date))
                    .font(.system(size: 10, weight: .regular, design: .default).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                Text(hhmmString(from: entry.snapshot.shiftDurationSeconds))
                    .font(.system(size: 10, weight: .semibold, design: .default).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .allowsTightening(true)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                Text(endTimeString(start: entry.snapshot.shiftStart, end: entry.snapshot.shiftEnd, fallback: entry.date))
                    .font(.system(size: 10, weight: .regular, design: .default).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allDayStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: displayedShiftCategoryIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)

                Text(displayedShiftCategoryTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let allDayDisplayDate {
                Text(allDayStatusDateString(allDayDisplayDate))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
            }

            Text("Ganztag")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var nextShiftView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let nextShiftStart = nextShiftStartForDisplay {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: displayedShiftCategoryIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)

                    Text(displayedShiftCategoryTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(nextShiftDateString(nextShiftStart))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                Text(timeString(nextShiftStart))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
            } else {
                Text("Keine Schicht geplant")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct PayScopeInlineLockScreenContent: View {
    let entry: PayScopeRectangularEntry

    private var displayedShiftCategoryIcon: String {
        entry.snapshot.shiftCategoryIcon ?? "briefcase.fill"
    }

    private var displayedShiftCategoryTitle: String {
        entry.snapshot.shiftCategoryTitle ?? "Arbeit"
    }

    private var isShiftActive: Bool {
        guard
            let shiftStart = entry.snapshot.shiftStart,
            let shiftEnd = entry.snapshot.shiftEnd,
            shiftEnd > shiftStart
        else {
            return false
        }

        return entry.date >= shiftStart && entry.date < shiftEnd
    }

    private var isAllDayStatus: Bool {
        guard
            entry.snapshot.hasAllDayStatus,
            let allDayDisplayDate
        else {
            return false
        }

        return Calendar.current.isDate(allDayDisplayDate, inSameDayAs: entry.date)
    }

    private var allDayDisplayDate: Date? {
        entry.snapshot.allDayDisplayDate
    }

    private var nextShiftStartForDisplay: Date? {
        if
            let shiftStart = entry.snapshot.shiftStart,
            let shiftEnd = entry.snapshot.shiftEnd,
            shiftEnd > shiftStart,
            entry.date < shiftStart
        {
            return shiftStart
        }

        if let nextShiftStart = entry.snapshot.nextShiftStart, nextShiftStart > entry.date {
            return nextShiftStart
        }

        return nil
    }

    var body: some View {
        if isShiftActive {
            HStack(spacing: 4) {
                Image(systemName: displayedShiftCategoryIcon)
                if let shiftEnd = entry.snapshot.shiftEnd {
                    RemainingTimerText(end: shiftEnd)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .allowsTightening(true)
                } else {
                    Text("00:00:00")
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .allowsTightening(true)
                }
            }
        } else if isAllDayStatus {
            HStack(spacing: 4) {
                Image(systemName: displayedShiftCategoryIcon)
                Text(allDayStatusInlineString(title: displayedShiftCategoryTitle, date: allDayDisplayDate))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
            }
        } else if let nextShiftStart = nextShiftStartForDisplay {
            HStack(spacing: 4) {
                Image(systemName: displayedShiftCategoryIcon)
                Text(nextShiftInlineString(nextShiftStart))
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
            }
        } else {
            Text("Keine Schicht geplant")
                .lineLimit(1)
        }
    }
}

private struct PayScopeCurrentShiftCardContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: PayScopeRectangularEntry

    private var accent: Color {
        liveAccentColor(from: entry.snapshot.themeAccentRawValue)
    }

    private var icon: String {
        entry.snapshot.shiftCategoryIcon ?? "briefcase.fill"
    }

    private var title: String {
        entry.snapshot.shiftCategoryTitle ?? "Arbeit"
    }

    var body: some View {
        TimelineView(.periodic(from: entry.date, by: 60)) { timeline in
            cardContent(at: timeline.date)
                .padding(family == .systemSmall ? 14 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: family == .systemSmall ? 26 : 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: family == .systemSmall ? 26 : 30, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: family == .systemSmall ? 26 : 30, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                }
                .padding(6)
        }
    }

    @ViewBuilder
    private func cardContent(at now: Date) -> some View {
        if isActive(at: now) {
            activeShiftCard(at: now)
        } else if isAllDayStatus(at: now) {
            allDayCard
        } else if let nextStart = nextShiftStartForDisplay(at: now) {
            upcomingShiftCard(start: nextStart)
        } else {
            emptyCard
        }
    }

    private func activeShiftCard(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 12) {
            header(status: "Aktiv", statusIcon: "bolt.fill")

            HStack(alignment: .top) {
                Text(workedTitle(at: now))
                    .font(.system(size: family == .systemSmall ? 30 : 38, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(remainingText(at: now))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }

            progressTrack(progress: progress(at: now))

            HStack {
                Text(timeString(entry.snapshot.shiftStart ?? now))
                Spacer(minLength: 8)
                Text(endTimeString(start: entry.snapshot.shiftStart, end: entry.snapshot.shiftEnd, fallback: now))
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.62)

            if family == .systemMedium {
                HStack(spacing: 10) {
                    metric("Dauer", hhmmString(from: entry.snapshot.shiftDurationSeconds))
                    if let cents = entry.snapshot.completedPayCents {
                        metric("Lohn", currencyString(cents: cents))
                    }
                }
            } else {
                HStack {
                    Text(hhmmString(from: entry.snapshot.shiftDurationSeconds))
                    Spacer(minLength: 8)
                    if let cents = entry.snapshot.completedPayCents {
                        Text(currencyString(cents: cents))
                    }
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            }
        }
    }

    private var allDayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(status: "Heute", statusIcon: "calendar")
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: family == .systemSmall ? 28 : 34, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("Ganztag")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func upcomingShiftCard(start: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(status: "Nächste", statusIcon: "clock.fill")
            Spacer(minLength: 0)
            Text(nextShiftDateString(start))
                .font(.system(size: family == .systemSmall ? 24 : 32, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .foregroundStyle(.primary)
            Text("\(timeString(start)) Uhr")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(accent)
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(status: "PayScope", statusIcon: "sparkle")
            Spacer(minLength: 0)
            Text("Keine Schicht")
                .font(.system(size: family == .systemSmall ? 24 : 32, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Heute ist nichts geplant")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func header(status: String, statusIcon: String) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: family == .systemSmall ? 15 : 17, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: family == .systemSmall ? 32 : 36, height: family == .systemSmall ? 32 : 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Label(status, systemImage: statusIcon)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressTrack(progress: Double) -> some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width * min(max(progress, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.16))
                Capsule()
                    .fill(accent)
                    .frame(width: width)
                    .shadow(color: accent.opacity(0.35), radius: 7, y: 1)
            }
        }
        .frame(height: family == .systemSmall ? 7 : 8)
    }

    private func isActive(at now: Date) -> Bool {
        guard
            let start = entry.snapshot.shiftStart,
            let end = entry.snapshot.shiftEnd,
            end > start
        else {
            return false
        }

        return now >= start && now < end
    }

    private func isAllDayStatus(at now: Date) -> Bool {
        guard entry.snapshot.hasAllDayStatus, let date = entry.snapshot.allDayDisplayDate else {
            return false
        }
        return Calendar.current.isDate(date, inSameDayAs: now)
    }

    private func nextShiftStartForDisplay(at now: Date) -> Date? {
        if
            let start = entry.snapshot.shiftStart,
            let end = entry.snapshot.shiftEnd,
            end > start,
            now < start
        {
            return start
        }

        if let nextShiftStart = entry.snapshot.nextShiftStart, nextShiftStart > now {
            return nextShiftStart
        }

        return nil
    }

    private func workedSeconds(at now: Date) -> Int {
        if let referenceStart = entry.snapshot.workedReferenceStart {
            return max(0, Int(now.timeIntervalSince(referenceStart)))
        }

        guard let start = entry.snapshot.shiftStart else {
            return entry.snapshot.workedTodaySeconds ?? 0
        }

        return max(0, Int(now.timeIntervalSince(start)))
    }

    private func workedTitle(at now: Date) -> String {
        "\(hhmmString(from: workedSeconds(at: now))) h"
    }

    private func remainingText(at now: Date) -> String {
        guard let end = entry.snapshot.shiftEnd else { return "läuft" }
        let remaining = max(0, Int(end.timeIntervalSince(now)))
        return "\(hhmmString(from: remaining)) h übrig"
    }

    private func progress(at now: Date) -> Double {
        let total = max(1, entry.snapshot.shiftDurationSeconds)
        return min(max(Double(workedSeconds(at: now)) / Double(total), 0), 1)
    }
}

private struct PayScopeWatchLiveActivitySmallContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>
    let now: Date

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    private var phase: LiveActivityPhase {
        liveActivityPhase(for: context)
    }

    var body: some View {
        VStack(spacing: 7) {
            PayScopeWatchActivityRing(
                progress: ringProgress,
                iconName: iconName,
                accent: accent,
                lineWidth: 5
            )
            .frame(width: 48, height: 48)

            VStack(spacing: 1) {
                Text(primaryText)
                    .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)

                Text(secondaryText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PayScopeLiveActivityEdgeFade(accent: accent)
        }
    }

    private var ringProgress: Double {
        switch phase {
        case .completed:
            return 1
        case .upcoming:
            return 0
        case .active:
            return context.state.isTimedShift == false ? 1 : liveActivityProgress(for: context, now: now)
        }
    }

    private var iconName: String {
        switch phase {
        case .completed:
            return "checkmark"
        case .upcoming:
            return context.state.shiftCategoryIcon
        case .active:
            return context.state.isPaused ? "pause.fill" : context.state.shiftCategoryIcon
        }
    }

    private var primaryText: String {
        switch phase {
        case .completed:
            return currencyString(cents: context.state.completedPayCents)
        case .upcoming:
            return timeString(context.attributes.timelineStart)
        case .active:
            if context.state.isTimedShift == false {
                return hhmmString(from: context.state.workedTodaySeconds)
            }
            if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                return hhmmString(from: max(0, Int(min(now, context.attributes.timelineEnd).timeIntervalSince(pauseStartedAt))))
            }
            return hhmmString(from: max(0, Int(context.attributes.timelineEnd.timeIntervalSince(now))))
        }
    }

    private var secondaryText: String {
        switch phase {
        case .completed:
            return "fertig"
        case .upcoming:
            return "Start"
        case .active:
            return context.state.isPaused ? "Pause" : "läuft"
        }
    }
}

private struct PayScopeWatchLiveActivityMediumContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>
    let now: Date

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    private var phase: LiveActivityPhase {
        liveActivityPhase(for: context)
    }

    var body: some View {
        HStack(spacing: 11) {
            PayScopeWatchActivityRing(
                progress: ringProgress,
                iconName: iconName,
                accent: accent,
                lineWidth: 6
            )
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(currencyString(cents: context.state.completedPayCents))
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)

                        Text("Start \(timeString(context.attributes.timelineStart))")
                            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Text(primaryText)
                    .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)

                HStack(alignment: .center, spacing: 8) {
                    Text(secondaryText)
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Spacer(minLength: 6)

                    pauseButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            PayScopeLiveActivityEdgeFade(accent: accent)
        }
    }

    private var ringProgress: Double {
        switch phase {
        case .completed:
            return 1
        case .upcoming:
            return 0
        case .active:
            return context.state.isTimedShift == false ? 1 : liveActivityProgress(for: context, now: now)
        }
    }

    private var iconName: String {
        switch phase {
        case .completed:
            return "checkmark"
        case .upcoming:
            return context.state.shiftCategoryIcon
        case .active:
            return context.state.isPaused ? "pause.fill" : context.state.shiftCategoryIcon
        }
    }

    private var title: String {
        switch phase {
        case .completed:
            return "Schicht beendet"
        case .upcoming:
            return "Nächste Schicht"
        case .active:
            return context.state.isPaused ? "Pause läuft" : context.attributes.title
        }
    }

    private var primaryText: String {
        switch phase {
        case .completed:
            return hhmmString(from: context.state.workedTodaySeconds)
        case .upcoming:
            return timeString(context.attributes.timelineStart)
        case .active:
            if context.state.isTimedShift == false {
                return hhmmString(from: context.state.workedTodaySeconds)
            }
            if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                return hhmmString(from: max(0, Int(min(now, context.attributes.timelineEnd).timeIntervalSince(pauseStartedAt))))
            }
            return hhmmString(from: max(0, Int(context.attributes.timelineEnd.timeIntervalSince(now))))
        }
    }

    private var secondaryText: String {
        switch phase {
        case .completed:
            return "gearbeitet"
        case .upcoming:
            return nextShiftDateString(context.attributes.timelineStart)
        case .active:
            return context.state.isPaused ? "Pause" : endTimeString(
                start: context.attributes.timelineStart,
                end: context.attributes.timelineEnd,
                fallback: context.attributes.timelineEnd
            )
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        if phase == .active && context.state.isTimedShift != false {
            if context.state.isPaused {
                Button(intent: EndPauseControlIntent()) {
                    Label("Pause Ende", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.82))
                        .frame(width: 28, height: 22)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: StartPauseControlIntent()) {
                    Label("Pause", systemImage: "pause.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(width: 28, height: 22)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PayScopeWatchActivityRing: View {
    let progress: Double
    let iconName: String
    let accent: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: iconName)
                .font(.system(size: lineWidth > 5 ? 20 : 16, weight: .black))
                .foregroundStyle(accent)
        }
    }
}

private struct PayScopeLiveActivityLockScreenContent: View {
    @Environment(\.activityFamily) private var activityFamily

    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    private var phase: LiveActivityPhase {
        liveActivityPhase(for: context)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            if activityFamily == .small {
                PayScopeWatchLiveActivitySmallContent(
                    context: context,
                    now: timeline.date
                )
            } else if activityFamily == .medium {
                PayScopeWatchLiveActivityMediumContent(
                    context: context,
                    now: timeline.date
                )
            } else {
                Group {
                    switch phase {
                    case .completed:
                        completedContent
                    case .upcoming:
                        upcomingContent
                    case .active:
                        activeContent
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    PayScopeLiveActivityEdgeFade(accent: accent)
                }
            }
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        if context.state.isTimedShift == false {
            staticStatusContent
        } else {
            timedActiveContent
        }
    }

    private var timedActiveContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.title)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(currencyString(cents: context.state.completedPayCents))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    primaryCountdown

                    Text(shiftArrowRangeString(
                        start: context.attributes.timelineStart,
                        end: context.attributes.timelineEnd
                    ))
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }
                .layoutPriority(2)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    workedTimer
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("gearbeitet")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
            .padding(.top, 4)

            HStack {
                Spacer(minLength: 0)
                pauseButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var staticStatusContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: context.state.shiftCategoryIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)

                Text(context.attributes.title)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hhmmString(from: context.state.workedTodaySeconds))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)

                    Text("Stunden")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.white.opacity(0.36))
                }
                .layoutPriority(2)

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(currencyString(cents: context.state.completedPayCents))
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text("Geld")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.white.opacity(0.36))
                }
            }
        }
    }

    private var completedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }

                Text("PayScope")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))

                Spacer(minLength: 8)

                Text("jetzt")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.34))
            }
            .padding(.bottom, 10)

            Text("Guter Job heute")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.36))
                .padding(.bottom, 3)

            Text("Schicht beendet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                liveActivityPill(
                    currencyString(cents: context.state.completedPayCents),
                    foreground: accent,
                    background: accent.opacity(0.18),
                    border: accent.opacity(0.35)
                )

                liveActivityPill(
                    workedHoursSummaryString(from: context.state.workedTodaySeconds),
                    foreground: .white.opacity(0.66),
                    background: .white.opacity(0.08),
                    border: .white.opacity(0.15)
                )
            }
            .padding(.bottom, context.state.nextShiftStart == nil ? 0 : 10)

            if let nextShiftStart = context.state.nextShiftStart {
                Divider()
                    .overlay(.white.opacity(0.1))
                    .padding(.bottom, 8)

                HStack {
                    Text("Nächste Schicht")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.36))

                    Spacer(minLength: 8)

                    Text(nextShiftInlineString(nextShiftStart))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
    }

    private var upcomingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nächste Schicht")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.52))

                Spacer(minLength: 8)

                Image(systemName: context.state.shiftCategoryIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(nextShiftAbsoluteWeekdayDateString(context.attributes.timelineStart))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.66)

            HStack {
                Text(timeString(context.attributes.timelineStart))
                Spacer(minLength: 8)
                Text(hhmmString(from: context.state.nextShiftDurationSeconds))
                Spacer(minLength: 8)
                Text(endTimeString(
                    start: context.attributes.timelineStart,
                    end: context.attributes.timelineEnd,
                    fallback: context.attributes.timelineEnd
                ))
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var primaryCountdown: some View {
        if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
            PauseTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        } else {
            RemainingTimerText(end: context.attributes.timelineEnd)
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
    }

    @ViewBuilder
    private var workedTimer: some View {
        if context.state.isPaused {
            Text(hhmmssString(from: context.state.workedTodaySeconds))
        } else {
            WorkedTimerText(
                start: context.state.workedReferenceStart,
                end: context.attributes.timelineEnd
            )
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        if context.state.isPaused {
            Button(intent: EndPauseControlIntent()) {
                Label("Pause Ende", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button(intent: StartPauseControlIntent()) {
                Label("Pause", systemImage: "pause.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PayScopeLiveActivityExpandedContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    private var phase: LiveActivityPhase {
        liveActivityPhase(for: context)
    }

    var body: some View {
        Group {
            switch phase {
            case .completed:
                completedContent
            case .upcoming:
                upcomingContent
            case .active:
                activeContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            PayScopeLiveActivityEdgeFade(accent: accent)
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        if context.state.isTimedShift == false {
            staticStatusContent
        } else {
            timedActiveContent
        }
    }

    private var timedActiveContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 10)

                Text(currencyString(cents: context.state.completedPayCents))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    primaryCountdown

                    Text(shiftArrowRangeString(
                        start: context.attributes.timelineStart,
                        end: context.attributes.timelineEnd
                    ))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }
                .layoutPriority(2)

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 2) {
                    workedTimer
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)

                    Text("gearbeitet")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.36))
                }
            }

            HStack {
                Spacer()
                pauseButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var staticStatusContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: context.state.shiftCategoryIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)

                Text(context.attributes.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hhmmString(from: context.state.workedTodaySeconds))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)

                    Text("Stunden")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.36))
                }
                .layoutPriority(2)

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(currencyString(cents: context.state.completedPayCents))
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text("Geld")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.36))
                }
            }
        }
    }

    private var completedContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Schicht beendet")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(currencyString(cents: context.state.completedPayCents))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(accent)
            }

            Text(nextShiftText(
                start: context.state.nextShiftStart,
                workedSeconds: context.state.workedTodaySeconds,
                completedPayCents: context.state.completedPayCents
            ))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.white.opacity(0.56))
            .lineLimit(2)
            .minimumScaleFactor(0.72)
        }
    }

    private var upcomingContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Nächste Schicht")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(timeString(context.attributes.timelineStart))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(accent)
            }

            Text(nextShiftAbsoluteWeekdayDateString(context.attributes.timelineStart))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            HStack {
                Text(hhmmString(from: context.state.nextShiftDurationSeconds))
                Spacer(minLength: 8)
                Text(endTimeString(
                    start: context.attributes.timelineStart,
                    end: context.attributes.timelineEnd,
                    fallback: context.attributes.timelineEnd
                ))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.42))
        }
    }

    @ViewBuilder
    private var primaryCountdown: some View {
        if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
            PauseTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        } else {
            RemainingTimerText(end: context.attributes.timelineEnd)
                .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
    }

    @ViewBuilder
    private var workedTimer: some View {
        if context.state.isPaused {
            Text(hhmmssString(from: context.state.workedTodaySeconds))
        } else {
            WorkedTimerText(
                start: context.state.workedReferenceStart,
                end: context.attributes.timelineEnd
            )
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        if context.state.isPaused {
            Button(intent: EndPauseControlIntent()) {
                Label("Pause Ende", systemImage: "play.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button(intent: StartPauseControlIntent()) {
                Label("Pause", systemImage: "pause.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private func liveActivityPill(
    _ text: String,
    foreground: Color,
    background: Color,
    border: Color
) -> some View {
    Text(text)
        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
        .foregroundStyle(foreground)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(border, lineWidth: 0.5)
                }
        )
}

private struct PayScopeLiveActivityProgressBar: View {
    let accent: Color
    let progress: Double
    var height: CGFloat = 2.5

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let width = max(0, proxy.size.width * clampedProgress)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(height: height)

                RoundedRectangle(cornerRadius: height, style: .continuous)
                    .fill(accent)
                    .frame(width: width, height: height)
            }
        }
        .frame(height: height)
    }
}

private struct PayScopeLiveActivityEdgeFade: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let horizontalDepth = min(proxy.size.width * 0.48, 180)
            let verticalDepth = min(proxy.size.height * 0.65, 130)

            ZStack {
                accent.opacity(0.015)

                HStack(spacing: 0) {
                    horizontalEdgeGradient
                        .frame(width: horizontalDepth)

                    Spacer(minLength: 0)

                    horizontalEdgeGradient
                        .rotationEffect(.degrees(180))
                        .frame(width: horizontalDepth)
                }

                VStack(spacing: 0) {
                    verticalEdgeGradient
                        .frame(height: verticalDepth)

                    Spacer(minLength: 0)

                    verticalEdgeGradient
                        .rotationEffect(.degrees(180))
                        .frame(height: verticalDepth)
                }
            }
            .mask(ContainerRelativeShape())
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var horizontalEdgeGradient: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(0.26),
                accent.opacity(0.11),
                accent.opacity(0.04),
                accent.opacity(0.015)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var verticalEdgeGradient: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(0.26),
                accent.opacity(0.11),
                accent.opacity(0.04),
                accent.opacity(0.015)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct PayScopeLiveActivityProgressRing: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    var body: some View {
        ProgressView(
            timerInterval: context.attributes.timelineStart...context.attributes.timelineEnd,
            countsDown: false,
            label: { EmptyView() },
            currentValueLabel: { EmptyView() }
        )
        .progressViewStyle(.circular)
        .tint(liveActivityAccent(for: context.state))
        .frame(width: 18, height: 18)
        .accessibilityLabel("Schichtfortschritt")
    }
}

private struct PayScopeLiveActivityDynamicIslandLeadingContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    var body: some View {
        switch liveActivityPhase(for: context) {
        case .completed:
            VStack(alignment: .leading, spacing: 2) {
                Text("Nächste Schicht")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
            }
        case .upcoming:
            VStack(alignment: .leading, spacing: 2) {
                Text("Nächste Schicht")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        case .active:
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.isTimedShift == false ? context.attributes.title : (context.state.isPaused ? "Pause läuft" : context.attributes.title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if context.state.isTimedShift == false {
                    Text(hhmmString(from: context.state.workedTodaySeconds))
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                    PauseTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    RemainingTimerText(end: context.attributes.timelineEnd)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
    }
}

private struct PayScopeLiveActivityDynamicIslandTrailingContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    var body: some View {
        switch liveActivityPhase(for: context) {
        case .completed:
            if let nextShiftStart = context.state.nextShiftStart {
                Text(nextShiftInlineString(nextShiftStart))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Text("Nicht geplant")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        case .upcoming:
            Text(nextShiftInlineString(context.attributes.timelineStart))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        case .active:
            if context.state.isTimedShift == false {
                Text(currencyString(cents: context.state.completedPayCents))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                PauseTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                WorkedTimerText(
                    start: context.state.workedReferenceStart,
                    end: context.attributes.timelineEnd
                )
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
        }
    }
}

private struct PayScopeLiveActivityDynamicIslandBottomContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    var body: some View {
        switch liveActivityPhase(for: context) {
        case .completed:
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                Text(
                    nextShiftText(
                        start: context.state.nextShiftStart,
                        workedSeconds: context.state.workedTodaySeconds,
                        completedPayCents: context.state.completedPayCents
                    )
                )
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .upcoming:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock.badge")
                Text(
                    nextShiftText(
                        start: context.attributes.timelineStart,
                        workedSeconds: context.state.workedTodaySeconds,
                        completedPayCents: context.state.completedPayCents
                    )
                )
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .active:
            if context.state.isTimedShift == false {
                HStack(spacing: 8) {
                    Image(systemName: context.state.shiftCategoryIcon)
                    Text(hhmmString(from: context.state.workedTodaySeconds))
                    Text(currencyString(cents: context.state.completedPayCents))
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                            PauseTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        } else {
                            RemainingTimerText(end: context.attributes.timelineEnd)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        Text(shiftArrowRangeString(
                            start: context.attributes.timelineStart,
                            end: context.attributes.timelineEnd
                        ))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    if context.state.isPaused {
                        Button(intent: EndPauseControlIntent()) {
                            Label("Pause Ende", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    } else {
                        Button(intent: StartPauseControlIntent()) {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

extension PayScope_WidgetsAttributes {
    fileprivate static var preview: PayScope_WidgetsAttributes {
        PayScope_WidgetsAttributes(
            title: "Arbeit heute",
            timelineStart: Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: .now) ?? .now,
            timelineEnd: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now
        )
    }
}

extension PayScope_WidgetsAttributes.ContentState {
    fileprivate static var morning: PayScope_WidgetsAttributes.ContentState {
        PayScope_WidgetsAttributes.ContentState(
            workedTodaySeconds: 2 * 3600 + 20 * 60,
            workedReferenceStart: .now.addingTimeInterval(-(2 * 3600 + 20 * 60)),
            shiftCategoryIcon: "briefcase.fill",
            themeAccentRawValue: "blue",
            isCompleted: false,
            completedPayCents: 0,
            nextShiftStart: nil,
            nextShiftDurationSeconds: 0,
            isPaused: false,
            pauseStartedAt: nil
        )
    }

    fileprivate static var afternoon: PayScope_WidgetsAttributes.ContentState {
        PayScope_WidgetsAttributes.ContentState(
            workedTodaySeconds: 6 * 3600 + 40 * 60,
            workedReferenceStart: .now.addingTimeInterval(-(6 * 3600 + 40 * 60)),
            shiftCategoryIcon: "square.and.pencil",
            themeAccentRawValue: "green",
            isCompleted: true,
            completedPayCents: 18640,
            nextShiftStart: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            nextShiftDurationSeconds: 8 * 3600,
            isPaused: false,
            pauseStartedAt: nil
        )
    }
}

#Preview("Notification", as: .content, using: PayScope_WidgetsAttributes.preview) {
    PayScope_WidgetsLiveActivity()
} contentStates: {
    PayScope_WidgetsAttributes.ContentState.morning
    PayScope_WidgetsAttributes.ContentState.afternoon
}

#Preview("Rectangular Lock Screen", as: .accessoryRectangular) {
    PayScope_WidgetsRectangularLockScreen()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewLongDuration(date: .now)
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}


#Preview("Inline Lock Screen", as: .accessoryInline) {
    PayScope_WidgetsInlineLockScreen()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewLongDuration(date: .now)
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

#Preview("Current Shift Card Small", as: .systemSmall) {
    PayScope_CurrentShiftCardWidget()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewLongDuration(date: .now)
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

#Preview("Current Shift Card Medium", as: .systemMedium) {
    PayScope_CurrentShiftCardWidget()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewLongDuration(date: .now)
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

private struct PayScopeLiveActivityMainView: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(phase == .active ? .primary : liveActivityAccent(for: context.state))

            if phase == .completed {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Color.accentColor)
                    Text(
                        nextShiftText(
                            start: context.state.nextShiftStart,
                            workedSeconds: context.state.workedTodaySeconds,
                            completedPayCents: context.state.completedPayCents
                        )
                    )
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if phase == .upcoming {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Color.accentColor)
                    Text(
                        nextShiftText(
                            start: context.attributes.timelineStart,
                            workedSeconds: context.state.workedTodaySeconds,
                            completedPayCents: context.state.completedPayCents
                        )
                    )
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                            PauseTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(liveActivityAccent(for: context.state))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } else {
                            RemainingTimerText(end: context.attributes.timelineEnd)
                                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(liveActivityAccent(for: context.state))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Spacer(minLength: 8)

                        if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                            PauseTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                                .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(liveActivityAccent(for: context.state))
                                .lineLimit(1)
                        } else {
                            WorkedTimerText(
                                start: context.state.workedReferenceStart,
                                end: context.attributes.timelineEnd
                            )
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }

                    Text(shiftArrowRangeString(
                        start: context.attributes.timelineStart,
                        end: context.attributes.timelineEnd
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    HStack {
                        Spacer()

                        if context.state.isPaused {
                            Button(intent: EndPauseControlIntent()) {
                                Label("Pause Ende", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(liveActivityAccent(for: context.state))
                        } else {
                            Button(intent: StartPauseControlIntent()) {
                                Label("Pause", systemImage: "pause.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(liveActivityAccent(for: context.state))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var phase: LiveActivityPhase {
        liveActivityPhase(for: context)
    }

    private var title: String {
        switch phase {
        case .completed:
            return "Nächste Schicht"
        case .upcoming:
            return "Nächste Schicht"
        case .active:
            return context.state.isPaused ? "Pause läuft" : context.attributes.title
        }
    }
}

private struct RemainingTimerText: View {
    let end: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(hhmmssString(from: Int(end.timeIntervalSince(timeline.date))))
        }
    }
}

private struct WorkedTimerText: View {
    let start: Date
    let end: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let current = min(max(timeline.date, start), end)
            Text(hhmmssString(from: Int(current.timeIntervalSince(start))))
        }
    }
}

private struct PauseTimerText: View {
    let start: Date
    let end: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let current = min(max(timeline.date, start), end)
            Text(hhmmssString(from: Int(current.timeIntervalSince(start))))
        }
    }
}

private enum LiveActivityPhase {
    case upcoming
    case active
    case completed
}

private func liveActivityPhase(
    for context: ActivityViewContext<PayScope_WidgetsAttributes>,
    now: Date = .now
) -> LiveActivityPhase {
    if context.state.isCompleted || now >= context.attributes.timelineEnd {
        return .completed
    }

    if now < context.attributes.timelineStart {
        return .upcoming
    }

    return .active
}

private func liveActivityProgress(
    for context: ActivityViewContext<PayScope_WidgetsAttributes>,
    now: Date = .now
) -> Double {
    let duration = max(1, Int(context.attributes.timelineEnd.timeIntervalSince(context.attributes.timelineStart)))
    let workedSeconds: Int

    if context.state.isCompleted {
        workedSeconds = context.state.workedTodaySeconds
    } else if context.state.isPaused {
        workedSeconds = context.state.workedTodaySeconds
    } else if now <= context.attributes.timelineStart {
        workedSeconds = 0
    } else {
        workedSeconds = max(0, Int(now.timeIntervalSince(context.state.workedReferenceStart)))
    }

    return min(max(Double(workedSeconds) / Double(duration), 0), 1)
}

private func liveAccentColor(from rawValue: String) -> Color {
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

private func liveActivityAccent(for state: PayScope_WidgetsAttributes.ContentState) -> Color {
    liveAccentColor(from: state.shiftCategoryColorRawValue ?? state.themeAccentRawValue)
}

private func hhmmString(from seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    return String(format: "%02d:%02d", hours, minutes)
}

private func hhmmssString(from seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    let secs = safe % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
}

private func currencyString(cents: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale.current
    return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "-"
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func shiftRangeString(start: Date, end: Date) -> String {
    let suffix = Calendar.current.isDate(start, inSameDayAs: end) ? "" : " (+1)"
    return "\(timeString(start)) - \(timeString(end))\(suffix)"
}

private func shiftArrowRangeString(start: Date, end: Date) -> String {
    let suffix = Calendar.current.isDate(start, inSameDayAs: end) ? "" : " +1"
    return "\(timeString(start)) -> \(timeString(end))\(suffix)"
}

private func endTimeString(start: Date?, end: Date?, fallback: Date) -> String {
    guard let start, let end else {
        return timeString(end ?? fallback)
    }
    let suffix = Calendar.current.isDate(start, inSameDayAs: end) ? "" : " +1"
    return "\(timeString(end))\(suffix)"
}

private func nextShiftText(start: Date?, workedSeconds: Int, completedPayCents: Int) -> String {
    let payText = currencyString(cents: completedPayCents)
    let workedText = workedHoursSummaryString(from: workedSeconds)

    guard let start else {
        return "Heute hast du \(payText) mit \(workedText) erarbeitet. Die nächste Schicht ist noch nicht geplant."
    }

    if Calendar.current.isDate(start, inSameDayAs: .now) {
        return "Heute hast du \(payText) mit \(workedText) erarbeitet. Die nächste Schicht ist um \(timeString(start)) Uhr."
    }

    let dayLabel = nextShiftDayLabel(start) ?? nextShiftAbsoluteWeekdayDateString(start)
    return "Heute hast du \(payText) mit \(workedText) erarbeitet. Die nächste Schicht ist \(dayLabel) um \(timeString(start)) Uhr."
}

private func workedHoursSummaryString(from seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    return "\(hours):\(String(format: "%02d", minutes))h"
}

private func nextShiftDateString(_ date: Date) -> String {
    return nextShiftAbsoluteWeekdayDateString(date)
}

private func nextShiftInlineString(_ date: Date) -> String {
    if Calendar.current.isDate(date, inSameDayAs: .now) {
        return timeString(date)
    }

    let dayLabel = nextShiftDayLabel(date) ?? nextShiftAbsoluteDateString(date)
    return "\(dayLabel) - \(timeString(date))"
}

private func allDayStatusInlineString(title: String, date: Date?) -> String {
    guard let date else { return title }
    let dayLabel = nextShiftDayLabel(date) ?? nextShiftAbsoluteDateString(date)
    return "\(title) - \(dayLabel)"
}

private func allDayStatusDateString(_ date: Date) -> String {
    if let dayLabel = nextShiftDayLabel(date) {
        return "\(dayLabel), \(nextShiftAbsoluteDateString(date))"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "EEE, dd.MM."
    return formatter.string(from: date)
}

private func nextShiftDayLabel(_ date: Date, now: Date = .now) -> String? {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) {
        return "Heute"
    }

    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
        return nil
    }

    if calendar.isDate(date, inSameDayAs: tomorrow) {
        return "Morgen"
    }

    return nil
}

private func nextShiftAbsoluteWeekdayDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "EEEE, dd.MM.yyyy"
    return formatter.string(from: date)
}

private func nextShiftAbsoluteDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "dd.MM."
    return formatter.string(from: date)
}
