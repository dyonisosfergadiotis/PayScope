import Foundation
import SwiftUI

extension Notification.Name {
    static let menuBarSnapshotDidReload = Notification.Name("menuBarSnapshotDidReload")
    static let menuBarSnapshotReloadFailed = Notification.Name("menuBarSnapshotReloadFailed")
}

enum DayType: String, Codable, CaseIterable, Identifiable {
    case work
    case manual
    case vacation
    case holiday
    case sick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .work: return "Arbeit"
        case .manual: return "Manuell"
        case .vacation: return "Urlaub"
        case .holiday: return "Feiertag"
        case .sick: return "Krank"
        }
    }

    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .manual: return "square.and.pencil"
        case .vacation: return "sun.max.fill"
        case .holiday: return "flag.fill"
        case .sick: return "cross.case.fill"
        }
    }

    var tint: Color {
        switch self {
        case .work: return .blue
        case .manual: return .purple
        case .vacation: return .mint
        case .holiday: return .orange
        case .sick: return .red
        }
    }
}

enum PayMode: String, Codable, CaseIterable, Identifiable {
    case hourly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hourly: return "Stündlich"
        case .monthly: return "Monatlich"
        }
    }
}

enum WeekStart: String, Codable, CaseIterable, Identifiable {
    case monday
    case sunday

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monday: return "Montag"
        case .sunday: return "Sonntag"
        }
    }
}

enum HolidayCreditingMode: String, Codable, CaseIterable, Identifiable {
    case fixedValue
    case lookback13Weeks
    case zero
    case weeklyTargetDistributed

    static var allCases: [HolidayCreditingMode] {
        [.fixedValue, .lookback13Weeks]
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixedValue, .weeklyTargetDistributed, .zero: return "Hat festen Wert"
        case .lookback13Weeks: return "Folgt 13-Wochen-Regel"
        }
    }
}

enum VacationCreditingMode: String, Codable, CaseIterable, Identifiable {
    case lookback13Weeks
    case fixedValue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lookback13Weeks: return "Folgt 13-Wochen-Regel"
        case .fixedValue: return "Hat festen Wert"
        }
    }
}

enum ThemeAccent: String, Codable, CaseIterable, Identifiable {
    case system
    case blue
    case green
    case purple
    case orange
    case pink
    case teal
    case red
    case indigo

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        case .teal: return .teal
        case .red: return .red
        case .indigo: return .indigo
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .blue: return "Blau"
        case .green: return "Grün"
        case .purple: return "Lila"
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .teal: return "Türkis"
        case .red: return "Rot"
        case .indigo: return "Indigo"
        }
    }
}

enum CalendarCellDisplayMode: String, Codable, CaseIterable, Identifiable {
    case dot
    case hours
    case pay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dot: return "Icon"
        case .hours: return "Stunden"
        case .pay: return "Geld"
        }
    }
}

enum CalendarHoursBreakMode: String, Codable, CaseIterable, Identifiable {
    case withoutBreak
    case withBreak

    var id: String { rawValue }

    var label: String {
        switch self {
        case .withoutBreak: return "Ohne Pause"
        case .withBreak: return "Mit Pause"
        }
    }
}

final class TimeSegment {
    var start: Date = Date()
    var end: Date = Date()
    var breakSeconds: Int = 0

    init(start: Date = Date(), end: Date = Date(), breakSeconds: Int = 0) {
        self.start = start
        self.end = end
        self.breakSeconds = breakSeconds
    }
}

final class DayEntry {
    var date: Date = Date()
    var type: DayType = DayType.work
    var notes: String = ""
    var segments: [TimeSegment] = []
    var manualWorkedSeconds: Int?
    var creditedOverrideSeconds: Int?

    init(
        date: Date = Date(),
        type: DayType = DayType.work,
        notes: String = "",
        segments: [TimeSegment] = [],
        manualWorkedSeconds: Int? = nil,
        creditedOverrideSeconds: Int? = nil
    ) {
        self.date = date.startOfDayUTC()
        self.type = type
        self.notes = notes
        self.segments = segments
        self.manualWorkedSeconds = manualWorkedSeconds
        self.creditedOverrideSeconds = creditedOverrideSeconds
    }

    var isEmptyTrackedDay: Bool {
        manualWorkedSeconds == nil && segments.isEmpty
    }
}

final class Settings {
    var hasCompletedOnboarding: Bool = false
    var payMode: PayMode = PayMode.hourly
    var hourlyRateCents: Int?
    var monthlySalaryCents: Int?
    var weeklyTargetSeconds: Int?
    var weekStart: WeekStart = WeekStart.monday
    var vacationLookbackCount: Int = 13
    var vacationCreditingMode: VacationCreditingMode?
    var vacationFixedSeconds: Int?
    var countMissingAsZero: Bool = true
    var strictHistoryRequired: Bool = true
    var holidayCreditingMode: HolidayCreditingMode = HolidayCreditingMode.fixedValue
    var holidayFixedSeconds: Int?
    var scheduledWorkdaysCount: Int = 5
    var themeAccent: ThemeAccent = ThemeAccent.system
    var calendarCellDisplayMode: CalendarCellDisplayMode?
    var calendarHoursBreakMode: CalendarHoursBreakMode?
    var showCalendarWeekNumbers: Bool?
    var showCalendarWeekHours: Bool?
    var showCalendarWeekPay: Bool?
    var timelineMinMinute: Int?
    var timelineMaxMinute: Int?
    var holidayCountryCode: String?
    var holidaySubdivisionCode: String?
    var autoSetHolidayCategory: Bool?
    var markPaidHolidays: Bool?
    var paidHolidayWeekdayMask: Int?
    var netWageTaxPercent: Double?
    var netPensionPercent: Double?
    var netMonthlyAllowanceEuro: Double?
    var netBonusesCSV: String?

    init(
        hasCompletedOnboarding: Bool = false,
        payMode: PayMode = .hourly,
        hourlyRateCents: Int? = nil,
        monthlySalaryCents: Int? = nil,
        weeklyTargetSeconds: Int? = nil,
        weekStart: WeekStart = .monday,
        vacationLookbackCount: Int = 13,
        vacationCreditingMode: VacationCreditingMode = .lookback13Weeks,
        vacationFixedSeconds: Int? = nil,
        countMissingAsZero: Bool = true,
        strictHistoryRequired: Bool = true,
        holidayCreditingMode: HolidayCreditingMode = .fixedValue,
        holidayFixedSeconds: Int? = nil,
        scheduledWorkdaysCount: Int = 5,
        themeAccent: ThemeAccent = .system,
        calendarCellDisplayMode: CalendarCellDisplayMode? = .dot,
        calendarHoursBreakMode: CalendarHoursBreakMode = .withoutBreak,
        showCalendarWeekNumbers: Bool = false,
        showCalendarWeekHours: Bool = false,
        showCalendarWeekPay: Bool = false,
        timelineMinMinute: Int? = 6 * 60,
        timelineMaxMinute: Int? = 22 * 60,
        holidayCountryCode: String? = "DE",
        holidaySubdivisionCode: String? = nil,
        autoSetHolidayCategory: Bool = false,
        markPaidHolidays: Bool = false,
        paidHolidayWeekdayMask: Int? = nil,
        netWageTaxPercent: Double? = nil,
        netPensionPercent: Double? = nil,
        netMonthlyAllowanceEuro: Double? = nil,
        netBonusesCSV: String? = nil
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.payMode = payMode
        self.hourlyRateCents = hourlyRateCents
        self.monthlySalaryCents = monthlySalaryCents
        self.weeklyTargetSeconds = weeklyTargetSeconds
        self.weekStart = weekStart
        self.vacationLookbackCount = vacationLookbackCount
        self.vacationCreditingMode = vacationCreditingMode
        self.vacationFixedSeconds = vacationFixedSeconds.map { max(0, $0) }
        self.countMissingAsZero = countMissingAsZero
        self.strictHistoryRequired = strictHistoryRequired
        self.holidayCreditingMode = holidayCreditingMode
        self.holidayFixedSeconds = holidayFixedSeconds.map { max(0, $0) }
        self.scheduledWorkdaysCount = min(max(scheduledWorkdaysCount, 1), 7)
        self.themeAccent = themeAccent
        self.calendarCellDisplayMode = calendarCellDisplayMode
        self.calendarHoursBreakMode = calendarHoursBreakMode
        self.showCalendarWeekNumbers = showCalendarWeekNumbers
        self.showCalendarWeekHours = showCalendarWeekHours
        self.showCalendarWeekPay = showCalendarWeekPay
        self.timelineMinMinute = timelineMinMinute
        self.timelineMaxMinute = timelineMaxMinute
        self.holidayCountryCode = holidayCountryCode
        self.holidaySubdivisionCode = holidaySubdivisionCode
        self.autoSetHolidayCategory = autoSetHolidayCategory
        self.markPaidHolidays = markPaidHolidays
        self.paidHolidayWeekdayMask = Settings.sanitizedWeekdayMask(paidHolidayWeekdayMask)
        self.netWageTaxPercent = netWageTaxPercent
        self.netPensionPercent = netPensionPercent
        self.netMonthlyAllowanceEuro = netMonthlyAllowanceEuro
        self.netBonusesCSV = netBonusesCSV
    }
}

extension Settings {
    var effectiveVacationCreditingMode: VacationCreditingMode {
        vacationCreditingMode ?? .lookback13Weeks
    }

    var effectiveVacationFixedSeconds: Int {
        max(0, vacationFixedSeconds ?? 0)
    }

    var effectiveHolidayCreditingMode: HolidayCreditingMode {
        switch holidayCreditingMode {
        case .lookback13Weeks:
            return .lookback13Weeks
        case .fixedValue, .weeklyTargetDistributed, .zero:
            return .fixedValue
        }
    }

    var effectiveHolidayFixedSeconds: Int {
        if let holidayFixedSeconds {
            return max(0, holidayFixedSeconds)
        }
        if holidayCreditingMode == .zero {
            return 0
        }
        return distributedHolidaySeconds
    }

    private var distributedHolidaySeconds: Int {
        guard let weeklyTargetSeconds, weeklyTargetSeconds > 0 else { return 0 }
        let safeWorkdays = max(1, scheduledWorkdaysCount)
        return Int((Double(weeklyTargetSeconds) / Double(safeWorkdays)).rounded())
    }

    var effectiveCalendarHoursBreakMode: CalendarHoursBreakMode {
        calendarHoursBreakMode ?? .withoutBreak
    }

    var effectiveShowCalendarWeekNumbers: Bool {
        showCalendarWeekNumbers ?? false
    }

    var effectiveShowCalendarWeekHours: Bool {
        showCalendarWeekHours ?? false
    }

    var effectiveShowCalendarWeekPay: Bool {
        showCalendarWeekPay ?? false
    }

    var effectiveMarkPaidHolidays: Bool {
        markPaidHolidays ?? false
    }

    var effectiveAutoSetHolidayCategory: Bool {
        autoSetHolidayCategory ?? false
    }

    var effectivePaidHolidayWeekdayMask: Int {
        let fallbackMask = Self.defaultWeekdayMask(
            weekStart: weekStart,
            scheduledWorkdaysCount: scheduledWorkdaysCount
        )
        return Self.sanitizedWeekdayMask(paidHolidayWeekdayMask) ?? fallbackMask
    }

    func isPaidHolidayWeekday(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date.startOfDayLocal(calendar: calendar))
        return isPaidHolidayWeekday(weekday: weekday)
    }

    func isPaidHolidayWeekday(weekday: Int) -> Bool {
        guard (1...7).contains(weekday) else { return false }
        let bit = 1 << (weekday - 1)
        return (effectivePaidHolidayWeekdayMask & bit) != 0
    }

    func updatingPaidHolidayWeekdayMask(weekday: Int, isSelected: Bool) -> Int {
        guard (1...7).contains(weekday) else {
            return effectivePaidHolidayWeekdayMask
        }
        let bit = 1 << (weekday - 1)
        var mask = effectivePaidHolidayWeekdayMask
        if isSelected {
            mask |= bit
        } else {
            mask &= ~bit
        }
        return Self.sanitizedWeekdayMask(mask) ?? 0
    }

    private static func sanitizedWeekdayMask(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return value & 0b1111111
    }

    private static func defaultWeekdayMask(weekStart: WeekStart, scheduledWorkdaysCount: Int) -> Int {
        let count = min(max(scheduledWorkdaysCount, 1), 7)
        let orderedWeekdays = weekStart == .sunday
            ? [1, 2, 3, 4, 5, 6, 7]
            : [2, 3, 4, 5, 6, 7, 1]

        var mask = 0
        for weekday in orderedWeekdays.prefix(count) {
            mask |= (1 << (weekday - 1))
        }
        return mask
    }
}

final class HolidayCalendarDay {
    var key: String = ""
    var date: Date = Date()
    var localName: String = ""
    var countryCode: String = ""
    var subdivisionCode: String?
    var sourceYear: Int = 0

    init(
        date: Date = Date(),
        localName: String = "",
        countryCode: String = "",
        subdivisionCode: String?,
        sourceYear: Int = 0
    ) {
        let normalizedDate = date.startOfDayUTC()
        let normalizedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedSubdivision = subdivisionCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        self.date = normalizedDate
        self.localName = localName
        self.countryCode = normalizedCountry
        self.subdivisionCode = normalizedSubdivision
        self.sourceYear = sourceYear
        self.key = HolidayCalendarDay.makeKey(
            date: normalizedDate,
            countryCode: normalizedCountry,
            subdivisionCode: normalizedSubdivision
        )
    }

    static func makeKey(date: Date, countryCode: String, subdivisionCode: String?) -> String {
        let dayKey = date.startOfDayUTC().utcDayKey
        let subdivisionPart = subdivisionCode?.uppercased() ?? "ALL"
        return "\(countryCode.uppercased())-\(subdivisionPart)-\(dayKey)"
    }
}

final class NetWageMonthConfig {
    var monthStart: Date = Date()
    var wageTaxPercent: Double?
    var pensionPercent: Double?
    var monthlyAllowanceEuro: Double?
    var bonusesCSV: String = ""

    init(
        monthStart: Date = Date(),
        wageTaxPercent: Double? = nil,
        pensionPercent: Double? = nil,
        monthlyAllowanceEuro: Double? = nil,
        bonusesCSV: String = ""
    ) {
        self.monthStart = monthStart.startOfMonthUTC()
        self.wageTaxPercent = wageTaxPercent
        self.pensionPercent = pensionPercent
        self.monthlyAllowanceEuro = monthlyAllowanceEuro
        self.bonusesCSV = bonusesCSV
    }
}

extension Date {
    var utcDayKey: String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    func startOfDayUTC() -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month, .day], from: self)
        return utc.date(from: comps) ?? self
    }

    func startOfDayLocal(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: self)
    }

    func localDayKey(calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    func isSameLocalDay(as other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(self, inSameDayAs: other)
    }

    func startOfMonthLocal(calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components)?.startOfDayLocal(calendar: calendar) ?? startOfDayLocal(calendar: calendar)
    }

    func startOfMonthUTC() -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month], from: self)
        return utc.date(from: comps)?.startOfDayUTC() ?? startOfDayUTC()
    }

    func addingDays(_ days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: self) ?? self
    }
}
