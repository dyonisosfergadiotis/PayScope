import SwiftUI
import SwiftData
import Combine

struct TodayFocusView: View {
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]
    @Bindable var settings: Settings

    @State private var now = Date()

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 36
            let ringSize = max(190, min(width * 0.96, geometry.size.height * 0.62))

            VStack(spacing: 12) {
                header

                VStack(spacing: 8) {
                    TodayFocusRingChart(
                        bounds: timelineBounds,
                        workedIntervals: workedIntervals,
                        nowMinuteOfDay: nowMinuteOfDay,
                        workedLabel: workedDisplayLabel,
                        breakSeconds: breakSeconds,
                        accent: settings.themeAccent.color
                    )
                    .frame(width: ringSize, height: ringSize)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .onReceive(refreshTimer) { value in
            now = value
        }
        .animation(.snappy(duration: 0.35), value: settings.timelineMinMinute)
        .animation(.snappy(duration: 0.35), value: settings.timelineMaxMinute)
        .animation(.snappy(duration: 0.35), value: settings.themeAccent)
    }

    private var todayStart: Date {
        now.startOfDayLocal()
    }

    private var todayEntry: DayEntry? {
        entries.first(where: { $0.date.isSameLocalDay(as: todayStart) })
    }

    private var nextEntry: DayEntry? {
        entries.first(where: { $0.date > todayStart })
    }

    private var workedSeconds: Int {
        guard let day = todayEntry else { return 0 }
        if let manual = day.manualWorkedSeconds {
            return max(0, manual)
        }
        return day.segments.reduce(0) { partial, segment in
            let segmentSeconds = max(0, Int(segment.end.timeIntervalSince(segment.start)) - max(0, segment.breakSeconds))
            return partial + segmentSeconds
        }
    }

    private var breakSeconds: Int {
        guard let day = todayEntry else { return 0 }
        return day.segments.reduce(0) { partial, segment in
            partial + max(0, segment.breakSeconds)
        }
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

    private var timelineBounds: ClosedRange<Int> {
        let fallbackStart = 6 * 60
        let fallbackEnd = 22 * 60
        let rawStart = settings.timelineMinMinute ?? fallbackStart
        let rawEnd = settings.timelineMaxMinute ?? fallbackEnd

        let start = max(0, min(rawStart, 23 * 60))
        let end = min(24 * 60, max(rawEnd, start + 60))
        return start...end
    }

    private var workedIntervals: [ClosedRange<Double>] {
        guard let day = todayEntry else { return [] }

        if let manual = day.manualWorkedSeconds {
            let span = Double(max(1, timelineBounds.upperBound - timelineBounds.lowerBound))
            let manualMinutes = min(span, Double(max(0, manual)) / 60.0)
            guard manualMinutes > 0 else { return [] }
            let start = Double(timelineBounds.lowerBound)
            return [start...(start + manualMinutes)]
        }

        let raw = day.segments.compactMap { segment -> ClosedRange<Double>? in
            let start = max(Double(timelineBounds.lowerBound), min(Double(timelineBounds.upperBound), minuteOfDay(from: segment.start)))
            let end = max(Double(timelineBounds.lowerBound), min(Double(timelineBounds.upperBound), minuteOfDay(from: segment.end)))
            guard end > start else { return nil }
            return start...end
        }

        return mergeIntervals(raw)
    }

    private var timelineStartDate: Date {
        dateAtMinute(timelineBounds.lowerBound, on: todayStart)
    }

    private var timelineEndDate: Date {
        dateAtMinute(timelineBounds.upperBound, on: todayStart)
    }

    private var timelineProgress: Double {
        let total = timelineEndDate.timeIntervalSince(timelineStartDate)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(timelineStartDate)
        return min(max(elapsed / total, 0), 1)
    }

    private var nowMinuteOfDay: Double {
        minuteOfDay(from: now)
    }

    private var workedDisplayLabel: String {
        "\(PayScopeFormatters.hhmmString(seconds: workedSeconds)) h"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PayScopeFormatters.day.string(from: todayStart))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Heute im Fokus")
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: todayTypeIcon)
                if todayHasShiftDeviation {
                    Image(systemName: "pencil")
                        .font(.caption2.weight(.bold))
                }
                Text(todayTypeLabel)
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(todayTypeColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(todayTypeColor.opacity(0.14), in: Capsule())
        }
    }

    private var detailPanel: some View {
        VStack(spacing: 10) {
            detailRow(
                title: "Pausenblöcke",
                value: pauseInfoText,
                systemImage: "cup.and.saucer.fill"
            )
            detailRow(
                title: "Erfasst",
                value: trackedInfoText,
                systemImage: "clock.arrow.circlepath"
            )
            detailRow(
                title: targetInfoTitle,
                value: targetInfoText,
                systemImage: targetInfoIcon
            )
            detailRow(
                title: "Jetzt",
                value: nowInfoText,
                systemImage: "gauge.with.needle"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .payScopeCard(accent: settings.themeAccent.color)
    }

    private var todayTypeLabel: String {
        if let today = todayEntry {
            return today.type.label
        }
        if let next = nextEntry {
            return "Nächste: \(PayScopeFormatters.day.string(from: next.date))"
        }
        return "Kein Eintrag"
    }

    private var todayTypeIcon: String {
        if todayEntry != nil {
            return todayEntry?.type.icon ?? "calendar.badge.exclamationmark"
        }
        return nextEntry != nil ? "calendar.badge.clock" : "calendar.badge.exclamationmark"
    }

    private var todayTypeColor: Color {
        if let today = todayEntry {
            return today.type.tint
        }
        return nextEntry != nil ? settings.themeAccent.color : .secondary
    }

    private var todayHasShiftDeviation: Bool {
        todayEntry?.creditedOverrideSeconds != nil
    }

    private var pauseBlocksCount: Int {
        guard let day = todayEntry else { return 0 }
        return day.segments.filter { $0.breakSeconds > 0 }.count
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
            !day.segments.isEmpty,
            let first = day.segments.map(\.start).min(),
            let last = day.segments.map(\.end).max()
        else {
            return "Keine Segmente"
        }
        let suffix = day.segments.count == 1 ? "Segment" : "Segmente"
        return "\(PayScopeFormatters.time.string(from: first)) - \(PayScopeFormatters.time.string(from: last)) · \(day.segments.count) \(suffix)"
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
        let percent = Int((timelineProgress * 100).rounded())
        return "\(PayScopeFormatters.time.string(from: now)) · \(percent)% im Fenster"
    }

    private func detailRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.themeAccent.color)
                    .frame(width: 16)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func mergeIntervals(_ intervals: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        var result: [ClosedRange<Double>] = [sorted[0]]

        for interval in sorted.dropFirst() {
            guard let last = result.last else {
                result.append(interval)
                continue
            }

            if interval.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, interval.upperBound)
            } else {
                result.append(interval)
            }
        }

        return result
    }

    private func dateAtMinute(_ minute: Int, on dayStart: Date) -> Date {
        if minute >= 24 * 60 {
            return dayStart.addingTimeInterval(24 * 3600)
        }
        let hour = max(0, minute / 60)
        let minPart = max(0, minute % 60)
        return Calendar.current.date(bySettingHour: hour, minute: minPart, second: 0, of: dayStart) ?? dayStart
    }

    private func minuteOfDay(from date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
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
        String(format: "%02d", (minute / 60) % 24)
    }

    private func formatTimeLabel(_ minute: Double) -> String {
        let clamped = max(0, min(24 * 60, Int(minute.rounded())))
        let hour = clamped / 60
        let mins = clamped % 60
        return String(format: "%02d:%02d", hour, mins)
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
