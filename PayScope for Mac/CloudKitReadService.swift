import CloudKit
import Foundation

enum CloudKitReadRecordKeys {
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
        case weekStart
        case vacationLookbackCount
        case vacationCreditingMode
        case vacationFixedSeconds
        case countMissingAsZero
        case strictHistoryRequired
        case holidayCreditingMode
        case holidayFixedSeconds
        case scheduledWorkdaysCount
        case themeAccent
        case calendarCellDisplayMode
        case calendarHoursBreakMode
        case showCalendarWeekNumbers
        case showCalendarWeekHours
        case showCalendarWeekPay
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
}

struct CloudSnapshot: Codable, Equatable {
    struct DayEntryPayload: Codable, Equatable {
        let date: Date
        let updatedAt: Date?
        let type: DayType
        let notes: String
        let manualWorkedSeconds: Int?
        let creditedOverrideSeconds: Int?
        let shiftStart: Date?
        let shiftEnd: Date?
        let breakSeconds: Int?
        let alwaysApplyFifteenMinuteBuffer: Bool?
    }

    struct SettingsPayload: Codable, Equatable {
        let hasCompletedOnboarding: Bool
        let payMode: PayMode
        let hourlyRateCents: Int?
        let monthlySalaryCents: Int?
        let weeklyTargetSeconds: Int?
        let weekStart: WeekStart
        let vacationLookbackCount: Int
        let vacationCreditingMode: VacationCreditingMode?
        let vacationFixedSeconds: Int?
        let countMissingAsZero: Bool
        let strictHistoryRequired: Bool
        let holidayCreditingMode: HolidayCreditingMode
        let holidayFixedSeconds: Int?
        let scheduledWorkdaysCount: Int
        let themeAccent: ThemeAccent
        let calendarCellDisplayMode: CalendarCellDisplayMode?
        let calendarHoursBreakMode: CalendarHoursBreakMode?
        let showCalendarWeekNumbers: Bool?
        let showCalendarWeekHours: Bool?
        let showCalendarWeekPay: Bool?
        let alwaysApplyFifteenMinuteBuffer: Bool?
        let holidayCountryCode: String?
        let holidaySubdivisionCode: String?
        let autoSetHolidayCategory: Bool?
        let markPaidHolidays: Bool?
        let paidHolidayWeekdayMask: Int?
        let netWageTaxPercent: Double?
        let netPensionPercent: Double?
        let netMonthlyAllowanceEuro: Double?
        let netBonusesCSV: String?
    }

    struct NetWageConfigPayload: Codable, Equatable {
        let monthStart: Date
        let wageTaxPercent: Double?
        let pensionPercent: Double?
        let monthlyAllowanceEuro: Double?
        let bonusesCSV: String
    }

    struct HolidayPayload: Codable, Equatable {
        let date: Date
        let localName: String
        let countryCode: String
        let subdivisionCode: String?
        let sourceYear: Int
    }

    let settings: SettingsPayload?
    let dayEntries: [DayEntryPayload]
    let netWageConfigs: [NetWageConfigPayload]
    let holidays: [HolidayPayload]
}

enum CloudKitReadServiceError: LocalizedError {
    case accountUnavailable
    case accountRestricted
    case noAccount
    case temporarilyUnavailable
    case couldNotDetermineAccountStatus

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "iCloud-Konto nicht verfügbar auf diesem Mac"
        case .accountRestricted:
            return "iCloud-Konto ist eingeschränkt"
        case .noAccount:
            return "Kein iCloud-Konto angemeldet"
        case .temporarilyUnavailable:
            return "iCloud ist derzeit nicht verfügbar"
        case .couldNotDetermineAccountStatus:
            return "iCloud-Kontostatus konnte nicht bestimmt werden"
        }
    }
}

actor CloudKitReadService {
    static let shared = CloudKitReadService()
    private static let legacyTimeSegmentRecordType = "timesegment"

    private struct SegmentPayload {
        let start: Date
        let end: Date
        let breakSeconds: Int
    }

    private static let settingsSingletonRecordID = CKRecord.ID(recordName: "settings-singleton")
    private let container = CKContainer.default()
    private let privateDatabase = CKContainer.default().privateCloudDatabase

    func fetchSnapshot() async throws -> CloudSnapshot {
        let accountStatus = try await container.accountStatus()
        switch accountStatus {
        case .available:
            break
        case .noAccount:
            throw CloudKitReadServiceError.noAccount
        case .restricted:
            throw CloudKitReadServiceError.accountRestricted
        case .temporarilyUnavailable:
            throw CloudKitReadServiceError.temporarilyUnavailable
        case .couldNotDetermine:
            throw CloudKitReadServiceError.couldNotDetermineAccountStatus
        @unknown default:
            throw CloudKitReadServiceError.accountUnavailable
        }

        async let settings = fetchSettingsSingleton()
        async let dayEntries = fetchDayEntries()
        async let netConfigs = fetchNetWageConfigs()
        async let holidays = fetchHolidayDays()

        return CloudSnapshot(
            settings: try? await settings,
            dayEntries: try await dayEntries,
            netWageConfigs: (try? await netConfigs) ?? [],
            holidays: (try? await holidays) ?? []
        )
    }

    private func queryRecords(_ query: CKQuery) async throws -> [CKRecord] {
        var all: [CKRecord] = []
        var page = try await privateDatabase.records(matching: query)
        all.append(contentsOf: resolvePageRecords(page.matchResults))

        var cursor = page.queryCursor
        while let current = cursor {
            page = try await privateDatabase.records(continuingMatchFrom: current)
            all.append(contentsOf: resolvePageRecords(page.matchResults))
            cursor = page.queryCursor
        }
        return all
    }

    private func resolvePageRecords<S: Sequence>(_ matches: S) -> [CKRecord]
    where S.Element == (CKRecord.ID, Result<CKRecord, Error>) {
        var records: [CKRecord] = []
        for (_, result) in matches {
            switch result {
            case .success(let record):
                records.append(record)
            case .failure:
                // Best effort: ignore failed single-record matches and keep successful records.
                continue
            }
        }
        return records
    }

    private func isMissingRecordTypeError(_ error: Error, recordType: String) -> Bool {
        let details: String
        if let ckError = error as? CKError {
            details = "\(ckError.localizedDescription) \(String(describing: ckError.userInfo))".lowercased()
        } else {
            details = "\(error)".lowercased()
        }

        guard details.contains("did not find record type") else {
            return false
        }

        return details.contains(recordType.lowercased())
            || details.contains("record type")
    }

    private func fetchDayEntries() async throws -> [CloudSnapshot.DayEntryPayload] {
        async let dayRecordsTask: [CKRecord] = queryRecords(
            CKQuery(recordType: CloudKitReadRecordKeys.DayEntry.type.rawValue, predicate: NSPredicate(value: true))
        )
        async let segmentMapTask: [String: [SegmentPayload]] = fetchTimeSegmentsByDayKey()

        let records = try await dayRecordsTask
        let segmentsByDayKey = try await segmentMapTask

        var latestByUTCDayKey: [String: CloudSnapshot.DayEntryPayload] = [:]

        for record in records {
            guard
                let date = record[CloudKitReadRecordKeys.DayEntry.date.rawValue] as? Date,
                let typeRaw = record[CloudKitReadRecordKeys.DayEntry.dayType.rawValue] as? String,
                let type = DayType.fromPersistedRaw(typeRaw)
            else {
                continue
            }

            let updatedAt = (record[CloudKitReadRecordKeys.DayEntry.updatedAt.rawValue] as? Date)
                ?? record.modificationDate
                ?? date
            let notes = record[CloudKitReadRecordKeys.DayEntry.notes.rawValue] as? String ?? ""
            var manualWorkedSeconds = (record[CloudKitReadRecordKeys.DayEntry.manualWorkedSeconds.rawValue] as? NSNumber)?.intValue
            var creditedOverrideSeconds = (record[CloudKitReadRecordKeys.DayEntry.creditedOverrideSeconds.rawValue] as? NSNumber)?.intValue
            let alwaysApplyFifteenMinuteBuffer = (record[
                CloudKitReadRecordKeys.DayEntry.alwaysApplyFifteenMinuteBuffer.rawValue
            ] as? NSNumber)?.boolValue

            var shiftStart = record[CloudKitReadRecordKeys.DayEntry.shiftStart.rawValue] as? Date
            var shiftEnd = record[CloudKitReadRecordKeys.DayEntry.shiftEnd.rawValue] as? Date
            var breakSeconds = (record[CloudKitReadRecordKeys.DayEntry.breakSeconds.rawValue] as? NSNumber)?.intValue

            switch type {
            case .work:
                // Only work entries should recover legacy segment-based shift fields.
                if shiftStart == nil || shiftEnd == nil {
                    let key = dayKey(for: date)
                    if let segments = segmentsByDayKey[key], !segments.isEmpty {
                        let starts = segments.map(\.start)
                        let ends = segments.map(\.end)
                        shiftStart = starts.min()
                        shiftEnd = ends.max()
                        breakSeconds = segments.reduce(0) { $0 + max(0, $1.breakSeconds) }
                    }
                }
                manualWorkedSeconds = nil
                creditedOverrideSeconds = nil

            case .manual:
                // Manual entries should carry duration only, without shift fields.
                if manualWorkedSeconds == nil,
                   let start = shiftStart,
                   let end = shiftEnd,
                   end > start {
                    let rawSeconds = Int(end.timeIntervalSince(start))
                    let pause = max(0, breakSeconds ?? 0)
                    manualWorkedSeconds = max(0, rawSeconds - pause)
                }
                shiftStart = nil
                shiftEnd = nil
                breakSeconds = nil
                creditedOverrideSeconds = nil

            case .vacation, .holiday, .sick:
                // Credited entries should not be interpreted as shift records.
                shiftStart = nil
                shiftEnd = nil
                breakSeconds = nil
            }

            manualWorkedSeconds = manualWorkedSeconds.map { max(0, $0) }
            creditedOverrideSeconds = creditedOverrideSeconds.map { max(0, $0) }

            let payload = CloudSnapshot.DayEntryPayload(
                date: date,
                updatedAt: updatedAt,
                type: type,
                notes: notes,
                manualWorkedSeconds: manualWorkedSeconds,
                creditedOverrideSeconds: creditedOverrideSeconds,
                shiftStart: shiftStart,
                shiftEnd: shiftEnd,
                breakSeconds: breakSeconds,
                alwaysApplyFifteenMinuteBuffer: alwaysApplyFifteenMinuteBuffer
            )
            let key = dayKey(for: date)
            let existingUpdatedAt = latestByUTCDayKey[key]?.updatedAt ?? .distantPast
            if existingUpdatedAt >= updatedAt {
                continue
            }
            latestByUTCDayKey[key] = payload
        }

        return deduplicateByLocalDayKeepingNewest(Array(latestByUTCDayKey.values))
    }

    private func fetchTimeSegmentsByDayKey() async throws -> [String: [SegmentPayload]] {
        let recordTypes = [
            CloudKitReadRecordKeys.TimeSegment.type.rawValue,
            Self.legacyTimeSegmentRecordType
        ]

        var records: [CKRecord] = []
        var seenRecordTypes: Set<String> = []

        for recordType in recordTypes where seenRecordTypes.insert(recordType).inserted {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            do {
                records.append(contentsOf: try await queryRecords(query))
            } catch {
                if isMissingRecordTypeError(error, recordType: recordType) {
                    continue
                }
                throw error
            }
        }

        var grouped: [String: [SegmentPayload]] = [:]

        for record in records {
            guard
                let start = record[CloudKitReadRecordKeys.TimeSegment.start.rawValue] as? Date,
                let end = record[CloudKitReadRecordKeys.TimeSegment.end.rawValue] as? Date,
                end > start
            else {
                continue
            }

            guard
                let ref = record[CloudKitReadRecordKeys.TimeSegment.dayEntryRef.rawValue] as? CKRecord.Reference,
                let key = dayKey(fromDayRecordName: ref.recordID.recordName)
            else {
                continue
            }

            let breakSeconds = (record[CloudKitReadRecordKeys.TimeSegment.breakSeconds.rawValue] as? NSNumber)?.intValue ?? 0
            grouped[key, default: []].append(
                SegmentPayload(start: start, end: end, breakSeconds: max(0, breakSeconds))
            )
        }

        return grouped
    }

    private func dayKey(for date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func deduplicateByLocalDayKeepingNewest(
        _ values: [CloudSnapshot.DayEntryPayload]
    ) -> [CloudSnapshot.DayEntryPayload] {
        var latestByLocalDayKey: [String: CloudSnapshot.DayEntryPayload] = [:]
        let localCalendar = Calendar.current

        for payload in values {
            let key = localDayKey(for: payload.date, calendar: localCalendar)
            guard let existing = latestByLocalDayKey[key] else {
                latestByLocalDayKey[key] = payload
                continue
            }

            let existingUpdatedAt = existing.updatedAt ?? .distantPast
            let candidateUpdatedAt = payload.updatedAt ?? .distantPast
            if candidateUpdatedAt > existingUpdatedAt {
                latestByLocalDayKey[key] = payload
            }
        }

        return Array(latestByLocalDayKey.values)
    }

    private func localDayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func dayKey(fromDayRecordName recordName: String) -> String? {
        guard recordName.hasPrefix("day-") else { return nil }
        let remainder = recordName.dropFirst(4)
        let parts = remainder.split(separator: "-")
        guard parts.count == 3 else { return nil }
        return String(format: "%04d-%02d-%02d", Int(parts[0]) ?? 0, Int(parts[1]) ?? 0, Int(parts[2]) ?? 0)
    }

    private func fetchSettingsSingleton() async throws -> CloudSnapshot.SettingsPayload? {
        if let singleton = try? await privateDatabase.record(for: Self.settingsSingletonRecordID),
           let converted = convertSettings(from: singleton) {
            return converted
        }

        let query = CKQuery(
            recordType: CloudKitReadRecordKeys.Settings.type.rawValue,
            predicate: NSPredicate(value: true)
        )
        let records = try await queryRecords(query)
        let candidates = records.compactMap { record -> (Date, CloudSnapshot.SettingsPayload)? in
            guard let converted = convertSettings(from: record) else { return nil }
            let updatedAt = (record[CloudKitReadRecordKeys.Settings.updatedAt.rawValue] as? Date)
                ?? record.modificationDate
                ?? Date.distantPast
            return (updatedAt, converted)
        }
        return candidates.max(by: { $0.0 < $1.0 })?.1
    }

    private func fetchHolidayDays() async throws -> [CloudSnapshot.HolidayPayload] {
        let query = CKQuery(
            recordType: CloudKitReadRecordKeys.HolidayCalendarDay.type.rawValue,
            predicate: NSPredicate(value: true)
        )
        let records = try await queryRecords(query)
        return records.compactMap { record in
            guard
                let date = record[CloudKitReadRecordKeys.HolidayCalendarDay.date.rawValue] as? Date,
                let localName = record[CloudKitReadRecordKeys.HolidayCalendarDay.localName.rawValue] as? String,
                let countryCode = record[CloudKitReadRecordKeys.HolidayCalendarDay.countryCode.rawValue] as? String,
                let sourceYear = (record[CloudKitReadRecordKeys.HolidayCalendarDay.sourceYear.rawValue] as? NSNumber)?.intValue
            else {
                return nil
            }
            let key = record[CloudKitReadRecordKeys.HolidayCalendarDay.key.rawValue] as? String
            let subdivisionCode = record[CloudKitReadRecordKeys.HolidayCalendarDay.subdivisionCode.rawValue] as? String
            let normalizedDate = key
                .flatMap(holidayDateFromKey)
                ?? utcStartOfDay(for: date)
            return CloudSnapshot.HolidayPayload(
                date: normalizedDate,
                localName: localName,
                countryCode: countryCode,
                subdivisionCode: subdivisionCode,
                sourceYear: sourceYear
            )
        }
    }

    private func holidayDateFromKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count >= 3 else { return nil }

        let yearPart = parts[parts.count - 3]
        let monthPart = parts[parts.count - 2]
        let dayPart = parts[parts.count - 1]

        guard
            let year = Int(yearPart),
            let month = Int(monthPart),
            let day = Int(dayPart)
        else {
            return nil
        }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func utcStartOfDay(for date: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = utc.dateComponents([.year, .month, .day], from: date)
        return utc.date(from: components) ?? date
    }

    private func fetchNetWageConfigs() async throws -> [CloudSnapshot.NetWageConfigPayload] {
        let query = CKQuery(
            recordType: CloudKitReadRecordKeys.NetWageMonthConfig.type.rawValue,
            predicate: NSPredicate(value: true)
        )
        let records = try await queryRecords(query)
        return records.compactMap { record in
            guard let monthStart = record[CloudKitReadRecordKeys.NetWageMonthConfig.monthStart.rawValue] as? Date else {
                return nil
            }
            let wageTax = (record[CloudKitReadRecordKeys.NetWageMonthConfig.wageTaxPercent.rawValue] as? NSNumber)?.doubleValue
            let pension = (record[CloudKitReadRecordKeys.NetWageMonthConfig.pensionPercent.rawValue] as? NSNumber)?.doubleValue
            let allowance = (record[CloudKitReadRecordKeys.NetWageMonthConfig.monthlyAllowanceEuro.rawValue] as? NSNumber)?.doubleValue
            let bonusesCSV = record[CloudKitReadRecordKeys.NetWageMonthConfig.bonusesCSV.rawValue] as? String ?? ""
            return CloudSnapshot.NetWageConfigPayload(
                monthStart: monthStart,
                wageTaxPercent: wageTax,
                pensionPercent: pension,
                monthlyAllowanceEuro: allowance,
                bonusesCSV: bonusesCSV
            )
        }
    }

    private func convertSettings(from record: CKRecord) -> CloudSnapshot.SettingsPayload? {
        let hasCompletedOnboarding = (record[CloudKitReadRecordKeys.Settings.hasCompletedOnboarding.rawValue] as? NSNumber)?.boolValue ?? false
        let payMode = PayMode(rawValue: record[CloudKitReadRecordKeys.Settings.payMode.rawValue] as? String ?? "") ?? .hourly
        let hourlyRateCents = (record[CloudKitReadRecordKeys.Settings.hourlyRateCents.rawValue] as? NSNumber)?.intValue
        let monthlySalaryCents = (record[CloudKitReadRecordKeys.Settings.monthlySalaryCents.rawValue] as? NSNumber)?.intValue
        let weeklyTargetSeconds = (record[CloudKitReadRecordKeys.Settings.weeklyTargetSeconds.rawValue] as? NSNumber)?.intValue
        let weekStart = WeekStart(rawValue: record[CloudKitReadRecordKeys.Settings.weekStart.rawValue] as? String ?? "") ?? .monday
        let vacationLookbackCount = max(1, (record[CloudKitReadRecordKeys.Settings.vacationLookbackCount.rawValue] as? NSNumber)?.intValue ?? 13)
        let vacationCreditingMode = VacationCreditingMode(rawValue: record[CloudKitReadRecordKeys.Settings.vacationCreditingMode.rawValue] as? String ?? "")
        let vacationFixedSeconds = (record[CloudKitReadRecordKeys.Settings.vacationFixedSeconds.rawValue] as? NSNumber)?.intValue
        let countMissingAsZero = (record[CloudKitReadRecordKeys.Settings.countMissingAsZero.rawValue] as? NSNumber)?.boolValue ?? true
        let strictHistoryRequired = (record[CloudKitReadRecordKeys.Settings.strictHistoryRequired.rawValue] as? NSNumber)?.boolValue ?? true
        let holidayCreditingMode = HolidayCreditingMode(rawValue: record[CloudKitReadRecordKeys.Settings.holidayCreditingMode.rawValue] as? String ?? "")
            ?? .fixedValue
        let holidayFixedSeconds = (record[CloudKitReadRecordKeys.Settings.holidayFixedSeconds.rawValue] as? NSNumber)?.intValue
        let scheduledWorkdaysCount = min(max((record[CloudKitReadRecordKeys.Settings.scheduledWorkdaysCount.rawValue] as? NSNumber)?.intValue ?? 5, 1), 7)
        let themeAccent = ThemeAccent(rawValue: record[CloudKitReadRecordKeys.Settings.themeAccent.rawValue] as? String ?? "") ?? .blue
        let calendarCellDisplayMode = CalendarCellDisplayMode(rawValue: record[CloudKitReadRecordKeys.Settings.calendarCellDisplayMode.rawValue] as? String ?? "")
        let calendarHoursBreakMode = CalendarHoursBreakMode(rawValue: record[CloudKitReadRecordKeys.Settings.calendarHoursBreakMode.rawValue] as? String ?? "")
        let showCalendarWeekNumbers = (record[CloudKitReadRecordKeys.Settings.showCalendarWeekNumbers.rawValue] as? NSNumber)?.boolValue
        let showCalendarWeekHours = (record[CloudKitReadRecordKeys.Settings.showCalendarWeekHours.rawValue] as? NSNumber)?.boolValue
        let showCalendarWeekPay = (record[CloudKitReadRecordKeys.Settings.showCalendarWeekPay.rawValue] as? NSNumber)?.boolValue
        let alwaysApplyFifteenMinuteBuffer = (record[CloudKitReadRecordKeys.Settings.alwaysApplyFifteenMinuteBuffer.rawValue] as? NSNumber)?.boolValue
        let holidayCountryCode = record[CloudKitReadRecordKeys.Settings.holidayCountryCode.rawValue] as? String
        let holidaySubdivisionCode = record[CloudKitReadRecordKeys.Settings.holidaySubdivisionCode.rawValue] as? String
        let autoSetHolidayCategory = (record[CloudKitReadRecordKeys.Settings.autoSetHolidayCategory.rawValue] as? NSNumber)?.boolValue
        let markPaidHolidays = (record[CloudKitReadRecordKeys.Settings.markPaidHolidays.rawValue] as? NSNumber)?.boolValue
        let paidHolidayWeekdayMask = (record[CloudKitReadRecordKeys.Settings.paidHolidayWeekdayMask.rawValue] as? NSNumber)?.intValue
        let netWageTaxPercent = (record[CloudKitReadRecordKeys.Settings.netWageTaxPercent.rawValue] as? NSNumber)?.doubleValue
        let netPensionPercent = (record[CloudKitReadRecordKeys.Settings.netPensionPercent.rawValue] as? NSNumber)?.doubleValue
        let netMonthlyAllowanceEuro = (record[CloudKitReadRecordKeys.Settings.netMonthlyAllowanceEuro.rawValue] as? NSNumber)?.doubleValue
        let netBonusesCSV = record[CloudKitReadRecordKeys.Settings.netBonusesCSV.rawValue] as? String

        return CloudSnapshot.SettingsPayload(
            hasCompletedOnboarding: hasCompletedOnboarding,
            payMode: payMode,
            hourlyRateCents: hourlyRateCents,
            monthlySalaryCents: monthlySalaryCents,
            weeklyTargetSeconds: weeklyTargetSeconds,
            weekStart: weekStart,
            vacationLookbackCount: vacationLookbackCount,
            vacationCreditingMode: vacationCreditingMode,
            vacationFixedSeconds: vacationFixedSeconds,
            countMissingAsZero: countMissingAsZero,
            strictHistoryRequired: strictHistoryRequired,
            holidayCreditingMode: holidayCreditingMode,
            holidayFixedSeconds: holidayFixedSeconds,
            scheduledWorkdaysCount: scheduledWorkdaysCount,
            themeAccent: themeAccent,
            calendarCellDisplayMode: calendarCellDisplayMode,
            calendarHoursBreakMode: calendarHoursBreakMode,
            showCalendarWeekNumbers: showCalendarWeekNumbers,
            showCalendarWeekHours: showCalendarWeekHours,
            showCalendarWeekPay: showCalendarWeekPay,
            alwaysApplyFifteenMinuteBuffer: alwaysApplyFifteenMinuteBuffer,
            holidayCountryCode: holidayCountryCode,
            holidaySubdivisionCode: holidaySubdivisionCode,
            autoSetHolidayCategory: autoSetHolidayCategory,
            markPaidHolidays: markPaidHolidays,
            paidHolidayWeekdayMask: paidHolidayWeekdayMask,
            netWageTaxPercent: netWageTaxPercent,
            netPensionPercent: netPensionPercent,
            netMonthlyAllowanceEuro: netMonthlyAllowanceEuro,
            netBonusesCSV: netBonusesCSV
        )
    }
}
