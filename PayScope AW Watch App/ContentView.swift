import Combine
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WatchShiftViewModel()
    @State private var now = Date()
    @State private var focusScrollRequest = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let accent = viewModel.snapshot?.themeAccent ?? .blue

        NavigationStack {
            ZStack {
                WatchAppBackground(accent: accent)

                if let snapshot = viewModel.snapshot, !snapshot.displayDays.isEmpty {
                    WatchShiftCardsTimeline(
                        snapshot: snapshot,
                        now: now,
                        focusScrollRequest: focusScrollRequest
                    )
                } else {
                    WatchEmptyShiftState(
                        accent: accent,
                        failedReload: viewModel.lastReloadFailed
                    )
                }
            }
            .toolbar {
                WatchToolbarControls(
                    accent: accent,
                    focusDay: viewModel.snapshot?.focusDay(at: now),
                    now: now,
                    isReloading: viewModel.isReloading,
                    reloadAction: viewModel.requestSnapshot,
                    todayAction: {
                        focusScrollRequest += 1
                    }
                )
            }
        }
        .onReceive(timer) { value in
            now = value
        }
        .task {
            viewModel.requestSnapshot()
        }
    }
}

private struct WatchToolbarControls: ToolbarContent {
    let accent: Color
    let focusDay: WatchShiftDay?
    let now: Date
    let isReloading: Bool
    let reloadAction: () -> Void
    let todayAction: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: reloadAction) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .rotationEffect(.degrees(isReloading ? 180 : 0))
                    .animation(.snappy(duration: 0.45), value: isReloading)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.44), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Neu laden")
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                Spacer(minLength: 0)

                Button(action: todayAction) {
                    WatchTodayToolbarButton(
                        accent: focusDay?.categoryColor ?? accent,
                        progress: focusDay?.progress(at: now) ?? 0
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zurück zu Heute")
                .handGestureShortcut(.primaryAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct WatchTodayToolbarButton: View {
    let accent: Color
    let progress: Double

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 19, height: 19)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(.black.opacity(0.44), in: Capsule())
        .overlay {
            Capsule()
                .stroke(accent.opacity(0.48), lineWidth: 1)
        }
    }
}

private struct WatchShiftCardsTimeline: View {
    let snapshot: WatchShiftSnapshot
    let now: Date
    let focusScrollRequest: Int

    @State private var didScrollToFocus = false

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 12) {
                        ForEach(snapshot.displayDays) { day in
                            WatchCalendarDaySection(
                                day: day,
                                snapshot: snapshot,
                                now: now,
                                openCurrentShift: {}
                            )
                            .frame(
                                minHeight: max(128, geometry.size.height - 12),
                                alignment: .top
                            )
                            .id(day.id)
                            .scrollTransition(.animated.threshold(.visible(0.25))) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.985)
                                    .opacity(phase.isIdentity ? 1 : 0.62)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 8)
                    .padding(.top, 0)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
            .onAppear {
                scrollToFocusIfNeeded(proxy: proxy)
            }
            .onChange(of: focusScrollRequest) { _, _ in
                scrollToFocus(proxy: proxy)
            }
        }
    }

    private func scrollToFocusIfNeeded(proxy: ScrollViewProxy) {
        guard !didScrollToFocus else { return }
        guard let id = snapshot.preferredScrollID(at: now) else { return }
        didScrollToFocus = true
        scrollTo(id: id, proxy: proxy)
    }

    private func scrollToFocus(proxy: ScrollViewProxy) {
        guard let id = snapshot.preferredScrollID(at: now) else { return }
        scrollTo(id: id, proxy: proxy)
    }

    private func scrollTo(id: String, proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.5)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }
}

private struct WatchCalendarDaySection: View {
    let day: WatchShiftDay
    let snapshot: WatchShiftSnapshot
    let now: Date
    let openCurrentShift: () -> Void

    private var accent: Color {
        day.categoryColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WatchCalendarDayHeader(day: day, now: now, accent: accent)

            WatchCalendarShiftCard(
                day: day,
                snapshot: snapshot,
                now: now,
                openCurrentShift: openCurrentShift
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WatchCalendarDayHeader: View {
    let day: WatchShiftDay
    let now: Date
    let accent: Color

    private var isToday: Bool {
        day.date.isSameWatchDay(as: now)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(day.date, format: .dateTime.day())
                .font(.system(size: 31, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 0) {
                Text(Self.germanDateFormatter.weekdaySymbols[Calendar.current.component(.weekday, from: day.date) - 1])
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(isToday ? accent : .primary.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                Text(Self.germanDateFormatter.monthSymbols[Calendar.current.component(.month, from: day.date) - 1])
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private static let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()
}

private struct WatchCalendarShiftCard: View {
    let day: WatchShiftDay
    let snapshot: WatchShiftSnapshot
    let now: Date
    let openCurrentShift: () -> Void

    private var accent: Color {
        day.categoryColor
    }

    var body: some View {
        Button(action: openCurrentShift) {
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: day.iconName)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(accent)
                            .frame(width: 16, height: 16)

                        Text(day.dayTypeLabel)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        Spacer(minLength: 4)

                        Text(payMetric)
                            .font(.system(size: 17, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.54)
                    }

                    HStack(alignment: .top, spacing: 7) {
                        Text(startTimeText)
                            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.top, 4)

                        Spacer(minLength: 2)

                        VStack(spacing: 3) {
                            Text(durationMetric)
                                .font(.system(size: 11, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundStyle(accent)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(accent.opacity(0.62), lineWidth: 1)
                                }

                            HStack(spacing: 3) {
                                Image(systemName: "cup.and.saucer.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(accent.opacity(0.9))

                                Text(breakMetric)
                                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .accessibilityLabel("Pause \(breakMetric)")
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 2)

                        Text(endTimeText)
                            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.top, 4)
                    }

                    if let tipMetric {
                        Text(tipMetric)
                            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(day.isActive(at: now) ? 0.14 : 0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(accent.opacity(day.isActive(at: now) ? 0.72 : 0.22), lineWidth: day.isActive(at: now) ? 1.1 : 0.6)
            }
        }
        .buttonStyle(.plain)
    }

    private var startTimeText: String {
        guard let start = day.shiftStart, day.isTimedShift else {
            return "Ganzt."
        }
        return Self.timeFormatter.string(from: start)
    }

    private var endTimeText: String {
        guard let end = day.shiftEnd, day.isTimedShift else {
            return ""
        }
        return Self.timeFormatter.string(from: end)
    }

    private var payMetric: String {
        Self.currencyFormatter.string(from: NSNumber(value: Double(day.isActive(at: now) ? day.earnedSoFarPayCents : day.payCents) / 100.0)) ?? "0,00 €"
    }

    private var durationMetric: String {
        Self.hoursString(seconds: displayedHoursSeconds)
    }

    private var breakMetric: String {
        Self.hoursString(seconds: day.breakSeconds)
    }

    private var displayedHoursSeconds: Int {
        guard snapshot.calendarHoursBreakModeRawValue == "withBreak" else {
            return day.workedSeconds
        }

        guard let start = day.shiftStart, let end = day.shiftEnd, end > start else {
            return day.workedSeconds
        }

        return max(0, Int(end.timeIntervalSince(start)))
    }

    private var tipMetric: String? {
        guard snapshot.showTipsAmount, day.tipAmountCents > 0 else { return nil }
        return Self.currencyFormatter.string(from: NSNumber(value: Double(day.tipAmountCents) / 100.0))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func hoursString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        return String(format: "%d:%02d h", hours, minutes)
    }
}

private struct WatchTodayFocusView: View {
    let day: WatchShiftDay
    let snapshot: WatchShiftSnapshot
    let now: Date
    let dismissAction: () -> Void
    @GestureState private var swipeDownProgress = 0.0

    private var accent: Color {
        day.categoryColor
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = Self.layout(for: geometry.size)

            ZStack {
                WatchAppBackground(accent: accent)

                VStack(spacing: 0) {
                    WatchSwipeDownIndicator(accent: accent, progress: swipeDownProgress)
                        .padding(.top, layout.topInset)

                    WatchCalendarDayHeader(day: day, now: now, accent: accent)
                        .scaleEffect(layout.headerScale, anchor: .leading)
                        .frame(height: layout.headerHeight, alignment: .leading)
                        .padding(.top, layout.headerTopSpacing)

                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .stroke(accent.opacity(0.16), lineWidth: layout.ringLineWidth)

                            Circle()
                                .trim(from: 0, to: min(max(day.progress(at: now), 0), 1))
                                .stroke(
                                    accent,
                                    style: StrokeStyle(lineWidth: layout.ringLineWidth, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))

                            VStack(spacing: layout.centerTextSpacing) {
                                Text(countdownText)
                                    .font(.system(size: layout.countdownFontSize, weight: .black, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)

                                Text(durationText)
                                    .font(.system(size: layout.durationFontSize, weight: .black, design: .rounded).monospacedDigit())
                                    .foregroundStyle(accent)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.68)
                            }
                        }
                        .frame(width: layout.ringSize, height: layout.ringSize)
                        .padding(.top, layout.ringTopSpacing)

                        Spacer(minLength: layout.timeTopSpacing)

                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Start")
                                    .font(.system(size: layout.captionFontSize, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Text(startTimeText)
                                    .font(.system(size: layout.timeFontSize, weight: .black, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }

                            Spacer(minLength: layout.timeRowSpacing)

                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Ende")
                                    .font(.system(size: layout.captionFontSize, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Text(endTimeText)
                                    .font(.system(size: layout.timeFontSize, weight: .black, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }
                        }
                        .frame(width: layout.timeRowWidth)
                    }
                }
                .padding(.horizontal, layout.horizontalInset)
                .frame(width: geometry.size.width, height: geometry.size.height - layout.bottomInset, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 28)
                .updating($swipeDownProgress) { value, state, _ in
                    let verticalDistance = max(0, value.translation.height)
                    let horizontalDistance = abs(value.translation.width)

                    guard verticalDistance > horizontalDistance * 0.7 else {
                        state = 0
                        return
                    }

                    state = min(verticalDistance / 52, 1)
                }
                .onEnded { value in
                    let verticalDistance = value.translation.height
                    let horizontalDistance = abs(value.translation.width)

                    guard verticalDistance > 44,
                          verticalDistance > horizontalDistance * 1.35 else {
                        return
                    }

                    dismissAction()
                }
        )
    }

    private static func layout(for size: CGSize) -> WatchTodayLayout {
        let minDimension = min(size.width, size.height)
        let compactness = min(max((size.height - 206) / 54, 0), 1)
        let topInset: CGFloat = compactness < 0.4 ? 0 : 1
        let headerTopSpacing: CGFloat = 2 + (2 * compactness)
        let ringTopSpacing: CGFloat = 2 + (2 * compactness)
        let timeTopSpacing: CGFloat = 4 + (2 * compactness)
        let bottomInset: CGFloat = 10
        let indicatorHeight: CGFloat = 16
        let headerHeight: CGFloat = 35 + (4 * compactness)
        let captionFontSize: CGFloat = max(8, min(9, minDimension * 0.042))
        let timeFontSize: CGFloat = max(11, min(13, minDimension * 0.06))
        let timeRowHeight = captionFontSize + timeFontSize + 3
        let topAndHeaderHeight = topInset + indicatorHeight + headerTopSpacing + headerHeight
        let spacingHeight = ringTopSpacing + timeTopSpacing + bottomInset
        let fixedHeight = topAndHeaderHeight + spacingHeight + timeRowHeight
        let ringFromWidth = size.width * 0.66
        let ringFromHeight = max(100 as CGFloat, size.height - fixedHeight)
        let constrainedRingSize = min(ringFromWidth, ringFromHeight)
        let ringSize = min(136 as CGFloat, max(102 as CGFloat, constrainedRingSize))

        return WatchTodayLayout(
            horizontalInset: max(6, min(9, size.width * 0.04)),
            topInset: topInset,
            bottomInset: bottomInset,
            headerTopSpacing: headerTopSpacing,
            ringTopSpacing: ringTopSpacing,
            timeTopSpacing: timeTopSpacing,
            centerTextSpacing: 2 + compactness,
            headerScale: 0.84 + (0.1 * compactness),
            headerHeight: headerHeight,
            ringSize: ringSize,
            ringLineWidth: max(9, min(12, ringSize * 0.1)),
            countdownFontSize: max(20, min(25, ringSize * 0.21)),
            durationFontSize: max(10, min(12, ringSize * 0.1)),
            captionFontSize: captionFontSize,
            timeFontSize: timeFontSize,
            timeRowWidth: min(max(138, size.width * 0.74), max(145, size.width - 44)),
            timeRowSpacing: max(10, min(16, size.width * 0.08))
        )
    }

    private var countdownText: String {
        Self.countdownString(seconds: countdownSeconds)
    }

    private var countdownSeconds: Int {
        guard let start = day.shiftStart, let end = day.shiftEnd, end > start else {
            return 0
        }

        if now < start {
            return max(0, Int(start.timeIntervalSince(now).rounded(.down)))
        }

        return max(0, Int(end.timeIntervalSince(now).rounded(.down)))
    }

    private var durationText: String {
        WatchCalendarShiftCard.hoursString(seconds: displayedDurationSeconds)
    }

    private var displayedDurationSeconds: Int {
        guard let start = day.shiftStart, let end = day.shiftEnd, end > start else {
            return day.workedSeconds
        }

        if snapshot.calendarHoursBreakModeRawValue == "withBreak" {
            return max(0, Int(end.timeIntervalSince(start)))
        }

        return day.workedSeconds
    }

    private var startTimeText: String {
        guard let start = day.shiftStart, day.isTimedShift else { return "Ganzt." }
        return Self.timeFormatter.string(from: start)
    }

    private var endTimeText: String {
        guard let end = day.shiftEnd, day.isTimedShift else { return "-" }
        return Self.timeFormatter.string(from: end)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func countdownString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct WatchTodayLayout {
    let horizontalInset: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let headerTopSpacing: CGFloat
    let ringTopSpacing: CGFloat
    let timeTopSpacing: CGFloat
    let centerTextSpacing: CGFloat
    let headerScale: CGFloat
    let headerHeight: CGFloat
    let ringSize: CGFloat
    let ringLineWidth: CGFloat
    let countdownFontSize: CGFloat
    let durationFontSize: CGFloat
    let captionFontSize: CGFloat
    let timeFontSize: CGFloat
    let timeRowWidth: CGFloat
    let timeRowSpacing: CGFloat
}

private struct WatchSwipeDownIndicator: View {
    let accent: Color
    let progress: Double

    var body: some View {
        MorphingSwipeDownIndicatorShape(progress: progress)
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.58), accent.opacity(0.9)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 28, height: 11)
        .frame(height: 16)
        .animation(.snappy(duration: 0.16), value: progress)
        .accessibilityHidden(true)
    }
}

private struct MorphingSwipeDownIndicatorShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let centerY = rect.midY + (rect.height * 0.34 * clampedProgress)
        let edgeY = rect.midY - (rect.height * 0.24 * clampedProgress)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: edgeY))
        path.addLine(to: CGPoint(x: rect.midX, y: centerY))
        path.addLine(to: CGPoint(x: rect.maxX, y: edgeY))
        return path
    }
}

private struct WatchEmptyShiftState: View {
    let accent: Color
    let failedReload: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: failedReload ? "wifi.slash" : "calendar.badge.clock")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(accent)

            Text(failedReload ? "iPhone nicht erreichbar" : "Keine Schichten")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(failedReload ? "Cache bleibt aktiv" : "Tippe links zum Laden")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WatchAppBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            Color.black

            LinearGradient(
                colors: [
                    accent.opacity(0.11),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
