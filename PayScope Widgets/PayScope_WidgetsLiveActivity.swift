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
                .containerBackground(for: .widget) { Color.clear }
                .activityBackgroundTint(liveActivityBackgroundTint(for: context))
                .activitySystemActionForegroundColor(liveActivityAccent(for: context.state))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PayScopeLiveActivityDynamicIslandLeadingContent(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    PayScopeLiveActivityDynamicIslandCenterContent(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PayScopeLiveActivityDynamicIslandTrailingContent(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PayScopeLiveActivityDynamicIslandBottomContent(context: context)
                }
            } compactLeading: {
                if liveActivityPhase(for: context) == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(liveActivityAccent(for: context.state))
                } else {
                    switch liveActivityPhase(for: context) {
                    case .active:
                        Image(systemName: context.state.isPaused ? "pause.fill" : context.state.shiftCategoryIcon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(liveActivityAccent(for: context.state))
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
                    Group {
                        if context.state.isTimedShift == false {
                            Text(currencyString(cents: context.state.completedPayCents))
                        } else if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                            CompactElapsedTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                        } else {
                            CompactRemainingTimerText(end: context.attributes.timelineEnd)
                        }
                    }
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
                    PayScopeHomeWidgetContainerBackground(
                        accent: homeWidgetAccentColor(from: entry.snapshot.themeAccentRawValue)
                    )
                }
        }
        .configurationDisplayName("Schicht jetzt")
        .description("Fokussiert auf laufende Schicht und Arbeitszeit.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct PayScope_NextShiftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "PayScopeNextShiftWidget",
            provider: PayScopeRectangularProvider()
        ) { entry in
            PayScopeNextShiftWidgetContent(entry: entry)
                .containerBackground(for: .widget) {
                    PayScopeHomeWidgetContainerBackground(
                        accent: homeWidgetAccentColor(from: entry.snapshot.themeAccentRawValue)
                    )
                }
        }
        .configurationDisplayName("Nächste Schicht")
        .description("Zeigt nur den nächsten Start und den Countdown.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct PayScope_TodayPayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "PayScopeTodayPayWidget",
            provider: PayScopeRectangularProvider()
        ) { entry in
            PayScopeTodayPayWidgetContent(entry: entry)
                .containerBackground(for: .widget) {
                    PayScopeHomeWidgetContainerBackground(
                        accent: homeWidgetAccentColor(from: entry.snapshot.themeAccentRawValue)
                    )
                }
        }
        .configurationDisplayName("Lohn heute")
        .description("Zeigt nur heutigen Lohn und Arbeitszeit.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
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

                RemainingTimerText(end: nextShiftStart)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                Text("bis \(timeString(nextShiftStart)) Uhr")
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
                Text("in")
                    .font(.caption.weight(.semibold))
                RemainingTimerText(end: nextShiftStart)
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

private extension PayScopeRectangularEntry {
    var displayIcon: String {
        snapshot.shiftCategoryIcon ?? "briefcase.fill"
    }

    var displayTitle: String {
        snapshot.shiftCategoryTitle ?? "Arbeit"
    }

    func isActive(at now: Date) -> Bool {
        guard
            let start = snapshot.shiftStart,
            let end = snapshot.shiftEnd,
            end > start
        else {
            return false
        }

        return now >= start && now < end
    }

    func isAllDayStatus(at now: Date) -> Bool {
        guard snapshot.hasAllDayStatus, let date = snapshot.allDayDisplayDate else {
            return false
        }

        return Calendar.current.isDate(date, inSameDayAs: now)
    }

    func nextShiftStartForDisplay(at now: Date) -> Date? {
        if
            let start = snapshot.shiftStart,
            let end = snapshot.shiftEnd,
            end > start,
            now < start
        {
            return start
        }

        if let nextShiftStart = snapshot.nextShiftStart, nextShiftStart > now {
            return nextShiftStart
        }

        return nil
    }

    func workedSeconds(at now: Date) -> Int {
        let cappedNow = snapshot.shiftEnd.map { min(now, $0) } ?? now

        if let referenceStart = snapshot.workedReferenceStart {
            return max(0, Int(cappedNow.timeIntervalSince(referenceStart)))
        }

        guard let start = snapshot.shiftStart else {
            return snapshot.workedTodaySeconds ?? 0
        }

        return max(0, Int(cappedNow.timeIntervalSince(start)))
    }

    func workedTitle(at now: Date) -> String {
        "\(hhmmString(from: workedSeconds(at: now))) h"
    }

    func progress(at now: Date) -> Double {
        let total = max(1, snapshot.shiftDurationSeconds)
        return min(max(Double(workedSeconds(at: now)) / Double(total), 0), 1)
    }
}

private enum PayScopeHomeWidgetStyle {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.72)
    static let muted = Color.white.opacity(0.48)
}

private struct PayScopeHomeWidgetContainerBackground: View {
    let accent: Color

    var body: some View {
        Color(red: 0.045, green: 0.050, blue: 0.062)
            .overlay {
                LinearGradient(
                    colors: [
                        accent.opacity(0.22),
                        Color(red: 0.045, green: 0.050, blue: 0.062).opacity(0.10),
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }
}

private struct PayScopeHomeWidgetChrome<Content: View>: View {
    @Environment(\.widgetFamily) private var family

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(family == .systemSmall ? 9 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PayScopeHomeWidgetHeader: View {
    let title: String
    let subtitle: String?
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.22))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(accent)
            }
            .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct PayScopeHomeLayerCard<Content: View>: View {
    let accent: Color
    let prominence: Double
    let content: Content

    init(accent: Color, prominence: Double = 0.12, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.prominence = prominence
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent.opacity(prominence))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
            }
    }
}

private struct PayScopeHomeInfoPill: View {
    let text: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .black))
            Text(text)
                .font(.system(size: 10, weight: .black, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(accent.opacity(0.20))
        }
    }
}

private struct PayScopeHomeProgressBar: View {
    let accent: Color
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width * min(max(progress, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PayScopeHomeWidgetStyle.primary.opacity(0.16))
                Capsule()
                    .fill(accent)
                    .frame(width: width)
            }
        }
        .frame(height: 7)
    }
}

private struct PayScopeCurrentShiftCardContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: PayScopeRectangularEntry

    private var accent: Color {
        homeWidgetAccentColor(from: entry.snapshot.themeAccentRawValue)
    }

    var body: some View {
        TimelineView(.periodic(from: entry.date, by: 1)) { timeline in
            PayScopeHomeWidgetChrome {
                if entry.isActive(at: timeline.date) {
                    activeContent(at: timeline.date)
                } else if entry.isAllDayStatus(at: timeline.date) {
                    allDayContent
                } else if let nextStart = entry.nextShiftStartForDisplay(at: timeline.date) {
                    inactiveContent(nextStart: nextStart, now: timeline.date)
                } else {
                    emptyContent
                }
            }
        }
    }

    private func activeContent(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "Jetzt", subtitle: entry.displayTitle, icon: entry.displayIcon, accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.18) {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.workedTitle(at: now))
                            .font(.system(size: family == .systemSmall ? 27 : 40, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.46)

                        Spacer(minLength: 4)

                        Text("\(Int(entry.progress(at: now) * 100))%")
                            .font(.system(size: family == .systemSmall ? 11 : 13, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }

                    PayScopeHomeProgressBar(accent: accent, progress: entry.progress(at: now))

                    HStack(spacing: 6) {
                        PayScopeHomeInfoPill(text: activeFooter(at: now), icon: "flag.checkered", accent: accent)
                        if family != .systemSmall, let nextStart = entry.snapshot.nextShiftStart {
                            PayScopeHomeInfoPill(text: "danach \(nextShiftInlineString(nextStart))", icon: "calendar.badge.clock", accent: accent)
                        }
                    }
                }
            }

            if family == .systemSmall, let nextStart = entry.snapshot.nextShiftStart {
                compactLayer(title: "Danach", value: nextShiftInlineString(nextStart), icon: "calendar.badge.clock")
            } else if family != .systemSmall {
                compactLayer(title: "Lohn heute", value: currencyString(cents: entry.snapshot.completedPayCents ?? 0), icon: "eurosign.circle.fill")
            }
        }
    }

    private var allDayContent: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "Heute", subtitle: nil, icon: entry.displayIcon, accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.displayTitle)
                        .font(.system(size: family == .systemSmall ? 25 : 36, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)

                    Text("Ganztag")
                        .font(.system(size: family == .systemSmall ? 11 : 13, weight: .black, design: .rounded))
                        .foregroundStyle(accent)
                }
            }

            if let date = entry.snapshot.allDayDisplayDate {
                compactLayer(title: "Datum", value: allDayStatusDateString(date), icon: "calendar")
            }
        }
    }

    private func inactiveContent(nextStart: Date, now: Date) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "Heute frei", subtitle: entry.displayTitle, icon: entry.displayIcon, accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nächste")
                        .font(.system(size: family == .systemSmall ? 24 : 36, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(nextShiftInlineString(nextStart))
                        .font(.system(size: family == .systemSmall ? 11 : 14, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
            }

            compactLayer(title: "Countdown", value: compactRemainingString(to: nextStart, from: now), icon: "timer")
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "PayScope", subtitle: nil, icon: "sparkle", accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frei")
                        .font(.system(size: family == .systemSmall ? 30 : 42, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)

                    Text("Keine Schicht aktiv")
                        .font(.system(size: family == .systemSmall ? 11 : 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func compactLayer(title: String, value: String, icon: String) -> some View {
        PayScopeHomeLayerCard(accent: accent, prominence: 0.10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.muted)
                        .lineLimit(1)

                    Text(value)
                        .font(.system(size: family == .systemSmall ? 11 : 13, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
            }
        }
    }

    private func activeFooter(at now: Date) -> String {
        guard let end = entry.snapshot.shiftEnd else {
            return "läuft gerade"
        }

        return "bis \(endTimeString(start: entry.snapshot.shiftStart, end: end, fallback: now)) Uhr"
    }
}

private struct PayScopeNextShiftWidgetContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: PayScopeRectangularEntry

    private var accent: Color {
        homeWidgetAccentColor(from: entry.snapshot.themeAccentRawValue)
    }

    var body: some View {
        TimelineView(.periodic(from: entry.date, by: 1)) { timeline in
            PayScopeHomeWidgetChrome {
                if let nextStart = entry.nextShiftStartForDisplay(at: timeline.date) {
                    nextShiftContent(start: nextStart, now: timeline.date)
                } else if entry.isActive(at: timeline.date) {
                    activeFallback(at: timeline.date)
                } else if entry.isAllDayStatus(at: timeline.date) {
                    allDayFallback
                } else {
                    emptyContent
                }
            }
        }
    }

    private func nextShiftContent(start: Date, now: Date) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "Nächste", subtitle: entry.displayTitle, icon: "calendar.badge.clock", accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("in")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.muted)

                    RemainingTimerText(end: start)
                        .font(.system(size: family == .systemSmall ? 27 : 42, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.44)
                }
            }

            HStack(spacing: 7) {
                miniMetric(title: "Start", value: nextShiftInlineString(start), icon: "clock.fill")
                if family != .systemSmall {
                    miniMetric(title: "Heute", value: entry.workedTitle(at: now), icon: "briefcase.fill")
                }
            }
        }
    }

    private func activeFallback(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "Nächste", subtitle: "läuft gerade", icon: entry.displayIcon, accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Jetzt")
                        .font(.system(size: family == .systemSmall ? 29 : 42, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)

                    Text(activeEndText(at: now))
                        .font(.system(size: family == .systemSmall ? 11 : 14, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }

            if let nextStart = entry.snapshot.nextShiftStart {
                miniMetric(title: "Danach", value: nextShiftInlineString(nextStart), icon: "calendar")
            }
        }
    }

    private var allDayFallback: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "Heute", subtitle: "Ganztag", icon: entry.displayIcon, accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.18) {
                Text(entry.displayTitle)
                    .font(.system(size: family == .systemSmall ? 27 : 40, weight: .black, design: .rounded))
                    .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.56)
            }
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "Nächste", subtitle: nil, icon: "calendar.badge.clock", accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keine")
                        .font(.system(size: family == .systemSmall ? 30 : 42, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)

                    Text("Schicht geplant")
                        .font(.system(size: family == .systemSmall ? 11 : 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func miniMetric(title: String, value: String, icon: String) -> some View {
        PayScopeHomeLayerCard(accent: accent, prominence: 0.10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 13)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.muted)
                        .lineLimit(1)

                    Text(value)
                        .font(.system(size: family == .systemSmall ? 10 : 12, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                }
            }
        }
    }

    private func activeEndText(at now: Date) -> String {
        guard let end = entry.snapshot.shiftEnd else {
            return "läuft gerade"
        }

        return "bis \(endTimeString(start: entry.snapshot.shiftStart, end: end, fallback: now)) Uhr"
    }
}

private struct PayScopeTodayPayWidgetContent: View {
    @Environment(\.widgetFamily) private var family

    let entry: PayScopeRectangularEntry

    private var accent: Color {
        homeWidgetAccentColor(from: entry.snapshot.themeAccentRawValue)
    }

    var body: some View {
        TimelineView(.periodic(from: entry.date, by: 1)) { timeline in
            PayScopeHomeWidgetChrome {
                payContent(at: timeline.date)
            }
        }
    }

    private func payContent(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PayScopeHomeWidgetHeader(title: "Lohn", subtitle: "Heute", icon: "eurosign.circle.fill", accent: accent)

            PayScopeHomeLayerCard(accent: accent, prominence: 0.18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(currencyString(cents: entry.snapshot.completedPayCents ?? 0))
                        .font(.system(size: family == .systemSmall ? 27 : 42, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.44)

                    Text(workedSubtitle(at: now))
                        .font(.system(size: family == .systemSmall ? 10 : 13, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
            }

            if entry.isActive(at: now) {
                hybridLayer(title: "Aktuell", value: activeEndText(at: now), icon: entry.displayIcon)
            } else if let nextStart = entry.nextShiftStartForDisplay(at: now) {
                hybridLayer(title: "Nächste", value: nextShiftInlineString(nextStart), icon: "calendar.badge.clock")
            } else if entry.isAllDayStatus(at: now) {
                hybridLayer(title: "Heute", value: "Ganztag", icon: entry.displayIcon)
            } else {
                hybridLayer(title: "Status", value: "frei", icon: "moon.zzz.fill")
            }
        }
    }

    private func workedSubtitle(at now: Date) -> String {
        let seconds = entry.workedSeconds(at: now)

        guard seconds > 0 else {
            return "noch keine Arbeitszeit"
        }

        return "\(hhmmString(from: seconds)) h gearbeitet"
    }

    private func activeEndText(at now: Date) -> String {
        guard let end = entry.snapshot.shiftEnd else {
            return "läuft"
        }

        return "bis \(endTimeString(start: entry.snapshot.shiftStart, end: end, fallback: now))"
    }

    private func hybridLayer(title: String, value: String, icon: String) -> some View {
        PayScopeHomeLayerCard(accent: accent, prominence: 0.10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(PayScopeHomeWidgetStyle.muted)
                        .lineLimit(1)

                    Text(value)
                        .font(.system(size: family == .systemSmall ? 11 : 13, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(PayScopeHomeWidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                }
            }
        }
    }
}

private struct PayScopeWatchLiveActivitySmallContent: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let context: ActivityViewContext<PayScope_WidgetsAttributes>
    let now: Date

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    private var phase: LiveActivityPhase {
        liveActivityPhase(for: context, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            primaryCountdown
                .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.42)
                .frame(maxWidth: .infinity, alignment: .leading)

            PayScopeWatchLiveActivityProgressBar(
                accent: accent,
                progress: progress,
                isLuminanceReduced: isLuminanceReduced,
                height: 5
            )

            HStack(spacing: 8) {
                watchTime(value: timeString(context.attributes.timelineStart))
                Spacer(minLength: 0)
                watchTime(
                    value: endTimeString(
                        start: context.attributes.timelineStart,
                        end: context.attributes.timelineEnd,
                        fallback: context.attributes.timelineEnd
                    )
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            WatchLiveActivityGlassBackground(
                accent: accent,
                isActive: phase == .active,
                isLuminanceReduced: isLuminanceReduced
            )
        }
    }

    private var progress: Double {
        switch phase {
        case .completed:
            return 1
        case .upcoming:
            return 0
        case .active:
            return context.state.isTimedShift == false ? 1 : liveActivityProgress(for: context, now: now)
        }
    }

    @ViewBuilder
    private var primaryCountdown: some View {
        switch phase {
        case .completed:
            Text(hhmmString(from: context.state.workedTodaySeconds))
        case .upcoming:
            let current = min(Date(), context.attributes.timelineStart)
            Text(timerInterval: current...context.attributes.timelineStart, countsDown: true, showsHours: true)
        case .active:
            if context.state.isTimedShift == false {
                Text(hhmmString(from: context.state.workedTodaySeconds))
            } else if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                Text(timerInterval: pauseStartedAt...context.attributes.timelineEnd, countsDown: false, showsHours: true)
            } else {
                let current = min(Date(), context.attributes.timelineEnd)
                Text(timerInterval: current...context.attributes.timelineEnd, countsDown: true, showsHours: true)
            }
        }
    }

    private func watchTime(value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(isLuminanceReduced ? 0.70 : 0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
    }
}

private struct PayScopeWatchLiveActivityMediumContent: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let context: ActivityViewContext<PayScope_WidgetsAttributes>
    let now: Date

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    private var phase: LiveActivityPhase {
        liveActivityPhase(for: context, now: now)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = WatchLiveActivityMediumLayout(size: geometry.size)

            ZStack(alignment: .top) {
                WatchLiveActivityGlassBackground(
                    accent: accent,
                    isActive: phase == .active,
                    isLuminanceReduced: isLuminanceReduced
                )

                VStack(alignment: .leading, spacing: layout.stackSpacing) {
                    watchCountdown(layout: layout)
                    PayScopeWatchLiveActivityProgressBar(
                        accent: accent,
                        progress: progress,
                        isLuminanceReduced: isLuminanceReduced,
                        height: layout.progressHeight
                    )
                    watchTimeRow(layout: layout)
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
            }
        }
    }

    private func watchCountdown(layout: WatchLiveActivityMediumLayout) -> some View {
        primaryCountdown
            .font(.system(size: layout.countdownFontSize, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.40)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func watchTimeRow(layout: WatchLiveActivityMediumLayout) -> some View {
        HStack(alignment: .top, spacing: layout.metricSpacing) {
            watchMetric(value: timeString(context.attributes.timelineStart), alignment: .leading)

            Spacer(minLength: 0)

            watchMetric(
                value: endTimeString(
                    start: context.attributes.timelineStart,
                    end: context.attributes.timelineEnd,
                    fallback: context.attributes.timelineEnd
                ),
                alignment: .trailing
            )
        }
    }

    private var progress: Double {
        switch phase {
        case .completed:
            return 1
        case .upcoming:
            return 0
        case .active:
            return context.state.isTimedShift == false ? 1 : liveActivityProgress(for: context, now: now)
        }
    }

    @ViewBuilder
    private var primaryCountdown: some View {
        switch phase {
        case .completed:
            Text(hhmmString(from: context.state.workedTodaySeconds))
        case .upcoming:
            let current = min(Date(), context.attributes.timelineStart)
            Text(timerInterval: current...context.attributes.timelineStart, countsDown: true, showsHours: true)
        case .active:
            if context.state.isTimedShift == false {
                Text(hhmmString(from: context.state.workedTodaySeconds))
            } else if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
                Text(timerInterval: pauseStartedAt...context.attributes.timelineEnd, countsDown: false, showsHours: true)
            } else {
                let current = min(Date(), context.attributes.timelineEnd)
                Text(timerInterval: current...context.attributes.timelineEnd, countsDown: true, showsHours: true)
            }
        }
    }

    private func watchMetric(value: String, alignment: HorizontalAlignment) -> some View {
        Text(value)
            .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(isLuminanceReduced ? 0.72 : 0.94))
            .lineLimit(1)
            .minimumScaleFactor(0.64)
        .frame(minWidth: 50, alignment: alignment == .trailing ? .trailing : .leading)
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

private struct PayScopeWatchLiveActivityProgressBar: View {
    let accent: Color
    let progress: Double
    let isLuminanceReduced: Bool
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let width = proxy.size.width * clampedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(isLuminanceReduced ? 0.10 : 0.14))

                Capsule()
                    .fill(isLuminanceReduced ? .white.opacity(0.68) : accent)
                    .frame(width: width)
            }
        }
        .frame(height: height)
    }
}

private struct WatchLiveActivityGlassBackground: View {
    let accent: Color
    let isActive: Bool
    var isLuminanceReduced: Bool = false

    var body: some View {
        ZStack {
            Color.black

            if !isLuminanceReduced {
                LinearGradient(
                    colors: [
                        accent.opacity(isActive ? 0.20 : 0.12),
                        Color(red: 0.06, green: 0.10, blue: 0.12).opacity(0.74),
                        Color.black.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

private struct WatchLiveActivityMediumLayout {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let stackSpacing: CGFloat
    let countdownFontSize: CGFloat
    let progressHeight: CGFloat
    let metricSpacing: CGFloat

    init(size: CGSize) {
        let compactness = min(max((size.height - 150) / 42, 0), 1)
        horizontalPadding = max(10, min(14, size.width * 0.055))
        verticalPadding = max(12, min(16, size.height * 0.074))
        stackSpacing = 12 + compactness * 3
        countdownFontSize = max(58, min(74, size.width * 0.32))
        progressHeight = max(6, min(8, size.height * 0.038))
        metricSpacing = max(14, min(22, size.width * 0.08))
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
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if activityFamily == .small {
                GeometryReader { geometry in
                    if geometry.size.width > 260 {
                        lockScreenContent(at: timeline.date)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        PayScopeWatchLiveActivitySmallContent(
                            context: context,
                            now: timeline.date
                        )
                    }
                }
            } else if activityFamily == .medium {
                GeometryReader { geometry in
                    if geometry.size.width > 320 {
                        lockScreenContent(at: timeline.date)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        PayScopeWatchLiveActivityMediumContent(
                            context: context,
                            now: timeline.date
                        )
                    }
                }
            } else {
                lockScreenContent(at: timeline.date)
            }
        }
    }

    @ViewBuilder
    private func lockScreenContent(at now: Date) -> some View {
        switch liveActivityPhase(for: context, now: now) {
        case .completed:
            completedContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 0)
                .padding(.vertical, 2)
        case .upcoming:
            upcomingContent
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    PayScopeLiveActivityEdgeFade(accent: accent)
                }
        case .active:
            activeContent(at: now)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 0)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func activeContent(at now: Date) -> some View {
        if context.state.isTimedShift == false {
            staticStatusContent
                .padding(16)
                .background {
                    PayScopeLiveActivityEdgeFade(accent: accent)
                }
        } else {
            timedActiveContent(at: now)
        }
    }

    private func timedActiveContent(at now: Date) -> some View {
        HStack(spacing: 10) {
            PayScopeLockScreenCountdownRing(
                progress: liveActivityProgress(for: context, now: now),
                timerInterval: context.attributes.timelineStart...context.attributes.timelineEnd,
                iconName: context.state.isPaused ? "pause.fill" : context.state.shiftCategoryIcon,
                accent: accent
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 1) {

                lockScreenPrimaryCountdown

                HStack{
                    Text(lockScreenTimeRange)
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.leading, 5)
                }
                    
            }
            .layoutPriority(2)

            Spacer(minLength: 4)

            lockScreenPauseButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        /*.background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    //accent.opacity(0.13),
                                    .clear
                                    //.white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(accent.opacity(0.16), lineWidth: 0.75)
                }
        }*/
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var lockScreenTimeRange: String {
        "\(timeString(context.attributes.timelineStart)) → \(endTimeString(start: context.attributes.timelineStart, end: context.attributes.timelineEnd, fallback: context.attributes.timelineEnd))"
    }

    @ViewBuilder
    private var lockScreenPrimaryCountdown: some View {
        if context.state.isPaused, let pauseStartedAt = context.state.pauseStartedAt {
            PauseTimerText(start: pauseStartedAt, end: context.attributes.timelineEnd)
                .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        } else {
            RemainingTimerText(end: context.attributes.timelineEnd)
                .font(.system(size: 27, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
    }

    @ViewBuilder
    private var lockScreenPauseButton: some View {
        if context.state.isPaused {
            Button(intent: EndPauseControlIntent()) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.13), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(accent.opacity(0.30), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        } else {
            Button(intent: StartPauseControlIntent()) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    //.background(accent.opacity(0.13), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(accent.opacity(0.30), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
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
        HStack(alignment: .center, spacing: 10) {
            PayScopeLockScreenCountdownRing(
                progress: 1,
                iconName: "checkmark",
                accent: accent
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Schicht beendet")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)

                Text("Gut gemacht!")
                    .font(.system(size: 10, weight: .black))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .layoutPriority(2)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(currencyString(cents: context.state.completedPayCents))
                    .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(workedHoursSummaryString(from: context.state.workedTodaySeconds))
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        /*.background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.30))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.18),
                                    .white.opacity(0.03),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
                }
        }*/
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Group {
                switch liveActivityPhase(for: context, now: timeline.date) {
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

                Image(systemName: context.state.isPaused ? "pause.fill" : context.state.shiftCategoryIcon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                primaryCountdown

                shiftEndpointRow(
                    start: context.attributes.timelineStart,
                    end: context.attributes.timelineEnd,
                    foreground: .white.opacity(0.42)
                )
            }
            .layoutPriority(2)

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

private func shiftEndpointRow(start: Date, end: Date, foreground: Color) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("Start \(timeString(start))")
            .frame(maxWidth: .infinity, alignment: .leading)

        Text("Ende \(endTimeString(start: start, end: end, fallback: end))")
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .font(.system(size: 10, weight: .semibold).monospacedDigit())
    .foregroundStyle(foreground)
    .lineLimit(1)
    .minimumScaleFactor(0.72)
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
        Color.clear
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

private struct PayScopeDynamicIslandProgressRing: View {
    let progress: Double
    let iconName: String
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.20), lineWidth: 4)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: iconName)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(accent)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

private struct PayScopeLockScreenCountdownRing: View {
    let progress: Double
    var timerInterval: ClosedRange<Date>? = nil
    let iconName: String
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 4)

            progressLayer

            Circle()
                .fill(accent.opacity(0.1))
                .padding(3)

            Image(systemName: iconName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(accent)
        }
    }

    @ViewBuilder
    private var progressLayer: some View {
        if let timerInterval {
            ProgressView(
                timerInterval: timerInterval,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.circular)
            .tint(accent)
        } else {
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
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
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Fertig")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("Schicht beendet")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        case .upcoming:
            HStack(spacing: 7) {
                PayScopeDynamicIslandProgressRing(
                    progress: 0,
                    iconName: context.state.shiftCategoryIcon,
                    accent: accent
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Nächste")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Schicht")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .active:
            VStack(alignment: .leading, spacing: 1) {
                Text("Start")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))

                Text(timeString(context.attributes.timelineStart))
                    .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PayScopeLiveActivityDynamicIslandCenterContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    var body: some View {
        switch liveActivityPhase(for: context) {
        case .active:
            VStack(spacing: 1) {
                Text("Dauer")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))

                Text(activeDurationText)
                    .font(.system(size: 17, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }
            .frame(maxWidth: .infinity)
        case .completed, .upcoming:
            EmptyView()
        }
    }

    private var activeDurationText: String {
        if context.state.isTimedShift == false {
            return "offen"
        }

        let seconds = max(0, Int(context.attributes.timelineEnd.timeIntervalSince(context.attributes.timelineStart)))
        return "\(hhmmString(from: seconds)) h"
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
            VStack(alignment: .trailing, spacing: 1) {
                Text(currencyString(cents: context.state.completedPayCents))
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(accent)

                Text(context.state.nextShiftStart.map(nextShiftInlineString) ?? "Nicht geplant")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        case .upcoming:
            VStack(alignment: .trailing, spacing: 1) {
                Text(nextShiftInlineString(context.attributes.timelineStart))
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(hhmmString(from: context.state.nextShiftDurationSeconds))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
            }
        case .active:
            VStack(alignment: .trailing, spacing: 1) {
                Text("Ende")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))

                Text(activeEndText)
                    .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var activeEndText: String {
        if context.state.isTimedShift == false {
            return "offen"
        }

        return endTimeString(
            start: context.attributes.timelineStart,
            end: context.attributes.timelineEnd,
            fallback: context.attributes.timelineEnd
        )
    }
}

private struct PayScopeLiveActivityDynamicIslandBottomContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveActivityAccent(for: context.state)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            content(at: timeline.date)
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        switch liveActivityPhase(for: context, now: now) {
        case .completed:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                    Text(completedNextShiftSummary)
                    Spacer(minLength: 8)
                    Text(hhmmString(from: context.state.workedTodaySeconds))
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

                PayScopeLiveActivityProgressBar(accent: accent, progress: 1, height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .upcoming:
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "clock.badge")
                    Text(shiftArrowRangeString(
                        start: context.attributes.timelineStart,
                        end: context.attributes.timelineEnd
                    ))
                    Spacer(minLength: 8)
                    Text(hhmmString(from: context.state.nextShiftDurationSeconds))
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

                PayScopeLiveActivityProgressBar(accent: accent, progress: 0, height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .active:
            PayScopeLiveActivityProgressBar(
                accent: accent,
                progress: liveActivityProgress(for: context, now: now),
                height: 4
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var completedNextShiftSummary: String {
        guard let nextShiftStart = context.state.nextShiftStart else {
            return "Nächste offen"
        }

        return "Nächste \(nextShiftInlineString(nextShiftStart))"
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

#Preview("Schicht jetzt Small", as: .systemSmall) {
    PayScope_CurrentShiftCardWidget()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

#Preview("Schicht jetzt Medium", as: .systemMedium) {
    PayScope_CurrentShiftCardWidget()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

#Preview("Nächste Schicht Small", as: .systemSmall) {
    PayScope_NextShiftWidget()
} timeline: {
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

#Preview("Nächste Schicht Medium", as: .systemMedium) {
    PayScope_NextShiftWidget()
} timeline: {
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

#Preview("Lohn heute Small", as: .systemSmall) {
    PayScope_TodayPayWidget()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewLongDuration(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

#Preview("Lohn heute Medium", as: .systemMedium) {
    PayScope_TodayPayWidget()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewLongDuration(date: .now)
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
        let now = Date()
        Text(timerInterval: now...max(now, end), countsDown: true, showsHours: true)
    }
}

private struct CompactRemainingTimerText: View {
    let end: Date

    var body: some View {
        let now = Date()
        CompactTimerIntervalText(interval: now...max(now, end), countsDown: true)
    }
}

private struct WorkedTimerText: View {
    let start: Date
    let end: Date

    var body: some View {
        Text(timerInterval: start...end, countsDown: false, showsHours: true)
    }
}

private struct CompactElapsedTimerText: View {
    let start: Date
    let end: Date

    var body: some View {
        CompactTimerIntervalText(interval: start...end, countsDown: false)
    }
}

private struct CompactTimerIntervalText: View {
    let interval: ClosedRange<Date>
    let countsDown: Bool

    var body: some View {
        Text(timerInterval: interval, countsDown: countsDown, showsHours: true)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 50, alignment: .trailing)
    }
}

private struct PauseTimerText: View {
    let start: Date
    let end: Date

    var body: some View {
        Text(timerInterval: start...end, countsDown: false, showsHours: true)
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

private func liveActivityBackgroundTint(for context: ActivityViewContext<PayScope_WidgetsAttributes>) -> Color {
    Color.clear
}

private func liveActivityProgress(
    for context: ActivityViewContext<PayScope_WidgetsAttributes>,
    now: Date = .now
) -> Double {
    if context.state.isCompleted || now >= context.attributes.timelineEnd {
        return 1
    }

    if now <= context.attributes.timelineStart {
        return 0
    }

    let duration = max(1, context.attributes.timelineEnd.timeIntervalSince(context.attributes.timelineStart))
    let elapsed = now.timeIntervalSince(context.attributes.timelineStart)
    return min(max(elapsed / duration, 0), 1)
}

private func liveAccentColor(from rawValue: String) -> Color {
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

private func homeWidgetAccentColor(from rawValue: String) -> Color {
    if rawValue == "monochrome" {
        return .white
    }

    return liveAccentColor(from: rawValue)
}

private func liveActivityAccent(for state: PayScope_WidgetsAttributes.ContentState) -> Color {
    liveAccentColor(from: state.shiftCategoryColorRawValue ?? "monochrome")
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

private func shortClockString(from seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    let secs = safe % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }

    return String(format: "%02d:%02d", minutes, secs)
}

private func compactRemainingString(to end: Date, from now: Date) -> String {
    shortClockString(from: Int(max(0, end.timeIntervalSince(now))))
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
