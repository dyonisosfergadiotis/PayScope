# Calendar Today Shift Bottom Bar Backup

Source: `origin/main` at `b60655d40120880af1bd32c0f4e1ffe272086c6e`

This is the removed bottom calendar toolbar that showed today's shift preview. It is kept outside the app targets so the current UI stays without the bar.

## Toolbar Placement

```swift
ToolbarItem(placement: .bottomBar) {
    HStack {
        Spacer(minLength: 0)
        Button {
            jumpToCurrentMonth()
            activeSheet = .today
        } label: {
            todayBottomBarPill
        }
        .buttonStyle(.plain)
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
}
```

## Bottom Bar View And Helpers

```swift
private func jumpToCurrentMonth() {
    let currentMonth = displayedMonth.startOfMonthLocal()
    let targetMonth = Date().startOfMonthLocal()
    guard !currentMonth.isSameLocalDay(as: targetMonth) else {
        displayedMonth = Date()
        return
    }

    displayedMonth = targetMonth
}

private var todayBottomBarWidth: CGFloat {
    let baseWidth = toolbarContainerWidth > 0 ? toolbarContainerWidth : 390
    let proposedWidth = baseWidth * 0.9
    return min(max(proposedWidth, 276), 388)
}

private var todayBottomBarHeight: CGFloat {
    let scaledHeight = todayBottomBarWidth * 0.17
    return min(max(scaledHeight, 54), 68)
}

private var todayBottomBarRingSize: CGFloat {
    let scaledRing = todayBottomBarHeight * 0.52
    return min(max(scaledRing, 30), 40)
}

private var todayBottomBarPill: some View {
    HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {

            Text(todayWorkedDisplay)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("Heute • \(PayScopeFormatters.day.string(from: todayStart))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }

        Spacer(minLength: 6)

        CompletionRing(
            progress: todayShiftCompletionFraction,
            accent: settings.themeAccent.color
        )
        .frame(width: todayBottomBarRingSize, height: todayBottomBarRingSize)
        .padding(4)
        .background(
            Circle()
                .fill(settings.themeAccent.color.opacity(0.1))
        )
        .overlay(
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 0.8)
        )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 13)
    .padding(.vertical, 9)
    .frame(width: todayBottomBarWidth, height: todayBottomBarHeight, alignment: .leading)
    .background(
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        settings.themeAccent.color.opacity(0.3),
                        settings.themeAccent.color.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    )
    .overlay(
        Capsule(style: .continuous)
            .stroke(.white.opacity(0.08), lineWidth: 0.8)
    )
    .overlay(
        Capsule(style: .continuous)
            .stroke(settings.themeAccent.color.opacity(0.34), lineWidth: 1.1)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Heute Vorschau")
    .accessibilityValue("\(todayWorkedDisplay), \(todayShiftCompletionPercent)% der Schichtlänge")
}

private var todayStart: Date {
    now.startOfDayLocal()
}

private var todayEntry: DayEntry? {
    entries.first(where: { $0.date.isSameLocalDay(as: todayStart) })
}

private var todayWorkedDisplay: String {
    "\(PayScopeFormatters.hhmmString(seconds: todayWorkedSeconds)) h"
}

private var todayWorkedSeconds: Int {
    workedSeconds(until: now, for: todayEntry)
}

private var todayShiftCompletionFraction: Double {
    guard todayShiftLengthSeconds > 0 else { return 0 }
    let fraction = Double(todayWorkedSeconds) / Double(todayShiftLengthSeconds)
    return min(max(fraction, 0), 1)
}

private var todayShiftCompletionPercent: Int {
    Int((todayShiftCompletionFraction * 100).rounded())
}

private var todayShiftLengthSeconds: Int {
    shiftLengthSeconds(for: todayEntry)
}

private var plannedDaySeconds: Int? {
    guard let weeklyTarget = settings.weeklyTargetSeconds else { return nil }
    let days = max(1, settings.scheduledWorkdaysCount)
    return max(0, Int((Double(weeklyTarget) / Double(days)).rounded()))
}

private func shiftLengthSeconds(for day: DayEntry?) -> Int {
    guard let day else {
        return max(0, plannedDaySeconds ?? 0)
    }
    if let manual = day.manualWorkedSeconds {
        return max(0, manual)
    }

    if let start = day.shiftStart, let end = day.shiftEnd, end > start {
        let gross = max(0, Int(end.timeIntervalSince(start)))
        let breakSeconds = max(0, day.breakSeconds ?? 0)
        return max(0, gross - breakSeconds)
    }

    return max(0, plannedDaySeconds ?? 0)
}
```

## Completion Ring

```swift
private struct CompletionRing: View {
    let progress: Double
    let accent: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    accent.opacity(0.2),
                    lineWidth: 6
                )

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    accent,
                    style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}
```
