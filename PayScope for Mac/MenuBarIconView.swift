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
        formatter.dateFormat = "dd.MM - HH:mm"
        return formatter
    }()
    private static let nextWorkStartTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
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
            print("PayScopeMac MenuBarIconView: onAppear")
            now = Date()
            reloadSnapshot()
        }
        .onReceive(clockTimer) { referenceDate in
            now = referenceDate
        }
        .onReceive(snapshotReloadTimer) { _ in
            print("PayScopeMac MenuBarIconView: periodic cache reload")
            reloadSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarSnapshotDidReload)) { _ in
            print("PayScopeMac MenuBarIconView: received cloud reload notification")
            reloadSnapshot()
        }
    }

    private func menuBarIndicator(at referenceDate: Date) -> MenuBarIndicator? {
        guard let snapshot else {
            return nil
        }
        let calendar = Calendar.current
        let entriesByDate = entriesLookup(from: snapshot.dayEntries, calendar: calendar)
        let resolvedSettings = makeSettings(from: snapshot.settings)
        let todayKey = referenceDate.localDayKey(calendar: calendar)

        if let active = activeShiftEntry(in: snapshot.dayEntries, at: referenceDate) {
            return MenuBarIndicator(
                icon: active.type.icon,
                text: countdownText(until: active.shiftEnd ?? referenceDate, referenceDate: referenceDate)
            )
        }

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

    private func activeShiftEntry(
        in entries: [CloudSnapshot.DayEntryPayload],
        at referenceDate: Date
    ) -> CloudSnapshot.DayEntryPayload? {
        entries
            .filter { entry in
                guard entry.type == .work || entry.type == .manual else { return false }
                guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else { return false }
                return referenceDate >= start && referenceDate < end
            }
            .max { lhs, rhs in
                (lhs.shiftStart ?? .distantPast) < (rhs.shiftStart ?? .distantPast)
            }
    }

    private func reloadSnapshot() {
        Task {
            let envelope = await LocalCloudSnapshotStore.shared.load()
            if let envelope {
                let snapshot = envelope.snapshot
                print("PayScopeMac MenuBarIconView: cache loaded savedAt=\(envelope.savedAt) settings=\(snapshot.settings != nil) entries=\(snapshot.dayEntries.count) netConfigs=\(snapshot.netWageConfigs.count) holidays=\(snapshot.holidays.count)")
            } else {
                print("PayScopeMac MenuBarIconView: cache empty")
            }
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
            return workedSeconds(for: day, includeBreak: shouldIncludeBreaks(in: settings))
        case .vacation:
            if let overrideSeconds = day.creditedOverrideSeconds {
                return max(0, overrideSeconds)
            }
            if settings.effectiveVacationCreditingMode == .fixedValue {
                return settings.effectiveVacationFixedSeconds
            }
            let computed = creditedSeconds(for: day, entriesByDate: entriesByDate, settings: settings, calendar: calendar)
            if computed == 0, let cached = day.manualWorkedSeconds {
                return max(0, cached)
            }
            return computed
        case .holiday:
            if let overrideSeconds = day.creditedOverrideSeconds {
                return max(0, overrideSeconds)
            }
            if settings.effectiveHolidayCreditingMode == .fixedValue {
                return settings.effectiveHolidayFixedSeconds
            }
            let computed = creditedSeconds(for: day, entriesByDate: entriesByDate, settings: settings, calendar: calendar)
            if computed == 0, let cached = day.manualWorkedSeconds {
                return max(0, cached)
            }
            return computed
        case .sick:
            if let overrideSeconds = day.creditedOverrideSeconds {
                return max(0, overrideSeconds)
            }
            let computed = creditedSeconds(for: day, entriesByDate: entriesByDate, settings: settings, calendar: calendar)
            if computed == 0, let cached = day.manualWorkedSeconds {
                return max(0, cached)
            }
            return computed
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
                if settings.countMissingAsZero {
                    values.append(0)
                } else {
                    return 0
                }
                continue
            }

            let hasExplicitReferenceValue = refEntry.creditedOverrideSeconds != nil ||
                (refEntry.type == .vacation && settings.effectiveVacationCreditingMode == .fixedValue) ||
                (refEntry.type == .holiday && settings.effectiveHolidayCreditingMode == .fixedValue)
            let canDeriveReferenceValue = canDeriveCreditedReferenceValue(for: refEntry, settings: settings)

            if isEmptyTrackedDay(refEntry) && !hasExplicitReferenceValue && !canDeriveReferenceValue {
                if settings.countMissingAsZero {
                    values.append(0)
                } else {
                    return 0
                }
                continue
            }

            guard let seconds = referenceSeconds(
                for: refEntry,
                entriesByDate: entriesByDate,
                settings: settings,
                calendar: calendar
            ) else {
                return 0
            }
            values.append(seconds)
        }

        guard !values.isEmpty else { return 0 }

        let total = values.reduce(0, +)
        let averageRaw = Double(total) / Double(values.count)
        let roundedToMinute = Int(ceil(averageRaw / 60.0) * 60.0)
        return max(0, roundedToMinute)
    }

    private func referenceSeconds(
        for day: CloudSnapshot.DayEntryPayload,
        entriesByDate: [String: CloudSnapshot.DayEntryPayload],
        settings: Settings,
        calendar: Calendar
    ) -> Int? {
        if let overrideSeconds = day.creditedOverrideSeconds {
            return max(0, overrideSeconds)
        }

        if day.type == .vacation, settings.effectiveVacationCreditingMode == .fixedValue {
            return settings.effectiveVacationFixedSeconds
        }

        if day.type == .holiday, settings.effectiveHolidayCreditingMode == .fixedValue {
            return settings.effectiveHolidayFixedSeconds
        }

        if canDeriveCreditedReferenceValue(for: day, settings: settings) {
            return creditedSeconds(
                for: day,
                entriesByDate: entriesByDate,
                settings: settings,
                calendar: calendar
            )
        }

        return workedSeconds(for: day, includeBreak: shouldIncludeBreaks(in: settings))
    }

    private func shouldIncludeBreaks(in settings: Settings) -> Bool {
        !settings.effectiveCalculateBreaks || settings.effectiveCalendarHoursBreakMode == .withBreak
    }

    private func canDeriveCreditedReferenceValue(for day: CloudSnapshot.DayEntryPayload, settings: Settings) -> Bool {
        switch day.type {
        case .vacation:
            return settings.effectiveVacationCreditingMode == .lookback13Weeks
        case .holiday:
            return settings.effectiveHolidayCreditingMode == .lookback13Weeks
        case .sick:
            return true
        case .work, .manual:
            return false
        }
    }

    private func isEmptyTrackedDay(_ day: CloudSnapshot.DayEntryPayload) -> Bool {
        if let manualWorkedSeconds = day.manualWorkedSeconds, manualWorkedSeconds > 0 {
            return false
        }
        if let start = day.shiftStart, let end = day.shiftEnd, end > start {
            return false
        }
        return true
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
        resolved.calculateBreaks = payload.calculateBreaks
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
                text: nextWorkStartText(for: candidate.startDate, referenceDate: referenceDate, calendar: calendar)
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

    private func nextWorkStartText(for startDate: Date, referenceDate: Date, calendar: Calendar) -> String {
        let todayStart = referenceDate.startOfDayLocal(calendar: calendar)
        if
            let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
            calendar.isDate(startDate, inSameDayAs: tomorrowStart)
        {
            return "Morgen - \(Self.nextWorkStartTimeFormatter.string(from: startDate))"
        }

        return Self.nextWorkStartFormatter.string(from: startDate)
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
