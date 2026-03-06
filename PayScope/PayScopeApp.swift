import SwiftUI
import ActivityKit
import Combine
import CloudKit
import SwiftData
import os

@main
struct PayScopeApp: App {
    @StateObject private var cloudKitService = CloudKitService.shared

    private static let startupLogger = Logger(
        subsystem: "com.dyonisos.paysco",
        category: String(describing: PayScopeApp.self)
    )

    @MainActor
    private static let localModelContainer: ModelContainer = {
        let primaryStoreName = "LocalStore_v2"
        let recoveryStoreName = "LocalStore_v3"
        let recoveryFlagKey = "swiftdata.useRecoveryStore"

        let useRecoveryStoreFirst = UserDefaults.standard.bool(forKey: recoveryFlagKey)
        let orderedStoreNames = useRecoveryStoreFirst
            ? [recoveryStoreName, primaryStoreName]
            : [primaryStoreName, recoveryStoreName]

        var loadErrors: [String] = []

        for storeName in orderedStoreNames {
            do {
                let container = try makeLocalModelContainer(storeName: storeName)
                UserDefaults.standard.set(storeName == recoveryStoreName, forKey: recoveryFlagKey)
                #if DEBUG
                if storeName == recoveryStoreName {
                    print("SwiftData: using recovery store '\(recoveryStoreName)' after primary store load failure.")
                }
                #endif
                return container
            } catch {
                loadErrors.append("\(storeName): \(error)")
            }
        }

        startupLogger.fault("Failed to create persistent ModelContainer. Attempts: \(loadErrors.joined(separator: " | "), privacy: .public)")

        do {
            let fallback = try makeInMemoryModelContainer()
            startupLogger.error("Using in-memory SwiftData fallback container after persistent init failure.")
            return fallback
        } catch {
            fatalError("Failed to create fallback in-memory ModelContainer: \(error)")
        }
    }()

    @MainActor
    private static func makeLocalModelContainer(storeName: String) throws -> ModelContainer {
        // Local-only SwiftData store. Cloud sync is handled manually via CloudKitService.
        let config = ModelConfiguration(storeName, cloudKitDatabase: .none)
        return try ModelContainer(
            for: Settings.self,
                DayEntry.self,
                HolidayCalendarDay.self,
                NetWageMonthConfig.self,
                TimeSegment.self,
            configurations: config
        )
    }

    @MainActor
    private static func makeInMemoryModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: Settings.self,
                DayEntry.self,
                HolidayCalendarDay.self,
                NetWageMonthConfig.self,
                TimeSegment.self,
            configurations: config
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(cloudKitService)
                .modelContainer(Self.localModelContainer)
        }
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

            if existing.content.state == content.state,
               existing.content.staleDate == content.staleDate {
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

        let effectiveNow = min(max(now, timelineStart), timelineEnd)
        let workedTodaySeconds = workedSeconds(until: effectiveNow, for: todayEntry)
        let workedReferenceStart = max(
            timelineStart,
            effectiveNow.addingTimeInterval(TimeInterval(-workedTodaySeconds))
        )
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
        let weekStartWeekday = 2
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
        guard let day else { return (fallbackStart, fallbackEnd) }

        // New model: fixed shift times.
        if let start = day.shiftStart, let end = day.shiftEnd, end > start {
            return (start, end)
        }

        return (fallbackStart, fallbackEnd)
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

            guard let entry, hasTrackedWork(for: entry) else {
                continue
            }

            // We only show a next shift when fixed times exist.
            guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
                continue
            }

            let rawSeconds = Int(end.timeIntervalSince(start))
            let breakSeconds = max(0, entry.breakSeconds ?? 0)
            let durationSeconds = max(0, rawSeconds - breakSeconds)

            return (start, durationSeconds)
        }
        return nil
    }

    private static func hasTrackedWork(for day: DayEntry) -> Bool {
        // New model: fixed shift start/end.
        if let start = day.shiftStart, let end = day.shiftEnd, end > start {
            return true
        }

        // Manual days can still be valid if they have manual seconds.
        if let manualSeconds = day.manualWorkedSeconds {
            return manualSeconds > 0
        }

        return false
    }

    private static func workedSeconds(until now: Date, for day: DayEntry?) -> Int {
        guard let day else { return 0 }

        // Manual override
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }

        guard let start = day.shiftStart, let end = day.shiftEnd, end > start else { return 0 }

        // Only count within the shift window
        let effectiveNow = min(max(now, start), end)
        let rawSeconds = max(0, Int(effectiveNow.timeIntervalSince(start)))
        let breakSeconds = max(0, day.breakSeconds ?? 0)

        // Simple model: break is subtracted from worked time.
        return max(0, rawSeconds - breakSeconds)
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
