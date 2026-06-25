import CloudKit
import Foundation
import Combine
import os

enum CloudKitRecordKeys {
    enum DayEntry: String {
        case type = "DayEntry"
        case date
        case updatedAt
        case dayType
        case notes
        case manualWorkedSeconds
        case creditedOverrideSeconds
        case shiftStart
        case shiftEnd
        case breakSeconds
        case alwaysApplyFifteenMinuteBuffer
        case tipAmountCents
    }

    enum TimeSegment: String {
        case type = "TimeSegment"
        case start
        case end
        case breakSeconds
        case dayEntryRef
    }

    enum Settings: String {
        case type = "Settings"
        case payMode
        case hourlyRateCents
        case monthlySalaryCents
        case weeklyTargetSeconds
        case vacationLookbackCount
        case vacationCreditingMode
        case vacationFixedSeconds
        case countMissingAsZero
        case strictHistoryRequired
        case calculateBreaks
        case aushilfeModeEnabled
        case holidayCreditingMode
        case holidayFixedSeconds
        case scheduledWorkdaysCount
        case themeAccent
        case calendarCellDisplayMode
        case calendarHoursBreakMode
        case calendarSummaryDisplayMode
        case showCalendarWeekNumbers
        case showCalendarWeekHours
        case showCalendarWeekPay
        case showLiveActivity
        case liveActivityShowsUpcomingShift
        case liveActivityPauseModeEnabled
        case widgetShowsNextShift
        case widgetShowsAllDayStatus
        case alwaysApplyFifteenMinuteBuffer
        case holidayCountryCode
        case holidaySubdivisionCode
        case autoSetHolidayCategory
        case markPaidHolidays
        case paidHolidayWeekdayMask
        case netWageTaxPercent
        case netPensionPercent
        case netMonthlyAllowanceEuro
        case netBonusesCSV
        case showTipsButton
        case showTipsButtonAmount
        case manualCategoryColor
        case vacationCategoryColor
        case holidayCategoryColor
        case sickCategoryColor
        case shiftShortcut1
        case shiftShortcut2
        case shiftShortcut3
        case shiftShortcutName1
        case shiftShortcutName2
        case shiftShortcutName3
        case hasCompletedOnboarding
        case settingsKey
        case updatedAt
    }

    enum HolidayCalendarDay: String {
        case type = "HolidayCalendarDay"
        case key
        case date
        case localName
        case countryCode
        case subdivisionCode
        case sourceYear
    }
    
    enum NetWageMonthConfig: String {
        case type = "NetWageMonthConfig"
        case monthStart
        case wageTaxPercent
        case pensionPercent
        case monthlyAllowanceEuro
        case bonusesCSV
    }

    enum TipEntry: String {
        case type = "TipEntry"
        case id
        case date
        case amountCents
        case updatedAt
    }
}

final class CloudKitService: ObservableObject {
    private static let logger = Logger(
        subsystem: "com.dyonisos.paysco",
        category: String(describing: CloudKitService.self)
    )

    static let shared = CloudKitService()
    private static let settingsSingletonRecordID = CKRecord.ID(recordName: "settings-singleton")

    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private let privateDatabase: CKDatabase

    // MARK: - Sync Status
    @Published private(set) var isUnsynced: Bool = false
    @Published private(set) var lastSyncErrorDescription: String? = nil

    private func markSynced() {
        DispatchQueue.main.async { [weak self] in
            self?.isUnsynced = false
            self?.lastSyncErrorDescription = nil
        }
    }

    private func markSyncError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isUnsynced = true
            self?.lastSyncErrorDescription = String(describing: error)
        }
    }

    private init() {
        self.container = CKContainer.default()
        self.publicDatabase = container.publicCloudDatabase
        self.privateDatabase = container.privateCloudDatabase
    }

    private func dayEntryRecordID(for date: Date) -> CKRecord.ID {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        let key = String(format: "day-%04d-%02d-%02d", y, m, d)
        return CKRecord.ID(recordName: key)
    }

    private func netConfigRecordID(for monthStart: Date) -> CKRecord.ID {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month], from: monthStart.startOfMonthUTC())
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let key = String(format: "net-%04d-%02d-01", y, m)
        return CKRecord.ID(recordName: key)
    }

    private func holidayRecordID(for key: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "holiday-\(key)")
    }

    private func tipEntryRecordID(for id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "tip-\(id)")
    }

    private func normalizeHolidayCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizeHolidaySubdivisionCode(_ value: String?) -> String? {
        guard let normalized = normalizeHolidayCode(value) else { return nil }
        return normalized == "ALL" ? nil : normalized
    }

    private func deduplicateHolidayDays(_ days: [HolidayCalendarDay]) -> [HolidayCalendarDay] {
        var seenKeys: Set<String> = []
        var deduplicated: [HolidayCalendarDay] = []
        deduplicated.reserveCapacity(days.count)

        for day in days where seenKeys.insert(day.key).inserted {
            deduplicated.append(day)
        }
        return deduplicated
    }

    private func normalizedHolidayDays(
        _ days: [HolidayCalendarDay],
        countryCode: String,
        subdivisionCode: String?,
        year: Int
    ) -> [HolidayCalendarDay] {
        deduplicateHolidayDays(days).map { day in
            HolidayCalendarDay(
                date: day.date,
                localName: day.localName,
                countryCode: countryCode,
                subdivisionCode: subdivisionCode,
                sourceYear: year
            )
        }
    }

    private func applyHolidayValues(_ day: HolidayCalendarDay, to record: CKRecord) {
        record[CloudKitRecordKeys.HolidayCalendarDay.key.rawValue] = day.key
        record[CloudKitRecordKeys.HolidayCalendarDay.date.rawValue] = day.date.startOfDayUTC()
        record[CloudKitRecordKeys.HolidayCalendarDay.localName.rawValue] = day.localName
        record[CloudKitRecordKeys.HolidayCalendarDay.countryCode.rawValue] =
            normalizeHolidayCode(day.countryCode) ?? day.countryCode
        record[CloudKitRecordKeys.HolidayCalendarDay.subdivisionCode.rawValue] =
            normalizeHolidaySubdivisionCode(day.subdivisionCode)
        record[CloudKitRecordKeys.HolidayCalendarDay.sourceYear.rawValue] = NSNumber(value: day.sourceYear)
    }

    private func holidayRecordMatches(_ record: CKRecord, day: HolidayCalendarDay) -> Bool {
        let storedKey = record[CloudKitRecordKeys.HolidayCalendarDay.key.rawValue] as? String
        let storedDate = (record[CloudKitRecordKeys.HolidayCalendarDay.date.rawValue] as? Date)?.startOfDayUTC()
        let storedLocalName = record[CloudKitRecordKeys.HolidayCalendarDay.localName.rawValue] as? String
        let storedCountry = normalizeHolidayCode(
            record[CloudKitRecordKeys.HolidayCalendarDay.countryCode.rawValue] as? String
        )
        let storedSubdivision = normalizeHolidaySubdivisionCode(
            record[CloudKitRecordKeys.HolidayCalendarDay.subdivisionCode.rawValue] as? String
        )
        let storedSourceYear = (record[CloudKitRecordKeys.HolidayCalendarDay.sourceYear.rawValue] as? NSNumber)?
            .intValue

        return storedKey == day.key &&
            storedDate == day.date.startOfDayUTC() &&
            storedLocalName == day.localName &&
            storedCountry == normalizeHolidayCode(day.countryCode) &&
            storedSubdivision == normalizeHolidaySubdivisionCode(day.subdivisionCode) &&
            storedSourceYear == day.sourceYear
    }

    private func holidayKey(from record: CKRecord) -> String? {
        guard
            let date = record[CloudKitRecordKeys.HolidayCalendarDay.date.rawValue] as? Date,
            let countryCode = normalizeHolidayCode(
                record[CloudKitRecordKeys.HolidayCalendarDay.countryCode.rawValue] as? String
            )
        else {
            return nil
        }

        let subdivisionCode = normalizeHolidaySubdivisionCode(
            record[CloudKitRecordKeys.HolidayCalendarDay.subdivisionCode.rawValue] as? String
        )
        return HolidayCalendarDay.makeKey(
            date: date,
            countryCode: countryCode,
            subdivisionCode: subdivisionCode
        )
    }

    private func queryRecords(_ query: CKQuery) async throws -> [CKRecord] {
        var all: [CKRecord] = []
        var page = try await privateDatabase.records(matching: query)
        all.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })

        var queryCursor = page.queryCursor
        while let cursor = queryCursor {
            page = try await privateDatabase.records(continuingMatchFrom: cursor)
            all.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
            queryCursor = page.queryCursor
        }
        return all
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

    private func isLikelyMissingRecordTypeError(_ error: Error, recordType: String) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .unknownItem, .invalidArguments, .serverRejectedRequest, .partialFailure:
            let diagnostics = "\(ckError.localizedDescription) \(String(describing: ckError.userInfo))".lowercased()
            let normalizedRecordType = recordType.lowercased()
            return diagnostics.contains(normalizedRecordType) &&
                (diagnostics.contains("record type") || diagnostics.contains("recordtype")) &&
                (diagnostics.contains("not found") || diagnostics.contains("did not find") || diagnostics.contains("unknown"))
        default:
            return false
        }
    }

    private enum SettingsWriteProfile {
        case full
        case compatibility
    }

    private func shouldRetrySettingsSaveInCompatibilityMode(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .invalidArguments, .serverRejectedRequest:
            return true
        case .partialFailure:
            let diagnostics = "\(ckError.localizedDescription) \(String(describing: ckError.userInfo))".lowercased()
            return diagnostics.contains("field") || diagnostics.contains("schema") || diagnostics.contains("record")
        default:
            return false
        }
    }

    private func shouldRetryDayEntrySaveInCompatibilityMode(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .invalidArguments, .serverRejectedRequest:
            return true
        case .partialFailure:
            let diagnostics = "\(ckError.localizedDescription) \(String(describing: ckError.userInfo))".lowercased()
            return diagnostics.contains("field") || diagnostics.contains("schema") || diagnostics.contains("record")
        default:
            return false
        }
    }

    private func isWithinInterval(_ date: Date, interval: DateInterval) -> Bool {
        date >= interval.start && date <= interval.end
    }

    private func dayEntryRecordIDs(forLocalDay date: Date) -> [CKRecord.ID] {
        let localDay = date.startOfDayLocal()

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let localComps = Calendar.current.dateComponents([.year, .month, .day], from: localDay)
        let utcDay = utc.date(from: localComps) ?? localDay.startOfDayUTC()

        let candidates = [
            dayEntryRecordID(for: date),
            dayEntryRecordID(for: localDay),
            dayEntryRecordID(for: utcDay)
        ]

        var seen: Set<String> = []
        var unique: [CKRecord.ID] = []
        for id in candidates where seen.insert(id.recordName).inserted {
            unique.append(id)
        }
        return unique
    }

    private func deleteRecordIfExists(_ recordID: CKRecord.ID) async throws {
        do {
            try await privateDatabase.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    private func recordIfExists(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await privateDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func shouldDeleteDayEntryRecord(
        _ record: CKRecord,
        targetLocalDay: Date,
        canonicalRecordName: String
    ) -> Bool {
        if let storedDate = record[CloudKitRecordKeys.DayEntry.date.rawValue] as? Date {
            return storedDate.isSameLocalDay(as: targetLocalDay)
        }
        // Fallback for malformed legacy records without a date field.
        return record.recordID.recordName == canonicalRecordName
    }

    // MARK: - Account Status

    func checkAccountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    // MARK: - Save Operations

    func saveDayEntry(_ dayEntry: DayEntry) async throws {
        let updatedAt = dayEntry.updatedAt
        // Use UTC-normalized day for deterministic record ID
        let recordID = dayEntryRecordID(for: dayEntry.date)
        let record: CKRecord
        if let existing = try? await privateDatabase.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: CloudKitRecordKeys.DayEntry.type.rawValue, recordID: recordID)
        }

        record[CloudKitRecordKeys.DayEntry.date.rawValue] = dayEntry.date.startOfDayUTC()
        record[CloudKitRecordKeys.DayEntry.updatedAt.rawValue] = updatedAt as NSDate
        record[CloudKitRecordKeys.DayEntry.dayType.rawValue] = dayEntry.type.rawValue
        record[CloudKitRecordKeys.DayEntry.notes.rawValue] = nil
        if let tipAmountCents = dayEntry.tipAmountCents, tipAmountCents > 0 {
            record[CloudKitRecordKeys.DayEntry.tipAmountCents.rawValue] = NSNumber(value: tipAmountCents)
        } else {
            record[CloudKitRecordKeys.DayEntry.tipAmountCents.rawValue] = nil
        }

        // Shift fields (single start/end/breakSeconds)
        // We store only whole shifts now (no segments aggregation here)
        switch dayEntry.type {
        case .manual:
            record[CloudKitRecordKeys.DayEntry.manualWorkedSeconds.rawValue] =
                dayEntry.manualWorkedSeconds.map { NSNumber(value: max(0, $0)) }
            record[CloudKitRecordKeys.DayEntry.creditedOverrideSeconds.rawValue] = nil
            // Manual entries: only duration, no explicit shift times
            record[CloudKitRecordKeys.DayEntry.shiftStart.rawValue] = nil
            record[CloudKitRecordKeys.DayEntry.shiftEnd.rawValue] = nil
            record[CloudKitRecordKeys.DayEntry.breakSeconds.rawValue] = nil
            record[CloudKitRecordKeys.DayEntry.alwaysApplyFifteenMinuteBuffer.rawValue] = nil
        case .vacation, .holiday, .sick:
            record[CloudKitRecordKeys.DayEntry.manualWorkedSeconds.rawValue] =
                dayEntry.manualWorkedSeconds.map { NSNumber(value: max(0, $0)) }
            record[CloudKitRecordKeys.DayEntry.creditedOverrideSeconds.rawValue] =
                dayEntry.creditedOverrideSeconds.map { NSNumber(value: max(0, $0)) }
            // Credited types: value comes from rules/settings; no explicit shift times
            record[CloudKitRecordKeys.DayEntry.shiftStart.rawValue] = nil
            record[CloudKitRecordKeys.DayEntry.shiftEnd.rawValue] = nil
            record[CloudKitRecordKeys.DayEntry.breakSeconds.rawValue] = nil
            record[CloudKitRecordKeys.DayEntry.alwaysApplyFifteenMinuteBuffer.rawValue] = nil
        case .work:
            // Work entries use shift data; keep manual/credited fields empty to avoid stale carry-over.
            record[CloudKitRecordKeys.DayEntry.manualWorkedSeconds.rawValue] = nil
            record[CloudKitRecordKeys.DayEntry.creditedOverrideSeconds.rawValue] = nil
            if let alwaysApply = dayEntry.alwaysApplyFifteenMinuteBuffer {
                record[CloudKitRecordKeys.DayEntry.alwaysApplyFifteenMinuteBuffer.rawValue] = NSNumber(value: alwaysApply)
            } else {
                record[CloudKitRecordKeys.DayEntry.alwaysApplyFifteenMinuteBuffer.rawValue] = nil
            }
            if let start = dayEntry.shiftStart, let end = dayEntry.shiftEnd, end > start {
                let breakSecs = max(0, dayEntry.breakSeconds ?? 0)
                record[CloudKitRecordKeys.DayEntry.shiftStart.rawValue] = start
                record[CloudKitRecordKeys.DayEntry.shiftEnd.rawValue] = end
                record[CloudKitRecordKeys.DayEntry.breakSeconds.rawValue] = NSNumber(value: breakSecs)
            } else {
                // Invalid or missing shift times: clear fields
                record[CloudKitRecordKeys.DayEntry.shiftStart.rawValue] = nil
                record[CloudKitRecordKeys.DayEntry.shiftEnd.rawValue] = nil
                record[CloudKitRecordKeys.DayEntry.breakSeconds.rawValue] = nil
            }
        }

        do {
            _ = try await privateDatabase.save(record)
            Self.logger.debug("Upserted DayEntry for \(dayEntry.date, privacy: .public)")
            markSynced()
        } catch {
            guard shouldRetryDayEntrySaveInCompatibilityMode(error) else {
                markSyncError(error)
                throw error
            }

            do {
                // Compatibility retry for environments where this field is not in the CloudKit schema yet.
                record[CloudKitRecordKeys.DayEntry.alwaysApplyFifteenMinuteBuffer.rawValue] = nil
                record[CloudKitRecordKeys.DayEntry.tipAmountCents.rawValue] = nil
                _ = try await privateDatabase.save(record)
                Self.logger.warning(
                    "DayEntry save succeeded with compatibility profile after initial error: \(String(describing: error), privacy: .public)"
                )
                markSynced()
            } catch {
                markSyncError(error)
                throw error
            }
        }
    }

    // DEPRECATED: TimeSegment-based storage; use DayEntry.shiftStart/shiftEnd/breakSeconds instead.
    func saveTimeSegment(_ segment: TimeSegment, for dayEntryDate: Date) async throws {
        // Ensure DayEntry exists (idempotent upsert behavior expected from caller)
        let parentID = dayEntryRecordID(for: dayEntryDate.startOfDayLocal())
        let parentRef = CKRecord.Reference(recordID: parentID, action: .none)

        let record = CKRecord(recordType: CloudKitRecordKeys.TimeSegment.type.rawValue)
        record[CloudKitRecordKeys.TimeSegment.start.rawValue] = segment.start
        record[CloudKitRecordKeys.TimeSegment.end.rawValue] = segment.end
        record[CloudKitRecordKeys.TimeSegment.breakSeconds.rawValue] = NSNumber(value: segment.breakSeconds)
        record[CloudKitRecordKeys.TimeSegment.dayEntryRef.rawValue] = parentRef

        _ = try await privateDatabase.save(record)
        Self.logger.debug("Saved TimeSegment linked to DayEntry \(parentID.recordName, privacy: .public)")
    }

    // MARK: - Fetch Operations

    func fetchDayEntries(in interval: DateInterval) async throws -> [DayEntry] {
        do {
            let records: [CKRecord]

            do {
                let predicate = NSPredicate(
                    format: "\(CloudKitRecordKeys.DayEntry.date.rawValue) >=%@ AND \(CloudKitRecordKeys.DayEntry.date.rawValue) <= %@",
                    interval.start as NSDate,
                    interval.end as NSDate
                )

                let query = CKQuery(
                    recordType: CloudKitRecordKeys.DayEntry.type.rawValue,
                    predicate: predicate
                )
                query.sortDescriptors = [
                    NSSortDescriptor(
                        key: CloudKitRecordKeys.DayEntry.date.rawValue,
                        ascending: false
                    )
                ]
                records = try await queryRecords(query)
            } catch {
                guard isLikelyQueryIndexingError(error) else { throw error }
                Self.logger.warning("DayEntry date query failed, falling back to full scan. Error: \(String(describing: error), privacy: .public)")
                let fallbackQuery = CKQuery(
                    recordType: CloudKitRecordKeys.DayEntry.type.rawValue,
                    predicate: NSPredicate(value: true)
                )
                records = try await queryRecords(fallbackQuery)
            }

            let mapped = records
                .compactMap { convertToDayEntry(from: $0) }
                .filter { isWithinInterval($0.date, interval: interval) }
                .sorted { $0.date > $1.date }
            markSynced()
            return mapped
        } catch {
            markSyncError(error)
            throw error
        }
    }

    // DEPRECATED: TimeSegment-based storage; use DayEntry.shiftStart/shiftEnd/breakSeconds instead.
    func fetchTimeSegments(for dayEntryDate: Date) async throws -> [TimeSegment] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: dayEntryDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? Date.distantFuture

        let predicate = NSPredicate(
            format: "\(CloudKitRecordKeys.TimeSegment.start.rawValue) >= %@ AND \(CloudKitRecordKeys.TimeSegment.start.rawValue) < %@",
            dayStart as NSDate,
            dayEnd as NSDate
        )

        let query = CKQuery(
            recordType: CloudKitRecordKeys.TimeSegment.type.rawValue,
            predicate: predicate
        )

        query.sortDescriptors = [
            NSSortDescriptor(
                key: CloudKitRecordKeys.TimeSegment.start.rawValue,
                ascending: true
            )
        ]

        let result = try await privateDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }

        return records.compactMap { record in
            convertToTimeSegment(from: record)
        }
    }

    // MARK: - Delete Operations

    func deleteDayEntry(_ dayEntry: DayEntry) async throws {
        try await deleteDayEntry(on: dayEntry.date)
    }

    func deleteDayEntry(on date: Date) async throws {
        do {
            let targetLocalDay = date.startOfDayLocal()
            let dayEnd = targetLocalDay.addingDays(1)
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let localComps = Calendar.current.dateComponents([.year, .month, .day], from: targetLocalDay)
            let canonicalUTCDate = utc.date(from: localComps) ?? targetLocalDay.startOfDayUTC()
            let canonicalRecordName = dayEntryRecordID(for: canonicalUTCDate).recordName
            let candidateIDs = dayEntryRecordIDs(forLocalDay: targetLocalDay)

            for recordID in candidateIDs {
                guard let record = try await recordIfExists(recordID) else { continue }
                guard shouldDeleteDayEntryRecord(
                    record,
                    targetLocalDay: targetLocalDay,
                    canonicalRecordName: canonicalRecordName
                ) else {
                    continue
                }
                try await deleteRecordIfExists(recordID)
            }

            // Cleanup for legacy records that may have non-deterministic IDs.
            do {
                let predicate = NSPredicate(
                    format: "\(CloudKitRecordKeys.DayEntry.date.rawValue) >= %@ AND \(CloudKitRecordKeys.DayEntry.date.rawValue) < %@",
                    targetLocalDay as NSDate,
                    dayEnd as NSDate
                )
                let query = CKQuery(recordType: CloudKitRecordKeys.DayEntry.type.rawValue, predicate: predicate)
                let records = try await queryRecords(query)
                for record in records {
                    try await deleteRecordIfExists(record.recordID)
                }
            } catch {
                if !isLikelyQueryIndexingError(error) {
                    throw error
                }
                Self.logger.warning("Skipped legacy DayEntry cleanup query due to missing index. Error: \(String(describing: error), privacy: .public)")
            }

            Self.logger.debug("Deleted DayEntry and TimeSegment records for \(targetLocalDay, privacy: .public)")
            markSynced()
        } catch {
            markSyncError(error)
            throw error
        }
    }

    // DEPRECATED: TimeSegment-based storage; use DayEntry.shiftStart/shiftEnd/breakSeconds instead.
    func replaceTimeSegments(for dayDate: Date, with segments: [TimeSegment]) async throws {
        let dayStart = dayDate.startOfDayLocal()
        let dayEnd = dayStart.addingDays(1)
        // Delete existing segments linked by start time window
        let segPredicate = NSPredicate(
            format: "\(CloudKitRecordKeys.TimeSegment.start.rawValue) >= %@ AND \(CloudKitRecordKeys.TimeSegment.start.rawValue) < %@",
            dayStart as NSDate,
            dayEnd as NSDate
        )
        let segQuery = CKQuery(recordType: CloudKitRecordKeys.TimeSegment.type.rawValue, predicate: segPredicate)
        let segResult = try await privateDatabase.records(matching: segQuery)
        let segRecords = segResult.matchResults.compactMap { try? $0.1.get() }
        for record in segRecords {
            try await privateDatabase.deleteRecord(withID: record.recordID)
        }
        // Save new segments linked to DayEntry
        for seg in segments {
            try await saveTimeSegment(seg, for: dayDate)
        }
    }

    // MARK: - Conversion Helpers

    private func convertToDayEntry(from record: CKRecord) -> DayEntry? {
        guard
            let date = record[CloudKitRecordKeys.DayEntry.date.rawValue] as? Date,
            let dayTypeString = record[CloudKitRecordKeys.DayEntry.dayType.rawValue] as? String,
            let dayType = DayType.fromPersistedRaw(dayTypeString)
        else {
            return nil
        }

        let updatedAt = (record[CloudKitRecordKeys.DayEntry.updatedAt.rawValue] as? Date) ?? record.modificationDate ?? date
        let manualWorkedSeconds = (record[
            CloudKitRecordKeys.DayEntry.manualWorkedSeconds.rawValue
        ] as? NSNumber)?.intValue
        let creditedOverrideSeconds = (record[
            CloudKitRecordKeys.DayEntry.creditedOverrideSeconds.rawValue
        ] as? NSNumber)?.intValue
        let alwaysApplyFifteenMinuteBuffer = (record[
            CloudKitRecordKeys.DayEntry.alwaysApplyFifteenMinuteBuffer.rawValue
        ] as? NSNumber)?.boolValue
        let tipAmountCents = (record[
            CloudKitRecordKeys.DayEntry.tipAmountCents.rawValue
        ] as? NSNumber)?.intValue

        let entry = DayEntry(
            date: date,
            updatedAt: updatedAt,
            type: dayType,
            segments: [],
            manualWorkedSeconds: manualWorkedSeconds,
            creditedOverrideSeconds: creditedOverrideSeconds,
            alwaysApplyFifteenMinuteBuffer: alwaysApplyFifteenMinuteBuffer,
            tipAmountCents: tipAmountCents.map { max(0, $0) }
        )

        // Map shift fields
        if let s = record[CloudKitRecordKeys.DayEntry.shiftStart.rawValue] as? Date {
            entry.shiftStart = s
        }
        if let e = record[CloudKitRecordKeys.DayEntry.shiftEnd.rawValue] as? Date {
            entry.shiftEnd = e
        }
        if let b = (record[CloudKitRecordKeys.DayEntry.breakSeconds.rawValue] as? NSNumber)?.intValue {
            entry.breakSeconds = b
        }

        return entry
    }

    private func convertToSettings(from record: CKRecord) -> Settings? {
        let hasCompleted = (record[CloudKitRecordKeys.Settings.hasCompletedOnboarding.rawValue] as? NSNumber)?.boolValue ?? false

        let updatedAt = (record[CloudKitRecordKeys.Settings.updatedAt.rawValue] as? Date) ?? Date.distantPast
        let key = record[CloudKitRecordKeys.Settings.settingsKey.rawValue] as? String ?? "singleton"

        let payModeString = record[CloudKitRecordKeys.Settings.payMode.rawValue] as? String
        let payMode = PayMode(rawValue: payModeString ?? "") ?? .hourly

        let hourlyCents = (record[CloudKitRecordKeys.Settings.hourlyRateCents.rawValue] as? NSNumber)?.intValue
        let monthlyCents = (record[CloudKitRecordKeys.Settings.monthlySalaryCents.rawValue] as? NSNumber)?.intValue
        let weeklyTargetSeconds = (record[CloudKitRecordKeys.Settings.weeklyTargetSeconds.rawValue] as? NSNumber)?.intValue

        let themeAccentString = record[CloudKitRecordKeys.Settings.themeAccent.rawValue] as? String
        let themeAccent = ThemeAccent(rawValue: themeAccentString ?? "") ?? .blue

        let vacationLookbackCount = max(
            1,
            (record[CloudKitRecordKeys.Settings.vacationLookbackCount.rawValue] as? NSNumber)?.intValue ?? 13
        )
        let vacationCreditingModeRaw = record[CloudKitRecordKeys.Settings.vacationCreditingMode.rawValue] as? String
        let vacationCreditingMode = vacationCreditingModeRaw.flatMap(VacationCreditingMode.init(rawValue:))
        let vacationFixedSeconds = (record[CloudKitRecordKeys.Settings.vacationFixedSeconds.rawValue] as? NSNumber)?.intValue
        let holidayCreditingModeRaw = record[CloudKitRecordKeys.Settings.holidayCreditingMode.rawValue] as? String
        let holidayCreditingMode = holidayCreditingModeRaw.flatMap(HolidayCreditingMode.init(rawValue:)) ?? .fixedValue
        let holidayFixedSeconds = (record[CloudKitRecordKeys.Settings.holidayFixedSeconds.rawValue] as? NSNumber)?.intValue
        let countMissingAsZero = (record[CloudKitRecordKeys.Settings.countMissingAsZero.rawValue] as? NSNumber)?.boolValue ?? true
        let strictHistoryRequired = (record[CloudKitRecordKeys.Settings.strictHistoryRequired.rawValue] as? NSNumber)?.boolValue ?? true
        let calculateBreaks = (record[CloudKitRecordKeys.Settings.calculateBreaks.rawValue] as? NSNumber)?.boolValue
        let aushilfeModeEnabled = (record[CloudKitRecordKeys.Settings.aushilfeModeEnabled.rawValue] as? NSNumber)?.boolValue
        let scheduledWorkdaysCount = min(
            max((record[CloudKitRecordKeys.Settings.scheduledWorkdaysCount.rawValue] as? NSNumber)?.intValue ?? 5, 1),
            7
        )

        let calendarCellDisplayModeRaw = record[CloudKitRecordKeys.Settings.calendarCellDisplayMode.rawValue] as? String
        let calendarCellDisplayMode = calendarCellDisplayModeRaw.flatMap(CalendarCellDisplayMode.init(rawValue:))
        let calendarHoursBreakModeRaw = record[CloudKitRecordKeys.Settings.calendarHoursBreakMode.rawValue] as? String
        let calendarHoursBreakMode = calendarHoursBreakModeRaw.flatMap(CalendarHoursBreakMode.init(rawValue:))
        let calendarSummaryDisplayModeRaw = record[CloudKitRecordKeys.Settings.calendarSummaryDisplayMode.rawValue] as? String
        let calendarSummaryDisplayMode = calendarSummaryDisplayModeRaw.flatMap(CalendarSummaryDisplayMode.init(rawValue:))
        let showCalendarWeekNumbers = (record[CloudKitRecordKeys.Settings.showCalendarWeekNumbers.rawValue] as? NSNumber)?.boolValue
        let showCalendarWeekHours = (record[CloudKitRecordKeys.Settings.showCalendarWeekHours.rawValue] as? NSNumber)?.boolValue
        let showCalendarWeekPay = (record[CloudKitRecordKeys.Settings.showCalendarWeekPay.rawValue] as? NSNumber)?.boolValue
        let showLiveActivity = (record[CloudKitRecordKeys.Settings.showLiveActivity.rawValue] as? NSNumber)?.boolValue
        let liveActivityShowsUpcomingShift = (record[CloudKitRecordKeys.Settings.liveActivityShowsUpcomingShift.rawValue] as? NSNumber)?.boolValue
        let liveActivityPauseModeEnabled = (record[CloudKitRecordKeys.Settings.liveActivityPauseModeEnabled.rawValue] as? NSNumber)?.boolValue
        let widgetShowsNextShift = (record[CloudKitRecordKeys.Settings.widgetShowsNextShift.rawValue] as? NSNumber)?.boolValue
        let widgetShowsAllDayStatus = (record[CloudKitRecordKeys.Settings.widgetShowsAllDayStatus.rawValue] as? NSNumber)?.boolValue
        let alwaysApplyFifteenMinuteBuffer = (record[CloudKitRecordKeys.Settings.alwaysApplyFifteenMinuteBuffer.rawValue] as? NSNumber)?.boolValue
        let holidayCountryCode = record[CloudKitRecordKeys.Settings.holidayCountryCode.rawValue] as? String
        let holidaySubdivisionCode = record[CloudKitRecordKeys.Settings.holidaySubdivisionCode.rawValue] as? String
        let autoSetHolidayCategory = (record[CloudKitRecordKeys.Settings.autoSetHolidayCategory.rawValue] as? NSNumber)?.boolValue
        let markPaidHolidays = (record[CloudKitRecordKeys.Settings.markPaidHolidays.rawValue] as? NSNumber)?.boolValue
        let paidHolidayWeekdayMask = (record[CloudKitRecordKeys.Settings.paidHolidayWeekdayMask.rawValue] as? NSNumber)?.intValue
        let netWageTaxPercent = (record[CloudKitRecordKeys.Settings.netWageTaxPercent.rawValue] as? NSNumber)?.doubleValue
        let netPensionPercent = (record[CloudKitRecordKeys.Settings.netPensionPercent.rawValue] as? NSNumber)?.doubleValue
        let netMonthlyAllowanceEuro = (record[CloudKitRecordKeys.Settings.netMonthlyAllowanceEuro.rawValue] as? NSNumber)?.doubleValue
        let netBonusesCSV = record[CloudKitRecordKeys.Settings.netBonusesCSV.rawValue] as? String
        let showTipsButton = (record[CloudKitRecordKeys.Settings.showTipsButton.rawValue] as? NSNumber)?.boolValue
        let showTipsButtonAmount = (record[CloudKitRecordKeys.Settings.showTipsButtonAmount.rawValue] as? NSNumber)?.boolValue
        let manualCategoryColor = (record[CloudKitRecordKeys.Settings.manualCategoryColor.rawValue] as? String)
            .flatMap(ShiftCategoryColor.init(rawValue:))
        let vacationCategoryColor = (record[CloudKitRecordKeys.Settings.vacationCategoryColor.rawValue] as? String)
            .flatMap(ShiftCategoryColor.init(rawValue:))
        let holidayCategoryColor = (record[CloudKitRecordKeys.Settings.holidayCategoryColor.rawValue] as? String)
            .flatMap(ShiftCategoryColor.init(rawValue:))
        let sickCategoryColor = (record[CloudKitRecordKeys.Settings.sickCategoryColor.rawValue] as? String)
            .flatMap(ShiftCategoryColor.init(rawValue:))
        let shiftShortcut1 = record[CloudKitRecordKeys.Settings.shiftShortcut1.rawValue] as? String ?? ""
        let shiftShortcut2 = record[CloudKitRecordKeys.Settings.shiftShortcut2.rawValue] as? String ?? ""
        let shiftShortcut3 = record[CloudKitRecordKeys.Settings.shiftShortcut3.rawValue] as? String ?? ""
        let shiftShortcutName1 = record[CloudKitRecordKeys.Settings.shiftShortcutName1.rawValue] as? String
        let shiftShortcutName2 = record[CloudKitRecordKeys.Settings.shiftShortcutName2.rawValue] as? String
        let shiftShortcutName3 = record[CloudKitRecordKeys.Settings.shiftShortcutName3.rawValue] as? String

        let settings = Settings(
            key: key,
            updatedAt: updatedAt,
            hasCompletedOnboarding: hasCompleted,
            payMode: payMode,
            hourlyRateCents: hourlyCents,
            monthlySalaryCents: monthlyCents,
            weeklyTargetSeconds: weeklyTargetSeconds,
            vacationLookbackCount: vacationLookbackCount,
            vacationCreditingMode: vacationCreditingMode ?? .lookback13Weeks,
            vacationFixedSeconds: vacationFixedSeconds,
            countMissingAsZero: countMissingAsZero,
            strictHistoryRequired: strictHistoryRequired,
            calculateBreaks: calculateBreaks ?? true,
            aushilfeModeEnabled: aushilfeModeEnabled ?? false,
            holidayCreditingMode: holidayCreditingMode,
            holidayFixedSeconds: holidayFixedSeconds,
            scheduledWorkdaysCount: scheduledWorkdaysCount,
            themeAccent: themeAccent,
            calendarCellDisplayMode: calendarCellDisplayMode ?? .dot,
            calendarHoursBreakMode: calendarHoursBreakMode ?? .withoutBreak,
            calendarSummaryDisplayMode: calendarSummaryDisplayMode ?? .net,
            showCalendarWeekNumbers: showCalendarWeekNumbers ?? false,
            showCalendarWeekHours: showCalendarWeekHours ?? false,
            showCalendarWeekPay: showCalendarWeekPay ?? false,
            showLiveActivity: showLiveActivity ?? true,
            liveActivityShowsUpcomingShift: liveActivityShowsUpcomingShift ?? true,
            liveActivityPauseModeEnabled: liveActivityPauseModeEnabled ?? true,
            widgetShowsNextShift: widgetShowsNextShift ?? true,
            widgetShowsAllDayStatus: widgetShowsAllDayStatus ?? true,
            alwaysApplyFifteenMinuteBuffer: alwaysApplyFifteenMinuteBuffer ?? false,
            holidayCountryCode: holidayCountryCode,
            holidaySubdivisionCode: holidaySubdivisionCode,
            autoSetHolidayCategory: autoSetHolidayCategory ?? false,
            markPaidHolidays: markPaidHolidays ?? false,
            paidHolidayWeekdayMask: paidHolidayWeekdayMask,
            netWageTaxPercent: netWageTaxPercent,
            netPensionPercent: netPensionPercent,
            netMonthlyAllowanceEuro: netMonthlyAllowanceEuro,
            netBonusesCSV: netBonusesCSV,
            showTipsButton: showTipsButton ?? true,
            showTipsButtonAmount: showTipsButtonAmount ?? true,
            manualCategoryColor: manualCategoryColor ?? .lavender,
            vacationCategoryColor: vacationCategoryColor ?? .mint,
            holidayCategoryColor: holidayCategoryColor ?? .peach,
            sickCategoryColor: sickCategoryColor ?? .blush,
            shiftShortcut1: shiftShortcut1,
            shiftShortcut2: shiftShortcut2,
            shiftShortcut3: shiftShortcut3,
            shiftShortcutName1: shiftShortcutName1,
            shiftShortcutName2: shiftShortcutName2,
            shiftShortcutName3: shiftShortcutName3
        )
        settings.vacationCreditingMode = vacationCreditingMode
        settings.calculateBreaks = calculateBreaks
        settings.aushilfeModeEnabled = aushilfeModeEnabled
        settings.calendarCellDisplayMode = calendarCellDisplayMode
        settings.calendarHoursBreakMode = calendarHoursBreakMode
        settings.calendarSummaryDisplayMode = calendarSummaryDisplayMode
        settings.showCalendarWeekNumbers = showCalendarWeekNumbers
        settings.showCalendarWeekHours = showCalendarWeekHours
        settings.showCalendarWeekPay = showCalendarWeekPay
        settings.showLiveActivity = showLiveActivity
        settings.liveActivityShowsUpcomingShift = liveActivityShowsUpcomingShift
        settings.liveActivityPauseModeEnabled = liveActivityPauseModeEnabled
        settings.widgetShowsNextShift = widgetShowsNextShift
        settings.widgetShowsAllDayStatus = widgetShowsAllDayStatus
        settings.alwaysApplyFifteenMinuteBuffer = alwaysApplyFifteenMinuteBuffer
        settings.autoSetHolidayCategory = autoSetHolidayCategory
        settings.markPaidHolidays = markPaidHolidays
        settings.showTipsButton = showTipsButton
        settings.showTipsButtonAmount = showTipsButtonAmount
        settings.manualCategoryColor = manualCategoryColor
        settings.vacationCategoryColor = vacationCategoryColor
        settings.holidayCategoryColor = holidayCategoryColor
        settings.sickCategoryColor = sickCategoryColor

        return settings
    }

    // MARK: - Settings API

    func fetchSettings() async throws -> [Settings] {
        do {
            let query = CKQuery(recordType: CloudKitRecordKeys.Settings.type.rawValue, predicate: NSPredicate(value: true))
            let records = try await queryRecords(query)
            let mapped = records
                .compactMap { convertToSettings(from: $0) }
                .sorted { $0.updatedAt > $1.updatedAt }
            markSynced()
            return mapped
        } catch {
            markSyncError(error)
            throw error
        }
    }

    func fetchSettingsSingleton() async throws -> Settings? {
        do {
            if let record = try? await privateDatabase.record(for: Self.settingsSingletonRecordID),
               let mapped = convertToSettings(from: record) {
                markSynced()
                return mapped
            }

            let mapped: Settings?
            do {
                let predicate = NSPredicate(format: "\(CloudKitRecordKeys.Settings.settingsKey.rawValue) == %@", "singleton")
                let query = CKQuery(recordType: CloudKitRecordKeys.Settings.type.rawValue, predicate: predicate)
                let records = try await queryRecords(query)
                mapped = records
                    .compactMap { convertToSettings(from: $0) }
                    .max(by: { $0.updatedAt < $1.updatedAt })
            } catch {
                guard isLikelyQueryIndexingError(error) else { throw error }
                Self.logger.warning("Settings singleton query failed, falling back to full scan. Error: \(String(describing: error), privacy: .public)")
                let fallbackQuery = CKQuery(recordType: CloudKitRecordKeys.Settings.type.rawValue, predicate: NSPredicate(value: true))
                let records = try await queryRecords(fallbackQuery)
                mapped = records
                    .compactMap { record -> Settings? in
                        guard let settings = convertToSettings(from: record) else { return nil }
                        if record.recordID.recordName == Self.settingsSingletonRecordID.recordName {
                            return settings
                        }
                        return settings.key == "singleton" ? settings : nil
                    }
                    .max(by: { $0.updatedAt < $1.updatedAt })
            }

            markSynced()
            return mapped
        } catch {
            markSyncError(error)
            throw error
        }
    }

    private func buildSettingsRecord(
        from settings: Settings,
        saveDate: Date,
        profile: SettingsWriteProfile
    ) async -> CKRecord {
        let recordID = Self.settingsSingletonRecordID
        let record: CKRecord
        if let existing = try? await privateDatabase.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: CloudKitRecordKeys.Settings.type.rawValue, recordID: recordID)
        }
        applySettingsFields(to: record, from: settings, saveDate: saveDate, profile: profile)
        return record
    }

    private func applySettingsFields(
        to record: CKRecord,
        from settings: Settings,
        saveDate: Date,
        profile: SettingsWriteProfile
    ) {
        let includeExtendedFields = profile == .full

        record[CloudKitRecordKeys.Settings.settingsKey.rawValue] = "singleton"
        record[CloudKitRecordKeys.Settings.updatedAt.rawValue] = saveDate as NSDate
        record[CloudKitRecordKeys.Settings.hasCompletedOnboarding.rawValue] = NSNumber(value: settings.hasCompletedOnboarding)
        record[CloudKitRecordKeys.Settings.payMode.rawValue] = settings.payMode.rawValue
        if let hourly = settings.hourlyRateCents {
            record[CloudKitRecordKeys.Settings.hourlyRateCents.rawValue] = NSNumber(value: hourly)
        } else {
            record[CloudKitRecordKeys.Settings.hourlyRateCents.rawValue] = nil
        }
        if let monthly = settings.monthlySalaryCents {
            record[CloudKitRecordKeys.Settings.monthlySalaryCents.rawValue] = NSNumber(value: monthly)
        } else {
            record[CloudKitRecordKeys.Settings.monthlySalaryCents.rawValue] = nil
        }
        if let weekly = settings.weeklyTargetSeconds {
            record[CloudKitRecordKeys.Settings.weeklyTargetSeconds.rawValue] = NSNumber(value: weekly)
        } else {
            record[CloudKitRecordKeys.Settings.weeklyTargetSeconds.rawValue] = nil
        }
        let sanitizedVacationLookbackCount = max(1, settings.vacationLookbackCount)
        record[CloudKitRecordKeys.Settings.vacationLookbackCount.rawValue] = NSNumber(value: sanitizedVacationLookbackCount)
        if let vacationMode = settings.vacationCreditingMode {
            record[CloudKitRecordKeys.Settings.vacationCreditingMode.rawValue] = vacationMode.rawValue
        } else {
            record[CloudKitRecordKeys.Settings.vacationCreditingMode.rawValue] = nil
        }
        if let vacationFixedSeconds = settings.vacationFixedSeconds {
            record[CloudKitRecordKeys.Settings.vacationFixedSeconds.rawValue] = NSNumber(value: max(0, vacationFixedSeconds))
        } else {
            record[CloudKitRecordKeys.Settings.vacationFixedSeconds.rawValue] = nil
        }
        record[CloudKitRecordKeys.Settings.countMissingAsZero.rawValue] = NSNumber(value: settings.countMissingAsZero)
        record[CloudKitRecordKeys.Settings.strictHistoryRequired.rawValue] = NSNumber(value: settings.strictHistoryRequired)
        record[CloudKitRecordKeys.Settings.holidayCreditingMode.rawValue] = settings.holidayCreditingMode.rawValue
        if let holidayFixedSeconds = settings.holidayFixedSeconds {
            record[CloudKitRecordKeys.Settings.holidayFixedSeconds.rawValue] = NSNumber(value: max(0, holidayFixedSeconds))
        } else {
            record[CloudKitRecordKeys.Settings.holidayFixedSeconds.rawValue] = nil
        }
        let sanitizedWorkdaysCount = min(max(settings.scheduledWorkdaysCount, 1), 7)
        record[CloudKitRecordKeys.Settings.scheduledWorkdaysCount.rawValue] = NSNumber(value: sanitizedWorkdaysCount)
        record[CloudKitRecordKeys.Settings.themeAccent.rawValue] = settings.themeAccent.rawValue
        if let calendarDisplayMode = settings.calendarCellDisplayMode {
            record[CloudKitRecordKeys.Settings.calendarCellDisplayMode.rawValue] = calendarDisplayMode.rawValue
        } else {
            record[CloudKitRecordKeys.Settings.calendarCellDisplayMode.rawValue] = nil
        }
        if let calendarHoursBreakMode = settings.calendarHoursBreakMode {
            record[CloudKitRecordKeys.Settings.calendarHoursBreakMode.rawValue] = calendarHoursBreakMode.rawValue
        } else {
            record[CloudKitRecordKeys.Settings.calendarHoursBreakMode.rawValue] = nil
        }

        guard includeExtendedFields else { return }

        if let calculateBreaks = settings.calculateBreaks {
            record[CloudKitRecordKeys.Settings.calculateBreaks.rawValue] = NSNumber(value: calculateBreaks)
        } else {
            record[CloudKitRecordKeys.Settings.calculateBreaks.rawValue] = nil
        }
        if let aushilfeModeEnabled = settings.aushilfeModeEnabled {
            record[CloudKitRecordKeys.Settings.aushilfeModeEnabled.rawValue] = NSNumber(value: aushilfeModeEnabled)
        } else {
            record[CloudKitRecordKeys.Settings.aushilfeModeEnabled.rawValue] = nil
        }

        if let calendarSummaryDisplayMode = settings.calendarSummaryDisplayMode {
            record[CloudKitRecordKeys.Settings.calendarSummaryDisplayMode.rawValue] = calendarSummaryDisplayMode.rawValue
        } else {
            record[CloudKitRecordKeys.Settings.calendarSummaryDisplayMode.rawValue] = nil
        }
        if let show = settings.showCalendarWeekNumbers {
            record[CloudKitRecordKeys.Settings.showCalendarWeekNumbers.rawValue] = NSNumber(value: show)
        } else {
            record[CloudKitRecordKeys.Settings.showCalendarWeekNumbers.rawValue] = nil
        }
        if let show = settings.showCalendarWeekHours {
            record[CloudKitRecordKeys.Settings.showCalendarWeekHours.rawValue] = NSNumber(value: show)
        } else {
            record[CloudKitRecordKeys.Settings.showCalendarWeekHours.rawValue] = nil
        }
        if let show = settings.showCalendarWeekPay {
            record[CloudKitRecordKeys.Settings.showCalendarWeekPay.rawValue] = NSNumber(value: show)
        } else {
            record[CloudKitRecordKeys.Settings.showCalendarWeekPay.rawValue] = nil
        }
        if let showLiveActivity = settings.showLiveActivity {
            record[CloudKitRecordKeys.Settings.showLiveActivity.rawValue] = NSNumber(value: showLiveActivity)
        } else {
            record[CloudKitRecordKeys.Settings.showLiveActivity.rawValue] = nil
        }
        if let liveActivityShowsUpcomingShift = settings.liveActivityShowsUpcomingShift {
            record[CloudKitRecordKeys.Settings.liveActivityShowsUpcomingShift.rawValue] = NSNumber(value: liveActivityShowsUpcomingShift)
        } else {
            record[CloudKitRecordKeys.Settings.liveActivityShowsUpcomingShift.rawValue] = nil
        }
        if let liveActivityPauseModeEnabled = settings.liveActivityPauseModeEnabled {
            record[CloudKitRecordKeys.Settings.liveActivityPauseModeEnabled.rawValue] = NSNumber(value: liveActivityPauseModeEnabled)
        } else {
            record[CloudKitRecordKeys.Settings.liveActivityPauseModeEnabled.rawValue] = nil
        }
        if let widgetShowsNextShift = settings.widgetShowsNextShift {
            record[CloudKitRecordKeys.Settings.widgetShowsNextShift.rawValue] = NSNumber(value: widgetShowsNextShift)
        } else {
            record[CloudKitRecordKeys.Settings.widgetShowsNextShift.rawValue] = nil
        }
        if let widgetShowsAllDayStatus = settings.widgetShowsAllDayStatus {
            record[CloudKitRecordKeys.Settings.widgetShowsAllDayStatus.rawValue] = NSNumber(value: widgetShowsAllDayStatus)
        } else {
            record[CloudKitRecordKeys.Settings.widgetShowsAllDayStatus.rawValue] = nil
        }
        if let alwaysApplyFifteenMinuteBuffer = settings.alwaysApplyFifteenMinuteBuffer {
            record[CloudKitRecordKeys.Settings.alwaysApplyFifteenMinuteBuffer.rawValue] = NSNumber(value: alwaysApplyFifteenMinuteBuffer)
        } else {
            record[CloudKitRecordKeys.Settings.alwaysApplyFifteenMinuteBuffer.rawValue] = nil
        }
        if let holidayCountryCode = settings.holidayCountryCode {
            record[CloudKitRecordKeys.Settings.holidayCountryCode.rawValue] = holidayCountryCode
        } else {
            record[CloudKitRecordKeys.Settings.holidayCountryCode.rawValue] = nil
        }
        if let holidaySubdivisionCode = settings.holidaySubdivisionCode {
            record[CloudKitRecordKeys.Settings.holidaySubdivisionCode.rawValue] = holidaySubdivisionCode
        } else {
            record[CloudKitRecordKeys.Settings.holidaySubdivisionCode.rawValue] = nil
        }
        if let autoSetHolidayCategory = settings.autoSetHolidayCategory {
            record[CloudKitRecordKeys.Settings.autoSetHolidayCategory.rawValue] = NSNumber(value: autoSetHolidayCategory)
        } else {
            record[CloudKitRecordKeys.Settings.autoSetHolidayCategory.rawValue] = nil
        }
        if let markPaidHolidays = settings.markPaidHolidays {
            record[CloudKitRecordKeys.Settings.markPaidHolidays.rawValue] = NSNumber(value: markPaidHolidays)
        } else {
            record[CloudKitRecordKeys.Settings.markPaidHolidays.rawValue] = nil
        }
        if let paidHolidayWeekdayMask = settings.paidHolidayWeekdayMask {
            record[CloudKitRecordKeys.Settings.paidHolidayWeekdayMask.rawValue] = NSNumber(value: paidHolidayWeekdayMask)
        } else {
            record[CloudKitRecordKeys.Settings.paidHolidayWeekdayMask.rawValue] = nil
        }
        if let netWageTaxPercent = settings.netWageTaxPercent {
            record[CloudKitRecordKeys.Settings.netWageTaxPercent.rawValue] = NSNumber(value: netWageTaxPercent)
        } else {
            record[CloudKitRecordKeys.Settings.netWageTaxPercent.rawValue] = nil
        }
        if let netPensionPercent = settings.netPensionPercent {
            record[CloudKitRecordKeys.Settings.netPensionPercent.rawValue] = NSNumber(value: netPensionPercent)
        } else {
            record[CloudKitRecordKeys.Settings.netPensionPercent.rawValue] = nil
        }
        if let netMonthlyAllowanceEuro = settings.netMonthlyAllowanceEuro {
            record[CloudKitRecordKeys.Settings.netMonthlyAllowanceEuro.rawValue] = NSNumber(value: netMonthlyAllowanceEuro)
        } else {
            record[CloudKitRecordKeys.Settings.netMonthlyAllowanceEuro.rawValue] = nil
        }
        if let netBonusesCSV = settings.netBonusesCSV {
            record[CloudKitRecordKeys.Settings.netBonusesCSV.rawValue] = netBonusesCSV
        } else {
            record[CloudKitRecordKeys.Settings.netBonusesCSV.rawValue] = nil
        }
        if let showTipsButton = settings.showTipsButton {
            record[CloudKitRecordKeys.Settings.showTipsButton.rawValue] = NSNumber(value: showTipsButton)
        } else {
            record[CloudKitRecordKeys.Settings.showTipsButton.rawValue] = nil
        }
        if let showTipsButtonAmount = settings.showTipsButtonAmount {
            record[CloudKitRecordKeys.Settings.showTipsButtonAmount.rawValue] = NSNumber(value: showTipsButtonAmount)
        } else {
            record[CloudKitRecordKeys.Settings.showTipsButtonAmount.rawValue] = nil
        }
        record[CloudKitRecordKeys.Settings.manualCategoryColor.rawValue] = settings.effectiveManualCategoryColor.rawValue
        record[CloudKitRecordKeys.Settings.vacationCategoryColor.rawValue] = settings.effectiveVacationCategoryColor.rawValue
        record[CloudKitRecordKeys.Settings.holidayCategoryColor.rawValue] = settings.effectiveHolidayCategoryColor.rawValue
        record[CloudKitRecordKeys.Settings.sickCategoryColor.rawValue] = settings.effectiveSickCategoryColor.rawValue

        let shortcut1 = settings.shiftShortcut1.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortcut2 = settings.shiftShortcut2.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortcut3 = settings.shiftShortcut3.trimmingCharacters(in: .whitespacesAndNewlines)
        record[CloudKitRecordKeys.Settings.shiftShortcut1.rawValue] = shortcut1.isEmpty ? nil : shortcut1
        record[CloudKitRecordKeys.Settings.shiftShortcut2.rawValue] = shortcut2.isEmpty ? nil : shortcut2
        record[CloudKitRecordKeys.Settings.shiftShortcut3.rawValue] = shortcut3.isEmpty ? nil : shortcut3

        let name1 = settings.shiftShortcutName1?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name2 = settings.shiftShortcutName2?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name3 = settings.shiftShortcutName3?.trimmingCharacters(in: .whitespacesAndNewlines)
        record[CloudKitRecordKeys.Settings.shiftShortcutName1.rawValue] = (name1?.isEmpty == false) ? name1 : nil
        record[CloudKitRecordKeys.Settings.shiftShortcutName2.rawValue] = (name2?.isEmpty == false) ? name2 : nil
        record[CloudKitRecordKeys.Settings.shiftShortcutName3.rawValue] = (name3?.isEmpty == false) ? name3 : nil
    }

    func saveSettings(_ settings: Settings) async throws {
        let saveDate = Date()

        do {
            let fullRecord = await buildSettingsRecord(from: settings, saveDate: saveDate, profile: .full)
            _ = try await privateDatabase.save(fullRecord)
            settings.updatedAt = saveDate
            Self.logger.debug("Upserted Settings singleton")
            markSynced()
        } catch {
            guard shouldRetrySettingsSaveInCompatibilityMode(error) else {
                markSyncError(error)
                throw error
            }

            do {
                let compatibilityRecord = await buildSettingsRecord(
                    from: settings,
                    saveDate: saveDate,
                    profile: .compatibility
                )
                _ = try await privateDatabase.save(compatibilityRecord)
                settings.updatedAt = saveDate
                Self.logger.warning("Settings save succeeded with compatibility profile after initial error: \(String(describing: error), privacy: .public)")
                markSynced()
            } catch {
                markSyncError(error)
                throw error
            }
        }
    }

    @MainActor
    func loadOrCreateSettings(defaults: Settings = Settings()) async -> Settings {
        do {
            if let existing = try await fetchSettingsSingleton() {
                return existing
            }
        } catch {
            Self.logger.error("Failed to fetch settings singleton: \(String(describing: error), privacy: .public)")
        }

        // Not found or fetch failed: try to save defaults and return them
        do {
            try await saveSettings(defaults)
            return defaults
        } catch {
            Self.logger.error("Failed to save default settings: \(String(describing: error), privacy: .public)")
            return defaults
        }
    }

    // MARK: - Onboarding Gate Helpers

    /// Returns the current settings singleton (created with defaults if missing).
    /// Use `settings.hasCompletedOnboarding` to decide if onboarding should be shown.
    @MainActor
    func loadSettingsForOnboardingGate() async -> Settings {
        await loadOrCreateSettings(defaults: Settings())
    }

    /// Marks onboarding as completed and persists the settings singleton.
    @MainActor
    func markOnboardingCompleted(_ settings: Settings) async {
        let updated = settings
        updated.hasCompletedOnboarding = true
        do {
            try await saveSettings(updated)
        } catch {
            Self.logger.error("Failed to save onboarding completion: \(String(describing: error), privacy: .public)")
            markSyncError(error)
        }
    }

    // MARK: - HolidayCalendarDay API

    func saveHolidayDays(_ days: [HolidayCalendarDay]) async throws {
        do {
            let uniqueDays = deduplicateHolidayDays(days)
            var savedCount = 0

            for day in uniqueDays {
                let recordID = holidayRecordID(for: day.key)
                let record: CKRecord
                if let existing = try? await privateDatabase.record(for: recordID) {
                    if holidayRecordMatches(existing, day: day) {
                        continue
                    }
                    record = existing
                } else {
                    record = CKRecord(
                        recordType: CloudKitRecordKeys.HolidayCalendarDay.type.rawValue,
                        recordID: recordID
                    )
                }
                applyHolidayValues(day, to: record)
                try await privateDatabase.save(record)
                savedCount += 1
            }
            Self.logger.debug("Saved \(savedCount) changed HolidayCalendarDay records out of \(uniqueDays.count) checked")
            markSynced()
        } catch {
            markSyncError(error)
            throw error
        }
    }

    func replaceHolidayDays(
        _ days: [HolidayCalendarDay],
        countryCode: String,
        subdivisionCode: String?,
        year: Int
    ) async throws {
        do {
            let normalizedCountry = normalizeHolidayCode(countryCode) ?? "DE"
            let normalizedSubdivision = normalizeHolidaySubdivisionCode(subdivisionCode)
            let incomingDays = normalizedHolidayDays(
                days,
                countryCode: normalizedCountry,
                subdivisionCode: normalizedSubdivision,
                year: year
            )
            let incomingKeys = Set(incomingDays.map(\.key))

            let query = CKQuery(
                recordType: CloudKitRecordKeys.HolidayCalendarDay.type.rawValue,
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(
                        format: "\(CloudKitRecordKeys.HolidayCalendarDay.sourceYear.rawValue) == %d",
                        year
                    ),
                    NSPredicate(
                        format: "\(CloudKitRecordKeys.HolidayCalendarDay.countryCode.rawValue) == %@",
                        normalizedCountry
                    )
                ])
            )
            let existingRecords = try await queryRecords(query)
            var recordsToDeleteByName: [String: CKRecord.ID] = [:]
            var canonicalExistingRecordsByKey: [String: CKRecord] = [:]

            for record in existingRecords {
                let existingSubdivision = normalizeHolidaySubdivisionCode(
                    record[CloudKitRecordKeys.HolidayCalendarDay.subdivisionCode.rawValue] as? String
                )
                guard existingSubdivision == normalizedSubdivision else { continue }

                guard let existingKey = holidayKey(from: record) else {
                    recordsToDeleteByName[record.recordID.recordName] = record.recordID
                    continue
                }

                if !incomingKeys.contains(existingKey) {
                    recordsToDeleteByName[record.recordID.recordName] = record.recordID
                    continue
                }

                let canonicalRecordName = holidayRecordID(for: existingKey).recordName
                if record.recordID.recordName != canonicalRecordName {
                    // Cleanup legacy records that use non-canonical record IDs.
                    recordsToDeleteByName[record.recordID.recordName] = record.recordID
                    continue
                }

                canonicalExistingRecordsByKey[existingKey] = record
            }

            for recordID in recordsToDeleteByName.values {
                try await deleteRecordIfExists(recordID)
            }

            let daysToSave = incomingDays.filter { day in
                guard let existing = canonicalExistingRecordsByKey[day.key] else { return true }
                return !holidayRecordMatches(existing, day: day)
            }

            if !daysToSave.isEmpty {
                try await saveHolidayDays(daysToSave)
            } else {
                markSynced()
            }
        } catch {
            markSyncError(error)
            throw error
        }
    }

    func deleteHolidayDays(countryCode: String? = nil, subdivisionCode: String? = nil) async throws -> Int {
        do {
            let normalizedCountry: String? = {
                let candidate = countryCode?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased() ?? ""
                return candidate.isEmpty ? nil : candidate
            }()
            let normalizedSubdivision: String? = {
                let candidate = subdivisionCode?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased() ?? ""
                return candidate.isEmpty ? nil : candidate
            }()

            var predicates: [NSPredicate] = []
            if let normalizedCountry {
                predicates.append(
                    NSPredicate(
                        format: "\(CloudKitRecordKeys.HolidayCalendarDay.countryCode.rawValue) == %@",
                        normalizedCountry
                    )
                )
            }
            if let normalizedSubdivision {
                predicates.append(
                    NSPredicate(
                        format: "\(CloudKitRecordKeys.HolidayCalendarDay.subdivisionCode.rawValue) == %@",
                        normalizedSubdivision
                    )
                )
            }

            let predicate: NSPredicate = predicates.isEmpty
                ? NSPredicate(value: true)
                : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            let query = CKQuery(
                recordType: CloudKitRecordKeys.HolidayCalendarDay.type.rawValue,
                predicate: predicate
            )
            let records = try await queryRecords(query)

            for record in records {
                try await deleteRecordIfExists(record.recordID)
            }

            markSynced()
            return records.count
        } catch {
            markSyncError(error)
            throw error
        }
    }

    func clearStaleHolidayMarkers(validHolidayDates: Set<Date>, year: Int) async throws -> Int {
        let normalizedValidDates = Set(validHolidayDates.map { $0.startOfDayLocal() })
        guard let yearInterval = dayInterval(forYear: year) else { return 0 }

        let entries = try await fetchDayEntries(in: yearInterval)
        var cleanedCount = 0

        for entry in entries where entry.type == .holiday {
            let localDate = entry.date.startOfDayLocal()
            guard !normalizedValidDates.contains(localDate) else { continue }

            if shouldKeepDayEntryWhenRemovingHolidayMarker(entry) {
                entry.type = .work
                entry.creditedOverrideSeconds = nil
                try await saveDayEntry(entry)
            } else {
                try await deleteDayEntry(on: entry.date)
            }

            cleanedCount += 1
        }

        return cleanedCount
    }

    func fetchHolidayDays(countryCode: String?, subdivisionCode: String?, year: Int) async throws -> [HolidayCalendarDay] {
        do {
            let normalizedCountry = normalizeHolidayCode(countryCode)
            let normalizedSubdivision = normalizeHolidaySubdivisionCode(subdivisionCode)

            var predicates: [NSPredicate] = []
            predicates.append(NSPredicate(format: "\(CloudKitRecordKeys.HolidayCalendarDay.sourceYear.rawValue) == %d", year))
            if let country = normalizedCountry {
                predicates.append(NSPredicate(format: "\(CloudKitRecordKeys.HolidayCalendarDay.countryCode.rawValue) == %@", country))
            }
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            let query = CKQuery(recordType: CloudKitRecordKeys.HolidayCalendarDay.type.rawValue, predicate: predicate)
            let records = try await queryRecords(query)
            let mapped = records.compactMap { convertToHolidayCalendarDay(from: $0) }
            let filtered = mapped.filter { holiday in
                normalizeHolidaySubdivisionCode(holiday.subdivisionCode) == normalizedSubdivision
            }
            let uniqueByKey = Dictionary(filtered.map { ($0.key, $0) }, uniquingKeysWith: { current, _ in current })
            let sorted = uniqueByKey.values.sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }
                return lhs.key < rhs.key
            }
            markSynced()
            return sorted
        } catch {
            markSyncError(error)
            throw error
        }
    }

    // MARK: - TipEntry API

    func saveTipEntry(_ tip: TipEntry) async throws {
        do {
            let recordID = tipEntryRecordID(for: tip.id)
            let record: CKRecord
            if let existing = try? await privateDatabase.record(for: recordID) {
                record = existing
            } else {
                record = CKRecord(recordType: CloudKitRecordKeys.TipEntry.type.rawValue, recordID: recordID)
            }

            record[CloudKitRecordKeys.TipEntry.id.rawValue] = tip.id
            record[CloudKitRecordKeys.TipEntry.date.rawValue] = tip.date.startOfDayLocal()
            record[CloudKitRecordKeys.TipEntry.amountCents.rawValue] = NSNumber(value: max(0, tip.amountCents))
            record[CloudKitRecordKeys.TipEntry.updatedAt.rawValue] = tip.updatedAt as NSDate

            _ = try await privateDatabase.save(record)
            Self.logger.debug("Upserted TipEntry \(tip.id, privacy: .public)")
            markSynced()
        } catch {
            markSyncError(error)
            throw error
        }
    }

    func fetchTipEntries(in interval: DateInterval) async throws -> [TipEntry] {
        do {
            let records: [CKRecord]

            do {
                let predicate = NSPredicate(
                    format: "\(CloudKitRecordKeys.TipEntry.date.rawValue) >= %@ AND \(CloudKitRecordKeys.TipEntry.date.rawValue) <= %@",
                    interval.start as NSDate,
                    interval.end as NSDate
                )
                let query = CKQuery(recordType: CloudKitRecordKeys.TipEntry.type.rawValue, predicate: predicate)
                query.sortDescriptors = [
                    NSSortDescriptor(key: CloudKitRecordKeys.TipEntry.date.rawValue, ascending: false)
                ]
                records = try await queryRecords(query)
            } catch {
                guard isLikelyQueryIndexingError(error) else { throw error }
                Self.logger.warning("TipEntry date query failed, falling back to full scan. Error: \(String(describing: error), privacy: .public)")
                let fallbackQuery = CKQuery(
                    recordType: CloudKitRecordKeys.TipEntry.type.rawValue,
                    predicate: NSPredicate(value: true)
                )
                records = try await queryRecords(fallbackQuery)
            }

            let mapped = records
                .compactMap { convertToTipEntry(from: $0) }
                .filter { isWithinInterval($0.date, interval: interval) }
                .sorted { $0.date > $1.date }
            markSynced()
            return mapped
        } catch {
            if isLikelyMissingRecordTypeError(error, recordType: CloudKitRecordKeys.TipEntry.type.rawValue) {
                markSynced()
                return []
            }
            markSyncError(error)
            throw error
        }
    }

    func deleteTipEntry(_ tip: TipEntry) async throws {
        do {
            try await deleteRecordIfExists(tipEntryRecordID(for: tip.id))
            Self.logger.debug("Deleted TipEntry \(tip.id, privacy: .public)")
            markSynced()
        } catch {
            markSyncError(error)
            throw error
        }
    }

    // MARK: - NetWageMonthConfig API

    func saveNetWageConfig(_ config: NetWageMonthConfig) async throws {
        do {
            let recordID = netConfigRecordID(for: config.monthStart)
            let record: CKRecord
            if let existing = try? await privateDatabase.record(for: recordID) {
                record = existing
            } else {
                record = CKRecord(recordType: CloudKitRecordKeys.NetWageMonthConfig.type.rawValue, recordID: recordID)
            }
            record[CloudKitRecordKeys.NetWageMonthConfig.monthStart.rawValue] = config.monthStart
            if let tax = config.wageTaxPercent { record[CloudKitRecordKeys.NetWageMonthConfig.wageTaxPercent.rawValue] = NSNumber(value: tax) } else { record[CloudKitRecordKeys.NetWageMonthConfig.wageTaxPercent.rawValue] = nil }
            if let pension = config.pensionPercent { record[CloudKitRecordKeys.NetWageMonthConfig.pensionPercent.rawValue] = NSNumber(value: pension) } else { record[CloudKitRecordKeys.NetWageMonthConfig.pensionPercent.rawValue] = nil }
            if let allowance = config.monthlyAllowanceEuro { record[CloudKitRecordKeys.NetWageMonthConfig.monthlyAllowanceEuro.rawValue] = NSNumber(value: allowance) } else { record[CloudKitRecordKeys.NetWageMonthConfig.monthlyAllowanceEuro.rawValue] = nil }
            record[CloudKitRecordKeys.NetWageMonthConfig.bonusesCSV.rawValue] = config.bonusesCSV
            _ = try await privateDatabase.save(record)
            Self.logger.debug("Upserted NetWageMonthConfig for \(config.monthStart, privacy: .public)")
            markSynced()
        } catch {
            markSyncError(error)
            throw error
        }
    }

    func fetchNetWageConfigs() async throws -> [NetWageMonthConfig] {
        do {
            let query = CKQuery(recordType: CloudKitRecordKeys.NetWageMonthConfig.type.rawValue, predicate: NSPredicate(value: true))
            let result = try await privateDatabase.records(matching: query)
            let records = result.matchResults.compactMap { try? $0.1.get() }
            let mapped = records.compactMap { convertToNetWageMonthConfig(from: $0) }
            markSynced()
            return mapped
        } catch {
            markSyncError(error)
            throw error
        }
    }

    private func convertToTipEntry(from record: CKRecord) -> TipEntry? {
        guard
            let date = record[CloudKitRecordKeys.TipEntry.date.rawValue] as? Date,
            let amount = record[CloudKitRecordKeys.TipEntry.amountCents.rawValue] as? NSNumber
        else {
            return nil
        }

        let fallbackID: String = {
            let recordName = record.recordID.recordName
            if recordName.hasPrefix("tip-") {
                return String(recordName.dropFirst(4))
            }
            return recordName
        }()
        let id = record[CloudKitRecordKeys.TipEntry.id.rawValue] as? String ?? fallbackID
        let updatedAt = (record[CloudKitRecordKeys.TipEntry.updatedAt.rawValue] as? Date) ?? record.modificationDate ?? date

        return TipEntry(
            id: id,
            date: date,
            amountCents: amount.intValue,
            updatedAt: updatedAt
        )
    }

    private func convertToNetWageMonthConfig(from record: CKRecord) -> NetWageMonthConfig? {
        guard let monthStart = record[CloudKitRecordKeys.NetWageMonthConfig.monthStart.rawValue] as? Date else { return nil }
        let wageTax = (record[CloudKitRecordKeys.NetWageMonthConfig.wageTaxPercent.rawValue] as? NSNumber)?.doubleValue
        let pension = (record[CloudKitRecordKeys.NetWageMonthConfig.pensionPercent.rawValue] as? NSNumber)?.doubleValue
        let allowance = (record[CloudKitRecordKeys.NetWageMonthConfig.monthlyAllowanceEuro.rawValue] as? NSNumber)?.doubleValue
        let bonuses = record[CloudKitRecordKeys.NetWageMonthConfig.bonusesCSV.rawValue] as? String ?? ""

        return NetWageMonthConfig(
            monthStart: monthStart,
            wageTaxPercent: wageTax,
            pensionPercent: pension,
            monthlyAllowanceEuro: allowance,
            bonusesCSV: bonuses
        )
    }

    private func convertToHolidayCalendarDay(from record: CKRecord) -> HolidayCalendarDay? {
        guard
            let date = record[CloudKitRecordKeys.HolidayCalendarDay.date.rawValue] as? Date,
            let localName = record[CloudKitRecordKeys.HolidayCalendarDay.localName.rawValue] as? String,
            let countryCode = normalizeHolidayCode(
                record[CloudKitRecordKeys.HolidayCalendarDay.countryCode.rawValue] as? String
            ),
            let sourceYearNum = record[CloudKitRecordKeys.HolidayCalendarDay.sourceYear.rawValue] as? NSNumber
        else {
            return nil
        }

        let subdivisionCode = normalizeHolidaySubdivisionCode(
            record[CloudKitRecordKeys.HolidayCalendarDay.subdivisionCode.rawValue] as? String
        )
        return HolidayCalendarDay(
            date: date,
            localName: localName,
            countryCode: countryCode,
            subdivisionCode: subdivisionCode,
            sourceYear: sourceYearNum.intValue
        )
    }

    private func convertToTimeSegment(from record: CKRecord) -> TimeSegment? {
        guard
            let start = record[CloudKitRecordKeys.TimeSegment.start.rawValue] as? Date,
            let end = record[CloudKitRecordKeys.TimeSegment.end.rawValue] as? Date
        else {
            return nil
        }

        let breakSeconds = (record[CloudKitRecordKeys.TimeSegment.breakSeconds.rawValue] as? NSNumber)?
            .intValue ?? 0

        return TimeSegment(start: start, end: end, breakSeconds: breakSeconds)
    }

    private func dayInterval(forYear year: Int) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endExclusive = calendar.date(byAdding: .year, value: 1, to: start) else {
            return nil
        }
        return DateInterval(start: start, end: endExclusive.addingTimeInterval(-1))
    }

    private func shouldKeepDayEntryWhenRemovingHolidayMarker(_ entry: DayEntry) -> Bool {
        if let start = entry.shiftStart, let end = entry.shiftEnd, end > start {
            return true
        }
        if let manualWorkedSeconds = entry.manualWorkedSeconds, manualWorkedSeconds > 0 {
            return true
        }
        return false
    }
}
