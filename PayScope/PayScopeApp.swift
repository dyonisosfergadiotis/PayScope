import SwiftUI
import ActivityKit
import Combine
import CloudKit
import SwiftData
import WidgetKit
import os

@main
struct PayScopeApp: App {
    @StateObject private var cloudKitService = CloudKitService.shared
    @Environment(\.scenePhase) private var scenePhase

    private static let startupLogger = Logger(
        subsystem: "com.dyonisos.paysco",
        category: String(describing: PayScopeApp.self)
    )

    @MainActor
    static let localModelContainer: ModelContainer = {
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
                .environment(\.locale, Locale(identifier: "de_DE"))
                .environmentObject(cloudKitService)
                .modelContainer(Self.localModelContainer)
                .task {
                    await handlePendingControlCenterAction()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await handlePendingControlCenterAction()
                    }
                }
        }
    }

    @MainActor
    private func handlePendingControlCenterAction() async {
        guard let action = PayScopeControlCenterActionStore.takePendingAction() else { return }

        switch action.kind {
        case .startShift:
            _ = await PayScopeIntentActionService.startShift()
        case .endShift:
            _ = await PayScopeIntentActionService.endShift()
        case .addTip:
            guard let amountEuro = action.amountEuro else { return }
            _ = await PayScopeIntentActionService.addTip(amountEuro: amountEuro)
        case .markTodaySick:
            await PayScopeIntentActionService.markTodaySick()
        }
    }
}

enum PayScopeControlCenterActionKind: String, Codable {
    case startShift
    case endShift
    case addTip
    case markTodaySick
}

struct PayScopeControlCenterAction: Codable {
    var id: String
    var kind: PayScopeControlCenterActionKind
    var amountEuro: Double?
}

enum PayScopeControlCenterActionStore {
    private static let appGroupIdentifier = "group.DyonisosFergadiotis.PayScope"
    private static let pendingActionKey = "payscope.controlCenter.pendingAction.v1"

    static func takePendingAction() -> PayScopeControlCenterAction? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: pendingActionKey),
            let action = try? JSONDecoder().decode(PayScopeControlCenterAction.self, from: data)
        else {
            return nil
        }

        defaults.removeObject(forKey: pendingActionKey)
        return action
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
    private static let rectangularWidgetKind = "PayScopeRectangularLockScreenWidget"
    private static let inlineWidgetKind = "PayScopeInlineLockScreenWidget"
    private static let rectangularWidgetAppGroupIdentifier = "group.DyonisosFergadiotis.PayScope"
    private static let rectangularWidgetSnapshotKey = "payscope.rectangularWidgetSnapshot.v1"

    private struct RectangularWidgetSnapshot: Codable {
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

    static func syncAtAppLaunch(settings: Settings, entries: [DayEntry], now: Date = .now) async {
        persistRectangularWidgetSnapshot(settings: settings, entries: entries, now: now)

        guard settings.effectiveShowLiveActivity else {
            await endAllActivities()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let payload = launchPayload(settings: settings, entries: entries, now: now) else {
            await endAllActivities()
            return
        }

        await startOrUpdate(with: payload)
    }

    private static func persistRectangularWidgetSnapshot(settings: Settings, entries: [DayEntry], now: Date) {
        guard let defaults = UserDefaults(suiteName: rectangularWidgetAppGroupIdentifier) else { return }

        let snapshot = rectangularWidgetSnapshot(settings: settings, entries: entries, now: now)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        defaults.set(data, forKey: rectangularWidgetSnapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: rectangularWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: inlineWidgetKind)
    }

    private static func rectangularWidgetSnapshot(settings: Settings, entries: [DayEntry], now: Date) -> RectangularWidgetSnapshot {
        let dayStart = now.startOfDayLocal()
        let payload = launchPayload(settings: settings, entries: entries, now: now)

        if let payload, now >= payload.timelineStart, now < payload.timelineEnd {
            return RectangularWidgetSnapshot(
                themeAccentRawValue: payload.themeAccentRawValue,
                isShiftActive: true,
                shiftCategoryTitle: payload.shiftCategoryTitle,
                shiftCategoryIcon: payload.shiftCategoryIcon,
                shiftStart: payload.timelineStart,
                shiftEnd: payload.timelineEnd,
                shiftDurationSeconds: max(0, Int(payload.timelineEnd.timeIntervalSince(payload.timelineStart))),
                workedReferenceStart: payload.workedReferenceStart,
                workedTodaySeconds: payload.workedTodaySeconds,
                completedPayCents: payload.completedPayCents,
                nextShiftStart: settings.effectiveWidgetShowsNextShift ? payload.nextShiftStart : nil,
                isAllDayStatus: nil,
                allDayYear: nil,
                allDayMonth: nil,
                allDayDay: nil
            )
        }

        if settings.effectiveWidgetShowsAllDayStatus, let allDayEntry = entries.first(where: {
            $0.date.isSameLocalDay(as: dayStart) &&
            ($0.type == .vacation || $0.type == .holiday || $0.type == .sick)
        }) {
            let dayComponents = Calendar.current.dateComponents([.year, .month, .day], from: dayStart)
            return RectangularWidgetSnapshot(
                themeAccentRawValue: settings.themeAccent.rawValue,
                isShiftActive: false,
                shiftCategoryTitle: shiftTitle(for: allDayEntry.type),
                shiftCategoryIcon: shiftIcon(for: allDayEntry.type),
                shiftStart: nil,
                shiftEnd: nil,
                shiftDurationSeconds: 0,
                workedReferenceStart: nil,
                workedTodaySeconds: nil,
                completedPayCents: nil,
                nextShiftStart: settings.effectiveWidgetShowsNextShift ? nextUpcomingShiftStart(after: now, entries: entries) : nil,
                isAllDayStatus: true,
                allDayYear: dayComponents.year,
                allDayMonth: dayComponents.month,
                allDayDay: dayComponents.day
            )
        }

        if let payload, settings.effectiveWidgetShowsNextShift {
            let isShiftActive = now >= payload.timelineStart && now < payload.timelineEnd
            return RectangularWidgetSnapshot(
                themeAccentRawValue: payload.themeAccentRawValue,
                isShiftActive: isShiftActive,
                shiftCategoryTitle: payload.shiftCategoryTitle,
                shiftCategoryIcon: payload.shiftCategoryIcon,
                shiftStart: payload.timelineStart,
                shiftEnd: payload.timelineEnd,
                shiftDurationSeconds: max(0, Int(payload.timelineEnd.timeIntervalSince(payload.timelineStart))),
                workedReferenceStart: payload.workedReferenceStart,
                workedTodaySeconds: payload.workedTodaySeconds,
                completedPayCents: payload.completedPayCents,
                nextShiftStart: payload.nextShiftStart,
                isAllDayStatus: nil,
                allDayYear: nil,
                allDayMonth: nil,
                allDayDay: nil
            )
        }

        let nextShiftStart = settings.effectiveWidgetShowsNextShift ? nextUpcomingShiftStart(after: now, entries: entries) : nil
        let nextShiftCategoryIcon: String?
        let nextShiftCategoryTitle: String?
        if let nextShiftStart {
            let nextShiftDay = nextShiftStart.startOfDayLocal()
            let nextShiftEntry = entries.first(where: { $0.date.isSameLocalDay(as: nextShiftDay) })
            nextShiftCategoryIcon = shiftIcon(for: nextShiftEntry?.type)
            nextShiftCategoryTitle = shiftTitle(for: nextShiftEntry?.type)
        } else {
            nextShiftCategoryIcon = nil
            nextShiftCategoryTitle = nil
        }

        return RectangularWidgetSnapshot(
            themeAccentRawValue: settings.themeAccent.rawValue,
            isShiftActive: false,
            shiftCategoryTitle: nextShiftCategoryTitle,
            shiftCategoryIcon: nextShiftCategoryIcon,
            shiftStart: nil,
            shiftEnd: nil,
            shiftDurationSeconds: 0,
            workedReferenceStart: nil,
            workedTodaySeconds: nil,
            completedPayCents: nil,
            nextShiftStart: nextShiftStart,
            isAllDayStatus: nil,
            allDayYear: nil,
            allDayMonth: nil,
            allDayDay: nil
        )
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
        let activeShift = activeShiftCandidate(at: now, entries: entries)
        let todayEntry = entries.first(where: { $0.date.isSameLocalDay(as: dayStart) })
        if activeShift == nil, let todayEntry {
            switch todayEntry.type {
            case .vacation, .holiday, .sick:
                return nil
            case .work, .manual:
                break
            }
        }

        let todayShift = shiftCandidate(on: dayStart, entries: entries)
        guard let baseShift = activeShift ?? todayShift else {
            return nil
        }

        let explicitUpcomingShift = nextShiftCandidate(after: dayStart, entries: entries)

        let focusShift: ShiftCandidate
        if let activeShift {
            focusShift = activeShift
        } else if let todayShift, now <= todayShift.end {
            focusShift = todayShift
        } else if let explicitUpcomingShift {
            focusShift = explicitUpcomingShift
        } else {
            focusShift = baseShift
        }

        let timelineStart = focusShift.start
        let timelineEnd = focusShift.end
        guard now >= timelineStart && now < timelineEnd || settings.effectiveLiveActivityShowsUpcomingShift else {
            return nil
        }
        let effectiveNow = min(max(now, timelineStart), timelineEnd)
        let focusShiftWorkedSeconds = workedSeconds(
            until: effectiveNow,
            for: focusShift.entry,
            calculateBreaks: settings.effectiveCalculateBreaks
        )
        let workedReferenceStart = max(
            timelineStart,
            effectiveNow.addingTimeInterval(TimeInterval(-focusShiftWorkedSeconds))
        )
        let workedReferenceShift = todayShift ?? activeShift ?? focusShift
        let todayEffectiveNow = min(max(now, workedReferenceShift.start), workedReferenceShift.end)
        let workedTodaySeconds = workedSeconds(
            until: todayEffectiveNow,
            for: workedReferenceShift.entry,
            calculateBreaks: settings.effectiveCalculateBreaks
        )
        let completedPayCents = service.payCents(for: workedTodaySeconds, settings: settings)
        let isCompleted = now >= timelineEnd
        let shiftCategoryIcon = shiftIcon(for: focusShift.entry?.type)
        let shiftCategoryTitle = shiftTitle(for: focusShift.entry?.type)
        let nextShift = nextShift(after: focusShift.dayStart, entries: entries, settings: settings)
        let title = focusShift.dayStart.isSameLocalDay(as: dayStart) ? "\(shiftCategoryTitle) heute" : "\(shiftCategoryTitle) läuft"
        let staleDate = nextShift?.start ?? timelineEnd.addingTimeInterval(60)

        return LaunchPayload(
            title: title,
            shiftCategoryTitle: shiftCategoryTitle,
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

    private static func activeShiftCandidate(at referenceDate: Date, entries: [DayEntry]) -> ShiftCandidate? {
        entries.compactMap { entry -> ShiftCandidate? in
            switch entry.type {
            case .work, .manual:
                break
            case .vacation, .holiday, .sick:
                return nil
            }

            guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
                return nil
            }
            guard start <= referenceDate, referenceDate < end else {
                return nil
            }

            return ShiftCandidate(
                dayStart: entry.date.startOfDayLocal(),
                entry: entry,
                start: start,
                end: end
            )
        }
        .max { lhs, rhs in
            lhs.start < rhs.start
        }
    }

    private static func shiftCandidate(on dayStart: Date, entries: [DayEntry]) -> ShiftCandidate? {
        guard let entry = entries.first(where: { $0.date.isSameLocalDay(as: dayStart) }) else {
            return nil
        }

        switch entry.type {
        case .vacation, .holiday, .sick:
            return nil
        case .work, .manual:
            break
        }

        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
            return nil
        }

        return ShiftCandidate(
            dayStart: dayStart,
            entry: entry,
            start: start,
            end: end
        )
    }

    private static func nextShiftCandidate(after dayStart: Date, entries: [DayEntry]) -> ShiftCandidate? {
        for dayOffset in 1...21 {
            let candidateDay = dayStart.addingDays(dayOffset)
            guard let candidate = shiftCandidate(on: candidateDay, entries: entries) else {
                continue
            }
            return candidate
        }
        return nil
    }

    private static func nextShift(
        after dayStart: Date,
        entries: [DayEntry],
        settings: Settings
    ) -> (start: Date, durationSeconds: Int)? {
        guard let candidate = nextShiftCandidate(after: dayStart, entries: entries) else {
            return nil
        }

        return (
            candidate.start,
            shiftDurationSeconds(
                for: candidate.entry,
                start: candidate.start,
                end: candidate.end,
                calculateBreaks: settings.effectiveCalculateBreaks
            )
        )
    }

    private static func nextUpcomingShiftStart(after now: Date, entries: [DayEntry]) -> Date? {
        nextExplicitUpcomingShiftCandidate(after: now, entries: entries)?.start
    }

    private static func nextExplicitUpcomingShiftCandidate(after now: Date, entries: [DayEntry]) -> ShiftCandidate? {
        let dayStart = now.startOfDayLocal()

        for dayOffset in 0...21 {
            let candidateDayStart = dayStart.addingDays(dayOffset)
            guard let candidate = shiftCandidate(on: candidateDayStart, entries: entries) else {
                continue
            }
            guard candidate.start > now, candidate.end > now else {
                continue
            }
            return candidate
        }

        return nil
    }

    private static func shiftDurationSeconds(
        for day: DayEntry?,
        start: Date,
        end: Date,
        calculateBreaks: Bool
    ) -> Int {
        let rawSeconds = max(0, Int(end.timeIntervalSince(start)))
        guard calculateBreaks else { return rawSeconds }
        let breakSeconds = max(0, day?.breakSeconds ?? 0)
        return max(0, rawSeconds - breakSeconds)
    }

    private static func workedSeconds(until now: Date, for day: DayEntry?, calculateBreaks: Bool) -> Int {
        guard let day else { return 0 }

        // Manual override
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }

        guard let start = day.shiftStart, let end = day.shiftEnd, end > start else { return 0 }

        // Only count within the shift window
        let effectiveNow = min(max(now, start), end)
        let rawSeconds = max(0, Int(effectiveNow.timeIntervalSince(start)))
        guard calculateBreaks else { return rawSeconds }
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
        let shiftCategoryTitle: String
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

    private struct ShiftCandidate {
        let dayStart: Date
        let entry: DayEntry?
        let start: Date
        let end: Date
    }
}
