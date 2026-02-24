import SwiftUI
import SwiftData
import ActivityKit

@main
struct PayScopeApp: App {
    var sharedModelContainer: ModelContainer = {
        let fileManager = FileManager.default
        do {
            let applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("Failed to ensure Application Support directory: \(error)")
            #endif
        }

        let schema = Schema([
            DayEntry.self,
            TimeSegment.self,
            Settings.self,
            NetWageMonthConfig.self,
            HolidayCalendarDay.self
        ])

        let localFallbackConfiguration = ModelConfiguration(
            "PayScope",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        let isolatedLocalConfiguration = ModelConfiguration(
            "PayScopeLocalFallback",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        let inMemoryConfiguration = ModelConfiguration(
            "PayScopeInMemoryFallback",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [localFallbackConfiguration])
        } catch {
            #if DEBUG
            print("Local ModelContainer failed, trying isolated local store: \(error)")
            #endif
            do {
                return try ModelContainer(for: schema, configurations: [isolatedLocalConfiguration])
            } catch {
                #if DEBUG
                print("Isolated local ModelContainer failed, using in-memory fallback: \(error)")
                #endif
                do {
                    return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
                } catch {
                    preconditionFailure("Could not create any ModelContainer configuration: \(error)")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

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

@MainActor
enum PayScopeLiveActivityManager {
    private static let service = CalculationService()

    static func syncAtAppLaunch(settings: Settings, entries: [DayEntry], now: Date = .now) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let payload = launchPayload(settings: settings, entries: entries, now: now) else {
            await endAllActivities()
            return
        }

        await startOrUpdate(with: payload)
    }

    private static func startOrUpdate(with payload: LaunchPayload) async {
        let content = ActivityContent(
            state: PayScope_WidgetsAttributes.ContentState(
                workedTodaySeconds: payload.workedTodaySeconds,
                workedReferenceStart: payload.workedReferenceStart,
                shiftCategoryIcon: payload.shiftCategoryIcon,
                themeAccentRawValue: payload.themeAccentRawValue,
                isCompleted: payload.isCompleted,
                completedPayCents: payload.completedPayCents,
                nextShiftStart: payload.nextShiftStart,
                nextShiftDurationSeconds: payload.nextShiftDurationSeconds
            ),
            staleDate: payload.staleDate
        )

        let attributes = PayScope_WidgetsAttributes(
            title: payload.title,
            timelineStart: payload.timelineStart,
            timelineEnd: payload.timelineEnd
        )

        if let existing = Activity<PayScope_WidgetsAttributes>.activities.first {
            if existing.attributes.title != attributes.title ||
                existing.attributes.timelineStart != attributes.timelineStart ||
                existing.attributes.timelineEnd != attributes.timelineEnd {
                await existing.end(nil, dismissalPolicy: .immediate)
                _ = try? Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                return
            }

            await existing.update(content)
            return
        }

        _ = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    private static func endAllActivities() async {
        for activity in Activity<PayScope_WidgetsAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func launchPayload(settings: Settings, entries: [DayEntry], now: Date) -> LaunchPayload? {
        let dayStart = now.startOfDayLocal()
        let todayEntry = entries.first(where: { $0.date.isSameLocalDay(as: dayStart) })
        if let todayEntry {
            switch todayEntry.type {
            case .vacation, .holiday, .sick:
                return nil
            case .work, .manual:
                guard hasTrackedWork(for: todayEntry) else { return nil }
                break
            }
        } else if !isScheduledWorkday(now, settings: settings) {
            return nil
        }

        let fallbackStart = dateAtMinute(settings.timelineMinMinute ?? 8 * 60, on: dayStart)
        let fallbackEnd = dateAtMinute(settings.timelineMaxMinute ?? 17 * 60, on: dayStart)
        let shiftWindow = shiftWindow(for: todayEntry, fallbackStart: fallbackStart, fallbackEnd: fallbackEnd)
        let timelineStart = shiftWindow.start
        let timelineEnd = shiftWindow.end

        guard timelineEnd > timelineStart else { return nil }
        guard now >= timelineStart else { return nil }

        let effectiveNow = min(now, timelineEnd)
        let workedTodaySeconds = workedSeconds(until: effectiveNow, for: todayEntry)
        let workedReferenceStart = effectiveNow.addingTimeInterval(TimeInterval(-workedTodaySeconds))
        let completedPayCents = service.payCents(for: workedTodaySeconds, settings: settings)
        let isCompleted = now >= timelineEnd
        let shiftCategoryIcon = shiftIcon(for: todayEntry?.type)
        let shiftCategoryTitle = shiftTitle(for: todayEntry?.type)
        let nextShift = nextShift(after: dayStart, entries: entries, settings: settings)
        let staleDate = nextShift?.start ?? dayStart.addingDays(1)

        return LaunchPayload(
            title: "\(shiftCategoryTitle) heute",
            timelineStart: timelineStart,
            timelineEnd: timelineEnd,
            workedTodaySeconds: workedTodaySeconds,
            workedReferenceStart: workedReferenceStart,
            shiftCategoryIcon: shiftCategoryIcon,
            themeAccentRawValue: settings.themeAccent.rawValue,
            isCompleted: isCompleted,
            completedPayCents: completedPayCents,
            nextShiftStart: nextShift?.start,
            nextShiftDurationSeconds: nextShift?.durationSeconds ?? 0,
            staleDate: staleDate
        )
    }

    private static func isScheduledWorkday(_ date: Date, settings: Settings) -> Bool {
        let calendar = Calendar.current
        let weekStartWeekday = settings.weekStart == .sunday ? 1 : 2
        let currentWeekday = calendar.component(.weekday, from: date)
        let index = (currentWeekday - weekStartWeekday + 7) % 7
        return index < min(max(settings.scheduledWorkdaysCount, 1), 7)
    }

    private static func dateAtMinute(_ minute: Int, on dayStart: Date) -> Date {
        let clamped = min(max(minute, 0), 24 * 60)
        if clamped >= 24 * 60 {
            return dayStart.addingTimeInterval(24 * 3600)
        }
        let hour = clamped / 60
        let minutes = clamped % 60
        return Calendar.current.date(bySettingHour: hour, minute: minutes, second: 0, of: dayStart) ?? dayStart
    }

    private static func shiftWindow(for day: DayEntry?, fallbackStart: Date, fallbackEnd: Date) -> (start: Date, end: Date) {
        guard let day, !day.segments.isEmpty else {
            return (fallbackStart, fallbackEnd)
        }

        let starts = day.segments.map(\.start)
        let ends = day.segments.map(\.end)
        guard let minStart = starts.min(), let maxEnd = ends.max(), maxEnd > minStart else {
            return (fallbackStart, fallbackEnd)
        }
        return (minStart, maxEnd)
    }

    private static func nextShift(after dayStart: Date, entries: [DayEntry], settings: Settings) -> (start: Date, durationSeconds: Int)? {
        for dayOffset in 1...21 {
            let candidateDay = dayStart.addingDays(dayOffset)
            let entry = entries.first(where: { $0.date.isSameLocalDay(as: candidateDay) })

            if let entry {
                switch entry.type {
                case .vacation, .holiday, .sick:
                    continue
                case .work, .manual:
                    break
                }
            } else if !isScheduledWorkday(candidateDay, settings: settings) {
                continue
            }

            let fallbackStart = dateAtMinute(settings.timelineMinMinute ?? 8 * 60, on: candidateDay)
            let fallbackEnd = dateAtMinute(settings.timelineMaxMinute ?? 17 * 60, on: candidateDay)
            let window = shiftWindow(for: entry, fallbackStart: fallbackStart, fallbackEnd: fallbackEnd)
            guard window.end > window.start else { continue }

            let durationSeconds: Int
            if let manual = entry?.manualWorkedSeconds {
                durationSeconds = max(0, manual)
            } else {
                durationSeconds = max(0, Int(window.end.timeIntervalSince(window.start)))
            }

            return (window.start, durationSeconds)
        }
        return nil
    }

    private static func hasTrackedWork(for day: DayEntry) -> Bool {
        if let manualSeconds = day.manualWorkedSeconds {
            return manualSeconds > 0
        }
        return !day.segments.isEmpty
    }

    private static func workedSeconds(until now: Date, for day: DayEntry?) -> Int {
        guard let day else { return 0 }
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }

        return day.segments.reduce(0) { partial, segment in
            guard now > segment.start else { return partial }
            let effectiveEnd = min(now, segment.end)
            let elapsedSeconds = max(0, Int(effectiveEnd.timeIntervalSince(segment.start)))
            let totalSegmentSeconds = max(1, Int(segment.end.timeIntervalSince(segment.start)))
            let breakSeconds = max(0, segment.breakSeconds)
            let elapsedBreak = Int((Double(breakSeconds) * Double(elapsedSeconds) / Double(totalSegmentSeconds)).rounded())
            return partial + max(0, elapsedSeconds - elapsedBreak)
        }
    }

    private static func shiftIcon(for type: DayType?) -> String {
        switch type {
        case .manual:
            return "square.and.pencil"
        case .vacation:
            return "sun.max.fill"
        case .holiday:
            return "flag.fill"
        case .sick:
            return "cross.case.fill"
        case .work, .none:
            return "briefcase.fill"
        }
    }

    private static func shiftTitle(for type: DayType?) -> String {
        switch type {
        case .manual:
            return "Manuell"
        case .vacation:
            return "Urlaub"
        case .holiday:
            return "Feiertag"
        case .sick:
            return "Krank"
        case .work, .none:
            return "Arbeit"
        }
    }

    private struct LaunchPayload {
        let title: String
        let timelineStart: Date
        let timelineEnd: Date
        let workedTodaySeconds: Int
        let workedReferenceStart: Date
        let shiftCategoryIcon: String
        let themeAccentRawValue: String
        let isCompleted: Bool
        let completedPayCents: Int
        let nextShiftStart: Date?
        let nextShiftDurationSeconds: Int
        let staleDate: Date
    }
}
