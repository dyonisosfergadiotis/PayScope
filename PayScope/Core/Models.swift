import Foundation
import SwiftData
import SwiftUI

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

    func tint(for accent: ThemeAccent) -> Color {
        if self == .work { return accent.color }

        let remainingAccents = ThemeAccent.categoryColorOrder.filter { $0 != accent }
        let vacationTint = remainingAccents[0].color
        let holidayTint = remainingAccents[1].color
        let manualTint = remainingAccents[2].color
        let sickTint = remainingAccents[3].color

        switch self {
        case .work: return accent.color
        case .vacation: return vacationTint
        case .holiday: return holidayTint
        case .manual: return manualTint
        case .sick: return sickTint
        }
    }

    var tint: Color {
        tint(for: .blue)
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
    // Legacy modes kept for backwards compatibility with existing records.
    // They are normalized through `Settings.effectiveHolidayCreditingMode`.
    case weeklyTargetDistributed
    case zero

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

    // The first four non-accent colors are used by:
    // vacation -> holiday -> manual -> sick.
    static let categoryColorOrder: [ThemeAccent] = [
        .green,
        .orange,
        .purple,
        .red,
        .teal,
        .indigo,
        .pink,
        .blue
    ]
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

@Model
final class TimeSegment {
    var start: Date
    var end: Date
    var breakSeconds: Int
    var dayEntry: DayEntry?

    init(start: Date, end: Date, breakSeconds: Int = 0) {
        self.start = start
        self.end = end
        self.breakSeconds = breakSeconds
    }
}

@Model
final class DayEntry {
    var date: Date
    var updatedAt: Date
    var type: DayType
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \TimeSegment.dayEntry) var segments: [TimeSegment]
    var manualWorkedSeconds: Int?
    var creditedOverrideSeconds: Int?
    var shiftStart: Date?
    var shiftEnd: Date?
    var breakSeconds: Int?

    init(
        date: Date,
        updatedAt: Date = Date(),
        type: DayType = .work,
        notes: String = "",
        segments: [TimeSegment] = [],
        manualWorkedSeconds: Int? = nil,
        creditedOverrideSeconds: Int? = nil
    ) {
        self.date = date.startOfDayUTC()
        self.updatedAt = updatedAt
        self.type = type
        self.notes = notes
        self.segments = segments
        self.manualWorkedSeconds = manualWorkedSeconds
        self.creditedOverrideSeconds = creditedOverrideSeconds
    }

    var isEmptyTrackedDay: Bool {
        if let manualWorkedSeconds, manualWorkedSeconds > 0 {
            return false
        }
        if let shiftStart, let shiftEnd, shiftEnd > shiftStart {
            return false
        }
        return true
    }
}

@Model
final class Settings {
    var key: String
    var updatedAt: Date
    var hasCompletedOnboarding: Bool
    var payMode: PayMode
    var hourlyRateCents: Int?
    var monthlySalaryCents: Int?
    var weeklyTargetSeconds: Int?
    var weekStart: WeekStart
    var vacationLookbackCount: Int
    var vacationCreditingMode: VacationCreditingMode?
    var vacationFixedSeconds: Int?
    var countMissingAsZero: Bool
    var strictHistoryRequired: Bool
    var holidayCreditingMode: HolidayCreditingMode
    var holidayFixedSeconds: Int?
    var scheduledWorkdaysCount: Int
    var themeAccent: ThemeAccent
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

    var shiftShortcut1: String
    var shiftShortcut2: String
    var shiftShortcut3: String
    var shiftShortcutName1: String?
    var shiftShortcutName2: String?
    var shiftShortcutName3: String?

    init(
        key: String = "singleton",
        updatedAt: Date = Date(),
        hasCompletedOnboarding: Bool = false,
        payMode: PayMode = .hourly,
        hourlyRateCents: Int? = nil,
        monthlySalaryCents: Int? = nil,
        weeklyTargetSeconds: Int? = nil,
        weekStart _: WeekStart = .monday,
        vacationLookbackCount: Int = 13,
        vacationCreditingMode: VacationCreditingMode = .lookback13Weeks,
        vacationFixedSeconds: Int? = nil,
        countMissingAsZero: Bool = true,
        strictHistoryRequired: Bool = true,
        holidayCreditingMode: HolidayCreditingMode = .fixedValue,
        holidayFixedSeconds: Int? = nil,
        scheduledWorkdaysCount: Int = 5,
        themeAccent: ThemeAccent = .blue,
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
        netBonusesCSV: String? = nil,
        shiftShortcut1: String = "",
        shiftShortcut2: String = "",
        shiftShortcut3: String = "",
        shiftShortcutName1: String? = nil,
        shiftShortcutName2: String? = nil,
        shiftShortcutName3: String? = nil
    ) {
        self.key = key
        self.updatedAt = updatedAt
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.payMode = payMode
        self.hourlyRateCents = hourlyRateCents
        self.monthlySalaryCents = monthlySalaryCents
        self.weeklyTargetSeconds = weeklyTargetSeconds
        self.weekStart = .monday
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
        self.shiftShortcut1 = shiftShortcut1
        self.shiftShortcut2 = shiftShortcut2
        self.shiftShortcut3 = shiftShortcut3
        self.shiftShortcutName1 = shiftShortcutName1
        self.shiftShortcutName2 = shiftShortcutName2
        self.shiftShortcutName3 = shiftShortcutName3
    }
}

extension Settings {
    func applyValues(from source: Settings) {
        hasCompletedOnboarding = source.hasCompletedOnboarding
        payMode = source.payMode
        hourlyRateCents = source.hourlyRateCents
        monthlySalaryCents = source.monthlySalaryCents
        weeklyTargetSeconds = source.weeklyTargetSeconds
        weekStart = .monday
        vacationLookbackCount = source.vacationLookbackCount
        vacationCreditingMode = source.vacationCreditingMode
        vacationFixedSeconds = source.vacationFixedSeconds
        countMissingAsZero = source.countMissingAsZero
        strictHistoryRequired = source.strictHistoryRequired
        holidayCreditingMode = source.holidayCreditingMode
        holidayFixedSeconds = source.holidayFixedSeconds
        scheduledWorkdaysCount = source.scheduledWorkdaysCount
        themeAccent = source.themeAccent
        calendarCellDisplayMode = source.calendarCellDisplayMode
        calendarHoursBreakMode = source.calendarHoursBreakMode
        showCalendarWeekNumbers = source.showCalendarWeekNumbers
        showCalendarWeekHours = source.showCalendarWeekHours
        showCalendarWeekPay = source.showCalendarWeekPay
        timelineMinMinute = source.timelineMinMinute
        timelineMaxMinute = source.timelineMaxMinute
        holidayCountryCode = source.holidayCountryCode
        holidaySubdivisionCode = source.holidaySubdivisionCode
        autoSetHolidayCategory = source.autoSetHolidayCategory
        markPaidHolidays = source.markPaidHolidays
        paidHolidayWeekdayMask = source.paidHolidayWeekdayMask
        netWageTaxPercent = source.netWageTaxPercent
        netPensionPercent = source.netPensionPercent
        netMonthlyAllowanceEuro = source.netMonthlyAllowanceEuro
        netBonusesCSV = source.netBonusesCSV
        shiftShortcut1 = source.shiftShortcut1
        shiftShortcut2 = source.shiftShortcut2
        shiftShortcut3 = source.shiftShortcut3
        shiftShortcutName1 = source.shiftShortcutName1
        shiftShortcutName2 = source.shiftShortcutName2
        shiftShortcutName3 = source.shiftShortcutName3
        updatedAt = source.updatedAt
    }

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
            weekStart: .monday,
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

    private static func defaultWeekdayMask(weekStart _: WeekStart, scheduledWorkdaysCount: Int) -> Int {
        let count = min(max(scheduledWorkdaysCount, 1), 7)
        let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

        var mask = 0
        for weekday in orderedWeekdays.prefix(count) {
            mask |= (1 << (weekday - 1))
        }
        return mask
    }

    private var distributedHolidaySeconds: Int {
        guard let weeklyTargetSeconds else { return 0 }
        return weeklyTargetSeconds / max(1, min(7, scheduledWorkdaysCount))
    }
}

@Model
final class HolidayCalendarDay {
    var key: String
    var date: Date
    var localName: String
    var countryCode: String
    var subdivisionCode: String?
    var sourceYear: Int

    init(
        date: Date,
        localName: String,
        countryCode: String,
        subdivisionCode: String?,
        sourceYear: Int
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
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month, .day], from: date.startOfDayUTC())
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        let dayKey = String(format: "%04d-%02d-%02d", y, m, d)
        let subdivisionPart = (subdivisionCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "ALL"
        return "\(countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())-\(subdivisionPart)-\(dayKey)"
    }
}

@Model
final class NetWageMonthConfig {
    var monthStart: Date
    var wageTaxPercent: Double?
    var pensionPercent: Double?
    var monthlyAllowanceEuro: Double?
    var bonusesCSV: String

    init(
        monthStart: Date,
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
    func startOfDayLocal(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: self)
    }

    func isSameLocalDay(as other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(self, inSameDayAs: other)
    }

    func startOfMonthLocal(calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components)?.startOfDayLocal(calendar: calendar) ?? startOfDayLocal(calendar: calendar)
    }

    func addingDays(_ days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: self) ?? self
    }

    func startOfDayUTC() -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month, .day], from: self)
        return utc.date(from: comps) ?? self
    }

    func startOfMonthUTC() -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month], from: self)
        return utc.date(from: comps)?.startOfDayUTC() ?? self
    }
}
extension Notification.Name {
    static let dayEntriesDidChange = Notification.Name("LocalDayEntryStore.dayEntriesDidChange")
}
