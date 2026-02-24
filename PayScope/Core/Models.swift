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
    case zero
    case weeklyTargetDistributed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zero: return "Null"
        case .weeklyTargetDistributed: return "Sollzeit verteilt"
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

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
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
    @Attribute(.unique) var date: Date
    var type: DayType
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \TimeSegment.dayEntry) var segments: [TimeSegment]
    var manualWorkedSeconds: Int?
    var creditedOverrideSeconds: Int?

    init(
        date: Date,
        type: DayType = .work,
        notes: String = "",
        segments: [TimeSegment] = [],
        manualWorkedSeconds: Int? = nil,
        creditedOverrideSeconds: Int? = nil
    ) {
        self.date = date.startOfDayLocal()
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

@Model
final class Settings {
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
        holidayCreditingMode: HolidayCreditingMode = .zero,
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

@Model
final class HolidayCalendarDay {
    @Attribute(.unique) var key: String
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
        let normalizedDate = date.startOfDayLocal()
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
        let dayKey = String(Int(date.startOfDayLocal().timeIntervalSinceReferenceDate))
        let subdivisionPart = subdivisionCode?.uppercased() ?? "ALL"
        return "\(countryCode.uppercased())-\(subdivisionPart)-\(dayKey)"
    }
}

@Model
final class NetWageMonthConfig {
    @Attribute(.unique) var monthStart: Date
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
        self.monthStart = monthStart.startOfMonthLocal()
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
}
