import SwiftUI
import SwiftData
import Combine

struct TodayFocusView: View {
    @Query(sort: \DayEntry.date) private var queryEntries: [DayEntry]
    @Bindable var settings: Settings
    let entriesOverride: [DayEntry]?

    @State private var now = Date()

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let service = CalculationService()

    private struct TimelineScaleItem: Identifiable {
        let minute: Int
        let label: String
        let progress: Double
        let isBoundary: Bool

        var id: String { "\(minute)-\(label)" }
    }

    private struct FocusShift {
        let entry: DayEntry
        let state: FocusShiftState
    }

    private enum FocusShiftState {
        case today
        case runningFromPreviousDay
        case upcomingAfterCompletedShift
        case upcoming
    }

    init(settings: Settings, entriesOverride: [DayEntry]? = nil) {
        self.settings = settings
        self.entriesOverride = entriesOverride
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompactSheet = geometry.size.height < 700
            let isNarrow = geometry.size.width < 390
            let horizontalPadding: CGFloat = isNarrow ? 14 : 16
            let cardSpacing: CGFloat = isCompactSheet || isNarrow ? 12 : 14
            let verticalSpacing: CGFloat = isCompactSheet || isNarrow ? 14 : 18

                VStack(spacing: verticalSpacing) {
                    header(isCompact: isCompactSheet || isNarrow)

                    shiftCard(isCompact: isCompactSheet || isNarrow)

                    metricsGrid(spacing: cardSpacing, isCompact: isCompactSheet || isNarrow)
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 20)
        }
        .onReceive(refreshTimer) { value in
            now = value
        }
        .animation(.snappy(duration: 0.35), value: focusAccentAnimationKey)
        //.payScopeBackground(accent: focusAccentColor)
    }

    private var todayStart: Date {
        now.startOfDayLocal()
    }

    private var timelineAnchorStart: Date {
        focusShift?.entry.date.startOfDayLocal() ?? todayStart
    }

    private var entries: [DayEntry] {
        entriesOverride ?? queryEntries
    }

    private var focusAccentColor: Color {
        if let type = focusShift?.entry.type {
            return settings.categoryColor(for: type)
        }
        if let type = nextEntry?.type {
            return settings.categoryColor(for: type)
        }
        return settings.categoryColor(for: .work)
    }

    private var focusAccentAnimationKey: String {
        let type = todayEntry?.type ?? nextEntry?.type
        let color = type.flatMap(settings.categoryColorSelection(for:))?.rawValue ?? settings.themeAccent.rawValue
        return "\(type?.rawValue ?? "empty")-\(color)"
    }

    private var todayEntryForToday: DayEntry? {
        entries.first(where: { $0.date.isSameLocalDay(as: todayStart) })
    }

    private var focusShift: FocusShift? {
        if let active = service.activeShiftEntry(at: now, entries: entries) {
            let state: FocusShiftState = active.date.isSameLocalDay(as: todayStart) ? .today : .runningFromPreviousDay
            return FocusShift(entry: active, state: state)
        }

        if let today = todayEntryForToday {
            if let end = today.shiftEnd, now >= end.addingTimeInterval(15 * 60),
               let next = nextShiftEntry(after: now) {
                return FocusShift(entry: next, state: .upcomingAfterCompletedShift)
            }

            return FocusShift(entry: today, state: .today)
        }

        if let next = nextShiftEntry(after: now) {
            return FocusShift(entry: next, state: .upcoming)
        }

        return nil
    }

    private var todayEntry: DayEntry? {
        focusShift?.entry
    }

    private var nextEntry: DayEntry? {
        nextShiftEntry(after: now)
    }

    private var isShowingUpcomingShift: Bool {
        switch focusShift?.state {
        case .upcomingAfterCompletedShift, .upcoming:
            return true
        case .today, .runningFromPreviousDay, .none:
            return false
        }
    }

    private var workedSeconds: Int {
        guard let day = todayEntry else { return 0 }
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }
        if let start = day.shiftStart, let end = day.shiftEnd, end > start {
            let gross = max(0, Int(end.timeIntervalSince(start)))
            guard settings.effectiveCalculateBreaks else { return gross }
            let breakSeconds = max(0, day.breakSeconds ?? 0)
            return max(0, gross - breakSeconds)
        }
        return 0
    }

    private var breakSeconds: Int {
        guard let day = todayEntry else { return 0 }
        return max(0, day.breakSeconds ?? 0)
    }

    private var displayWorkedSeconds: Int {
        guard let todayEntry else { return 0 }

        if todayEntry.type == .work,
           todayEntry.manualWorkedSeconds == nil,
           let start = todayEntry.shiftStart,
           let end = todayEntry.shiftEnd,
           end > start {
            return workedSeconds(until: now, for: todayEntry)
        }

        return service.dayComputation(for: todayEntry, allEntries: entries, settings: settings).valueSecondsOrZero
    }

    private var displayPayCents: Int {
        service.payCents(for: todayEarnedSecondsSoFar, settings: settings)
    }

    private var totalShiftSeconds: Int {
        guard let day = todayEntry else {
            return plannedDaySeconds ?? 0
        }

        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }

        if let start = day.shiftStart, let end = day.shiftEnd, end > start {
            let gross = max(0, Int(end.timeIntervalSince(start)))
            guard settings.effectiveCalculateBreaks else { return gross }
            return max(0, gross - breakSeconds)
        }

        return service.dayComputation(for: day, allEntries: entries, settings: settings).valueSecondsOrZero
    }

    private var shiftProgress: Double {
        guard totalShiftSeconds > 0 else { return 0 }
        return min(max(Double(displayWorkedSeconds) / Double(totalShiftSeconds), 0), 1)
    }

    private var shiftRemainingSeconds: Int {
        max(0, totalShiftSeconds - displayWorkedSeconds)
    }

    private var plannedDaySeconds: Int? {
        guard let weekly = settings.weeklyTargetSeconds else { return nil }
        let days = max(1, settings.scheduledWorkdaysCount)
        return max(0, Int((Double(weekly) / Double(days)).rounded()))
    }

    private var remainingSeconds: Int? {
        guard let planned = plannedDaySeconds else { return nil }
        return max(0, planned - workedSeconds)
    }

    private var dayBounds: ClosedRange<Int> {
        guard
            let day = todayEntry,
            let start = day.shiftStart,
            let end = day.shiftEnd,
            let range = ShiftTimeRange(anchorDate: day.date, start: start, end: end),
            range.crossesMidnight
        else {
            return 0...(24 * 60)
        }

        let lower = min(18 * 60, max(0, range.startMinute - 60))
        let upper = max(30 * 60, min(ShiftTimeRange.maxEndMinuteOffset, range.endMinuteOffset + 60))
        return lower...upper
    }

    private var shiftTimeRange: ShiftTimeRange? {
        guard
            let day = todayEntry,
            let start = day.shiftStart,
            let end = day.shiftEnd
        else {
            return nil
        }
        return ShiftTimeRange(anchorDate: day.date, start: start, end: end)
    }

    private var workedIntervals: [ClosedRange<Double>] {
        guard let day = todayEntry else { return [] }

        if let manual = day.manualWorkedSeconds {
            let span = Double(max(1, dayBounds.upperBound - dayBounds.lowerBound))
            let manualMinutes = min(span, Double(max(0, manual)) / 60.0)
            guard manualMinutes > 0 else { return [] }
            let start = Double(dayBounds.lowerBound)
            return [start...(start + manualMinutes)]
        }

        guard let startDate = day.shiftStart, let endDate = day.shiftEnd, endDate > startDate else {
            return []
        }
        let start = max(Double(dayBounds.lowerBound), min(Double(dayBounds.upperBound), minuteOffset(from: timelineAnchorStart, to: startDate)))
        let end = max(Double(dayBounds.lowerBound), min(Double(dayBounds.upperBound), minuteOffset(from: timelineAnchorStart, to: endDate)))
        guard end > start else { return [] }
        return [start...end]
    }

    private var dayStartDate: Date {
        dateAtMinute(dayBounds.lowerBound, on: timelineAnchorStart)
    }

    private var dayEndDate: Date {
        dateAtMinute(dayBounds.upperBound, on: timelineAnchorStart)
    }

    private var dayProgress: Double {
        let total = dayEndDate.timeIntervalSince(dayStartDate)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(dayStartDate)
        return min(max(elapsed / total, 0), 1)
    }

    private var nowMinuteOfDay: Double {
        minuteOffset(from: timelineAnchorStart, to: now)
    }

    private var workedDisplayLabel: String {
        "\(PayScopeFormatters.hhmmString(seconds: displayWorkedSeconds)) h"
    }

    private var weekWorkedSeconds: Int {
        service.weekEarnedSecondsSoFar(entries: entries, asOf: now, settings: settings)
    }

    private var weekWorkedDisplayLabel: String {
        "\(PayScopeFormatters.hhmmString(seconds: weekWorkedSeconds)) h"
    }

    private var headerValueCaption: String {
        guard let todayEntry else { return "erfasst" }
        return todayEntry.type == .work ? "erfasst" : "gutgeschrieben"
    }

    private var showsRemainingHeader: Bool {
        todayEntry?.type == .work
    }

    private var todayEarnedSecondsSoFar: Int {
        service.todayEarnedSecondsSoFar(entries: entries, asOf: now, settings: settings)
    }

    private func header(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 14 : 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(PayScopeFormatters.day.string(from: timelineAnchorStart))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary.opacity(0.86))
                    Text(headerTitle)
                        .font(.system(isCompact ? .title : .largeTitle, design: .rounded).weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .payScopeTextTransition(value: headerTitle)
                }

                Spacer(minLength: 10)

                statusPill(isCompact: isCompact)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(workedDisplayLabel)
                    .font(.system(size: isCompact ? 34 : 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .payScopeNumericTransition(value: workedDisplayLabel)

                Text(headerValueCaption)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 10)

                if showsRemainingHeader {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(shiftRemainingText)
                            .font(.system(isCompact ? .headline : .title3, design: .rounded).weight(.black))
                            .foregroundStyle(focusAccentColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .payScopeNumericTransition(value: shiftRemainingText)
                        Text(remainingCaption)
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }
            }
        }
        .padding(isCompact ? 16 : 20)
        .payScopeGlassSurface(
            accent: focusAccentColor,
            cornerRadius: isCompact ? 24 : 28,
            tintOpacity: 0.07,
            shadowOpacity: 0.09,
            isInteractive: true
        )
        .payScopeLiquidGlassTapFeedback(
            accent: focusAccentColor,
            in: RoundedRectangle(cornerRadius: isCompact ? 24 : 28, style: .continuous),
            tintOpacity: 0.05
        )
    }

    private func statusPill(isCompact: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: todayTypeIcon)
                .font(.system(.caption, design: .rounded).weight(.black))
            Text(todayTypeLabel)
                .payScopeTextTransition(value: todayTypeLabel)
        }
        .font(.system(isCompact ? .caption : .callout, design: .rounded).weight(.bold))
        .foregroundStyle(todayTypeColor)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, isCompact ? 7 : 9)
        .payScopeGlassControl(
            accent: todayTypeColor,
            cornerRadius: isCompact ? 15 : 18,
            tintOpacity: 0.08,
            isInteractive: false
        )
    }

    private func shiftCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 14 : 18) {

            HStack(alignment: .firstTextBaseline, spacing: isCompact ? 8 : 12) {
                timeBlock(title: "Start", value: shiftStartLabel, isCompact: isCompact)

                VStack(spacing: isCompact ? 6 : 9) {
                    Rectangle()
                        .fill(focusAccentColor.opacity(0.18))
                        .frame(height: 1)
                    Text(compactDurationString(seconds: totalShiftSeconds))
                        .font(.system(isCompact ? .callout : .title3, design: .rounded).weight(.black))
                        .foregroundStyle(focusAccentColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .payScopeNumericTransition(value: totalShiftSeconds)
                        .minimumScaleFactor(0.7)
                    Rectangle()
                        .fill(focusAccentColor.opacity(0.18))
                        .frame(height: 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isCompact ? 8 : 12)

                timeBlock(title: "Ende", value: shiftEndLabel, alignment: .trailing, isCompact: isCompact)
            }

            VStack(spacing: isCompact ? 9 : 12) {
                progressTrack

                timelineLabels
            }
        }
        .padding(isCompact ? 16 : 20)
        .frame(maxWidth: .infinity)
        .payScopeGlassSurface(
            accent: focusAccentColor,
            cornerRadius: isCompact ? 22 : 26,
            tintOpacity: 0.06,
            shadowOpacity: 0.08,
            isInteractive: true
        )
        .payScopeLiquidGlassTapFeedback(
            accent: focusAccentColor,
            in: RoundedRectangle(cornerRadius: isCompact ? 22 : 26, style: .continuous),
            tintOpacity: 0.048
        )
    }

    private func metricsGrid(spacing: CGFloat, isCompact: Bool) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: isCompact ? 96 : 108), spacing: spacing)
        ]

        return LazyVGrid(columns: columns, spacing: spacing) {
            metricCard(
                icon: "stopwatch.fill",
                iconTint: focusAccentColor,
                value: weekWorkedDisplayLabel,
                label: "Diese Woche",
                isCompact: isCompact
            )
            metricCard(
                icon: "cup.and.saucer.fill",
                iconTint: .orange,
                value: breakSeconds > 0 ? "\(PayScopeFormatters.hhmmString(seconds: breakSeconds)) h" : "-",
                label: "Pause",
                isCompact: isCompact
            )
            metricCard(
                icon: "eurosign",
                iconTint: .green,
                value: PayScopeFormatters.currencyString(cents: displayPayCents),
                label: "Erarbeitet",
                valueTint: focusAccentColor,
                isCompact: isCompact
            )
        }
    }

    private var todayTypeLabel: String {
        if isShowingUpcomingShift {
            return todayEntry?.type.label ?? "Geplant"
        }
        if let today = todayEntry {
            return today.type.label
        }
        if let next = nextEntry {
            return "Nächste: \(PayScopeFormatters.day.string(from: next.date))"
        }
        return "Kein Eintrag"
    }

    private var todayTypeIcon: String {
        if isShowingUpcomingShift {
            return todayEntry?.type.icon ?? "calendar.badge.clock"
        }
        if todayEntry != nil {
            return todayEntry?.type.icon ?? "calendar.badge.exclamationmark"
        }
        return nextEntry != nil ? "calendar.badge.clock" : "calendar.badge.exclamationmark"
    }

    private var todayTypeColor: Color {
        if isShowingUpcomingShift {
            return focusAccentColor
        }
        if let today = todayEntry {
            return settings.categoryColor(for: today.type)
        }
        if let next = nextEntry {
            return settings.categoryColor(for: next.type)
        }
        return .secondary
    }

    private var todayHasShiftDeviation: Bool {
        todayEntry?.creditedOverrideSeconds != nil
    }

    private var shiftStartLabel: String {
        guard let range = shiftTimeRange else {
            guard let start = todayEntry?.shiftStart else { return "-" }
            return PayScopeFormatters.time.string(from: start)
        }
        return ShiftTimeRange.displayMinute(range.startMinute)
    }

    private var shiftEndLabel: String {
        guard let range = shiftTimeRange else {
            guard let end = todayEntry?.shiftEnd else { return "-" }
            return PayScopeFormatters.time.string(from: end)
        }
        return ShiftTimeRange.displayMinute(range.endMinuteOffset)
    }

    private var shiftRemainingText: String {
        guard todayEntry != nil else { return "kein Eintrag" }

        if isShowingUpcomingShift, let start = todayEntry?.shiftStart {
            return countdownDurationString(seconds: max(0, Int(start.timeIntervalSince(now))))
        }

        if totalShiftSeconds <= 0 {
            return "Ende"
        }

        return "\(compactDurationString(seconds: shiftRemainingSeconds))"
    }

    private var headerTitle: String {
        switch focusShift?.state {
        case .upcomingAfterCompletedShift:
            return "Nächste Schicht"
        case .upcoming:
            return "Geplant"
        case .runningFromPreviousDay:
            return "Läuft weiter"
        case .today:
            return "Heute"
        case .none:
            return "Heute"
        }
    }

    private var remainingCaption: String {
        isShowingUpcomingShift ? "Bis Start" : "Verbleibend"
    }

    private var progressTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let markerX = min(max(width * shiftProgress, 0), width)
            let scaleItems = timelineScaleItems(for: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(focusAccentColor.opacity(0.18))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                focusAccentColor.opacity(0.55),
                                focusAccentColor
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: markerX)

                ForEach(scaleItems) { item in
                    let tickWidth: CGFloat = item.isBoundary ? 2 : 1
                    let tickHeight: CGFloat = item.isBoundary ? 11 : 8
                    let tickX = min(max(width * item.progress - tickWidth / 2, 0), max(0, width - tickWidth))

                    RoundedRectangle(cornerRadius: tickWidth / 2, style: .continuous)
                        .fill(.white.opacity(item.isBoundary ? 0.62 : 0.42))
                        .frame(width: tickWidth, height: tickHeight)
                        .offset(x: tickX)
                }

                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(focusAccentColor, lineWidth: 3)
                    )
                    .shadow(color: focusAccentColor.opacity(0.34), radius: 4, x: 0, y: 2)
                    .offset(x: min(max(0, markerX - 8), max(0, width - 16)))
            }
        }
        .frame(height: 16)
    }

    private var timelineLabels: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let labelWidth = timelineLabelWidth
            let scaleItems = timelineScaleItems(for: width)

            ZStack(alignment: .topLeading) {
                ForEach(Array(scaleItems.enumerated()), id: \.element.id) { index, item in
                    let x = width * item.progress
                    let isFirst = index == 0
                    let isLast = index == scaleItems.count - 1
                    let alignment: Alignment = isFirst ? .leading : (isLast ? .trailing : .center)
                    let offset = isFirst ? 0 : (isLast ? max(0, width - labelWidth) : min(max(0, x - labelWidth / 2), max(0, width - labelWidth)))

                    Text(item.label)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: labelWidth, alignment: alignment)
                        .offset(x: offset)
                }
            }
        }
        .frame(height: 14)
    }

    private var timelineLabelWidth: CGFloat {
        shiftTimeRange?.crossesMidnight == true ? 68 : 52
    }

    private func timelineScaleItems(for width: CGFloat) -> [TimelineScaleItem] {
        guard let range = shiftTimeRange else {
            return [
                TimelineScaleItem(minute: 0, label: "Start", progress: 0, isBoundary: true),
                TimelineScaleItem(minute: 1, label: "50%", progress: 0.5, isBoundary: false),
                TimelineScaleItem(minute: 2, label: "Ende", progress: 1, isBoundary: true)
            ]
        }

        let duration = max(1, range.durationMinutes)
        let stepMinutes = timelineScaleStepMinutes(durationMinutes: duration, width: width)
        var minutes = [range.startMinute]
        var tick = ((range.startMinute / stepMinutes) + 1) * stepMinutes

        while tick < range.endMinuteOffset {
            minutes.append(tick)
            tick += stepMinutes
        }

        if minutes.last != range.endMinuteOffset {
            minutes.append(range.endMinuteOffset)
        }

        let items = minutes.map { minute in
            TimelineScaleItem(
                minute: minute,
                label: ShiftTimeRange.displayMinute(minute),
                progress: min(max(Double(minute - range.startMinute) / Double(duration), 0), 1),
                isBoundary: minute == range.startMinute || minute == range.endMinuteOffset
            )
        }

        return spacedTimelineScaleItems(items, width: width)
    }

    private func timelineScaleStepMinutes(durationMinutes: Int, width: CGFloat) -> Int {
        let minGap = max(44, timelineLabelWidth * 0.84)
        let maxLabels = max(3, min(12, Int(width / minGap) + 1))
        let maxInteriorLabels = max(1, maxLabels - 2)
        let idealStep = Double(durationMinutes) / Double(maxInteriorLabels + 1)
        let roundedStep = max(30, Int(ceil(idealStep / 30.0)) * 30)
        let allowedSteps = [30, 60, 120, 180, 240, 360, 720]
        return allowedSteps.first { $0 >= roundedStep } ?? 720
    }

    private func spacedTimelineScaleItems(_ items: [TimelineScaleItem], width: CGFloat) -> [TimelineScaleItem] {
        guard items.count > 2 else { return items }

        let minGap = max(44, timelineLabelWidth * 0.84)
        let start = items[0]
        let end = items[items.count - 1]
        var result = [start]

        for item in items.dropFirst().dropLast() {
            let x = width * item.progress
            let previousX = width * (result.last?.progress ?? 0)
            let endX = width * end.progress

            guard x - previousX >= minGap, endX - x >= minGap else {
                continue
            }

            result.append(item)
        }

        result.append(end)
        return result
    }

    private var pauseBlocksCount: Int {
        guard let day = todayEntry else { return 0 }
        return max(0, day.breakSeconds ?? 0) > 0 ? 1 : 0
    }

    private var pauseInfoText: String {
        guard breakSeconds > 0 else { return "Keine Pause" }
        if pauseBlocksCount > 0 {
            let suffix = pauseBlocksCount == 1 ? "Block" : "Blöcke"
            return "\(PayScopeFormatters.hhmmString(seconds: breakSeconds)) in \(pauseBlocksCount) \(suffix)"
        }
        return PayScopeFormatters.hhmmString(seconds: breakSeconds)
    }

    private var trackedInfoText: String {
        guard let day = todayEntry else { return "Kein Eintrag" }
        if day.manualWorkedSeconds != nil {
            return "Manuell erfasst"
        }
        guard
            let first = day.shiftStart,
            let last = day.shiftEnd,
            last > first
        else {
            return "Keine Schichtzeit"
        }
        return ShiftTimeRange.displayRange(start: first, end: last)
    }

    private var targetInfoTitle: String {
        guard let remaining = remainingSeconds else { return "Sollzeit" }
        return remaining > 0 ? "Sollzeit offen" : "Sollzeit"
    }

    private var targetInfoText: String {
        guard let remaining = remainingSeconds else { return "Kein Sollwert gesetzt" }
        return remaining > 0 ? "Noch \(PayScopeFormatters.hhmmString(seconds: remaining))" : "Soll erreicht"
    }

    private var targetInfoIcon: String {
        guard let remaining = remainingSeconds else { return "target" }
        return remaining > 0 ? "timer" : "checkmark.seal.fill"
    }

    private var nowInfoText: String {
        let percent = Int((dayProgress * 100).rounded())
        return "\(PayScopeFormatters.time.string(from: now)) · \(percent)% des Tages"
    }

    private func detailColumns(isCompact: Bool) -> [GridItem] {
        [
            GridItem(.flexible(), spacing: isCompact ? 8 : 10),
            GridItem(.flexible(), spacing: isCompact ? 8 : 10)
        ]
    }

    private func detailTile(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundStyle(focusAccentColor)
                .frame(width: 28, height: 28)
                .payScopeLiquidGlassIcon(accent: focusAccentColor, tintOpacity: 0.11, shadowOpacity: 0.06)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(value)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .payScopeNumericTransition(value: value)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .payScopeGlassControl(
            accent: focusAccentColor,
            cornerRadius: 16,
            tintOpacity: 0.045,
            isInteractive: false
        )
    }

    private func timeBlock(
        title: String,
        value: String,
        alignment: HorizontalAlignment = .leading,
        isCompact: Bool
    ) -> some View {
        VStack(alignment: alignment, spacing: isCompact ? 5 : 7) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.black))
                .textCase(.uppercase)
                .foregroundStyle(.secondary.opacity(0.78))
            Text(value)
                .font(.system(size: isCompact ? 30 : 38, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .payScopeNumericTransition(value: value)
        }
        .frame(minWidth: isCompact ? 76 : 98, alignment: alignment == .trailing ? .trailing : .leading)
    }

    private func metricCard(
        icon: String,
        iconTint: Color,
        value: String,
        label: String,
        valueTint: Color = .primary,
        isCompact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 9 : 12) {
            Image(systemName: icon)
                .font(.system(isCompact ? .caption : .subheadline, design: .rounded).weight(.black))
                .foregroundStyle(iconTint)
                .frame(width: isCompact ? 34 : 40, height: isCompact ? 34 : 40)
                .payScopeLiquidGlassIcon(
                    accent: iconTint,
                    in: RoundedRectangle(cornerRadius: isCompact ? 11 : 14, style: .continuous),
                    tintOpacity: 0.13,
                    shadowOpacity: 0.07
                )

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(isCompact ? .headline : .title3, design: .rounded).weight(.black))
                    .foregroundStyle(valueTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .payScopeNumericTransition(value: value)
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary.opacity(0.78))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(isCompact ? 12 : 16)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 112 : 132, alignment: .topLeading)
        .payScopeGlassSurface(
            accent: focusAccentColor,
            cornerRadius: isCompact ? 18 : 22,
            tintOpacity: 0.05,
            shadowOpacity: 0.06,
            isInteractive: true
        )
        .payScopeLiquidGlassTapFeedback(
            accent: iconTint,
            in: RoundedRectangle(cornerRadius: isCompact ? 18 : 22, style: .continuous),
            tintOpacity: 0.048
        )
    }

    private func compactDurationString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60

        if minutes == 0 {
            return "\(hours) h"
        }
        if hours == 0 {
            return "\(minutes) min"
        }
        return String(format: "%d:%02d h", hours, minutes)
    }

    private func countdownDurationString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let days = clamped / 86_400
        let hours = (clamped % 86_400) / 3_600
        let minutes = (clamped % 3_600) / 60

        if days == 0 {
            return String(format: "%02d:%02d", hours, minutes)
        }

        return String(format: "%02d:%02d:%02d", days, hours, minutes)
    }

    private func workedSeconds(until now: Date, for day: DayEntry?) -> Int {
        guard let day else { return 0 }
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }

        if let start = day.shiftStart, let end = day.shiftEnd, end > start {
            guard now > start else { return 0 }
            let effectiveEnd = min(now, end)
            let elapsedSeconds = max(0, Int(effectiveEnd.timeIntervalSince(start)))
            guard settings.effectiveCalculateBreaks else { return elapsedSeconds }
            let totalShiftSeconds = max(1, Int(end.timeIntervalSince(start)))
            let breakSeconds = max(0, day.breakSeconds ?? 0)
            let elapsedBreak = Int((Double(breakSeconds) * Double(elapsedSeconds) / Double(totalShiftSeconds)).rounded())
            return max(0, elapsedSeconds - elapsedBreak)
        }

        return 0
    }

    private func nextShiftEntry(after referenceDate: Date) -> DayEntry? {
        entries
            .filter { entry in
                guard entry.type == .work || entry.type == .manual else { return false }
                guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else { return false }
                return start > referenceDate
            }
            .min { lhs, rhs in
                (lhs.shiftStart ?? .distantFuture) < (rhs.shiftStart ?? .distantFuture)
            }
    }

    private func dateAtMinute(_ minute: Int, on dayStart: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: minute, to: dayStart.startOfDayLocal()) ?? dayStart
    }

    private func minuteOffset(from start: Date, to end: Date) -> Double {
        let minutes = Calendar.current.dateComponents([.minute], from: start.startOfDayLocal(), to: end).minute
            ?? Int(end.timeIntervalSince(start.startOfDayLocal()) / 60)
        return Double(minutes)
    }
}

private struct TodayFocusRingChart: View {
    let bounds: ClosedRange<Int>
    let workedIntervals: [ClosedRange<Double>]
    let nowMinuteOfDay: Double
    let workedLabel: String
    let breakSeconds: Int
    let accent: Color

    private var totalMinutes: Double {
        max(1, Double(bounds.upperBound - bounds.lowerBound))
    }

    private var tickMinutes: [Int] {
        var ticks: [Int] = [bounds.lowerBound]
        var current = ((bounds.lowerBound + 59) / 60) * 60
        while current < bounds.upperBound {
            if current > bounds.lowerBound {
                ticks.append(current)
            }
            current += 60
        }
        if ticks.last != bounds.upperBound {
            ticks.append(bounds.upperBound)
        }
        return ticks
    }

    private var hourLabelMinutes: [Int] {
        tickMinutes.filter { $0 != bounds.lowerBound && $0 != bounds.upperBound }
    }

    private var hourTickMinutes: [Int] {
        hourLabelMinutes
    }

    private var segmentMarkers: [SegmentMarker] {
        workedIntervals.enumerated().flatMap { index, interval in
            [
                SegmentMarker(
                    id: "\(index)-start",
                    minute: interval.lowerBound,
                    label: formatTimeLabel(interval.lowerBound),
                    isStart: true
                ),
                SegmentMarker(
                    id: "\(index)-end",
                    minute: interval.upperBound,
                    label: formatTimeLabel(interval.upperBound),
                    isStart: false
                )
            ]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let ringWidth = max(12, side * 0.102)
            let center = CGPoint(x: side / 2, y: side / 2)
            let ringRadius = side * 0.35
            let circumference = 2 * CGFloat.pi * ringRadius
            let capPadProgress = Double((ringWidth * 0.5) / max(1, circumference))
            let ringInset = max(0, (side / 2) - ringRadius)
            let hourLabelRadius = ringRadius - (ringWidth * 0.92)
            let adaptiveHourLabels = adaptiveHourLabels(for: side, labelRadius: hourLabelRadius)
            let hourLabelPoints = adaptiveHourLabels.map {
                point(center: center, radius: hourLabelRadius, radians: angleInRadians(for: Double($0)))
            }
            let resolvedSegmentLabels = resolvedSegmentLabels(
                center: center,
                side: side,
                ringRadius: ringRadius,
                ringWidth: ringWidth,
                protectedPoints: hourLabelPoints
            )
            let nowAngle = angleInRadians(for: nowMinuteOfDay)
            let startAngle = angleInRadians(for: Double(bounds.lowerBound))
            let endAngle = angleInRadians(for: Double(bounds.upperBound))
            let nowPoint = point(center: center, radius: ringRadius, radians: nowAngle)
            let nowInnerPoint = point(center: center, radius: ringRadius - (ringWidth * 0.5), radians: nowAngle)
            let nowOuterPoint = point(center: center, radius: ringRadius + (ringWidth * 0.5), radians: nowAngle)
            let startInnerPoint = point(center: center, radius: ringRadius - (ringWidth * 0.52), radians: startAngle)
            let startOuterPoint = point(center: center, radius: ringRadius + (ringWidth * 0.52), radians: startAngle)
            let endInnerPoint = point(center: center, radius: ringRadius - (ringWidth * 0.52), radians: endAngle)
            let endOuterPoint = point(center: center, radius: ringRadius + (ringWidth * 0.52), radians: endAngle)

            ZStack {
                Circle()
                    .inset(by: ringInset)
                    .stroke(accent.opacity(0.1), style: StrokeStyle(lineWidth: ringWidth + 8, lineCap: .round))
                    .rotationEffect(Angle.degrees(-90))

                Circle()
                    .inset(by: ringInset)
                    .stroke(.white.opacity(0.26), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(Angle.degrees(-90))

                ForEach(Array(workedIntervals.enumerated()), id: \.offset) { _, interval in
                    Circle()
                        .inset(by: ringInset)
                        .trim(
                            from: min(max(progress(for: interval.lowerBound) + capPadProgress, 0), 1),
                            to: min(max(progress(for: interval.upperBound) - capPadProgress, 0), 1)
                        )
                        .stroke(
                            LinearGradient(
                                colors: [accent.opacity(0.95), accent.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .opacity(progress(for: interval.upperBound) - progress(for: interval.lowerBound) > (capPadProgress * 2) ? 1 : 0)
                        .rotationEffect(Angle.degrees(-90))
                        .shadow(color: accent.opacity(0.24), radius: 5, x: 0, y: 2)
                }

                Canvas { context, size in
                    let drawCenter = CGPoint(x: size.width / 2, y: size.height / 2)
                    let drawRadius = ringRadius

                    for minute in hourTickMinutes {
                        let radians = angleInRadians(for: Double(minute))
                        let innerRadius = drawRadius - (ringWidth * 0.4)
                        let outerRadius = drawRadius + (ringWidth * 0.4)

                        var tickPath = Path()
                        tickPath.move(to: point(center: drawCenter, radius: innerRadius, radians: radians))
                        tickPath.addLine(to: point(center: drawCenter, radius: outerRadius, radians: radians))

                        context.stroke(
                            tickPath,
                            with: .color(Color.secondary.opacity(0.4)),
                            lineWidth: 1
                        )
                    }
                }

                Path { path in
                    path.move(to: startInnerPoint)
                    path.addLine(to: startOuterPoint)
                }
                .stroke(style: StrokeStyle(lineWidth: 2.2))
                .foregroundStyle(accent.opacity(0.95))

                Path { path in
                    path.move(to: endInnerPoint)
                    path.addLine(to: endOuterPoint)
                }
                .stroke(style: StrokeStyle(lineWidth: 1.4))
                .foregroundStyle(.white.opacity(0.8))

                ForEach(adaptiveHourLabels, id: \.self) { minute in
                    Text(hourLabel(for: minute))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .position(
                            point(center: center, radius: hourLabelRadius, radians: angleInRadians(for: Double(minute)))
                        )
                }

                ForEach(resolvedSegmentLabels) { item in
                    Circle()
                        .fill(item.isStart ? accent : .white.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .position(item.markerPoint)

                    Text(item.label)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(.secondarySystemBackground).opacity(0.94),
                                            accent.opacity(0.14),
                                            Color(.systemBackground).opacity(0.98)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(accent.opacity(0.22), lineWidth: 0.8)
                        )
                        .position(item.labelPoint)
                }

                Path { path in
                    path.move(to: nowInnerPoint)
                    path.addLine(to: nowOuterPoint)
                }
                .stroke(style: StrokeStyle(lineWidth: 1.3))
                .foregroundStyle(.white.opacity(0.92))

                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.9), lineWidth: 1.5)
                    )
                    .shadow(color: accent.opacity(0.45), radius: 4, x: 0, y: 0)
                    .position(nowPoint)

                VStack(spacing: 3) {
                    Text(workedLabel)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("Pause \(PayScopeFormatters.hhmmString(seconds: breakSeconds))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 18)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func progress(for minute: Double) -> Double {
        let clamped = min(max(minute, Double(bounds.lowerBound)), Double(bounds.upperBound))
        return (clamped - Double(bounds.lowerBound)) / totalMinutes
    }

    private func angleInRadians(for minute: Double) -> CGFloat {
        CGFloat(((progress(for: minute) * 360) - 90) * .pi / 180)
    }

    private func point(center: CGPoint, radius: CGFloat, radians: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }

    private func adaptiveHourLabels(for side: CGFloat, labelRadius: CGFloat) -> [Int] {
        let candidates = hourLabelMinutes
        guard !candidates.isEmpty else { return [] }

        let circumference = 2 * .pi * labelRadius
        let minSpacing: CGFloat = side < 190 ? 36 : 32
        let maxVisible = max(4, Int(circumference / minSpacing))
        let stride = max(1, Int(ceil(Double(candidates.count) / Double(maxVisible))))

        var result = candidates.enumerated().compactMap { index, minute in
            index.isMultiple(of: stride) ? minute : nil
        }
        if let first = candidates.first, !result.contains(first) {
            result.insert(first, at: 0)
        }
        return result
    }

    private func resolvedSegmentLabels(
        center: CGPoint,
        side: CGFloat,
        ringRadius: CGFloat,
        ringWidth: CGFloat,
        protectedPoints: [CGPoint]
    ) -> [ResolvedSegmentLabel] {
        let sorted = segmentMarkers.sorted { $0.minute < $1.minute }
        var placed: [CGPoint] = []
        var resolved: [ResolvedSegmentLabel] = []
        let safeRect = CGRect(x: 20, y: 14, width: side - 40, height: side - 28)
        let minimumOutsideRadius = ringRadius + (ringWidth * 1.2)
        let angleOffsets: [CGFloat] = [0, -0.1, 0.1, -0.18, 0.18, -0.26, 0.26, -0.34, 0.34]
        let radiusOffsets: [CGFloat] = [0, 10, 20, 30, 40]

        for marker in sorted {
            let baseAngle = angleInRadians(for: marker.minute)
            let markerPoint = point(center: center, radius: ringRadius + (ringWidth * 0.52), radians: baseAngle)
            let baseLabelRadius = ringRadius + (ringWidth * 1.4)

            var chosenPoint: CGPoint?

            outer: for radiusOffset in radiusOffsets {
                for angleOffset in angleOffsets {
                    let candidate = point(
                        center: center,
                        radius: baseLabelRadius + radiusOffset,
                        radians: baseAngle + angleOffset
                    )

                    guard safeRect.contains(candidate) else { continue }
                    guard distance(candidate, center) >= minimumOutsideRadius else { continue }
                    guard !hasCollision(candidate, with: placed, minDistance: 48) else { continue }
                    guard !hasCollision(candidate, with: protectedPoints, minDistance: 30) else { continue }
                    chosenPoint = candidate
                    break outer
                }
            }

            if chosenPoint == nil {
                var fallback = point(center: center, radius: baseLabelRadius + 46, radians: baseAngle)
                fallback = CGPoint(
                    x: min(max(safeRect.minX, fallback.x), safeRect.maxX),
                    y: min(max(safeRect.minY, fallback.y), safeRect.maxY)
                )
                if distance(fallback, center) < minimumOutsideRadius {
                    fallback = point(center: center, radius: minimumOutsideRadius + 8, radians: baseAngle)
                }

                var stabilized = fallback
                var tries = 0
                while hasCollision(stabilized, with: placed, minDistance: 48) && tries < 10 {
                    let direction: CGFloat = tries.isMultiple(of: 2) ? 1 : -1
                    let offsetAngle = baseAngle + (CGFloat(tries + 1) * 0.08 * direction)
                    stabilized = point(
                        center: center,
                        radius: minimumOutsideRadius + 22 + (CGFloat(tries) * 4),
                        radians: offsetAngle
                    )
                    tries += 1
                }
                chosenPoint = stabilized
            }

            let finalPoint = chosenPoint ?? point(center: center, radius: minimumOutsideRadius + 20, radians: baseAngle)

            placed.append(finalPoint)
            resolved.append(
                ResolvedSegmentLabel(
                    id: marker.id,
                    label: marker.label,
                    isStart: marker.isStart,
                    markerPoint: markerPoint,
                    labelPoint: finalPoint
                )
            )
        }

        return resolved
    }

    private func hasCollision(_ point: CGPoint, with points: [CGPoint], minDistance: CGFloat) -> Bool {
        points.contains { distance($0, point) < minDistance }
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func hourLabel(for minute: Int) -> String {
        let suffix = minute >= 24 * 60 ? " +1" : ""
        return String(format: "%02d%@", (minute / 60) % 24, suffix)
    }

    private func formatTimeLabel(_ minute: Double) -> String {
        ShiftTimeRange.displayMinute(Int(minute.rounded()))
    }
}

private struct SegmentMarker: Identifiable {
    let id: String
    let minute: Double
    let label: String
    let isStart: Bool
}

private struct ResolvedSegmentLabel: Identifiable {
    let id: String
    let label: String
    let isStart: Bool
    let markerPoint: CGPoint
    let labelPoint: CGPoint
}
