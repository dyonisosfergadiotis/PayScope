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

struct TVShiftEntry: Identifiable, Equatable {
    let id: String
    let date: Date
    let updatedAt: Date
    let type: TVShiftDayType
    let shiftStart: Date?
    let shiftEnd: Date?
    let breakSeconds: Int

    var hasTimedShift: Bool {
        guard let shiftStart, let shiftEnd else { return false }
        return shiftEnd > shiftStart
    }

    nonisolated func overlaps(_ interval: DateInterval) -> Bool {
        guard let shiftStart, let shiftEnd, shiftEnd > shiftStart else {
            return interval.contains(date)
        }
        return shiftStart < interval.end && shiftEnd > interval.start
    }
}

struct TVWeekSchedule: Equatable {
    let weekStart: Date
    let weekEnd: Date
    let entries: [TVShiftEntry]
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
        timedEntries.contains { $0.type == .work }
    }

    var totalShiftSeconds: Int {
        timedEntries.reduce(0) { result, entry in
            guard let start = entry.shiftStart, let end = entry.shiftEnd else { return result }
            return result + max(0, Int(end.timeIntervalSince(start)) - entry.breakSeconds)
        }
    }
}
