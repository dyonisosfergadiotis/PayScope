import Combine
import EventKit
import Foundation
import UIKit

@MainActor
final class AppleCalendarSyncService: ObservableObject {
    static let shared = AppleCalendarSyncService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncSummary: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var includedEntryTypes: Set<DayType>
    @Published private(set) var calendarAccent: ThemeAccent

    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private let calendarTitle = "PayScope"

    private let enabledKey = "payscope.appleCalendarSync.enabled.v1"
    private let calendarIdentifierKey = "payscope.appleCalendarSync.calendarIdentifier.v1"
    private let eventIDsKey = "payscope.appleCalendarSync.eventIDsByDay.v1"
    private let eventSignaturesKey = "payscope.appleCalendarSync.eventSignaturesByDay.v1"
    private let calendarAccentKey = "payscope.appleCalendarSync.calendarAccent.v1"
    private let eventMarkerPrefix = "PayScope-ID:"
    private static let includedEntryTypesDefaultsKey = "payscope.appleCalendarSync.includedEntryTypes.v1"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: enabledKey)
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        self.includedEntryTypes = Self.loadIncludedEntryTypes(from: defaults)
        self.calendarAccent = ThemeAccent(rawValue: defaults.string(forKey: calendarAccentKey) ?? "") ?? .blue
    }

    var authorizationStatusLabel: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Noch nicht angefragt"
        case .restricted:
            return "Eingeschränkt"
        case .denied:
            return "Verweigert"
        case .authorized:
            return "Erlaubt"
        case .writeOnly:
            return "Nur Schreiben"
        case .fullAccess:
            return "Erlaubt"
        @unknown default:
            return "Unbekannt"
        }
    }

    var calendarDisplayName: String {
        if let calendarIdentifier,
           let calendar = eventStore.calendar(withIdentifier: calendarIdentifier) {
            return calendar.title
        }
        return calendarTitle
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func disableSync() {
        isEnabled = false
        defaults.set(false, forKey: enabledKey)
        lastSyncSummary = "Automatischer Export ist deaktiviert."
        lastErrorMessage = nil
    }

    func setIncludedEntryType(_ type: DayType, isIncluded: Bool, entries: [DayEntry], settings: Settings? = nil) async {
        if isIncluded {
            includedEntryTypes.insert(type)
        } else {
            includedEntryTypes.remove(type)
        }
        storeIncludedEntryTypes()

        guard isEnabled else { return }
        await sync(entries: entries, settings: settings)
    }

    func setCalendarAccent(_ accent: ThemeAccent) async {
        calendarAccent = accent
        defaults.set(accent.rawValue, forKey: calendarAccentKey)

        refreshAuthorizationStatus()
        guard isEnabled || hasFullCalendarAccess else { return }

        do {
            if isEnabled {
                try await ensureCalendarAccess()
            } else {
                refreshAuthorizationStatus()
            }

            if let calendar = existingPayScopeCalendar() {
                try saveCalendarColor(calendar)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func enableAndSync(entries: [DayEntry], settings: Settings? = nil) async throws {
        do {
            try await performSync(entries: entries, allEntries: entries, settings: settings, enablesSync: true)
        } catch {
            isEnabled = false
            defaults.set(false, forKey: enabledKey)
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func sync(entries: [DayEntry], allEntries: [DayEntry]? = nil, settings: Settings? = nil) async {
        guard isEnabled else { return }
        do {
            try await performSync(
                entries: entries,
                allEntries: allEntries ?? entries,
                settings: settings,
                enablesSync: false
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func sync(entry: DayEntry, allEntries: [DayEntry]? = nil, settings: Settings? = nil) async {
        await sync(entries: [entry], allEntries: allEntries, settings: settings)
    }

    func deleteEvent(for day: Date) async {
        guard isEnabled else { return }

        do {
            try await ensureCalendarAccess()
            guard let calendar = try existingOrCreatePayScopeCalendar() else { return }

            var eventIDs = storedStringDictionary(forKey: eventIDsKey)
            var signatures = storedStringDictionary(forKey: eventSignaturesKey)
            let didRemove = try removeEvent(
                forKey: Self.localDayKey(for: day),
                calendar: calendar,
                eventIDs: &eventIDs,
                signatures: &signatures
            )
            store(eventIDs, forKey: eventIDsKey)
            store(signatures, forKey: eventSignaturesKey)

            if didRemove {
                lastSyncSummary = "Kalendereintrag entfernt."
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeAllExportedEvents() async throws {
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await ensureCalendarAccess()
            var removed = 0

            if let calendar = existingPayScopeCalendar() {
                let now = Date()
                let start = Calendar.current.date(byAdding: .year, value: -5, to: now) ?? now.addingTimeInterval(-5 * 365 * 24 * 60 * 60)
                let end = Calendar.current.date(byAdding: .year, value: 5, to: now) ?? now.addingTimeInterval(5 * 365 * 24 * 60 * 60)
                let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [calendar])

                for event in eventStore.events(matching: predicate)
                where event.notes?.contains(eventMarkerPrefix) == true {
                    try eventStore.remove(event, span: .thisEvent, commit: true)
                    removed += 1
                }
            }

            store([:], forKey: eventIDsKey)
            store([:], forKey: eventSignaturesKey)
            lastSyncSummary = removed == 1 ? "1 Kalendereintrag entfernt." : "\(removed) Kalendereinträge entfernt."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func performSync(entries: [DayEntry], allEntries: [DayEntry], settings: Settings?, enablesSync: Bool) async throws {
        isSyncing = true
        lastErrorMessage = nil
        defer { isSyncing = false }

        try await ensureCalendarAccess()
        if enablesSync {
            isEnabled = true
            defaults.set(true, forKey: enabledKey)
        }

        guard let calendar = try existingOrCreatePayScopeCalendar() else {
            throw AppleCalendarSyncError.calendarUnavailable
        }

        var eventIDs = storedStringDictionary(forKey: eventIDsKey)
        var signatures = storedStringDictionary(forKey: eventSignaturesKey)
        var inserted = 0
        var updated = 0
        var removed = 0

        for entry in entries {
            switch try syncEntry(entry, allEntries: allEntries, settings: settings, calendar: calendar, eventIDs: &eventIDs, signatures: &signatures) {
            case .inserted:
                inserted += 1
            case .updated:
                updated += 1
            case .removed:
                removed += 1
            case .unchanged:
                break
            }
        }

        store(eventIDs, forKey: eventIDsKey)
        store(signatures, forKey: eventSignaturesKey)

        let changed = inserted + updated + removed
        if changed == 0 {
            lastSyncSummary = "Kalender ist aktuell."
        } else {
            lastSyncSummary = "\(inserted) neu, \(updated) aktualisiert, \(removed) entfernt."
        }
    }

    private func ensureCalendarAccess() async throws {
        refreshAuthorizationStatus()

        switch authorizationStatus {
        case .notDetermined, .writeOnly:
            let granted = try await eventStore.requestFullAccessToEvents()
            refreshAuthorizationStatus()
            guard granted, hasFullCalendarAccess else {
                throw AppleCalendarSyncError.accessDenied
            }
        case .authorized, .fullAccess:
            return
        case .denied:
            throw AppleCalendarSyncError.accessDenied
        case .restricted:
            throw AppleCalendarSyncError.accessRestricted
        @unknown default:
            throw AppleCalendarSyncError.accessDenied
        }
    }

    private var hasFullCalendarAccess: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    private func syncEntry(
        _ entry: DayEntry,
        allEntries: [DayEntry],
        settings: Settings?,
        calendar: EKCalendar,
        eventIDs: inout [String: String],
        signatures: inout [String: String]
    ) throws -> SyncChange {
        let key = Self.localDayKey(for: entry.date)

        guard includedEntryTypes.contains(entry.type) else {
            return try removeEvent(forKey: key, calendar: calendar, eventIDs: &eventIDs, signatures: &signatures) ? .removed : .unchanged
        }

        guard let payload = CalendarEventPayload(entry: entry, allEntries: allEntries, settings: settings, marker: syncMarker(for: key)) else {
            return try removeEvent(forKey: key, calendar: calendar, eventIDs: &eventIDs, signatures: &signatures) ? .removed : .unchanged
        }

        if signatures[key] == payload.signature,
           let eventIdentifier = eventIDs[key],
           let existing = eventStore.event(withIdentifier: eventIdentifier),
           existing.calendar.calendarIdentifier == calendar.calendarIdentifier {
            return .unchanged
        }

        let existing = existingEvent(forKey: key, payload: payload, calendar: calendar, eventIDs: eventIDs)
        let event = existing ?? EKEvent(eventStore: eventStore)
        let wasExisting = existing != nil

        event.calendar = calendar
        event.title = payload.title
        event.startDate = payload.startDate
        event.endDate = payload.endDate
        event.isAllDay = payload.isAllDay
        event.notes = payload.notes
        event.url = URL(string: "payscope://shift/\(key)")
        event.alarms = []

        try eventStore.save(event, span: .thisEvent, commit: true)
        if let eventIdentifier = event.eventIdentifier {
            eventIDs[key] = eventIdentifier
        }
        signatures[key] = payload.signature

        return wasExisting ? .updated : .inserted
    }

    private func removeEvent(
        forKey key: String,
        calendar: EKCalendar,
        eventIDs: inout [String: String],
        signatures: inout [String: String]
    ) throws -> Bool {
        let event = existingEvent(forKey: key, payload: nil, calendar: calendar, eventIDs: eventIDs)
        if let event {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
        eventIDs.removeValue(forKey: key)
        signatures.removeValue(forKey: key)
        return event != nil
    }

    private func existingEvent(
        forKey key: String,
        payload: CalendarEventPayload?,
        calendar: EKCalendar,
        eventIDs: [String: String]
    ) -> EKEvent? {
        if let eventIdentifier = eventIDs[key],
           let event = eventStore.event(withIdentifier: eventIdentifier),
           event.calendar.calendarIdentifier == calendar.calendarIdentifier {
            return event
        }

        let interval = payload.map { DateInterval(start: $0.searchStartDate, end: $0.searchEndDate) }
            ?? searchInterval(forKey: key)
        let predicate = eventStore.predicateForEvents(withStart: interval.start, end: interval.end, calendars: [calendar])
        return eventStore.events(matching: predicate).first {
            $0.notes?.contains(syncMarker(for: key)) == true || $0.url?.absoluteString == "payscope://shift/\(key)"
        }
    }

    private func existingOrCreatePayScopeCalendar() throws -> EKCalendar? {
        if let existing = existingPayScopeCalendar() {
            try saveCalendarColor(existing)
            return existing
        }

        guard let source = preferredCalendarSource() else {
            return nil
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = calendarTitle
        calendar.source = source
        calendar.cgColor = calendarAccent.uiColor.cgColor

        try eventStore.saveCalendar(calendar, commit: true)
        calendarIdentifier = calendar.calendarIdentifier
        return calendar
    }

    private func existingPayScopeCalendar() -> EKCalendar? {
        if let calendarIdentifier,
           let calendar = eventStore.calendar(withIdentifier: calendarIdentifier),
           calendar.allowsContentModifications {
            return calendar
        }

        let calendars = eventStore.calendars(for: .event)
        if let calendar = calendars.first(where: { $0.title == calendarTitle && $0.allowsContentModifications }) {
            calendarIdentifier = calendar.calendarIdentifier
            return calendar
        }

        return nil
    }

    private func preferredCalendarSource() -> EKSource? {
        if let defaultSource = eventStore.defaultCalendarForNewEvents?.source,
           defaultSource.sourceType != .subscribed {
            return defaultSource
        }

        if let iCloud = eventStore.sources.first(where: {
            $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud")
        }) {
            return iCloud
        }

        if let local = eventStore.sources.first(where: { $0.sourceType == .local }) {
            return local
        }

        return eventStore.sources.first(where: { $0.sourceType != .subscribed })
    }

    private var calendarIdentifier: String? {
        get { defaults.string(forKey: calendarIdentifierKey) }
        set { defaults.set(newValue, forKey: calendarIdentifierKey) }
    }

    private func storedStringDictionary(forKey key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func store(_ dictionary: [String: String], forKey key: String) {
        defaults.set(dictionary, forKey: key)
    }

    private func storeIncludedEntryTypes() {
        defaults.set(includedEntryTypes.map(\.rawValue).sorted(), forKey: Self.includedEntryTypesDefaultsKey)
    }

    private func saveCalendarColor(_ calendar: EKCalendar) throws {
        calendar.cgColor = calendarAccent.uiColor.cgColor
        try eventStore.saveCalendar(calendar, commit: true)
    }

    private func syncMarker(for key: String) -> String {
        "\(eventMarkerPrefix) \(key)"
    }

    private func searchInterval(forKey key: String) -> DateInterval {
        let start = Self.date(fromLocalDayKey: key) ?? Date().startOfDayLocal()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(2 * 24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    private static func localDayKey(for date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    private static func date(fromLocalDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func loadIncludedEntryTypes(from defaults: UserDefaults) -> Set<DayType> {
        guard let rawValues = defaults.stringArray(forKey: includedEntryTypesDefaultsKey) else {
            return Set(DayType.allCases)
        }

        return Set(rawValues.compactMap(DayType.fromPersistedRaw))
    }
}

private enum SyncChange {
    case inserted
    case updated
    case removed
    case unchanged
}

private enum AppleCalendarSyncError: LocalizedError {
    case accessDenied
    case accessRestricted
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Kalenderzugriff wurde nicht erlaubt. Bitte erlaube PayScope den vollen Kalenderzugriff in den iOS-Einstellungen."
        case .accessRestricted:
            return "Kalenderzugriff ist auf diesem Gerät eingeschränkt."
        case .calendarUnavailable:
            return "Es konnte kein beschreibbarer Apple-Kalender erstellt werden."
        }
    }
}

private struct CalendarEventPayload {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String
    let signature: String
    let searchStartDate: Date
    let searchEndDate: Date

    init?(entry: DayEntry, allEntries: [DayEntry], settings: Settings?, marker: String) {
        let dayStart = entry.date.startOfDayLocal()
        let trimmedNotes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let endOfSearch = Calendar.current.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart.addingTimeInterval(2 * 24 * 60 * 60)

        switch entry.type {
        case .work:
            guard let shiftStart = entry.shiftStart,
                  let shiftEnd = entry.shiftEnd,
                  shiftEnd > shiftStart
            else {
                return nil
            }
            title = entry.type.label
            startDate = shiftStart
            endDate = shiftEnd
            isAllDay = false
        case .manual:
            if let shiftStart = entry.shiftStart,
               let shiftEnd = entry.shiftEnd,
               shiftEnd > shiftStart {
                title = entry.type.label
                startDate = shiftStart
                endDate = shiftEnd
                isAllDay = false
            } else {
                guard (entry.manualWorkedSeconds ?? 0) > 0 else {
                    return nil
                }
                title = entry.type.label
                startDate = dayStart
                endDate = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
                isAllDay = true
            }
        case .vacation, .holiday, .sick:
            title = entry.type.label
            startDate = dayStart
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
            isAllDay = true
        }

        searchStartDate = dayStart
        searchEndDate = endOfSearch

        var lines = [
            "PayScope",
            "Kategorie: \(entry.type.label)"
        ]

        if !isAllDay {
            lines.append("Zeit: \(Self.timeRangeString(start: startDate, end: endDate))")
        }

        let computedValues = Self.computedValues(for: entry, allEntries: allEntries, settings: settings)
        let durationText = computedValues.durationSeconds.map { Self.durationString(seconds: $0) } ?? "-"
        let payText = computedValues.payCents.map { PayScopeFormatters.currencyString(cents: $0) } ?? "-"
        lines.append("Dauer: \(durationText)")
        lines.append("Pause: \(Self.durationString(seconds: computedValues.breakSeconds))")
        lines.append("Lohn: \(payText)")

        if !trimmedNotes.isEmpty {
            lines.append("")
            lines.append(trimmedNotes)
        }

        lines.append("")
        lines.append(marker)
        notes = lines.joined(separator: "\n")

        signature = [
            title,
            entry.type.rawValue,
            Self.dateSignature(startDate),
            Self.dateSignature(endDate),
            isAllDay ? "1" : "0",
            "\(computedValues.durationSeconds ?? 0)",
            "\(computedValues.breakSeconds)",
            "\(computedValues.payCents ?? 0)",
            "\(entry.creditedOverrideSeconds ?? 0)",
            trimmedNotes
        ].joined(separator: "|")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func timeRangeString(start: Date, end: Date) -> String {
        let suffix = Calendar.current.isDate(start, inSameDayAs: end) ? "" : " (+1)"
        return "\(timeFormatter.string(from: start))-\(timeFormatter.string(from: end))\(suffix)"
    }

    private static func dateSignature(_ date: Date) -> String {
        String(format: "%.0f", date.timeIntervalSinceReferenceDate)
    }

    private static func durationString(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let hoursPart = minutes / 60
        let minutePart = minutes % 60
        if hoursPart == 0 {
            return "\(minutePart) min"
        }
        if minutePart == 0 {
            return "\(hoursPart) h"
        }
        return "\(hoursPart) h \(minutePart) min"
    }

    private static func computedValues(
        for entry: DayEntry,
        allEntries: [DayEntry],
        settings: Settings?
    ) -> (durationSeconds: Int?, breakSeconds: Int, payCents: Int?) {
        let breakSeconds = entry.type == .work ? max(0, entry.breakSeconds ?? 0) : 0
        let service = CalculationService()

        if let settings {
            switch service.exportComputation(for: entry, allEntries: allEntries, settings: settings) {
            case let .ok(valueSeconds, valueCents), let .warning(valueSeconds, valueCents, _):
                return (valueSeconds, breakSeconds, valueCents)
            case .error:
                if let fallback = fallbackDurationSeconds(for: entry, service: service) {
                    return (fallback, breakSeconds, service.payCents(for: fallback, settings: settings))
                }
                return (nil, breakSeconds, nil)
            }
        }

        return (fallbackDurationSeconds(for: entry, service: service), breakSeconds, nil)
    }

    private static func fallbackDurationSeconds(for entry: DayEntry, service: CalculationService) -> Int? {
        if let manualWorkedSeconds = entry.manualWorkedSeconds, manualWorkedSeconds > 0 {
            return manualWorkedSeconds
        }

        switch service.workedSeconds(for: entry) {
        case let .success(seconds):
            return seconds
        case .failure:
            return nil
        }
    }
}

private extension ThemeAccent {
    var uiColor: UIColor {
        switch self {
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .purple: return .systemPurple
        case .orange: return .systemOrange
        case .pink: return .systemPink
        case .teal: return .systemTeal
        case .red: return .systemRed
        case .indigo: return .systemIndigo
        }
    }
}
