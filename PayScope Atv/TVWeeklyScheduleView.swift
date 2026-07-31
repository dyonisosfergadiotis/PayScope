import SwiftUI

private struct TVBackgroundView: View {
    var body: some View {
        ZStack {
            Color.black

            EllipticalGradient(
                colors: [
                    Color(red: 0.22, green: 0.39, blue: 0.70).opacity(0.22),
                    .clear
                ],
                center: .init(x: 0.2, y: 0.25),
                endRadiusFraction: 0.45
            )

            EllipticalGradient(
                colors: [
                    Color(red: 0.39, green: 0.24, blue: 0.63).opacity(0.17),
                    .clear
                ],
                center: .init(x: 0.8, y: 0.72),
                endRadiusFraction: 0.38
            )
        }
        .ignoresSafeArea()
    }
}

struct TVWeeklyScheduleView: View {
    @ObservedObject var viewModel: TVWeeklyScheduleViewModel

    var body: some View {
        ZStack {
            TVBackgroundView()

            content
                .padding(.horizontal, 56)
                .padding(.vertical, 38)
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
        case .loaded(let schedule, let notice):
            TVWeekDashboard(
                schedule: schedule,
                notice: notice,
                previousWeek: { viewModel.moveWeek(by: -1) },
                currentWeek: { viewModel.jumpToCurrentWeek() },
                nextWeek: { viewModel.moveWeek(by: 1) }
            )
        }
    }
}

private struct TVWeekDashboard: View {
    let schedule: TVWeekSchedule
    let notice: String?
    let previousWeek: () -> Void
    let currentWeek: () -> Void
    let nextWeek: () -> Void
    @State private var selectedEntry: TVShiftEntry?
    @FocusState private var focusedControl: TVRemoteFocusTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let notice {
                TVLocalDataNotice(message: notice)
            }

            TVWeekCalendarGrid(schedule: schedule) { entry in
                selectedEntry = entry
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable()
                .focused($focusedControl, equals: .timeline)

            weekNavigator
        }
        .onAppear {
            focusedControl = .currentWeek
        }
        .onPlayPauseCommand(perform: currentWeek)
        .onMoveCommand { direction in
            guard focusedControl == .timeline else { return }
            switch direction {
            case .left:
                previousWeek()
            case .right:
                nextWeek()
            default:
                break
            }
        }
        .alert("Eintrag", isPresented: selectedEntryBinding) {
            Button("OK", role: .cancel) {
                selectedEntry = nil
            }
        } message: {
            if let selectedEntry {
                Text(detailText(for: selectedEntry))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 36) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PayScope")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.40))
                    .kerning(1.0)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("KW \(weekNumber)")
                        .font(.system(size: 43, weight: .bold, design: .rounded))
                    Text(weekTitle)
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(.white.opacity(0.44))
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 30)

            HStack(spacing: 12) {
                TVWeekMetricChip(
                    systemImage: schedule.hasWork ? "briefcase.fill" : "checkmark.circle.fill",
                    value: "\(schedule.entries.count)",
                    label: "Einträge",
                    tint: schedule.hasWork ? schedule.colorSettings.color(for: .work) : Color(red: 0.28, green: 0.76, blue: 0.44)
                )

                TVWeekMetricChip(
                    systemImage: "clock.fill",
                    value: durationText(schedule.totalShiftSeconds),
                    label: "Woche",
                    tint: Color(red: 0.24, green: 0.58, blue: 0.92)
                )

                TVWeekMetricChip(
                    systemImage: "arrow.clockwise",
                    value: schedule.generatedAt.formatted(date: .omitted, time: .shortened),
                    label: "Update",
                    tint: Color(red: 0.52, green: 0.42, blue: 0.88)
                )
            }
        }
    }

    private var weekNavigator: some View {
        HStack(spacing: 10) {
            glassNavButton(
                label: "Vorige Woche",
                systemImage: "chevron.left",
                target: .previousWeek,
                isPrimary: false,
                action: previousWeek
            )

            glassNavButton(
                label: "Diese Woche",
                systemImage: "calendar",
                target: .currentWeek,
                isPrimary: true,
                action: currentWeek
            )

            glassNavButton(
                label: "Nächste Woche",
                systemImage: "chevron.right",
                target: .nextWeek,
                isPrimary: false,
                action: nextWeek
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func glassNavButton(
        label: String,
        systemImage: String,
        target: TVRemoteFocusTarget,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedControl == target

        return Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: isPrimary ? .semibold : .regular))
            }
            .foregroundStyle(isPrimary ? .white : .white.opacity(0.68))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(.white.opacity(isPrimary ? 0.14 : 0.07))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isFocused ? .white.opacity(0.50) : .white.opacity(isPrimary ? 0.25 : 0.15),
                                lineWidth: isFocused ? 1.5 : 0.5
                            )
                    }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.22))
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                            .padding(.top, 1)
                    }
            }
            .shadow(color: isFocused ? .white.opacity(0.10) : .clear, radius: 10)
            .scaleEffect(isFocused ? 1.025 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedControl, equals: target)
    }

    private var selectedEntryBinding: Binding<Bool> {
        Binding(
            get: { selectedEntry != nil },
            set: { isPresented in
                if !isPresented {
                    selectedEntry = nil
                }
            }
        )
    }

    private var weekNumber: Int {
        Calendar.current.component(.weekOfYear, from: schedule.weekStart)
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

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if minutes == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(minutes) m"
    }

    private func detailText(for entry: TVShiftEntry) -> String {
        var lines = [entry.type.label]
        if let start = entry.shiftStart, let end = entry.shiftEnd {
            lines.append("\(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))")
        } else {
            lines.append("Ohne feste Uhrzeit")
        }
        if let seconds = entry.displaySeconds {
            lines.append(durationText(seconds))
        }
        if entry.breakSeconds > 0 {
            lines.append("Pause \(durationText(entry.breakSeconds))")
        }
        return lines.joined(separator: "\n")
    }
}

private enum TVRemoteFocusTarget: Hashable {
    case timeline
    case previousWeek
    case currentWeek
    case nextWeek
}

private struct TVWeekMetricChip: View {
    let systemImage: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.top, 1)
                }
        }
        .shadow(color: .black.opacity(0.30), radius: 8, y: 3)
    }
}

private struct TVLocalDataNotice: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(red: 1.00, green: 0.86, blue: 0.50).opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "icloud.slash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 1.00, green: 0.85, blue: 0.47))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 1.00, green: 0.78, blue: 0.24).opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 1.00, green: 0.78, blue: 0.24).opacity(0.25), lineWidth: 0.5)
                }
        }
    }
}

private struct TVWeekCalendarGrid: View {
    let schedule: TVWeekSchedule
    let selectEntry: (TVShiftEntry) -> Void
    private let calendar = Calendar.current
    private let axisWidth: CGFloat = 76
    private let dayHeaderHeight: CGFloat = 82

    var body: some View {
        GeometryReader { proxy in
            let range = timeRange
            let availableHeight = max(320, proxy.size.height - dayHeaderHeight)
            let dayWidth = max(120, (proxy.size.width - axisWidth) / 7)

            ZStack(alignment: .topLeading) {
                gridBackground

                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    TVDayHeader(date: day)
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

                ForEach(displayEntries) { entry in
                    if let layout = blockLayout(for: entry, range: range, height: availableHeight, dayWidth: dayWidth) {
                        Button {
                            selectEntry(entry)
                        } label: {
                            TVShiftBlock(entry: entry, tint: schedule.colorSettings.color(for: entry.type))
                        }
                        .buttonStyle(.plain)
                        .frame(width: max(110, dayWidth - 22), height: layout.height)
                            .offset(x: axisWidth + CGFloat(layout.dayIndex) * dayWidth + 9, y: dayHeaderHeight + layout.y)
                    }
                }

                if schedule.entries.isEmpty {
                    TVEmptyWeekOverlay()
                        .frame(width: proxy.size.width - axisWidth, height: availableHeight)
                        .offset(x: axisWidth, y: dayHeaderHeight)
                }
            }
        }
    }

    private var gridBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            )
    }

    private var displayEntries: [TVShiftEntry] {
        schedule.entries.sorted { lhs, rhs in
            let lhsDate = lhs.shiftStart ?? lhs.date
            let rhsDate = rhs.shiftStart ?? rhs.date
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }
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
            return 7 * 60...18 * 60
        }

        let lower = max(0, (minStart / 60) * 60 - 60)
        let upper = min(36 * 60, ((maxEnd + 59) / 60) * 60 + 60)
        return lower...max(lower + 60, upper)
    }

    private func blockLayout(
        for entry: TVShiftEntry,
        range: ClosedRange<Int>,
        height: CGFloat,
        dayWidth: CGFloat
    ) -> (dayIndex: Int, y: CGFloat, height: CGFloat)? {
        guard let start = entry.shiftStart, let end = entry.shiftEnd, end > start else {
            let dayIndex = clampedDayIndex(for: entry.date)
            return (dayIndex, 0, min(132, max(112, height * 0.16)))
        }
        let dayIndex = clampedDayIndex(for: start)
        let startMinute = max(range.lowerBound, minuteOfDisplayDay(for: start, entry: entry))
        let endMinute = min(range.upperBound, minuteOfDisplayDay(for: end, entry: entry))
        let duration = max(30, endMinute - startMinute)
        let y = yOffset(for: startMinute, range: range, height: height)
        let blockHeight = max(132, CGFloat(duration) / CGFloat(range.upperBound - range.lowerBound) * height)
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

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(weekday)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(dayNumber)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.top, 14)
    }

    private var weekday: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE"
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
    let tint: Color
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: entry.type.symbolName)
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 30)

                Text(entry.type.label)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                TVShiftInfoLine(systemImage: timeIconName, text: timeText, opacity: 0.88)

                if let summaryText {
                    TVShiftInfoLine(systemImage: summaryIconName, text: summaryText, opacity: 0.74)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(style: cardStyle, isFocused: isFocused)
    }

    private var cardStyle: TVShiftCardStyle {
        TVShiftCardStyle(accent: tint)
    }

    private var timeText: String {
        guard let start = entry.shiftStart, let end = entry.shiftEnd else {
            return "Ohne feste Uhrzeit"
        }
        return "\(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
    }

    private var timeIconName: String {
        entry.hasTimedShift ? "clock.fill" : "calendar"
    }

    private var valueIconName: String {
        switch entry.type {
        case .work, .manual:
            return "hourglass"
        case .vacation, .holiday, .sick:
            return "checkmark.seal.fill"
        }
    }

    private var summaryIconName: String {
        entry.breakSeconds > 0 ? "hourglass" : valueIconName
    }

    private var summaryText: String? {
        guard let seconds = entry.displaySeconds else { return nil }
        switch entry.type {
        case .work:
            let workText = durationText(seconds)
            if entry.breakSeconds > 0 {
                return "\(workText) · \(durationText(entry.breakSeconds)) Pause"
            }
            return "\(workText) netto"
        case .manual:
            return "\(durationText(seconds)) Dauer"
        case .vacation, .holiday, .sick:
            return "\(durationText(seconds)) Gutschrift"
        }
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

private struct TVShiftInfoLine: View {
    let systemImage: String
    let text: String
    let opacity: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(.white.opacity(opacity))
    }
}

private struct TVShiftCardStyle {
    let accent: Color

    var gradientColors: [Color] {
        [
            accent.opacity(0.74),
            accent.opacity(0.54)
        ]
    }

    var borderColor: Color {
        accent.opacity(0.38)
    }

    var shadowColor: Color {
        accent.opacity(0.38)
    }
}

private struct LiquidGlassCardBackground: ViewModifier {
    let style: TVShiftCardStyle
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: style.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isFocused ? .white.opacity(0.45) : style.borderColor,
                                lineWidth: isFocused ? 1.0 : 0.5
                            )
                    }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(isFocused ? 0.40 : 0.22))
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                            .padding(.top, 1.5)
                    }
            }
            .shadow(
                color: isFocused ? style.shadowColor.opacity(0.70) : style.shadowColor,
                radius: isFocused ? 28 : 14,
                y: isFocused ? 8 : 4
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 2)
                }
            }
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFocused)
    }
}

private extension View {
    func liquidGlassCard(style: TVShiftCardStyle, isFocused: Bool) -> some View {
        modifier(LiquidGlassCardBackground(style: style, isFocused: isFocused))
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
