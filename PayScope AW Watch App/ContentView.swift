import Combine
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WatchShiftViewModel()
    @State private var now = Date()
    @State private var focusScrollRequest = 0
    @State private var isTodayFocusPresented = false

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
                        isTodayFocusPresented = true
                    }
                )
            }
            .sheet(isPresented: $isTodayFocusPresented) {
                if let snapshot = viewModel.snapshot,
                   let focusDay = snapshot.focusDay(at: now) {
                    WatchTodayFocusView(
                        day: focusDay,
                        snapshot: snapshot,
                        now: now
                    )
                } else {
                    WatchEmptyShiftState(accent: accent, failedReload: viewModel.lastReloadFailed)
                }
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
            Button(action: todayAction) {
                WatchTodayToolbarButton(
                    accent: focusDay?.categoryColor ?? accent,
                    progress: focusDay?.progress(at: now) ?? 0
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Heute")
            .handGestureShortcut(.primaryAction)
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

            Text("Today")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
            .onChange(of: snapshot.generatedAt) { _, _ in
                didScrollToFocus = false
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
                Text(day.date, format: .dateTime.weekday(.wide))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(isToday ? accent : .primary.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                Text(day.date, format: .dateTime.month(.wide))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }
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

                    HStack(alignment: .center, spacing: 7) {
                        Text(startTimeText)
                            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text(durationMetric)
                            .font(.system(size: 11, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(accent.opacity(0.62), lineWidth: 1)
                            }

                        Spacer(minLength: 2)

                        Text(endTimeText)
                            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
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

    private var accent: Color {
        day.categoryColor
    }

    var body: some View {
        ZStack {
            WatchAppBackground(accent: accent)

            VStack(spacing: 12) {
                WatchCalendarDayHeader(day: day, now: now, accent: accent)
                    .padding(.top, 2)

                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.16), lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: min(max(day.progress(at: now), 0), 1))
                        .stroke(
                            accent,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 3) {
                        Text(progressText)
                            .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)

                        Text(day.dayTypeLabel)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(width: 116, height: 116)

                VStack(spacing: 7) {
                    focusMetricRow("Start", value: startTimeText)
                    focusMetricRow("Ende", value: endTimeText)
                    focusMetricRow("Dauer", value: WatchCalendarShiftCard.hoursString(seconds: day.workedSeconds))
                    focusMetricRow("Geld", value: payMetric)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func focusMetricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var progressText: String {
        "\(Int((day.progress(at: now) * 100).rounded()))%"
    }

    private var startTimeText: String {
        guard let start = day.shiftStart, day.isTimedShift else { return "Ganzt." }
        return Self.timeFormatter.string(from: start)
    }

    private var endTimeText: String {
        guard let end = day.shiftEnd, day.isTimedShift else { return "-" }
        return Self.timeFormatter.string(from: end)
    }

    private var payMetric: String {
        Self.currencyFormatter.string(from: NSNumber(value: Double(day.isActive(at: now) ? day.earnedSoFarPayCents : day.payCents) / 100.0)) ?? "0,00 €"
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
