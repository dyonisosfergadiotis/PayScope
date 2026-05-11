//
//  PayScope_WidgetsLiveActivity.swift
//  PayScope Widgets
//
//  Created by Dyonisos Fergadiotis on 18.02.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PayScope_WidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var workedTodaySeconds: Int
        var workedReferenceStart: Date
        var shiftCategoryIcon: String
        var themeAccentRawValue: String
        var isCompleted: Bool
        var completedPayCents: Int
        var nextShiftStart: Date?
        var nextShiftDurationSeconds: Int
    }

    var title: String
    var timelineStart: Date
    var timelineEnd: Date
}

struct PayScope_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PayScope_WidgetsAttributes.self) { context in
            PayScopeLiveActivityExpandedContent(context: context)
                .activityBackgroundTint(liveAccentColor(from: context.state.themeAccentRawValue).opacity(0.18))
                .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    PayScopeLiveActivityDynamicIslandCenterContent(context: context)
                }

                DynamicIslandExpandedRegion(.bottom, priority: 1) {
                    PayScopeLiveActivityDynamicIslandBottomContent(context: context)
                }
            } compactLeading: {
                if liveActivityPhase(for: context) == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                } else {
                    Image(systemName: context.state.shiftCategoryIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                }
            } compactTrailing: {
                switch liveActivityPhase(for: context) {
                case .completed:
                    Text(Self.nextShiftCompactString(context.state.nextShiftStart))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                case .upcoming:
                    Text(Self.nextShiftCompactString(context.attributes.timelineStart))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                case .active:
                    Text(endTimeString(start: context.attributes.timelineStart, end: context.attributes.timelineEnd, fallback: context.attributes.timelineEnd))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                }
            } minimal: {
                Image(systemName: liveActivityPhase(for: context) == .completed ? "checkmark.circle.fill" : context.state.shiftCategoryIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
            }
            .keylineTint(liveAccentColor(from: context.state.themeAccentRawValue))
        }
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

private struct PayScopeLiveActivityExpandedContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    var body: some View {
        PayScopeLiveActivityMainView(context: context)
            .padding(16)
    }
}

private struct PayScopeLiveActivityDynamicIslandCenterContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveAccentColor(from: context.state.themeAccentRawValue)
    }

    var body: some View {
        switch liveActivityPhase(for: context) {
        case .completed:
            VStack(alignment: .leading, spacing: 2) {
                Text("Nächste Schicht")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                if let nextShiftStart = context.state.nextShiftStart {
                    Text(nextShiftInlineString(nextShiftStart))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("Noch nicht geplant")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .upcoming:
            VStack(alignment: .leading, spacing: 4) {
                Text("Nächste Schicht")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(nextShiftInlineString(context.attributes.timelineStart))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .active:
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                RemainingTimerText(end: context.attributes.timelineEnd)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PayScopeLiveActivityDynamicIslandBottomContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveAccentColor(from: context.state.themeAccentRawValue)
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
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(
                    timerInterval: context.attributes.timelineStart...context.attributes.timelineEnd,
                    countsDown: false,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .progressViewStyle(.linear)
                .tint(accent)

                HStack(alignment: .firstTextBaseline) {
                    WorkedTimerText(
                        start: context.state.workedReferenceStart,
                        end: context.attributes.timelineEnd
                    )
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(shiftRangeString(start: context.attributes.timelineStart, end: context.attributes.timelineEnd))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            nextShiftDurationSeconds: 0
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
            nextShiftDurationSeconds: 8 * 3600
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

private struct PayScopeLiveActivityMainView: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(phase == .active ? .primary : liveAccentColor(from: context.state.themeAccentRawValue))

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
                    HStack {
                        RemainingTimerText(end: context.attributes.timelineEnd)
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer()
                        VStack{
                            Spacer()
                            Text(shiftRangeString(start: context.attributes.timelineStart, end: context.attributes.timelineEnd))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(
                        timerInterval: context.attributes.timelineStart...context.attributes.timelineEnd,
                        countsDown: false
                    )
                    .tint(liveAccentColor(from: context.state.themeAccentRawValue))

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
            return context.attributes.title
        }
    }
}

private struct RemainingTimerText: View {
    let end: Date

    var body: some View {
        if end > .now {
            Text(timerInterval: Date()...end, countsDown: true, showsHours: true)
        } else {
            Text("00:00:00")
        }
    }
}

private struct WorkedTimerText: View {
    let start: Date
    let end: Date

    var body: some View {
        if end > .now {
            Text(timerInterval: start...end, countsDown: false, showsHours: true)
        } else {
            Text(hhmmssString(from: max(0, Int(end.timeIntervalSince(start)))))
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

private func liveAccentColor(from rawValue: String) -> Color {
    switch rawValue {
    case "blue": return .blue
    case "green": return .green
    case "purple": return .purple
    case "orange": return .orange
    case "pink": return .pink
    case "teal": return .teal
    case "red": return .red
    case "indigo": return .indigo
    default: return .blue
    }
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
