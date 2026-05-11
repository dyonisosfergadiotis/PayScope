import Foundation

struct WorkedSecondsError: Error {
    let message: String
}

enum ComputationResult: Equatable {
    case ok(valueSeconds: Int, valueCents: Int)
    case warning(valueSeconds: Int, valueCents: Int, message: String)
    case error(message: String, missingDates: [Date])

    var valueSecondsOrZero: Int {
        switch self {
        case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
            return valueSeconds
        case .error:
            return 0
        }
    }

    var valueCentsOrZero: Int {
        switch self {
        case let .ok(_, valueCents), let .warning(_, valueCents, _):
            return valueCents
        case .error:
            return 0
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

struct TotalsSummary {
    var totalSeconds: Int = 0
    var totalCents: Int = 0
    var warningCount: Int = 0
    var erroredDaysCount: Int = 0
    var omittedValueText: String = "Not estimated"
}

struct ShiftTimeRange: Equatable {
    static let minutesPerDay = 24 * 60
    static let maxEndMinuteOffset = 36 * 60
    static let maxDurationMinutes = minutesPerDay - 1

    let startMinute: Int
    let endMinuteOffset: Int

    init?(startMinute: Int, endClockMinute: Int) {
        guard (0..<Self.minutesPerDay).contains(startMinute) else { return nil }

        let normalizedEndClock = Self.normalizedClockMinute(endClockMinute)
        guard normalizedEndClock != startMinute else { return nil }

        let candidateEnd = normalizedEndClock > startMinute
            ? normalizedEndClock
            : normalizedEndClock + Self.minutesPerDay

        self.init(startMinute: startMinute, endMinuteOffset: candidateEnd)
    }

    init?(startMinute: Int, endMinuteOffset: Int) {
        guard (0..<Self.minutesPerDay).contains(startMinute) else { return nil }
        guard endMinuteOffset > startMinute else { return nil }
        guard endMinuteOffset <= Self.maxEndMinuteOffset else { return nil }
        guard endMinuteOffset - startMinute <= Self.maxDurationMinutes else { return nil }

        self.startMinute = startMinute
        self.endMinuteOffset = endMinuteOffset
    }

    init?(anchorDate: Date, start: Date, end: Date, calendar: Calendar = .current) {
        guard end > start else { return nil }
        let dayStart = anchorDate.startOfDayLocal(calendar: calendar)
        let startOffset = Self.minuteOffset(from: dayStart, to: start, calendar: calendar)
        let endOffset = Self.minuteOffset(from: dayStart, to: end, calendar: calendar)
        self.init(startMinute: startOffset, endMinuteOffset: endOffset)
    }

    var endClockMinute: Int {
        let value = endMinuteOffset % Self.minutesPerDay
        return value == 0 ? 0 : value
    }

    var durationMinutes: Int {
        max(0, endMinuteOffset - startMinute)
    }

    var durationSeconds: Int {
        durationMinutes * 60
    }

    var crossesMidnight: Bool {
        endMinuteOffset >= Self.minutesPerDay
    }

    func startDate(on anchorDate: Date, calendar: Calendar = .current) -> Date? {
        date(atMinuteOffset: startMinute, on: anchorDate, calendar: calendar)
    }

    func endDate(on anchorDate: Date, calendar: Calendar = .current) -> Date? {
        date(atMinuteOffset: endMinuteOffset, on: anchorDate, calendar: calendar)
    }

    func date(atMinuteOffset minuteOffset: Int, on anchorDate: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .minute, value: minuteOffset, to: anchorDate.startOfDayLocal(calendar: calendar))
    }

    func displayRange(calendar: Calendar = .current) -> String {
        let start = Self.displayMinute(startMinute).replacingOccurrences(of: " +1", with: "")
        let end = Self.displayMinute(endMinuteOffset).replacingOccurrences(of: " +1", with: "")
        let suffix = crossesMidnight ? " (+1)" : ""
        return "\(start)-\(end)\(suffix)"
    }

    static func displayRange(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        let suffix = calendar.isDate(start, inSameDayAs: end) ? "" : " (+1)"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))\(suffix)"
    }

    static func displayMinute(_ minuteOffset: Int) -> String {
        let clamped = max(0, min(maxEndMinuteOffset, minuteOffset))
        let clock = clamped % minutesPerDay
        let h = clock / 60
        let m = clock % 60
        let suffix = clamped >= minutesPerDay ? " +1" : ""
        return String(format: "%02d:%02d%@", h, m, suffix)
    }

    static func normalizedClockMinute(_ minute: Int) -> Int {
        if minute <= 0 { return 0 }
        if minute == minutesPerDay { return 0 }
        if minute > minutesPerDay { return minute % minutesPerDay }
        return min(minutesPerDay - 1, minute)
    }

    private static func minuteOffset(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.minute], from: start, to: end)
        return components.minute ?? Int(end.timeIntervalSince(start) / 60)
    }
}

struct CalculationService {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func workedSeconds(for day: DayEntry) -> Result<Int, WorkedSecondsError> {
        // Manual duration takes precedence for editable work/manual entries.
        // For credited types the computed value comes from day rules, not from manual cache fields.
        if let manual = day.manualWorkedSeconds {
            if manual < 0 {
                return .failure(WorkedSecondsError(message: "Manual worked seconds cannot be negative."))
            }
            if day.type == .work {
                return .success(applyLegalBreakToleranceCorrection(to: manual))
            }
            if day.type == .manual {
                return .success(manual)
            }
            return .success(0)
        }

        guard let start = day.shiftStart, let end = day.shiftEnd, end > start else {
            if !day.segments.isEmpty {
                return workedSeconds(forSegments: day.segments, dayType: day.type)
            }
            return .success(0)
        }

        let presenceSeconds = max(0, Int(end.timeIntervalSince(start)))

        // Non-work days: no legal-break correction, return presence directly
        if day.type != .work {
            return .success(presenceSeconds)
        }

        // Work: subtract explicit break, then apply legal rules/tolerance.
        let explicitBreakSeconds = max(0, day.breakSeconds ?? 0)
        let netWorkedSeconds = max(0, presenceSeconds - explicitBreakSeconds)

        let requiredBreak = legalMinimumBreakSeconds(forWorkedSeconds: netWorkedSeconds)
        let missingBreakComplement = max(0, requiredBreak - explicitBreakSeconds)
        let afterMinimumBreakCorrection = max(0, netWorkedSeconds - missingBreakComplement)

        return .success(applyLegalBreakToleranceCorrection(to: afterMinimumBreakCorrection))
    }

    func validateSegments(_ segments: [TimeSegment]) -> [WorkedSecondsError] {
        segments.compactMap { segment in
            guard segment.end > segment.start else {
                return WorkedSecondsError(message: "Segment end must be after start.")
            }
            let rawSeconds = max(0, Int(segment.end.timeIntervalSince(segment.start)))
            if segment.breakSeconds < 0 {
                return WorkedSecondsError(message: "Break seconds cannot be negative.")
            }
            if segment.breakSeconds > rawSeconds {
                return WorkedSecondsError(message: "Break cannot exceed segment duration.")
            }
            return nil
        }
    }

    func activeShiftEntry(at referenceDate: Date, entries: [DayEntry]) -> DayEntry? {
        entries
            .filter { entry in
                guard entry.type == .work || entry.type == .manual else { return false }
                guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else { return false }
                return start <= referenceDate && referenceDate < end
            }
            .max { lhs, rhs in
                (lhs.shiftStart ?? .distantPast) < (rhs.shiftStart ?? .distantPast)
            }
    }

    private func workedSeconds(forSegments segments: [TimeSegment], dayType: DayType) -> Result<Int, WorkedSecondsError> {
        let errors = validateSegments(segments)
        guard errors.isEmpty else {
            return .failure(errors[0])
        }

        let total = segments.reduce(0) { partial, segment in
            let presenceSeconds = max(0, Int(segment.end.timeIntervalSince(segment.start)))
            let explicitBreakSeconds = max(0, segment.breakSeconds)
            return partial + max(0, presenceSeconds - explicitBreakSeconds)
        }

        guard dayType == .work else {
            return .success(total)
        }

        let explicitBreakSeconds = segments.reduce(0) { $0 + max(0, $1.breakSeconds) }
        let requiredBreak = legalMinimumBreakSeconds(forWorkedSeconds: total)
        let missingBreakComplement = max(0, requiredBreak - explicitBreakSeconds)
        let corrected = max(0, total - missingBreakComplement)
        return .success(applyLegalBreakToleranceCorrection(to: corrected))
    }

    // Legal break tolerance correction:
    // Minutes 1...15 after 6h and 9h are not counted as work time, including :15.
    private func applyLegalBreakToleranceCorrection(to workedSeconds: Int) -> Int {
        let sixHours = 6 * 3600
        let nineHours = 9 * 3600
        let tolerance = 15 * 60

        var correction = 0

        if workedSeconds > sixHours && workedSeconds <= sixHours + tolerance {
            correction += workedSeconds - sixHours
        }

        if workedSeconds > nineHours && workedSeconds <= nineHours + tolerance {
            correction += workedSeconds - nineHours
        }

        return max(0, workedSeconds - correction)
    }

    private func legalMinimumBreakSeconds(forWorkedSeconds workedSeconds: Int) -> Int {
        let sixHours = 6 * 3600
        let nineHours = 9 * 3600
        let tolerance = 15 * 60
        let sixHoursWithTolerance = sixHours + tolerance
        let nineHoursWithTolerance = nineHours + tolerance

        if workedSeconds <= sixHoursWithTolerance { return 0 }
        if workedSeconds <= nineHoursWithTolerance { return 30 * 60 }
        return 45 * 60
    }

    func payCents(for seconds: Int, settings: Settings) -> Int {
        switch settings.payMode {
        case .hourly:
            guard let hourlyRateCents = settings.hourlyRateCents else { return 0 }
            return Int((Double(seconds) / 3600.0 * Double(hourlyRateCents)).rounded())
        case .monthly:
            guard
                let monthlySalaryCents = settings.monthlySalaryCents,
                let weeklyTargetSeconds = settings.weeklyTargetSeconds,
                weeklyTargetSeconds > 0
            else {
                return 0
            }
            let monthlyTargetSeconds = Double(weeklyTargetSeconds) * 52.0 / 12.0
            let hourlyRateCents = Double(monthlySalaryCents) / (monthlyTargetSeconds / 3600.0)
            return Int((Double(seconds) / 3600.0 * hourlyRateCents).rounded())
        }
    }

    func monthlyNetEuro(
        grossEuro: Double,
        bonusesEuro: Double,
        wageTaxPercent: Double?,
        pensionPercent: Double?,
        monthlyAllowanceEuro: Double?
    ) -> Double {
        let grossMonthly = max(0, grossEuro + bonusesEuro)
        let wageTaxRate = max(0, (wageTaxPercent ?? 0) / 100.0)
        let pensionRate = max(0, (pensionPercent ?? 0) / 100.0)
        let allowance = max(0, monthlyAllowanceEuro ?? 0)

        let taxableBase = max(0, grossMonthly - allowance)
        let wageTax = taxableBase * wageTaxRate
        let pension = grossMonthly * pensionRate

        return grossMonthly - wageTax - pension
    }

    func makeEntriesByDateLookup(from entries: [DayEntry]) -> [Date: DayEntry] {
        Dictionary(
            entries.map { ($0.date.startOfDayLocal(calendar: calendar), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
    }

    func dayComputation(for day: DayEntry, allEntries: [DayEntry], settings: Settings) -> ComputationResult {
        dayComputation(
            for: day,
            entriesByDate: makeEntriesByDateLookup(from: allEntries),
            settings: settings
        )
    }

    func exportComputation(for day: DayEntry, allEntries: [DayEntry], settings: Settings) -> ComputationResult {
        exportComputation(
            for: day,
            entriesByDate: makeEntriesByDateLookup(from: allEntries),
            settings: settings
        )
    }

    func exportComputation(for day: DayEntry, entriesByDate: [Date: DayEntry], settings: Settings) -> ComputationResult {
        if let savedSeconds = savedAutoCreditedSeconds(for: day) {
            return .ok(
                valueSeconds: savedSeconds,
                valueCents: payCents(for: savedSeconds, settings: settings)
            )
        }

        return dayComputation(for: day, entriesByDate: entriesByDate, settings: settings)
    }

    func dayComputation(for day: DayEntry, entriesByDate: [Date: DayEntry], settings: Settings) -> ComputationResult {
        switch day.type {
        case .work, .manual:
            switch workedSeconds(for: day) {
            case let .success(seconds):
                return .ok(valueSeconds: seconds, valueCents: payCents(for: seconds, settings: settings))
            case let .failure(message):
                return .error(message: message.message, missingDates: [])
            }
        case .vacation:
            if let overrideSeconds = day.creditedOverrideSeconds {
                let clamped = max(0, overrideSeconds)
                return .ok(valueSeconds: clamped, valueCents: payCents(for: clamped, settings: settings))
            }
            if settings.effectiveVacationCreditingMode == .fixedValue {
                let fixedSeconds = settings.effectiveVacationFixedSeconds
                return .ok(valueSeconds: fixedSeconds, valueCents: payCents(for: fixedSeconds, settings: settings))
            }
            return creditedResult(for: day, entriesByDate: entriesByDate, settings: settings)
        case .holiday:
            if let overrideSeconds = day.creditedOverrideSeconds {
                let clamped = max(0, overrideSeconds)
                return .ok(valueSeconds: clamped, valueCents: payCents(for: clamped, settings: settings))
            }
            if settings.effectiveHolidayCreditingMode == .fixedValue {
                let fixedSeconds = settings.effectiveHolidayFixedSeconds
                return .ok(valueSeconds: fixedSeconds, valueCents: payCents(for: fixedSeconds, settings: settings))
            }
            return creditedResult(for: day, entriesByDate: entriesByDate, settings: settings)
        case .sick:
            if let overrideSeconds = day.creditedOverrideSeconds {
                let clamped = max(0, overrideSeconds)
                return .ok(valueSeconds: clamped, valueCents: payCents(for: clamped, settings: settings))
            }
            return creditedResult(for: day, entriesByDate: entriesByDate, settings: settings)
        }
    }

    func holidayCreditedSeconds(settings: Settings) -> Int {
        settings.effectiveHolidayFixedSeconds
    }

    func creditedResult(for day: DayEntry, entriesByDate: [Date: DayEntry], settings: Settings) -> ComputationResult {
        let normalizedDate = day.date.startOfDayLocal(calendar: calendar)
        let lookback = max(1, settings.vacationLookbackCount)

        var values: [Int] = []
        var missingDates: [Date] = []

        for index in 1...lookback {
            let reference = normalizedDate.addingDays(index * -7, calendar: calendar).startOfDayLocal(calendar: calendar)
            guard let refEntry = entriesByDate[reference] else {
                if case let .error(message, missing) = missingReferenceResult(for: reference, settings: settings) {
                    return .error(message: message, missingDates: missing)
                }
                if settings.countMissingAsZero {
                    values.append(0)
                } else {
                    missingDates.append(reference)
                }
                continue
            }

            let hasExplicitReferenceValue = refEntry.creditedOverrideSeconds != nil ||
                (refEntry.type == .vacation && settings.effectiveVacationCreditingMode == .fixedValue) ||
                (refEntry.type == .holiday && settings.effectiveHolidayCreditingMode == .fixedValue)
            let canDeriveReferenceValue = canDeriveCreditedReferenceValue(for: refEntry, settings: settings)

            if refEntry.isEmptyTrackedDay && !hasExplicitReferenceValue && !canDeriveReferenceValue {
                if case let .error(message, missing) = missingReferenceResult(for: reference, settings: settings) {
                    return .error(message: message, missingDates: missing)
                }
                if settings.countMissingAsZero {
                    values.append(0)
                } else {
                    missingDates.append(reference)
                }
                continue
            }

            switch referenceSeconds(for: refEntry, entriesByDate: entriesByDate, settings: settings) {
            case let .success(seconds):
                values.append(seconds)
            case let .failure(message):
                return .error(message: "Reference day has invalid data: \(message.message)", missingDates: [reference])
            }
        }

        if !missingDates.isEmpty, !settings.countMissingAsZero {
            return .error(
                message: "Not enough history for lookback calculation. Missing \(missingDates.count) reference day(s).",
                missingDates: missingDates
            )
        }

        let divisor = values.isEmpty ? 0 : values.count
        guard divisor > 0 else {
            return .error(
                message: "Not enough history for lookback calculation.",
                missingDates: missingDates
            )
        }

        let total = values.reduce(0, +)
        let rawAverageSeconds = Double(total) / Double(divisor)
        let average = Int(ceil(rawAverageSeconds / 60.0) * 60.0)
        let pay = payCents(for: average, settings: settings)

        if values.allSatisfy({ $0 == 0 }) {
            return .warning(valueSeconds: 0, valueCents: 0, message: "All \(lookback) lookback values are 0.")
        }

        return .ok(valueSeconds: average, valueCents: pay)
    }

    private func referenceSeconds(
        for day: DayEntry,
        entriesByDate: [Date: DayEntry],
        settings: Settings
    ) -> Result<Int, WorkedSecondsError> {
        if let overrideSeconds = day.creditedOverrideSeconds {
            return .success(max(0, overrideSeconds))
        }

        if day.type == .vacation, settings.effectiveVacationCreditingMode == .fixedValue {
            return .success(settings.effectiveVacationFixedSeconds)
        }

        if day.type == .holiday, settings.effectiveHolidayCreditingMode == .fixedValue {
            return .success(settings.effectiveHolidayFixedSeconds)
        }

        if canDeriveCreditedReferenceValue(for: day, settings: settings) {
            let result = dayComputation(for: day, entriesByDate: entriesByDate, settings: settings)
            switch result {
            case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
                return .success(valueSeconds)
            case let .error(message, _):
                return .failure(WorkedSecondsError(message: message))
            }
        }

        return workedSeconds(for: day)
    }

    private func savedAutoCreditedSeconds(for day: DayEntry) -> Int? {
        guard day.creditedOverrideSeconds == nil else { return nil }
        guard day.type == .vacation || day.type == .holiday || day.type == .sick else { return nil }
        guard let seconds = day.manualWorkedSeconds else { return nil }
        return max(0, seconds)
    }

    private func canDeriveCreditedReferenceValue(for day: DayEntry, settings: Settings) -> Bool {
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

    private func missingReferenceResult(for date: Date, settings: Settings) -> ComputationResult? {
        if settings.strictHistoryRequired, !settings.countMissingAsZero {
            return .error(
                message: "Strict history required: missing reference day.",
                missingDates: [date]
            )
        }
        return nil
    }

    func weekStartDate(for date: Date, weekStart: WeekStart) -> Date {
        let normalized = date.startOfDayLocal(calendar: calendar)
        let weekday = calendar.component(.weekday, from: normalized)
        let desired: Int = weekStart == .monday ? 2 : 1
        let diff = (weekday - desired + 7) % 7
        return normalized.addingDays(-diff, calendar: calendar)
    }

    func periodSummary(
        entries: [DayEntry],
        from startDate: Date,
        to endDate: Date,
        settings: Settings
    ) -> TotalsSummary {
        periodSummary(
            entries: entries,
            entriesByDate: makeEntriesByDateLookup(from: entries),
            from: startDate,
            to: endDate,
            settings: settings
        )
    }

    func periodSummary(
        entries: [DayEntry],
        entriesByDate: [Date: DayEntry],
        from startDate: Date,
        to endDate: Date,
        settings: Settings
    ) -> TotalsSummary {
        var summary = TotalsSummary()
        let ranged = entries.filter { $0.date >= startDate && $0.date <= endDate }

        for day in ranged {
            let result = dayComputation(for: day, entriesByDate: entriesByDate, settings: settings)
            switch result {
            case let .ok(seconds, cents):
                summary.totalSeconds += seconds
                summary.totalCents += cents
            case let .warning(seconds, cents, _):
                summary.totalSeconds += seconds
                summary.totalCents += cents
                summary.warningCount += 1
            case .error:
                if day.type == .vacation || day.type == .holiday || day.type == .sick {
                    summary.erroredDaysCount += 1
                }
            }
        }

        return summary
    }
}
