import CloudKit
import Foundation

enum TVCloudKitShiftStoreError: LocalizedError {
    case noAccount
    case restricted
    case unavailable
    case unknownAccountStatus

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "Auf diesem Apple TV ist kein iCloud-Konto angemeldet."
        case .restricted:
            return "Das iCloud-Konto ist eingeschränkt."
        case .unavailable:
            return "iCloud ist gerade nicht verfügbar."
        case .unknownAccountStatus:
            return "Der iCloud-Kontostatus konnte nicht bestimmt werden."
        }
    }
}

actor TVCloudKitShiftStore: TVShiftScheduleStore {
    static let shared = TVCloudKitShiftStore()

    private enum RecordKeys {
        enum DayEntry: String {
            case type = "DayEntry"
            case date
            case updatedAt
            case dayType
            case manualWorkedSeconds
            case creditedOverrideSeconds
            case shiftStart
            case shiftEnd
            case breakSeconds
        }

        enum Settings: String {
            case type = "Settings"
            case settingsKey
            case updatedAt
            case themeAccent
            case workCategoryColor
            case manualCategoryColor
            case vacationCategoryColor
            case holidayCategoryColor
            case sickCategoryColor
        }

        enum TimeSegment: String {
            case type = "TimeSegment"
            case legacyType = "timesegment"
            case start
            case end
            case breakSeconds
            case dayEntryRef
        }
    }

    private struct SegmentPayload {
        let start: Date
        let end: Date
        let breakSeconds: Int
    }

    private let container = CKContainer(identifier: "iCloud.DyonisosFergadiotis.PayScope")
    private nonisolated static let settingsSingletonRecordID = CKRecord.ID(recordName: "settings-singleton")

    func fetchWeek(startingAt weekStart: Date, calendar: Calendar = .current) async throws -> TVWeekSchedule {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
        let queryStart = calendar.date(byAdding: .day, value: -1, to: weekStart) ?? weekStart
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: weekEnd) ?? weekEnd
        let queryInterval = DateInterval(start: queryStart, end: queryEnd)
        let displayInterval = DateInterval(start: weekStart, end: weekEnd)

        try await ensureAccountAvailable()

        let colorSettings = try await fetchColorSettings()
        let records = try await fetchDayEntryRecords(in: queryInterval)
        let segmentsByDay = try await fetchTimeSegmentsByDayKey(in: queryInterval)
        var latestByDayKey: [String: TVShiftEntry] = [:]

        for record in records {
            guard
                let date = record[RecordKeys.DayEntry.date.rawValue] as? Date,
                let rawType = record[RecordKeys.DayEntry.dayType.rawValue] as? String,
                let type = TVShiftDayType.fromPersistedRaw(rawType)
            else {
                continue
            }

            let updatedAt = (record[RecordKeys.DayEntry.updatedAt.rawValue] as? Date)
                ?? record.modificationDate
                ?? date
            var shiftStart = record[RecordKeys.DayEntry.shiftStart.rawValue] as? Date
            var shiftEnd = record[RecordKeys.DayEntry.shiftEnd.rawValue] as? Date
            var breakSeconds = (record[RecordKeys.DayEntry.breakSeconds.rawValue] as? NSNumber)?.intValue ?? 0
            var manualWorkedSeconds = (record[RecordKeys.DayEntry.manualWorkedSeconds.rawValue] as? NSNumber)?.intValue
            var creditedOverrideSeconds = (record[RecordKeys.DayEntry.creditedOverrideSeconds.rawValue] as? NSNumber)?.intValue

            if type == .work, (shiftStart == nil || shiftEnd == nil) {
                let key = utcDayKey(for: date)
                if let segments = segmentsByDay[key], !segments.isEmpty {
                    shiftStart = segments.map(\.start).min()
                    shiftEnd = segments.map(\.end).max()
                    breakSeconds = segments.reduce(0) { $0 + max(0, $1.breakSeconds) }
                }
            }

            switch type {
            case .work:
                manualWorkedSeconds = nil
                creditedOverrideSeconds = nil
            case .manual:
                if manualWorkedSeconds == nil,
                   let start = shiftStart,
                   let end = shiftEnd,
                   end > start {
                    manualWorkedSeconds = max(0, Int(end.timeIntervalSince(start)) - breakSeconds)
                }
                shiftStart = nil
                shiftEnd = nil
                breakSeconds = 0
                creditedOverrideSeconds = nil
            case .vacation, .holiday, .sick:
                shiftStart = nil
                shiftEnd = nil
                breakSeconds = 0
                manualWorkedSeconds = manualWorkedSeconds.map { max(0, $0) }
                creditedOverrideSeconds = creditedOverrideSeconds.map { max(0, $0) }
            }

            let entry = TVShiftEntry(
                id: record.recordID.recordName,
                date: calendar.startOfDay(for: date),
                updatedAt: updatedAt,
                type: type,
                shiftStart: shiftStart,
                shiftEnd: shiftEnd,
                breakSeconds: max(0, breakSeconds),
                manualWorkedSeconds: manualWorkedSeconds.map { max(0, $0) },
                creditedOverrideSeconds: creditedOverrideSeconds.map { max(0, $0) }
            )

            guard entry.overlaps(displayInterval) else { continue }

            let key = localDayKey(for: date, calendar: calendar)
            if let existing = latestByDayKey[key], existing.updatedAt >= updatedAt {
                continue
            }
            latestByDayKey[key] = entry
        }

        return TVWeekSchedule(
            weekStart: weekStart,
            weekEnd: weekEnd,
            entries: Array(latestByDayKey.values).sorted { $0.date < $1.date },
            colorSettings: colorSettings,
            generatedAt: Date()
        )
    }

    private func ensureAccountAvailable() async throws {
        switch try await container.accountStatus() {
        case .available:
            return
        case .noAccount:
            throw TVCloudKitShiftStoreError.noAccount
        case .restricted:
            throw TVCloudKitShiftStoreError.restricted
        case .temporarilyUnavailable:
            throw TVCloudKitShiftStoreError.unavailable
        case .couldNotDetermine:
            throw TVCloudKitShiftStoreError.unknownAccountStatus
        @unknown default:
            throw TVCloudKitShiftStoreError.unknownAccountStatus
        }
    }

    private func fetchDayEntryRecords(in interval: DateInterval) async throws -> [CKRecord] {
        let query = CKQuery(
            recordType: RecordKeys.DayEntry.type.rawValue,
            predicate: NSPredicate(
                format: "\(RecordKeys.DayEntry.date.rawValue) >= %@ AND \(RecordKeys.DayEntry.date.rawValue) <= %@",
                interval.start as NSDate,
                interval.end as NSDate
            )
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: RecordKeys.DayEntry.date.rawValue, ascending: true)
        ]

        do {
            return try await queryRecords(query)
        } catch {
            if isLikelyQueryIndexingError(error) {
                let fallback = try await queryRecords(
                    CKQuery(recordType: RecordKeys.DayEntry.type.rawValue, predicate: NSPredicate(value: true))
                )
                return fallback.filter { record in
                    guard let date = record[RecordKeys.DayEntry.date.rawValue] as? Date else { return false }
                    return interval.contains(date)
                }
            }
            if isMissingRecordTypeError(error, recordType: RecordKeys.DayEntry.type.rawValue) {
                return []
            }
            throw error
        }
    }

    private func fetchTimeSegmentsByDayKey(in interval: DateInterval) async throws -> [String: [SegmentPayload]] {
        let recordTypes = [
            RecordKeys.TimeSegment.type.rawValue,
            RecordKeys.TimeSegment.legacyType.rawValue
        ]
        var grouped: [String: [SegmentPayload]] = [:]

        for recordType in recordTypes {
            let records: [CKRecord]
            do {
                records = try await queryRecords(timeSegmentQuery(recordType: recordType, in: interval))
            } catch {
                if isMissingRecordTypeError(error, recordType: recordType) {
                    continue
                }
                if isLikelyQueryIndexingError(error) {
                    let fallback = try await queryRecords(
                        CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                    )
                    records = fallback.filter { record in
                        guard let start = record[RecordKeys.TimeSegment.start.rawValue] as? Date else { return false }
                        return interval.contains(start)
                    }
                } else {
                    throw error
                }
            }

            for record in records {
                guard
                    let start = record[RecordKeys.TimeSegment.start.rawValue] as? Date,
                    let end = record[RecordKeys.TimeSegment.end.rawValue] as? Date,
                    end > start,
                    let ref = record[RecordKeys.TimeSegment.dayEntryRef.rawValue] as? CKRecord.Reference,
                    let key = dayKey(fromDayRecordName: ref.recordID.recordName)
                else {
                    continue
                }

                let breakSeconds = (record[RecordKeys.TimeSegment.breakSeconds.rawValue] as? NSNumber)?.intValue ?? 0
                grouped[key, default: []].append(
                    SegmentPayload(start: start, end: end, breakSeconds: max(0, breakSeconds))
                )
            }
        }

        return grouped
    }

    private func fetchColorSettings() async throws -> TVShiftColorSettings {
        if let record = try? await container.privateCloudDatabase.record(for: Self.settingsSingletonRecordID) {
            return colorSettings(from: record)
        }

        let records: [CKRecord]
        do {
            let predicate = NSPredicate(format: "\(RecordKeys.Settings.settingsKey.rawValue) == %@", "singleton")
            let query = CKQuery(recordType: RecordKeys.Settings.type.rawValue, predicate: predicate)
            records = try await queryRecords(query)
        } catch {
            if isMissingRecordTypeError(error, recordType: RecordKeys.Settings.type.rawValue) {
                return TVShiftColorSettings()
            }
            guard isLikelyQueryIndexingError(error) else { throw error }
            let fallback = try await queryRecords(
                CKQuery(recordType: RecordKeys.Settings.type.rawValue, predicate: NSPredicate(value: true))
            )
            records = fallback.filter { record in
                record.recordID.recordName == Self.settingsSingletonRecordID.recordName
                    || record[RecordKeys.Settings.settingsKey.rawValue] as? String == "singleton"
            }
        }

        let newest = records.max { lhs, rhs in
            settingsUpdatedAt(lhs) < settingsUpdatedAt(rhs)
        }
        return newest.map(colorSettings(from:)) ?? TVShiftColorSettings()
    }

    private func colorSettings(from record: CKRecord) -> TVShiftColorSettings {
        let themeAccent = (record[RecordKeys.Settings.themeAccent.rawValue] as? String)
            .flatMap(TVThemeAccent.init(rawValue:)) ?? .blue
        let work = (record[RecordKeys.Settings.workCategoryColor.rawValue] as? String)
            .flatMap(TVShiftCategoryColor.init(rawValue:))
        let manual = (record[RecordKeys.Settings.manualCategoryColor.rawValue] as? String)
            .flatMap(TVShiftCategoryColor.init(rawValue:)) ?? .lavender
        let vacation = (record[RecordKeys.Settings.vacationCategoryColor.rawValue] as? String)
            .flatMap(TVShiftCategoryColor.init(rawValue:)) ?? .monochrome
        let holiday = (record[RecordKeys.Settings.holidayCategoryColor.rawValue] as? String)
            .flatMap(TVShiftCategoryColor.init(rawValue:)) ?? .peach
        let sick = (record[RecordKeys.Settings.sickCategoryColor.rawValue] as? String)
            .flatMap(TVShiftCategoryColor.init(rawValue:)) ?? .blush

        return TVShiftColorSettings(
            themeAccent: themeAccent,
            workCategoryColor: work,
            manualCategoryColor: manual,
            vacationCategoryColor: vacation,
            holidayCategoryColor: holiday,
            sickCategoryColor: sick
        )
    }

    private func settingsUpdatedAt(_ record: CKRecord) -> Date {
        (record[RecordKeys.Settings.updatedAt.rawValue] as? Date)
            ?? record.modificationDate
            ?? .distantPast
    }

    private func timeSegmentQuery(recordType: String, in interval: DateInterval) -> CKQuery {
        let query = CKQuery(
            recordType: recordType,
            predicate: NSPredicate(
                format: "\(RecordKeys.TimeSegment.start.rawValue) >= %@ AND \(RecordKeys.TimeSegment.start.rawValue) <= %@",
                interval.start as NSDate,
                interval.end as NSDate
            )
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: RecordKeys.TimeSegment.start.rawValue, ascending: true)
        ]
        return query
    }

    private func queryRecords(_ query: CKQuery) async throws -> [CKRecord] {
        let database = container.privateCloudDatabase
        var allRecords: [CKRecord] = []
        var page = try await database.records(matching: query)
        allRecords.append(contentsOf: records(from: page.matchResults))

        while let cursor = page.queryCursor {
            page = try await database.records(continuingMatchFrom: cursor)
            allRecords.append(contentsOf: records(from: page.matchResults))
        }

        return allRecords
    }

    private func records<S: Sequence>(from matches: S) -> [CKRecord]
    where S.Element == (CKRecord.ID, Result<CKRecord, Error>) {
        matches.compactMap { _, result in
            if case .success(let record) = result {
                return record
            }
            return nil
        }
    }

    private func isMissingRecordTypeError(_ error: Error, recordType: String) -> Bool {
        let diagnostics: String
        if let ckError = error as? CKError {
            diagnostics = "\(ckError.localizedDescription) \(String(describing: ckError.userInfo))".lowercased()
        } else {
            diagnostics = "\(error)".lowercased()
        }

        return diagnostics.contains("did not find record type") && diagnostics.contains(recordType.lowercased())
    }

    private func isLikelyQueryIndexingError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .invalidArguments, .serverRejectedRequest, .partialFailure:
            let diagnostics = "\(ckError.localizedDescription) \(String(describing: ckError.userInfo))".lowercased()
            return diagnostics.contains("index") || diagnostics.contains("queryable") || diagnostics.contains("sort")
        default:
            return false
        }
    }

    private func utcDayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func localDayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func dayKey(fromDayRecordName recordName: String) -> String? {
        guard recordName.hasPrefix("day-") else { return nil }
        let parts = recordName.dropFirst(4).split(separator: "-")
        guard parts.count == 3 else { return nil }
        return String(format: "%04d-%02d-%02d", Int(parts[0]) ?? 0, Int(parts[1]) ?? 0, Int(parts[2]) ?? 0)
    }
}
