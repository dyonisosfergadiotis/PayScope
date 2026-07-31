import Foundation

struct TVLocalShiftStore: TVShiftScheduleStore {
    func fetchWeek(startingAt weekStart: Date, calendar: Calendar = .current) async throws -> TVWeekSchedule {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
        let generatedAt = Date()

        return TVWeekSchedule(
            weekStart: weekStart,
            weekEnd: weekEnd,
            entries: [
                workEntry(
                    id: "local-early",
                    weekStart: weekStart,
                    dayOffset: 0,
                    startHour: 8,
                    startMinute: 30,
                    endHour: 16,
                    endMinute: 30,
                    breakMinutes: 30,
                    calendar: calendar,
                    updatedAt: generatedAt
                ),
                workEntry(
                    id: "local-late",
                    weekStart: weekStart,
                    dayOffset: 1,
                    startHour: 13,
                    startMinute: 45,
                    endHour: 21,
                    endMinute: 45,
                    breakMinutes: 45,
                    calendar: calendar,
                    updatedAt: generatedAt
                ),
                allDayEntry(
                    id: "local-sick",
                    weekStart: weekStart,
                    dayOffset: 2,
                    type: .sick,
                    calendar: calendar,
                    updatedAt: generatedAt
                ),
                workEntry(
                    id: "local-regular",
                    weekStart: weekStart,
                    dayOffset: 3,
                    startHour: 10,
                    startMinute: 0,
                    endHour: 18,
                    endMinute: 0,
                    breakMinutes: 30,
                    calendar: calendar,
                    updatedAt: generatedAt
                ),
                allDayEntry(
                    id: "local-vacation",
                    weekStart: weekStart,
                    dayOffset: 4,
                    type: .vacation,
                    calendar: calendar,
                    updatedAt: generatedAt
                ),
                workEntry(
                    id: "local-night",
                    weekStart: weekStart,
                    dayOffset: 5,
                    startHour: 18,
                    startMinute: 0,
                    endHour: 1,
                    endMinute: 0,
                    endDayOffset: 6,
                    breakMinutes: 30,
                    calendar: calendar,
                    updatedAt: generatedAt
                )
            ],
            colorSettings: TVShiftColorSettings(),
            generatedAt: generatedAt
        )
    }

    private func workEntry(
        id: String,
        weekStart: Date,
        dayOffset: Int,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        endDayOffset: Int? = nil,
        breakMinutes: Int,
        calendar: Calendar,
        updatedAt: Date
    ) -> TVShiftEntry {
        let start = date(
            weekStart: weekStart,
            dayOffset: dayOffset,
            hour: startHour,
            minute: startMinute,
            calendar: calendar
        )
        let end = date(
            weekStart: weekStart,
            dayOffset: endDayOffset ?? dayOffset,
            hour: endHour,
            minute: endMinute,
            calendar: calendar
        )

        return TVShiftEntry(
            id: "\(id)-\(dayKey(for: start, calendar: calendar))",
            date: calendar.startOfDay(for: start),
            updatedAt: updatedAt,
            type: .work,
            shiftStart: start,
            shiftEnd: end,
            breakSeconds: max(0, breakMinutes) * 60,
            manualWorkedSeconds: nil,
            creditedOverrideSeconds: nil
        )
    }

    private func allDayEntry(
        id: String,
        weekStart: Date,
        dayOffset: Int,
        type: TVShiftDayType,
        calendar: Calendar,
        updatedAt: Date
    ) -> TVShiftEntry {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart

        return TVShiftEntry(
            id: "\(id)-\(dayKey(for: date, calendar: calendar))",
            date: calendar.startOfDay(for: date),
            updatedAt: updatedAt,
            type: type,
            shiftStart: nil,
            shiftEnd: nil,
            breakSeconds: 0,
            manualWorkedSeconds: nil,
            creditedOverrideSeconds: 8 * 60 * 60
        )
    }

    private func date(
        weekStart: Date,
        dayOffset: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        ) ?? day
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
