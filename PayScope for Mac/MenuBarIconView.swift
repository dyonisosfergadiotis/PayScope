import Combine
import Foundation
import SwiftUI

struct MenuBarIconView: View {
    @State private var snapshot: CloudSnapshot?
    @State private var now = Date()

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let snapshotReloadTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private static let nextWorkStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 4) {
            if let indicator = menuBarIndicator(at: now) {
                Image(systemName: indicator.icon)
                Text(indicator.text)
                    .monospacedDigit()
            } else {
                Image(systemName: "clock.badge.checkmark")
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .fixedSize()
        .onAppear {
            now = Date()
            reloadSnapshot()
        }
        .onReceive(clockTimer) { referenceDate in
            now = referenceDate
        }
        .onReceive(snapshotReloadTimer) { _ in
            reloadSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarSnapshotDidReload)) { _ in
            reloadSnapshot()
        }
    }

    private func menuBarIndicator(at referenceDate: Date) -> MenuBarIndicator? {
        guard let snapshot else { return nil }
        let calendar = Calendar.current
        let entriesByDate = entriesLookup(from: snapshot.dayEntries, calendar: calendar)
        let resolvedSettings = makeSettings(from: snapshot.settings)
        let todayKey = referenceDate.localDayKey(calendar: calendar)

        if let today = entriesByDate[todayKey] {
            switch today.type {
            case .work, .manual:
                if let end = activeShiftEnd(for: today, at: referenceDate) {
                    return MenuBarIndicator(
                        icon: today.type.icon,
                        text: countdownText(until: end, referenceDate: referenceDate)
                    )
                }
            case .vacation, .holiday, .sick:
                let seconds = daySeconds(for: today, entriesByDate: entriesByDate, settings: resolvedSettings, calendar: calendar)
                return MenuBarIndicator(
                    icon: today.type.icon,
                    text: Formatters.hhmmString(seconds: seconds)
                )
            }
        }

        return nextEntryIndicator(
            after: referenceDate,
            entries: snapshot.dayEntries,
            entriesByDate: entriesByDate,
            settings: resolvedSettings,
            calendar: calendar
        )
    }

    private func countdownText(until end: Date, referenceDate: Date) -> String {
        let remainingSeconds = max(0, Int(end.timeIntervalSince(referenceDate)))
        let hours = remainingSeconds / 3_600
        let minutes = (remainingSeconds % 3_600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func activeShiftEnd(for entry: CloudSnapshot.DayEntryPayload, at referenceDate: Date) -> Date? {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
            return nil
        }
        guard referenceDate >= start, referenceDate < end else {
            return nil
        }
        return end
    }

    private func reloadSnapshot() {
        Task {
            let envelope = await LocalCloudSnapshotStore.shared.load()
            await MainActor.run {
                snapshot = envelope?.snapshot
            }
        }
    }

    private func entriesLookup(
        from entries: [CloudSnapshot.DayEntryPayload],
        calendar: Calendar
    ) -> [String: CloudSnapshot.DayEntryPayload] {
        Dictionary(entries.map { ($0.date.localDayKey(calendar: calendar), $0) }, uniquingKeysWith: { current, _ in current })
    }

    private func daySeconds(
        for day: CloudSnapshot.DayEntryPayload,
        entriesByDate: [String: CloudSnapshot.DayEntryPayload],
        settings: Settings,
        calendar: Calendar
    ) -> Int {
        switch day.type {
        case .work, .manual:
            return workedSeconds(for: day, includeBreak: settings.effectiveCalendarHoursBreakMode == .withBreak)
        case .vacation:
            if let overrideSeconds = day.creditedOverrideSeconds {
                return max(0, overrideSeconds)
            }
            if settings.effectiveVacationCreditingMode == .fixedValue {
                return settings.effectiveVacationFixedSeconds
            }
            return creditedSeconds(for: day, entriesByDate: entriesByDate, settings: settings, calendar: calendar)
        case .holiday:
            if let overrideSeconds = day.creditedOverrideSeconds {
                return max(0, overrideSeconds)
            }
            if settings.effectiveHolidayCreditingMode == .fixedValue {
                return settings.effectiveHolidayFixedSeconds
            }
            return creditedSeconds(for: day, entriesByDate: entriesByDate, settings: settings, calendar: calendar)
        case .sick:
            if let overrideSeconds = day.creditedOverrideSeconds {
                return max(0, overrideSeconds)
            }
            return creditedSeconds(for: day, entriesByDate: entriesByDate, settings: settings, calendar: calendar)
        }
    }

    private func creditedSeconds(
        for day: CloudSnapshot.DayEntryPayload,
        entriesByDate: [String: CloudSnapshot.DayEntryPayload],
        settings: Settings,
        calendar: Calendar
    ) -> Int {
        let normalizedDate = day.date.startOfDayLocal(calendar: calendar)
        let lookback = max(1, settings.vacationLookbackCount)
        var values: [Int] = []

        for index in 1...lookback {
            let referenceDate = normalizedDate.addingDays(index * -7, calendar: calendar).startOfDayLocal(calendar: calendar)
            let referenceKey = referenceDate.localDayKey(calendar: calendar)

            guard let refEntry = entriesByDate[referenceKey] else {
                if settings.strictHistoryRequired && !settings.countMissingAsZero {
                    return 0
                }
                values.append(0)
                continue
            }

            values.append(referenceSeconds(for: refEntry, settings: settings))
        }

        guard !values.isEmpty else { return 0 }

        let total = values.reduce(0, +)
        let averageRaw = Double(total) / Double(values.count)
        let roundedToMinute = Int(ceil(averageRaw / 60.0) * 60.0)
        return max(0, roundedToMinute)
    }

    private func referenceSeconds(for day: CloudSnapshot.DayEntryPayload, settings: Settings) -> Int {
        if let overrideSeconds = day.creditedOverrideSeconds {
            return max(0, overrideSeconds)
        }

        if day.type == .vacation, settings.effectiveVacationCreditingMode == .fixedValue {
            return settings.effectiveVacationFixedSeconds
        }

        if day.type == .holiday, settings.effectiveHolidayCreditingMode == .fixedValue {
            return settings.effectiveHolidayFixedSeconds
        }

        return workedSeconds(for: day, includeBreak: settings.effectiveCalendarHoursBreakMode == .withBreak)
    }

    private func workedSeconds(for day: CloudSnapshot.DayEntryPayload, includeBreak: Bool) -> Int {
        if let manual = day.manualWorkedSeconds, manual > 0 {
            return manual
        }

        guard let start = day.shiftStart, let end = day.shiftEnd, end > start else {
            return 0
        }

        let rawSeconds = Int(end.timeIntervalSince(start))
        let breakSeconds = max(0, day.breakSeconds ?? 0)
        let value = includeBreak ? rawSeconds : rawSeconds - breakSeconds
        return max(0, value)
    }

    private func makeSettings(from payload: CloudSnapshot.SettingsPayload?) -> Settings {
        let resolved = Settings()
        guard let payload else { return resolved }

        resolved.weeklyTargetSeconds = payload.weeklyTargetSeconds
        resolved.vacationLookbackCount = payload.vacationLookbackCount
        resolved.vacationCreditingMode = payload.vacationCreditingMode
        resolved.vacationFixedSeconds = payload.vacationFixedSeconds
        resolved.countMissingAsZero = payload.countMissingAsZero
        resolved.strictHistoryRequired = payload.strictHistoryRequired
        resolved.holidayCreditingMode = payload.holidayCreditingMode
        resolved.holidayFixedSeconds = payload.holidayFixedSeconds
        resolved.scheduledWorkdaysCount = payload.scheduledWorkdaysCount
        resolved.calendarHoursBreakMode = payload.calendarHoursBreakMode
        return resolved
    }

    private func nextEntryIndicator(
        after referenceDate: Date,
        entries: [CloudSnapshot.DayEntryPayload],
        entriesByDate: [String: CloudSnapshot.DayEntryPayload],
        settings: Settings,
        calendar: Calendar
    ) -> MenuBarIndicator? {
        let candidate = entries.compactMap { entry -> NextEntryCandidate? in
            switch entry.type {
            case .work:
                guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start, start > referenceDate else {
                    return nil
                }
                return NextEntryCandidate(entry: entry, startDate: start)
            case .manual, .vacation, .holiday, .sick:
                let dayStart = entry.date.startOfDayLocal(calendar: calendar)
                guard dayStart > referenceDate else { return nil }
                return NextEntryCandidate(entry: entry, startDate: dayStart)
            }
        }
        .min(by: { $0.startDate < $1.startDate })

        guard let candidate else { return nil }

        if candidate.entry.type == .work {
            return MenuBarIndicator(
                icon: candidate.entry.type.icon,
                text: Self.nextWorkStartFormatter.string(from: candidate.startDate)
            )
        }

        let seconds = daySeconds(
            for: candidate.entry,
            entriesByDate: entriesByDate,
            settings: settings,
            calendar: calendar
        )
        return MenuBarIndicator(
            icon: candidate.entry.type.icon,
            text: Formatters.hhmmString(seconds: seconds)
        )
    }

    private struct MenuBarIndicator {
        let icon: String
        let text: String
    }

    private struct NextEntryCandidate {
        let entry: CloudSnapshot.DayEntryPayload
        let startDate: Date
    }
}

#Preview {
    MenuBarIconView()
}
