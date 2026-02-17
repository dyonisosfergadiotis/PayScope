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
        XCTAssertEqual(try? result.get(), 9 * 3600 + 15 * 60)
    }

    func testLookbackSufficientHistoryOK() {
        let settings = Settings(hasCompletedOnboarding: true, payMode: .hourly, hourlyRateCents: 2000, strictHistoryRequired: true)
        let target = DayEntry(date: date(daysBack: 0), type: .vacation)
        var entries: [DayEntry] = [target]

        for i in 1...13 {
            let refDate = date(daysBack: i * 7)
            entries.append(DayEntry(date: refDate, type: .work, manualWorkedSeconds: 28800))
        }

        let result = CalculationService().creditedResult(for: target, allEntries: entries, settings: settings)
        if case let .ok(valueSeconds, _) = result {
            XCTAssertEqual(valueSeconds, 28800)
        } else {
            XCTFail("Expected ok")
        }
    }

    func testLookbackInsufficientHistoryReturnsZeroWarning() {
        let settings = Settings(hasCompletedOnboarding: true, strictHistoryRequired: true)
        let target = DayEntry(date: date(daysBack: 0), type: .sick)
        let result = CalculationService().creditedResult(for: target, allEntries: [target], settings: settings)
        if case let .warning(valueSeconds, _, _) = result {
            XCTAssertEqual(valueSeconds, 0)
        } else {
            XCTFail("Expected warning with zero value")
        }
    }

    func testMissingEntriesAlwaysCountAsZero() {
        let target = DayEntry(date: date(daysBack: 0), type: .vacation)

        let strictOffZeroOff = Settings(strictHistoryRequired: false, countMissingAsZero: false)
        let r1 = CalculationService().creditedResult(for: target, allEntries: [target], settings: strictOffZeroOff)
        if case .warning = r1 {} else { XCTFail("Expected warning") }

        let strictOffZeroOn = Settings(strictHistoryRequired: false, countMissingAsZero: true)
        let r2 = CalculationService().creditedResult(for: target, allEntries: [target], settings: strictOffZeroOn)
        if case .warning = r2 {} else { XCTFail("Expected warning") }
    }

    func testAllZerosTriggersWarning() {
        let settings = Settings(strictHistoryRequired: true)
        let target = DayEntry(date: date(daysBack: 0), type: .vacation)
        var entries: [DayEntry] = [target]
        for i in 1...13 {
            entries.append(DayEntry(date: date(daysBack: i * 7), type: .work))
        }
        let result = CalculationService().creditedResult(for: target, allEntries: entries, settings: settings)
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
        let zero = Settings(holidayCreditingMode: .zero, weeklyTargetSeconds: 180000)
        XCTAssertEqual(service.holidayCreditedSeconds(settings: zero), 0)

        let distributed = Settings(holidayCreditingMode: .weeklyTargetDistributed, weeklyTargetSeconds: 180000, scheduledWorkdaysCount: 5)
        XCTAssertEqual(service.holidayCreditedSeconds(settings: distributed), 36000)
    }

    func testHolidayUsesThirteenWeekRuleInStrictMode() {
        let settings = Settings(strictHistoryRequired: true)
        let holiday = DayEntry(date: date(daysBack: 0), type: .holiday)
        let result = CalculationService().dayComputation(for: holiday, allEntries: [holiday], settings: settings)

        if case let .warning(valueSeconds, _, _) = result {
            XCTAssertEqual(valueSeconds, 0)
        } else {
            XCTFail("Expected warning because missing history is counted as zero.")
        }
    }

    func testMissingWeeksAreIncludedAsZeroInAverage() {
        let settings = Settings(strictHistoryRequired: true)
        let target = DayEntry(date: date(daysBack: 0), type: .vacation)
        let oneReference = DayEntry(date: date(daysBack: 7), type: .work, manualWorkedSeconds: 13000)
        let result = CalculationService().creditedResult(for: target, allEntries: [target, oneReference], settings: settings)

        if case let .ok(valueSeconds, _) = result {
            XCTAssertEqual(valueSeconds, 1020)
        } else {
            XCTFail("Expected ok with averaged value including missing weeks as zero.")
        }
    }

    private func date(daysBack: Int) -> Date {
        Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(daysBack * -86400)))
    }

    private func dateFrom(year: Int, month: Int, day: Int) -> Date {
        let comps = DateComponents(calendar: calendar, year: year, month: month, day: day)
        return comps.date ?? Date()
    }
}
