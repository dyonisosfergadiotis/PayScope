import Foundation
import SwiftData
import SwiftUI

enum DayType: String, Codable, CaseIterable, Identifiable {
    case work
    case vacation
    case holiday
    case sick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .work: return "Work"
        case .vacation: return "Vacation"
        case .holiday: return "Holiday"
        case .sick: return "Sick"
        }
    }

    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .vacation: return "sun.max.fill"
        case .holiday: return "sparkles"
        case .sick: return "cross.case.fill"
        }
    }

    var tint: Color {
        switch self {
        case .work: return .blue
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

    init(
        date: Date,
        type: DayType = .work,
        notes: String = "",
        segments: [TimeSegment] = [],
        manualWorkedSeconds: Int? = nil
    ) {
        self.date = date.startOfDayLocal()
        self.type = type
        self.notes = notes
        self.segments = segments
        self.manualWorkedSeconds = manualWorkedSeconds
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
    var countMissingAsZero: Bool
    var strictHistoryRequired: Bool
    var holidayCreditingMode: HolidayCreditingMode
    var scheduledWorkdaysCount: Int
    var themeAccent: ThemeAccent
    var calendarCellDisplayMode: CalendarCellDisplayMode?
    var timelineMinMinute: Int?
    var timelineMaxMinute: Int?
    var netWageTaxPercent: Double?
    var netPensionPercent: Double?
    var netBonusesCSV: String?

    init(
        hasCompletedOnboarding: Bool = false,
        payMode: PayMode = .hourly,
        hourlyRateCents: Int? = nil,
        monthlySalaryCents: Int? = nil,
        weeklyTargetSeconds: Int? = nil,
        weekStart: WeekStart = .monday,
        vacationLookbackCount: Int = 13,
        countMissingAsZero: Bool = true,
        strictHistoryRequired: Bool = true,
        holidayCreditingMode: HolidayCreditingMode = .zero,
        scheduledWorkdaysCount: Int = 5,
        themeAccent: ThemeAccent = .system,
        calendarCellDisplayMode: CalendarCellDisplayMode? = .dot,
        timelineMinMinute: Int? = 6 * 60,
        timelineMaxMinute: Int? = 22 * 60,
        netWageTaxPercent: Double? = nil,
        netPensionPercent: Double? = nil,
        netBonusesCSV: String? = nil
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.payMode = payMode
        self.hourlyRateCents = hourlyRateCents
        self.monthlySalaryCents = monthlySalaryCents
        self.weeklyTargetSeconds = weeklyTargetSeconds
        self.weekStart = weekStart
        self.vacationLookbackCount = vacationLookbackCount
        self.countMissingAsZero = countMissingAsZero
        self.strictHistoryRequired = strictHistoryRequired
        self.holidayCreditingMode = holidayCreditingMode
        self.scheduledWorkdaysCount = min(max(scheduledWorkdaysCount, 1), 7)
        self.themeAccent = themeAccent
        self.calendarCellDisplayMode = calendarCellDisplayMode
        self.timelineMinMinute = timelineMinMinute
        self.timelineMaxMinute = timelineMaxMinute
        self.netWageTaxPercent = netWageTaxPercent
        self.netPensionPercent = netPensionPercent
        self.netBonusesCSV = netBonusesCSV
    }
}

@Model
final class NetWageMonthConfig {
    @Attribute(.unique) var monthStart: Date
    var wageTaxPercent: Double?
    var pensionPercent: Double?
    var bonusesCSV: String

    init(
        monthStart: Date,
        wageTaxPercent: Double? = nil,
        pensionPercent: Double? = nil,
        bonusesCSV: String = ""
    ) {
        self.monthStart = monthStart.startOfMonthLocal()
        self.wageTaxPercent = wageTaxPercent
        self.pensionPercent = pensionPercent
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
