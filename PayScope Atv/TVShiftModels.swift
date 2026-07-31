import Foundation
import SwiftUI

enum TVShiftDayType: String, Codable, CaseIterable, Identifiable {
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

    var symbolName: String {
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
        case .work: return Color(red: 0.18, green: 0.58, blue: 0.95)
        case .manual: return Color(red: 0.57, green: 0.42, blue: 0.90)
        case .vacation: return Color(red: 0.28, green: 0.76, blue: 0.44)
        case .holiday: return Color(red: 0.94, green: 0.56, blue: 0.20)
        case .sick: return Color(red: 0.90, green: 0.30, blue: 0.32)
        }
    }

    nonisolated static func fromPersistedRaw(_ rawValue: String) -> TVShiftDayType? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "work", "arbeit": return .work
        case "manual", "manuell": return .manual
        case "vacation", "urlaub": return .vacation
        case "holiday", "feiertag": return .holiday
        case "sick", "krank": return .sick
        default: return TVShiftDayType(rawValue: rawValue)
        }
    }
}

enum TVShiftCategoryColor: String, Codable, CaseIterable, Identifiable {
    case monochrome
    case mint
    case sage
    case sky
    case aqua
    case lavender
    case lilac
    case blush
    case peach
    case butter
    case coral

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .monochrome: return .primary
        case .mint: return Color(red: 0.22, green: 0.78, blue: 0.56)
        case .sage: return Color(red: 0.46, green: 0.72, blue: 0.30)
        case .sky: return Color(red: 0.24, green: 0.58, blue: 0.92)
        case .aqua: return Color(red: 0.16, green: 0.72, blue: 0.78)
        case .lavender: return Color(red: 0.52, green: 0.42, blue: 0.88)
        case .lilac: return Color(red: 0.70, green: 0.38, blue: 0.86)
        case .blush: return Color(red: 0.90, green: 0.32, blue: 0.54)
        case .peach: return Color(red: 0.94, green: 0.52, blue: 0.30)
        case .butter: return Color(red: 0.88, green: 0.70, blue: 0.16)
        case .coral: return Color(red: 0.90, green: 0.34, blue: 0.30)
        }
    }
}

enum TVThemeAccent: String, Codable {
    case blue
    case green
    case orange
    case purple
    case pink
    case teal
    case red
    case indigo

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.18, green: 0.58, blue: 0.95)
        case .green: return Color(red: 0.28, green: 0.76, blue: 0.44)
        case .orange: return Color(red: 0.94, green: 0.56, blue: 0.20)
        case .purple: return Color(red: 0.57, green: 0.42, blue: 0.90)
        case .pink: return Color(red: 0.93, green: 0.35, blue: 0.70)
        case .teal: return Color(red: 0.16, green: 0.72, blue: 0.78)
        case .red: return Color(red: 0.90, green: 0.30, blue: 0.32)
        case .indigo: return Color(red: 0.35, green: 0.42, blue: 0.92)
        }
    }
}

struct TVShiftColorSettings: Codable, Equatable {
    var themeAccent: TVThemeAccent = .blue
    var workCategoryColor: TVShiftCategoryColor?
    var manualCategoryColor: TVShiftCategoryColor = .lavender
    var vacationCategoryColor: TVShiftCategoryColor = .monochrome
    var holidayCategoryColor: TVShiftCategoryColor = .peach
    var sickCategoryColor: TVShiftCategoryColor = .blush

    nonisolated init(
        themeAccent: TVThemeAccent = .blue,
        workCategoryColor: TVShiftCategoryColor? = nil,
        manualCategoryColor: TVShiftCategoryColor = .lavender,
        vacationCategoryColor: TVShiftCategoryColor = .monochrome,
        holidayCategoryColor: TVShiftCategoryColor = .peach,
        sickCategoryColor: TVShiftCategoryColor = .blush
    ) {
        self.themeAccent = themeAccent
        self.workCategoryColor = workCategoryColor
        self.manualCategoryColor = manualCategoryColor
        self.vacationCategoryColor = vacationCategoryColor
        self.holidayCategoryColor = holidayCategoryColor
        self.sickCategoryColor = sickCategoryColor
    }

    func color(for type: TVShiftDayType) -> Color {
        switch type {
        case .work:
            return workCategoryColor?.color ?? themeAccent.color
        case .manual:
            return manualCategoryColor.color
        case .vacation:
            return vacationCategoryColor.color
        case .holiday:
            return holidayCategoryColor.color
        case .sick:
            return sickCategoryColor.color
        }
    }
}

struct TVShiftEntry: Codable, Identifiable, Equatable {
    let id: String
    let date: Date
    let updatedAt: Date
    let type: TVShiftDayType
    let shiftStart: Date?
    let shiftEnd: Date?
    let breakSeconds: Int
    let manualWorkedSeconds: Int?
    let creditedOverrideSeconds: Int?

    var hasTimedShift: Bool {
        guard let shiftStart, let shiftEnd else { return false }
        return shiftEnd > shiftStart
    }

    var displaySeconds: Int? {
        switch type {
        case .work:
            guard let shiftStart, let shiftEnd, shiftEnd > shiftStart else { return nil }
            return max(0, Int(shiftEnd.timeIntervalSince(shiftStart)) - breakSeconds)
        case .manual:
            return manualWorkedSeconds
        case .vacation, .holiday, .sick:
            return creditedOverrideSeconds ?? manualWorkedSeconds
        }
    }

    nonisolated func overlaps(_ interval: DateInterval) -> Bool {
        guard let shiftStart, let shiftEnd, shiftEnd > shiftStart else {
            return interval.contains(date)
        }
        return shiftStart < interval.end && shiftEnd > interval.start
    }
}

struct TVWeekSchedule: Codable, Equatable {
    let weekStart: Date
    let weekEnd: Date
    let entries: [TVShiftEntry]
    let colorSettings: TVShiftColorSettings
    let generatedAt: Date

    var timedEntries: [TVShiftEntry] {
        entries
            .filter(\.hasTimedShift)
            .sorted { ($0.shiftStart ?? .distantFuture) < ($1.shiftStart ?? .distantFuture) }
    }

    var allDayEntries: [TVShiftEntry] {
        entries
            .filter { !$0.hasTimedShift }
            .sorted { $0.date < $1.date }
    }

    var hasWork: Bool {
        entries.contains { $0.type == .work }
    }

    var totalShiftSeconds: Int {
        entries.reduce(0) { result, entry in
            result + max(0, entry.displaySeconds ?? 0)
        }
    }
}

protocol TVShiftScheduleStore {
    func fetchWeek(startingAt weekStart: Date, calendar: Calendar) async throws -> TVWeekSchedule
}
