import Foundation
import SwiftUI

enum WatchSnapshotBridgeKeys {
    static let payloadData = "payscope.watch.snapshot.data.v1"
    static let generatedAt = "payscope.watch.snapshot.generatedAt.v1"
    static let requestSnapshot = "requestSnapshot"
    static let reloadComplications = "reloadComplications"
    static let reloadIOSWidgets = "reloadIOSWidgets"
}

struct WatchShiftSnapshot: Codable, Equatable {
    var generatedAt: Date
    var themeAccentRawValue: String
    var calendarSummaryDisplayModeRawValue: String
    var calendarHoursBreakModeRawValue: String
    var showTipsAmount: Bool
    var days: [WatchShiftDay]

    init(
        generatedAt: Date,
        themeAccentRawValue: String,
        calendarSummaryDisplayModeRawValue: String,
        calendarHoursBreakModeRawValue: String,
        showTipsAmount: Bool,
        days: [WatchShiftDay]
    ) {
        self.generatedAt = generatedAt
        self.themeAccentRawValue = themeAccentRawValue
        self.calendarSummaryDisplayModeRawValue = calendarSummaryDisplayModeRawValue
        self.calendarHoursBreakModeRawValue = calendarHoursBreakModeRawValue
        self.showTipsAmount = showTipsAmount
        self.days = days.sorted { $0.date < $1.date }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .distantPast
        themeAccentRawValue = try container.decodeIfPresent(String.self, forKey: .themeAccentRawValue) ?? "blue"
        calendarSummaryDisplayModeRawValue = try container.decodeIfPresent(String.self, forKey: .calendarSummaryDisplayModeRawValue) ?? "grossNet"
        calendarHoursBreakModeRawValue = try container.decodeIfPresent(String.self, forKey: .calendarHoursBreakModeRawValue) ?? "withoutBreak"
        showTipsAmount = try container.decodeIfPresent(Bool.self, forKey: .showTipsAmount) ?? true
        days = (try container.decodeIfPresent([WatchShiftDay].self, forKey: .days) ?? [])
            .sorted { $0.date < $1.date }
    }

    var themeAccent: Color {
        WatchColorPalette.color(for: themeAccentRawValue)
    }

    var displayDays: [WatchShiftDay] {
        days.sorted { $0.date < $1.date }
    }

    func focusDay(at now: Date) -> WatchShiftDay? {
        if let active = displayDays.first(where: { $0.isActive(at: now) }) {
            return active
        }

        let today = now.startOfWatchDay()
        if let todayDay = displayDays.first(where: { $0.date.isSameWatchDay(as: today) }) {
            if let end = todayDay.shiftEnd,
               now >= end.addingTimeInterval(15 * 60),
               let next = nextTimedShift(after: now) {
                return next
            }
            return todayDay
        }

        return nextTimedShift(after: now)
    }

    func preferredScrollID(at now: Date) -> String? {
        if let focus = focusDay(at: now) {
            return focus.id
        }

        let today = now.startOfWatchDay()
        if let future = displayDays.first(where: { $0.date >= today }) {
            return future.id
        }

        return displayDays.last?.id
    }

    private func nextTimedShift(after now: Date) -> WatchShiftDay? {
        displayDays
            .filter { day in
                guard let start = day.shiftStart, let end = day.shiftEnd, end > start else { return false }
                return start > now
            }
            .min { ($0.shiftStart ?? .distantFuture) < ($1.shiftStart ?? .distantFuture) }
    }
}

struct WatchShiftDay: Codable, Equatable, Identifiable {
    var date: Date
    var dayTypeRawValue: String
    var dayTypeLabel: String
    var iconName: String
    var categoryColorRawValue: String
    var workedSeconds: Int
    var payCents: Int
    var earnedSoFarSeconds: Int
    var earnedSoFarPayCents: Int
    var shiftStart: Date?
    var shiftEnd: Date?
    var breakSeconds: Int
    var tipAmountCents: Int
    var updatedAt: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        dayTypeRawValue = try container.decodeIfPresent(String.self, forKey: .dayTypeRawValue) ?? "work"
        dayTypeLabel = try container.decodeIfPresent(String.self, forKey: .dayTypeLabel) ?? "Arbeit"
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "briefcase.fill"
        categoryColorRawValue = try container.decodeIfPresent(String.self, forKey: .categoryColorRawValue) ?? "blue"
        workedSeconds = try container.decodeIfPresent(Int.self, forKey: .workedSeconds) ?? 0
        payCents = try container.decodeIfPresent(Int.self, forKey: .payCents) ?? 0
        earnedSoFarSeconds = try container.decodeIfPresent(Int.self, forKey: .earnedSoFarSeconds) ?? workedSeconds
        earnedSoFarPayCents = try container.decodeIfPresent(Int.self, forKey: .earnedSoFarPayCents) ?? payCents
        shiftStart = try container.decodeIfPresent(Date.self, forKey: .shiftStart)
        shiftEnd = try container.decodeIfPresent(Date.self, forKey: .shiftEnd)
        breakSeconds = try container.decodeIfPresent(Int.self, forKey: .breakSeconds) ?? 0
        tipAmountCents = try container.decodeIfPresent(Int.self, forKey: .tipAmountCents) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? date
    }

    var id: String {
        "\(dayKey)-\(dayTypeRawValue)-\(updatedAt.timeIntervalSince1970)"
    }

    var dayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date.startOfWatchDay())
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    var categoryColor: Color {
        WatchColorPalette.color(for: categoryColorRawValue)
    }

    var isTimedShift: Bool {
        guard let start = shiftStart, let end = shiftEnd else { return false }
        return end > start
    }

    func isActive(at now: Date) -> Bool {
        guard let start = shiftStart, let end = shiftEnd, end > start else { return false }
        return now >= start && now < end
    }

    func isUpcoming(at now: Date) -> Bool {
        guard let start = shiftStart, let end = shiftEnd, end > start else { return false }
        return start > now
    }

    func isCompleted(at now: Date) -> Bool {
        guard let end = shiftEnd else {
            return date.startOfWatchDay() < now.startOfWatchDay()
        }
        return now >= end
    }

    func progress(at now: Date) -> Double {
        guard let start = shiftStart, let end = shiftEnd, end > start else {
            let dayStart = date.startOfWatchDay()
            guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
            return min(max(now.timeIntervalSince(dayStart) / dayEnd.timeIntervalSince(dayStart), 0), 1)
        }

        let total = max(1, end.timeIntervalSince(start))
        let elapsed = min(max(now.timeIntervalSince(start), 0), total)
        return min(max(elapsed / total, 0), 1)
    }
}

enum WatchColorPalette {
    static func color(for rawValue: String) -> Color {
        switch rawValue {
        case "blue":
            return .blue
        case "green":
            return .green
        case "purple":
            return .purple
        case "orange":
            return .orange
        case "pink":
            return Color(red: 1.0, green: 0.36, blue: 0.64)
        case "teal":
            return .teal
        case "red":
            return .red
        case "indigo":
            return .indigo
        case "mint":
            return Color(red: 0.22, green: 0.78, blue: 0.56)
        case "sage":
            return Color(red: 0.46, green: 0.72, blue: 0.30)
        case "sky":
            return Color(red: 0.24, green: 0.58, blue: 0.92)
        case "aqua":
            return Color(red: 0.16, green: 0.72, blue: 0.78)
        case "lavender":
            return Color(red: 0.52, green: 0.42, blue: 0.88)
        case "lilac":
            return Color(red: 0.70, green: 0.38, blue: 0.86)
        case "blush":
            return Color(red: 0.90, green: 0.32, blue: 0.54)
        case "peach":
            return Color(red: 0.94, green: 0.52, blue: 0.30)
        case "butter":
            return Color(red: 0.88, green: 0.70, blue: 0.16)
        case "coral":
            return Color(red: 0.90, green: 0.34, blue: 0.30)
        default:
            return .blue
        }
    }
}

enum WatchShiftSnapshotCache {
    private static let appGroupIdentifier = "group.DyonisosFergadiotis.PayScope"
    private static let fileName = "WatchShiftSnapshot.json"

    static func load() -> WatchShiftSnapshot? {
        if let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: WatchSnapshotBridgeKeys.payloadData),
           let snapshot = try? JSONDecoder().decode(WatchShiftSnapshot.self, from: data) {
            return snapshot
        }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WatchShiftSnapshot.self, from: data)
    }

    static func save(_ snapshot: WatchShiftSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(data, forKey: WatchSnapshotBridgeKeys.payloadData)
        defaults?.set(snapshot.generatedAt.timeIntervalSince1970, forKey: WatchSnapshotBridgeKeys.generatedAt)

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PayScope", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }
}

extension Date {
    func startOfWatchDay(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: self)
    }

    func isSameWatchDay(as other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(self, inSameDayAs: other)
    }
}
