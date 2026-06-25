import SwiftUI

struct TVWeeklyScheduleView: View {
    @ObservedObject var viewModel: TVWeeklyScheduleViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.08),
                    Color(red: 0.10, green: 0.11, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
                .padding(.horizontal, 74)
                .padding(.vertical, 54)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            TVLoadingStateView()
        case .failed(let message):
            TVErrorStateView(message: message) {
                Task {
                    await viewModel.reload()
                }
            }
        case .loaded(let schedule):
            TVWeekDashboard(
                schedule: schedule,
                previousWeek: { viewModel.moveWeek(by: -1) },
                currentWeek: { viewModel.jumpToCurrentWeek() },
                nextWeek: { viewModel.moveWeek(by: 1) }
            )
        }
    }
}

private struct TVWeekDashboard: View {
    let schedule: TVWeekSchedule
    let previousWeek: () -> Void
    let currentWeek: () -> Void
    let nextWeek: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            sidebar
                .frame(width: 380)

            TVWeekCalendarGrid(schedule: schedule)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text("PayScope")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))

                Text(weekTitle)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            TVWorkStatusCard(schedule: schedule)

            VStack(spacing: 14) {
                Button(action: previousWeek) {
                    Label("Vorige Woche", systemImage: "chevron.left")
                }

                Button(action: currentWeek) {
                    Label("Diese Woche", systemImage: "calendar")
                }

                Button(action: nextWeek) {
                    Label("Nächste Woche", systemImage: "chevron.right")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer(minLength: 18)

            Text("Aktualisiert \(schedule.generatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(30)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var weekTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        let start = formatter.string(from: schedule.weekStart)
        let endDate = Calendar.current.date(byAdding: .day, value: -1, to: schedule.weekEnd) ?? schedule.weekEnd
        let end = formatter.string(from: endDate)
        return "\(start) - \(end)"
    }
}

private struct TVWorkStatusCard: View {
    let schedule: TVWeekSchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(statusTitle, systemImage: schedule.hasWork ? "briefcase.fill" : "checkmark.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 22) {
                metric(value: "\(schedule.timedEntries.count)", label: "Schichten")
                metric(value: durationText(schedule.totalShiftSeconds), label: "Arbeitszeit")
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusTint.opacity(0.26), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(statusTint.opacity(0.55), lineWidth: 1)
        )
    }

    private var statusTitle: String {
        schedule.hasWork ? "Du arbeitest diese Woche" : "Keine Arbeit geplant"
    }

    private var statusTint: Color {
        schedule.hasWork ? Color(red: 0.20, green: 0.66, blue: 0.96) : Color(red: 0.28, green: 0.76, blue: 0.44)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if minutes == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(minutes) m"
    }
}

private struct TVWeekCalendarGrid: View {
    let schedule: TVWeekSchedule
    private let calendar = Calendar.current
    private let axisWidth: CGFloat = 78
    private let dayHeaderHeight: CGFloat = 88

    var body: some View {
        GeometryReader { proxy in
            let range = timeRange
            let availableHeight = max(320, proxy.size.height - dayHeaderHeight)
            let dayWidth = max(120, (proxy.size.width - axisWidth) / 7)

            ZStack(alignment: .topLeading) {
                gridBackground

                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    TVDayHeader(date: day, entries: entries(on: day))
                        .frame(width: dayWidth, height: dayHeaderHeight)
                        .offset(x: axisWidth + CGFloat(index) * dayWidth)
                }

                ForEach(timeTicks(in: range), id: \.self) { minute in
                    let y = dayHeaderHeight + yOffset(for: minute, range: range, height: availableHeight)
                    Text(timeLabel(for: minute))
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: axisWidth - 16, alignment: .trailing)
                        .offset(x: 0, y: y - 12)

                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)
                        .offset(x: axisWidth, y: y)
                }

                ForEach(schedule.timedEntries) { entry in
                    if let layout = blockLayout(for: entry, range: range, height: availableHeight, dayWidth: dayWidth) {
                        TVShiftBlock(entry: entry)
                            .frame(width: max(96, dayWidth - 18), height: layout.height)
                            .offset(x: axisWidth + CGFloat(layout.dayIndex) * dayWidth + 9, y: dayHeaderHeight + layout.y)
                    }
                }

                if schedule.timedEntries.isEmpty {
                    TVEmptyWeekOverlay()
                        .frame(width: proxy.size.width - axisWidth, height: availableHeight)
                        .offset(x: axisWidth, y: dayHeaderHeight)
                }
            }
        }
    }

    private var gridBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: schedule.weekStart) }
    }

    private var timeRange: ClosedRange<Int> {
        let timed = schedule.timedEntries.compactMap { entry -> (Int, Int)? in
            guard let start = entry.shiftStart, let end = entry.shiftEnd else { return nil }
            let startMinute = minuteOfDisplayDay(for: start, entry: entry)
            let endMinute = minuteOfDisplayDay(for: end, entry: entry)
            return (startMinute, max(startMinute + 30, endMinute))
        }

        guard let minStart = timed.map(\.0).min(), let maxEnd = timed.map(\.1).max() else {
            return 8 * 60...18 * 60
        }

        let lower = max(0, (minStart / 60) * 60 - 60)
        let upper = min(36 * 60, ((maxEnd + 59) / 60) * 60 + 60)
        return lower...max(lower + 60, upper)
    }

    private func entries(on day: Date) -> [TVShiftEntry] {
        schedule.entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private func blockLayout(
        for entry: TVShiftEntry,
        range: ClosedRange<Int>,
        height: CGFloat,
        dayWidth: CGFloat
    ) -> (dayIndex: Int, y: CGFloat, height: CGFloat)? {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else { return nil }
        let dayIndex = clampedDayIndex(for: start)
        let startMinute = max(range.lowerBound, minuteOfDisplayDay(for: start, entry: entry))
        let endMinute = min(range.upperBound, minuteOfDisplayDay(for: end, entry: entry))
        let duration = max(30, endMinute - startMinute)
        let y = yOffset(for: startMinute, range: range, height: height)
        let blockHeight = max(82, CGFloat(duration) / CGFloat(range.upperBound - range.lowerBound) * height)
        return (dayIndex, y, blockHeight)
    }

    private func clampedDayIndex(for date: Date) -> Int {
        let day = calendar.startOfDay(for: date)
        let raw = calendar.dateComponents([.day], from: schedule.weekStart, to: day).day ?? 0
        return min(max(raw, 0), 6)
    }

    private func minuteOfDisplayDay(for date: Date, entry: TVShiftEntry) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        var minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if let start = entry.shiftStart,
           !calendar.isDate(date, inSameDayAs: start),
           date > start {
            minute += 24 * 60
        }
        return minute
    }

    private func yOffset(for minute: Int, range: ClosedRange<Int>, height: CGFloat) -> CGFloat {
        let span = max(1, range.upperBound - range.lowerBound)
        return CGFloat(minute - range.lowerBound) / CGFloat(span) * height
    }

    private func timeTicks(in range: ClosedRange<Int>) -> [Int] {
        let first = ((range.lowerBound + 59) / 60) * 60
        guard first <= range.upperBound else { return [range.lowerBound, range.upperBound] }
        return stride(from: first, through: range.upperBound, by: 60).map { $0 }
    }

    private func timeLabel(for minute: Int) -> String {
        String(format: "%02d:00", minute / 60)
    }
}

private struct TVDayHeader: View {
    let date: Date
    let entries: [TVShiftEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(weekday)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            Text(dayNumber)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))

            HStack(spacing: 8) {
                ForEach(entries.filter { !$0.hasTimedShift }.prefix(2)) { entry in
                    Label(entry.type.label, systemImage: entry.type.symbolName)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(entry.type.tint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private var weekday: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM"
        return formatter.string(from: date)
    }
}

private struct TVShiftBlock: View {
    let entry: TVShiftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(entry.type.label, systemImage: entry.type.symbolName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(timeText)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)

            if entry.breakSeconds > 0 {
                Text("Pause \(durationText(entry.breakSeconds))")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(entry.type.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: entry.type.tint.opacity(0.24), radius: 20, y: 12)
    }

    private var timeText: String {
        guard let start = entry.shiftStart, let end = entry.shiftEnd else { return "Ganztägig" }
        return "\(start.formatted(date: .omitted, time: .shortened)) - \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func durationText(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }
}

private struct TVEmptyWeekOverlay: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))

            Text("Keine Schichten in dieser Woche")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("Die Apple-TV-App ist nur zur Ansicht gedacht.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TVLoadingStateView: View {
    var body: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
            Text("Schichten werden geladen")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TVErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.slash.fill")
                .font(.system(size: 70, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Schichten konnten nicht geladen werden")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)

            Button(action: retry) {
                Label("Erneut laden", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
