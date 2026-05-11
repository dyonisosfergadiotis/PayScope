import XCTest
@testable import PayScope

final class CalculationServiceTests: XCTestCase {
    private let calendar = Calendar.current

    func testSegmentValidation() {
        let now = Date()
        let invalid = TimeSegment(start: now, end: now.addingTimeInterval(3600), breakSeconds: 4000)
        let errors = CalculationService().validateSegments([invalid])
        XCTAssertFalse(errors.isEmpty)
    }

    func testWorkComputationUsesManual() {
        let entry = DayEntry(date: Date(), type: .work, manualWorkedSeconds: 7200)
        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 7200)
    }

    func testShiftTimeRangeParsesOvernightEndAsNextDay() {
        let range = ShiftTimeRange(startMinute: 22 * 60, endClockMinute: 6 * 60)

        XCTAssertEqual(range?.endMinuteOffset, 30 * 60)
        XCTAssertEqual(range?.durationSeconds, 8 * 3600)
        XCTAssertEqual(range?.crossesMidnight, true)
        XCTAssertEqual(range?.displayRange(), "22:00-06:00 (+1)")
    }

    func testShiftTimeRangeAllowsMidnightEndOnNextDay() {
        let range = ShiftTimeRange(startMinute: 23 * 60 + 30, endClockMinute: 0)

        XCTAssertEqual(range?.endMinuteOffset, 24 * 60)
        XCTAssertEqual(range?.durationSeconds, 30 * 60)
        XCTAssertEqual(range?.crossesMidnight, true)
    }

    func testShiftTimeRangeKeepsMorningShiftSameDay() {
        let range = ShiftTimeRange(startMinute: 0, endClockMinute: 6 * 60)

        XCTAssertEqual(range?.endMinuteOffset, 6 * 60)
        XCTAssertEqual(range?.durationSeconds, 6 * 3600)
        XCTAssertEqual(range?.crossesMidnight, false)
    }

    func testShiftTimeRangeRejectsEqualStartAndEnd() {
        XCTAssertNil(ShiftTimeRange(startMinute: 6 * 60, endClockMinute: 6 * 60))
    }

    func testOvernightShiftStoresAbsoluteEndOnNextDayAndSubtractsPause() {
        let day = dateFrom(year: 2026, month: 5, day: 12)
        let range = ShiftTimeRange(startMinute: 22 * 60, endClockMinute: 6 * 60)
        let entry = DayEntry(date: day, type: .work)
        entry.shiftStart = range?.startDate(on: day)
        entry.shiftEnd = range?.endDate(on: day)
        entry.breakSeconds = 30 * 60

        XCTAssertEqual(Calendar.current.component(.day, from: entry.shiftEnd ?? day), 13)
        XCTAssertEqual(try? CalculationService().workedSeconds(for: entry).get(), 7 * 3600 + 30 * 60)
    }

    func testOvernightShiftCountsInStartMonthAndStaysActiveAfterMidnight() {
        let service = CalculationService()
        let settings = Settings(payMode: .hourly, hourlyRateCents: 2000)
        let day = dateFrom(year: 2026, month: 5, day: 31)
        let range = ShiftTimeRange(startMinute: 22 * 60, endClockMinute: 6 * 60)
        let entry = DayEntry(date: day, type: .work)
        entry.shiftStart = range?.startDate(on: day)
        entry.shiftEnd = range?.endDate(on: day)
        entry.breakSeconds = 30 * 60

        let mayStart = dateFrom(year: 2026, month: 5, day: 1)
        let mayEnd = dateFrom(year: 2026, month: 5, day: 31).addingTimeInterval(24 * 3600 - 1)
        let summary = service.periodSummary(entries: [entry], from: mayStart, to: mayEnd, settings: settings)
        let afterMidnight = dateFrom(year: 2026, month: 6, day: 1).addingTimeInterval(2 * 3600)
        let active = service.activeShiftEntry(at: afterMidnight, entries: [entry])

        XCTAssertEqual(summary.totalSeconds, 7 * 3600 + 30 * 60)
        XCTAssertEqual(active?.shiftStart, entry.shiftStart)
    }

    func testCSVTransferRoundTripsOvernightEndDayOffset() {
        let day = dateFrom(year: 2026, month: 5, day: 12)
        let range = ShiftTimeRange(startMinute: 22 * 60, endClockMinute: 6 * 60)
        let entry = DayEntry(date: day, type: .work)
        entry.shiftStart = range?.startDate(on: day)
        entry.shiftEnd = range?.endDate(on: day)
        entry.breakSeconds = 30 * 60

        let columns = ShiftCSVTransfer.exportColumns(for: entry)
        let csv = """
        categoryIcon,date,start,end,endDayOffset,breakMinutes,type
        briefcase.fill,2026-05-12,22:00,06:00,1,30,work
        """
        let parsed = ShiftCSVTransfer.parse(csv: csv).rows.first

        XCTAssertEqual(columns.endDayOffset, "1")
        XCTAssertEqual(parsed?.endMinuteOffset, 30 * 60)
        XCTAssertEqual(parsed?.breakMinutes, 30)
        XCTAssertEqual(parsed?.hasValidTimeRange, true)
    }

    func testLegalBreakToleranceCorrectionAtSixHoursWindow() {
        let entry = DayEntry(date: Date(), type: .work, manualWorkedSeconds: 6 * 3600 + 10 * 60)
        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 6 * 3600)
    }

    func testLegalBreakToleranceCorrectionDoesNotApplyToManualType() {
        let entry = DayEntry(date: Date(), type: .manual, manualWorkedSeconds: 6 * 3600 + 10 * 60)
        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 6 * 3600 + 10 * 60)
    }

    func testLegalBreakToleranceCorrectionAtNineHoursWindow() {
        let entry = DayEntry(date: Date(), type: .work, manualWorkedSeconds: 9 * 3600 + 12 * 60)
        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 9 * 3600)
    }

    func testLegalBreakToleranceCorrectionAtSixHoursEdgeFifteenMinutes() {
        let entry = DayEntry(date: Date(), type: .work, manualWorkedSeconds: 6 * 3600 + 15 * 60)
        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 6 * 3600)
    }

    func testNoMandatoryBreakAppliedAtSixHoursFifteenMinutesWithoutExplicitBreak() {
        let start = dateFrom(year: 2026, month: 2, day: 17)
        let end = start.addingTimeInterval(6 * 3600 + 15 * 60)
        let segment = TimeSegment(start: start, end: end, breakSeconds: 0)
        let entry = DayEntry(date: start, type: .work, segments: [segment])

        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 6 * 3600)
    }

    func testNoToleranceCorrectionOutsideWindow() {
        let entry = DayEntry(date: Date(), type: .work, manualWorkedSeconds: 6 * 3600 + 20 * 60)
        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 6 * 3600 + 20 * 60)
    }

    func testUnderSixHoursWithBreakOnlySubtractsEnteredBreak() {
        let start = dateFrom(year: 2026, month: 2, day: 17)
        let end = start.addingTimeInterval(5 * 3600 + 50 * 60)
        let segment = TimeSegment(start: start, end: end, breakSeconds: 10 * 60)
        let entry = DayEntry(date: start, type: .work, segments: [segment])

        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 5 * 3600 + 40 * 60)
    }

    func testOverSixHoursWithTooLittleBreakSubtractsComplementToThirtyMinutes() {
        let start = dateFrom(year: 2026, month: 2, day: 17)
        let end = start.addingTimeInterval(7 * 3600)
        let segment = TimeSegment(start: start, end: end, breakSeconds: 10 * 60)
        let entry = DayEntry(date: start, type: .work, segments: [segment])

        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 6 * 3600 + 30 * 60)
    }

    func testOverNineHoursWithTooLittleBreakSubtractsComplementToFortyFiveMinutes() {
        let start = dateFrom(year: 2026, month: 2, day: 17)
        let end = start.addingTimeInterval(10 * 3600)
        let segment = TimeSegment(start: start, end: end, breakSeconds: 30 * 60)
        let entry = DayEntry(date: start, type: .work, segments: [segment])

        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 9 * 3600)
    }

    func testNineHoursWithoutExplicitBreakOnlyAppliesThirtyMinutes() {
        let start = dateFrom(year: 2026, month: 2, day: 17)
        let end = start.addingTimeInterval(9 * 3600)
        let segment = TimeSegment(start: start, end: end, breakSeconds: 0)
        let entry = DayEntry(date: start, type: .work, segments: [segment])

        let result = CalculationService().workedSeconds(for: entry)
        XCTAssertEqual(try? result.get(), 8 * 3600 + 30 * 60)
    }

    func testLookbackSufficientHistoryOK() {
        let settings = Settings(hasCompletedOnboarding: true, payMode: .hourly, hourlyRateCents: 2000, strictHistoryRequired: true)
        let targetDate = dateFrom(year: 2026, month: 5, day: 20)
        let target = DayEntry(date: targetDate, type: .vacation)
        var entries: [DayEntry] = [target]

        for i in 1...13 {
            let refDate = targetDate.addingDays(i * -7, calendar: calendar)
            entries.append(DayEntry(date: refDate, type: .work, manualWorkedSeconds: 28800))
        }

        let service = CalculationService()
        let result = service.creditedResult(for: target, entriesByDate: service.makeEntriesByDateLookup(from: entries), settings: settings)
        if case let .ok(valueSeconds, _) = result {
            XCTAssertEqual(valueSeconds, 28800)
        } else {
            XCTFail("Expected ok")
        }
    }

    func testLookbackInsufficientHistoryReturnsZeroWarning() {
        let settings = Settings(hasCompletedOnboarding: true, strictHistoryRequired: true)
        let target = DayEntry(date: date(daysBack: 0), type: .sick)
        let service = CalculationService()
        let result = service.creditedResult(for: target, entriesByDate: service.makeEntriesByDateLookup(from: [target]), settings: settings)
        if case let .warning(valueSeconds, _, _) = result {
            XCTAssertEqual(valueSeconds, 0)
        } else {
            XCTFail("Expected warning with zero value")
        }
    }

    func testMissingEntriesAlwaysCountAsZero() {
        let target = DayEntry(date: date(daysBack: 0), type: .vacation)

        let service = CalculationService()
        let strictOffZeroOff = Settings(countMissingAsZero: false, strictHistoryRequired: false)
        let r1 = service.creditedResult(for: target, entriesByDate: service.makeEntriesByDateLookup(from: [target]), settings: strictOffZeroOff)
        if case .error = r1 {} else { XCTFail("Expected missing history error") }

        let strictOffZeroOn = Settings(countMissingAsZero: true, strictHistoryRequired: false)
        let r2 = service.creditedResult(for: target, entriesByDate: service.makeEntriesByDateLookup(from: [target]), settings: strictOffZeroOn)
        if case .warning = r2 {} else { XCTFail("Expected warning") }
    }

    func testAllZerosTriggersWarning() {
        let settings = Settings(strictHistoryRequired: true)
        let target = DayEntry(date: date(daysBack: 0), type: .vacation)
        var entries: [DayEntry] = [target]
        for i in 1...13 {
            entries.append(DayEntry(date: date(daysBack: i * 7), type: .work))
        }
        let service = CalculationService()
        let result = service.creditedResult(for: target, entriesByDate: service.makeEntriesByDateLookup(from: entries), settings: settings)
        if case let .warning(valueSeconds, _, _) = result {
            XCTAssertEqual(valueSeconds, 0)
        } else {
            XCTFail("Expected warning")
        }
    }

    func testWeekGroupingByWeekStart() {
        let service = CalculationService()
        let date = dateFrom(year: 2026, month: 2, day: 18)
        let mondayStart = service.weekStartDate(for: date, weekStart: .monday)
        let sundayStart = service.weekStartDate(for: date, weekStart: .sunday)
        XCTAssertNotEqual(mondayStart, sundayStart)
    }

    func testHolidayCreditMode() {
        let service = CalculationService()
        let zero = Settings(weeklyTargetSeconds: 180000, holidayCreditingMode: .zero)
        XCTAssertEqual(service.holidayCreditedSeconds(settings: zero), 0)

        let distributed = Settings(weeklyTargetSeconds: 180000, holidayCreditingMode: .weeklyTargetDistributed, scheduledWorkdaysCount: 5)
        XCTAssertEqual(service.holidayCreditedSeconds(settings: distributed), 36000)
    }

    func testHolidayUsesThirteenWeekRuleInStrictMode() {
        let settings = Settings(strictHistoryRequired: true, holidayCreditingMode: .lookback13Weeks)
        let holiday = DayEntry(date: date(daysBack: 0), type: .holiday)
        let result = CalculationService().dayComputation(for: holiday, allEntries: [holiday], settings: settings)

        if case let .warning(valueSeconds, _, _) = result {
            XCTAssertEqual(valueSeconds, 0)
        } else {
            XCTFail("Expected warning because missing history is counted as zero.")
        }
    }

    func testExportComputationUsesStoredCreditedHolidayValue() {
        let settings = Settings(
            payMode: .hourly,
            hourlyRateCents: 2000,
            countMissingAsZero: false,
            strictHistoryRequired: true,
            holidayCreditingMode: .lookback13Weeks
        )
        let holiday = DayEntry(
            date: date(daysBack: 0),
            type: .holiday,
            manualWorkedSeconds: 8 * 3600
        )
        let result = CalculationService().exportComputation(for: holiday, allEntries: [holiday], settings: settings)

        if case let .ok(valueSeconds, valueCents) = result {
            XCTAssertEqual(valueSeconds, 8 * 3600)
            XCTAssertEqual(valueCents, 16000)
        } else {
            XCTFail("Expected export to use the saved credited value.")
        }
    }

    func testMissingWeeksAreIncludedAsZeroInAverage() {
        let settings = Settings(strictHistoryRequired: true)
        let target = DayEntry(date: date(daysBack: 0), type: .vacation)
        let oneReference = DayEntry(date: date(daysBack: 7), type: .work, manualWorkedSeconds: 13000)
        let service = CalculationService()
        let result = service.creditedResult(
            for: target,
            entriesByDate: service.makeEntriesByDateLookup(from: [target, oneReference]),
            settings: settings
        )

        if case let .ok(valueSeconds, _) = result {
            XCTAssertEqual(valueSeconds, 1020)
        } else {
            XCTFail("Expected ok with averaged value including missing weeks as zero.")
        }
    }

    func testVacationCanUseFixedValueMode() {
        let settings = Settings(
            payMode: .hourly,
            hourlyRateCents: 2000,
            vacationCreditingMode: .fixedValue,
            vacationFixedSeconds: 7 * 3600 + 30 * 60
        )
        let vacation = DayEntry(date: date(daysBack: 0), type: .vacation)
        let result = CalculationService().dayComputation(for: vacation, allEntries: [vacation], settings: settings)

        if case let .ok(valueSeconds, valueCents) = result {
            XCTAssertEqual(valueSeconds, 7 * 3600 + 30 * 60)
            XCTAssertEqual(valueCents, 15000)
        } else {
            XCTFail("Expected fixed vacation value to be used.")
        }
    }

    func testVacationFixedValueFallsBackToZeroWhenUnset() {
        let settings = Settings(vacationCreditingMode: .fixedValue, vacationFixedSeconds: nil)
        let vacation = DayEntry(date: date(daysBack: 0), type: .vacation)
        let result = CalculationService().dayComputation(for: vacation, allEntries: [vacation], settings: settings)

        if case let .ok(valueSeconds, _) = result {
            XCTAssertEqual(valueSeconds, 0)
        } else {
            XCTFail("Expected zero when no fixed vacation value is set.")
        }
    }

    func testVacationOverrideTakesPrecedenceOverFixedValue() {
        let settings = Settings(vacationCreditingMode: .fixedValue, vacationFixedSeconds: 8 * 3600)
        let vacation = DayEntry(
            date: date(daysBack: 0),
            type: .vacation,
            creditedOverrideSeconds: 6 * 3600 + 15 * 60
        )
        let result = CalculationService().dayComputation(for: vacation, allEntries: [vacation], settings: settings)

        if case let .ok(valueSeconds, _) = result {
            XCTAssertEqual(valueSeconds, 6 * 3600 + 15 * 60)
        } else {
            XCTFail("Expected override to have priority over fixed vacation value.")
        }
    }

    func testMonthlyNetUsesAllowanceForWageTaxBase() {
        let service = CalculationService()
        let net = service.monthlyNetEuro(
            grossEuro: 3000,
            bonusesEuro: 0,
            wageTaxPercent: 20,
            pensionPercent: 10,
            monthlyAllowanceEuro: 1000
        )
        XCTAssertEqual(net, 2300, accuracy: 0.001)
    }

    func testMonthlyNetHasZeroWageTaxWhenGrossBelowAllowance() {
        let service = CalculationService()
        let net = service.monthlyNetEuro(
            grossEuro: 900,
            bonusesEuro: 0,
            wageTaxPercent: 20,
            pensionPercent: 10,
            monthlyAllowanceEuro: 1000
        )
        XCTAssertEqual(net, 810, accuracy: 0.001)
    }

    private func date(daysBack: Int) -> Date {
        Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(daysBack * -86400)))
    }

    private func dateFrom(year: Int, month: Int, day: Int) -> Date {
        let comps = DateComponents(calendar: calendar, year: year, month: month, day: day)
        return comps.date ?? Date()
    }
}
