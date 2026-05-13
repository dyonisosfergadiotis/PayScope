import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct StartShiftIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Schicht starten" }
    nonisolated static var description: IntentDescription {
        IntentDescription("Startet die heutige Schicht in PayScope.")
    }
    nonisolated static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await PayScopeIntentActionService.startShift() {
        case .started:
            return .result(dialog: "Schicht gestartet.")
        case .alreadyRunning:
            return .result(dialog: "Es läuft bereits eine Schicht.")
        case .alreadyCompleted:
            return .result(dialog: "Für heute ist bereits eine abgeschlossene Schicht gespeichert.")
        }
    }
}

struct EndShiftIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Schicht beenden" }
    nonisolated static var description: IntentDescription {
        IntentDescription("Beendet die aktuell laufende Schicht in PayScope.")
    }
    nonisolated static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await PayScopeIntentActionService.endShift() {
        case .ended:
            return .result(dialog: "Schicht beendet.")
        case .alreadyEnded:
            return .result(dialog: "Die Schicht ist bereits beendet.")
        case .noRunningShift:
            return .result(dialog: "Es läuft keine Schicht.")
        }
    }
}

struct AddTipIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Trinkgeld hinzufügen" }
    nonisolated static var description: IntentDescription {
        IntentDescription("Fügt für heute Trinkgeld in PayScope hinzu.")
    }
    nonisolated static var openAppWhenRun: Bool { false }

    @Parameter(
        title: "Betrag in Euro",
        requestValueDialog: "Wie viel Trinkgeld möchtest du hinzufügen?"
    )
    var amount: Double

    init() {}

    init(amount: Double) {
        self.amount = amount
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await PayScopeIntentActionService.addTip(amountEuro: amount) {
        case .added:
            return .result(dialog: "Trinkgeld hinzugefügt.")
        case .invalidAmount:
            return .result(dialog: "Bitte gib ein Trinkgeld größer als null an.")
        }
    }
}

struct AddTwelveEuroTipIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Trinkgeld 12 Euro hinzufügen" }
    nonisolated static var description: IntentDescription {
        IntentDescription("Fügt für heute 12 Euro Trinkgeld in PayScope hinzu.")
    }
    nonisolated static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await PayScopeIntentActionService.addTip(amountEuro: 12) {
        case .added:
            return .result(dialog: "12 Euro Trinkgeld hinzugefügt.")
        case .invalidAmount:
            return .result(dialog: "Bitte gib ein Trinkgeld größer als null an.")
        }
    }
}

struct MarkTodaySickIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Heute krank markieren" }
    nonisolated static var description: IntentDescription {
        IntentDescription("Markiert den heutigen Tag in PayScope als krank.")
    }
    nonisolated static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await PayScopeIntentActionService.markTodaySick()
        return .result(dialog: "Heute als krank markiert.")
    }
}

struct PayScopeAppShortcuts: AppShortcutsProvider {
    nonisolated static var shortcutTileColor: ShortcutTileColor { .blue }

    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartShiftIntent(),
            phrases: [
                "\(.applicationName) Schicht starten",
                "Schicht mit \(.applicationName) starten"
            ],
            shortTitle: "Schicht starten",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: EndShiftIntent(),
            phrases: [
                "\(.applicationName) Schicht beenden",
                "Schicht mit \(.applicationName) beenden"
            ],
            shortTitle: "Schicht beenden",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: AddTwelveEuroTipIntent(),
            phrases: [
                "\(.applicationName) Trinkgeld 12 Euro hinzufügen",
                "Trinkgeld 12 Euro mit \(.applicationName) hinzufügen",
                "12 Euro Trinkgeld in \(.applicationName) hinzufügen"
            ],
            shortTitle: "12 Euro Trinkgeld",
            systemImageName: "eurosign.circle.fill"
        )
        AppShortcut(
            intent: MarkTodaySickIntent(),
            phrases: [
                "\(.applicationName) heute krank markieren",
                "Heute in \(.applicationName) krank markieren"
            ],
            shortTitle: "Krank",
            systemImageName: "cross.case.fill"
        )
    }
}

@MainActor
private enum PayScopeIntentActionService {
    enum StartShiftOutcome {
        case started
        case alreadyRunning
        case alreadyCompleted
    }

    enum EndShiftOutcome {
        case ended
        case alreadyEnded
        case noRunningShift
    }

    enum AddTipOutcome {
        case added
        case invalidAmount
    }

    private static let localDayStore = LocalDayEntryStore.shared
    private static let localTipStore = LocalTipEntryStore.shared
    private static let cloudKitService = CloudKitService.shared
    private static let calculationService = CalculationService()

    static func startShift(now: Date = .now) async -> StartShiftOutcome {
        let settings = loadSettings()
        let dayStart = now.startOfDayLocal()
        let existing = localDayStore.load(on: dayStart)

        if calculationService.activeShiftEntry(at: now, entries: nearbyEntries(around: now)) != nil {
            return .alreadyRunning
        }

        if let existing,
           existing.type == .work,
           let start = existing.shiftStart,
           let end = existing.shiftEnd,
           end > start,
           end <= now {
            return .alreadyCompleted
        }

        let target = existing ?? DayEntry(date: utcDate(forLocalDay: dayStart))
        target.date = utcDate(forLocalDay: dayStart)
        target.updatedAt = now
        target.type = .work
        target.notes = existing?.notes ?? ""
        target.manualWorkedSeconds = nil
        target.creditedOverrideSeconds = nil
        target.shiftStart = now

        let plannedEnd = existing?.shiftEnd.flatMap { $0 > now ? $0 : nil }
        let fallbackEnd = now.addingTimeInterval(TimeInterval(plannedShiftDurationSeconds(settings: settings)))
        target.shiftEnd = plannedEnd ?? fallbackEnd
        if let end = target.shiftEnd, end <= now {
            target.shiftEnd = fallbackEnd
        }

        target.breakSeconds = max(0, existing?.breakSeconds ?? 0)
        target.alwaysApplyFifteenMinuteBuffer = existing?.alwaysApplyFifteenMinuteBuffer
            ?? settings?.effectiveAlwaysApplyFifteenMinuteBuffer

        await saveDayEntryAndRefresh(target, settings: settings, now: now)
        return .started
    }

    static func endShift(now: Date = .now) async -> EndShiftOutcome {
        let settings = loadSettings()
        let activeEntry = calculationService.activeShiftEntry(at: now, entries: nearbyEntries(around: now))
        let todayEntry = localDayStore.load(on: now.startOfDayLocal())

        guard let target = activeEntry ?? todayEntry,
              let start = target.shiftStart else {
            return .noRunningShift
        }

        if let end = target.shiftEnd, end > start, end <= now {
            return .alreadyEnded
        }

        guard now > start else {
            return .noRunningShift
        }

        target.date = utcDate(forLocalDay: target.date.startOfDayLocal())
        target.updatedAt = now
        target.type = .work
        target.shiftEnd = now
        target.breakSeconds = max(0, target.breakSeconds ?? 0)
        target.manualWorkedSeconds = nil
        target.creditedOverrideSeconds = nil

        await saveDayEntryAndRefresh(target, settings: settings, now: now)
        return .ended
    }

    static func addTip(amountEuro: Double, now: Date = .now) async -> AddTipOutcome {
        guard amountEuro.isFinite, amountEuro > 0 else {
            return .invalidAmount
        }

        let cents = Int((amountEuro * 100).rounded(.toNearestOrAwayFromZero))
        guard cents > 0 else {
            return .invalidAmount
        }

        let tip = TipEntry(date: now.startOfDayLocal(), amountCents: cents, updatedAt: now)
        localTipStore.save(tip)

        do {
            try await cloudKitService.saveTipEntry(tip)
            localTipStore.markSynced(tip)
        } catch {
            #if DEBUG
            print("CloudKit tip save failed, persisted locally as fallback: \(error)")
            #endif
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .added
    }

    static func markTodaySick(now: Date = .now) async {
        let settings = loadSettings()
        let dayStart = now.startOfDayLocal()
        let existing = localDayStore.load(on: dayStart)
        let target = existing ?? DayEntry(date: utcDate(forLocalDay: dayStart))

        target.date = utcDate(forLocalDay: dayStart)
        target.updatedAt = now
        target.type = .sick
        target.notes = existing?.notes ?? ""
        target.shiftStart = nil
        target.shiftEnd = nil
        target.breakSeconds = 0
        target.manualWorkedSeconds = nil
        target.creditedOverrideSeconds = nil
        target.alwaysApplyFifteenMinuteBuffer = nil

        await saveDayEntryAndRefresh(target, settings: settings, now: now)
    }

    private static func saveDayEntryAndRefresh(_ entry: DayEntry, settings: Settings?, now: Date) async {
        localDayStore.save(entry)

        do {
            try await cloudKitService.saveDayEntry(entry)
            localDayStore.save(entry)
        } catch {
            #if DEBUG
            print("CloudKit day save failed, persisted locally as fallback: \(error)")
            #endif
        }

        await refreshSurfaces(settings: settings, now: now)
    }

    private static func refreshSurfaces(settings: Settings?, now: Date) async {
        WidgetCenter.shared.reloadAllTimelines()

        guard let settings else { return }
        let didCompleteOnboarding = settings.hasCompletedOnboarding ||
            UserDefaults.standard.bool(forKey: "payscope.onboarding.completed.sticky")
        guard didCompleteOnboarding else { return }

        let dayStart = now.startOfDayLocal()
        let interval = DateInterval(start: dayStart.addingDays(-2), end: dayStart.addingDays(35))
        let entries = localDayStore.loadAll(in: interval)
        await PayScopeLiveActivityManager.syncAtAppLaunch(settings: settings, entries: entries, now: now)
    }

    private static func nearbyEntries(around date: Date) -> [DayEntry] {
        let dayStart = date.startOfDayLocal()
        let interval = DateInterval(start: dayStart.addingDays(-2), end: dayStart.addingDays(2))
        return localDayStore.loadAll(in: interval)
    }

    private static func plannedShiftDurationSeconds(settings: Settings?) -> Int {
        guard let weeklyTargetSeconds = settings?.weeklyTargetSeconds, weeklyTargetSeconds > 0 else {
            return 8 * 60 * 60
        }

        let workdays = max(1, settings?.scheduledWorkdaysCount ?? 5)
        let seconds = Int((Double(weeklyTargetSeconds) / Double(workdays)).rounded())
        return max(15 * 60, seconds)
    }

    private static func loadSettings() -> Settings? {
        let context = PayScopeApp.localModelContainer.mainContext
        let descriptor = FetchDescriptor<Settings>(
            predicate: #Predicate<Settings> { $0.key == "singleton" }
        )
        let fetched = (try? context.fetch(descriptor)) ?? []
        return fetched.max { $0.updatedAt < $1.updatedAt }
    }

    private static func utcDate(forLocalDay date: Date) -> Date {
        let localDay = date.startOfDayLocal()
        let components = Calendar.current.dateComponents([.year, .month, .day], from: localDay)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: components) ?? localDay.startOfDayUTC()
    }
}
