import Foundation

struct SegmentValidationError: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

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

struct CalculationService {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func validateSegments(_ segments: [TimeSegment]) -> [SegmentValidationError] {
        segments.compactMap { segment in
            if segment.end <= segment.start {
                return SegmentValidationError(message: "End time must be after start time.")
            }
            if segment.breakSeconds < 0 {
                return SegmentValidationError(message: "Break cannot be negative.")
            }
            let duration = Int(segment.end.timeIntervalSince(segment.start))
            if segment.breakSeconds > duration {
                return SegmentValidationError(message: "Break exceeds segment duration.")
            }
            return nil
        }
    }

    func workedSeconds(for day: DayEntry) -> Result<Int, WorkedSecondsError> {
        if let manual = day.manualWorkedSeconds {
            if manual < 0 {
                return .failure(WorkedSecondsError(message: "Manual worked seconds cannot be negative."))
            }
            return .success(applyLegalBreakToleranceCorrection(to: manual))
        }

        let errors = validateSegments(day.segments)
        if !errors.isEmpty {
            return .failure(WorkedSecondsError(message: errors.map(\.message).joined(separator: " ")))
        }

        let presenceSeconds = day.segments.reduce(0) { partial, segment in
            partial + max(0, Int(segment.end.timeIntervalSince(segment.start)))
        }
        let explicitBreakSeconds = day.segments.reduce(0) { partial, segment in
            partial + max(0, segment.breakSeconds)
        }
        let netWorkedSeconds = max(0, presenceSeconds - explicitBreakSeconds)

        let requiredBreak = legalMinimumBreakSeconds(forWorkedSeconds: netWorkedSeconds)
        let missingBreakComplement = max(0, requiredBreak - explicitBreakSeconds)
        let afterMinimumBreakCorrection = max(0, netWorkedSeconds - missingBreakComplement)

        return .success(applyLegalBreakToleranceCorrection(to: afterMinimumBreakCorrection))
    }

    // Legal break tolerance correction:
    // Minutes 1...15 after 6h and 9h are not counted as work time.
    private func applyLegalBreakToleranceCorrection(to workedSeconds: Int) -> Int {
        let sixHours = 6 * 3600
        let nineHours = 9 * 3600
        let tolerance = 15 * 60

        var correction = 0

        if workedSeconds > sixHours && workedSeconds < sixHours + tolerance {
            correction += workedSeconds - sixHours
        }

        if workedSeconds > nineHours && workedSeconds < nineHours + tolerance {
            correction += workedSeconds - nineHours
        }

        return max(0, workedSeconds - correction)
    }

    private func legalMinimumBreakSeconds(forWorkedSeconds workedSeconds: Int) -> Int {
        let sixHours = 6 * 3600
        let nineHours = 9 * 3600
        if workedSeconds > nineHours { return 45 * 60 }
        if workedSeconds > sixHours { return 30 * 60 }
        return 0
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

    func dayComputation(for day: DayEntry, allEntries: [DayEntry], settings: Settings) -> ComputationResult {
        switch day.type {
        case .work:
            switch workedSeconds(for: day) {
            case let .success(seconds):
                return .ok(valueSeconds: seconds, valueCents: payCents(for: seconds, settings: settings))
            case let .failure(message):
                return .error(message: message.message, missingDates: [])
            }
        case .vacation, .holiday, .sick:
            if day.manualWorkedSeconds != nil || !day.segments.isEmpty {
                switch workedSeconds(for: day) {
                case let .success(seconds):
                    return .ok(valueSeconds: seconds, valueCents: payCents(for: seconds, settings: settings))
                case let .failure(message):
                    return .error(message: message.message, missingDates: [])
                }
            }
            return creditedResult(for: day, allEntries: allEntries, settings: settings)
        }
    }

    func holidayCreditedSeconds(settings: Settings) -> Int {
        switch settings.holidayCreditingMode {
        case .zero:
            return 0
        case .weeklyTargetDistributed:
            guard let weeklyTargetSeconds = settings.weeklyTargetSeconds else { return 0 }
            return weeklyTargetSeconds / max(1, min(7, settings.scheduledWorkdaysCount))
        }
    }

    func creditedResult(for day: DayEntry, allEntries: [DayEntry], settings: Settings) -> ComputationResult {
        let normalizedDate = day.date.startOfDayLocal(calendar: calendar)
        let lookback = max(1, settings.vacationLookbackCount)
        let entriesByDate = Dictionary(uniqueKeysWithValues: allEntries.map { ($0.date.startOfDayLocal(calendar: calendar), $0) })

        var values: [Int] = []
        var missing: [Date] = []

        for index in 1...lookback {
            let reference = normalizedDate.addingDays(index * -7, calendar: calendar).startOfDayLocal(calendar: calendar)
            guard let refEntry = entriesByDate[reference] else {
                missing.append(reference)
                if settings.countMissingAsZero {
                    values.append(0)
                }
                continue
            }

            if refEntry.isEmptyTrackedDay {
                values.append(0)
                continue
            }

            switch workedSeconds(for: refEntry) {
            case let .success(seconds):
                values.append(seconds)
            case let .failure(message):
                return .error(message: "Reference day has invalid data: \(message.message)", missingDates: [reference])
            }
        }

        if settings.strictHistoryRequired && !missing.isEmpty {
            return .error(message: "Insufficient 13-week history for strict mode.", missingDates: missing)
        }

        if !settings.strictHistoryRequired && !settings.countMissingAsZero && !missing.isEmpty {
            return .error(message: "Missing reference entries. Enable 'count missing as zero' or create entries.", missingDates: missing)
        }

        if values.count < lookback {
            return .error(message: "Not enough reference values available.", missingDates: missing)
        }

        let total = values.reduce(0, +)
        let average = Int((Double(total) / Double(lookback)).rounded())
        let pay = payCents(for: average, settings: settings)

        if values.allSatisfy({ $0 == 0 }) {
            return .warning(valueSeconds: 0, valueCents: 0, message: "All 13 lookback values are 0.")
        }

        return .ok(valueSeconds: average, valueCents: pay)
    }

    func weekStartDate(for date: Date, weekStart: WeekStart) -> Date {
        let normalized = date.startOfDayLocal(calendar: calendar)
        let weekday = calendar.component(.weekday, from: normalized)
        let desired: Int = weekStart == .sunday ? 1 : 2
        let diff = (weekday - desired + 7) % 7
        return normalized.addingDays(-diff, calendar: calendar)
    }

    func periodSummary(
        entries: [DayEntry],
        from startDate: Date,
        to endDate: Date,
        settings: Settings
    ) -> TotalsSummary {
        var summary = TotalsSummary()
        let ranged = entries.filter { $0.date >= startDate && $0.date <= endDate }

        for day in ranged {
            let result = dayComputation(for: day, allEntries: entries, settings: settings)
            switch result {
            case let .ok(seconds, cents):
                summary.totalSeconds += seconds
                summary.totalCents += cents
            case let .warning(seconds, cents, _):
                summary.totalSeconds += seconds
                summary.totalCents += cents
                summary.warningCount += 1
            case .error:
                if day.type == .vacation || day.type == .sick {
                    summary.erroredDaysCount += 1
                }
            }
        }

        return summary
    }
}
