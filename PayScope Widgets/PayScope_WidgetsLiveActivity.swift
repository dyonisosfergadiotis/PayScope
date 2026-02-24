//
//  PayScope_WidgetsLiveActivity.swift
//  PayScope Widgets
//
//  Created by Dyonisos Fergadiotis on 18.02.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PayScope_WidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var workedTodaySeconds: Int
        var workedReferenceStart: Date
        var shiftCategoryIcon: String
        var themeAccentRawValue: String
        var isCompleted: Bool
        var completedPayCents: Int
        var nextShiftStart: Date?
        var nextShiftDurationSeconds: Int
    }

    var title: String
    var timelineStart: Date
    var timelineEnd: Date
}

struct PayScope_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PayScope_WidgetsAttributes.self) { context in
            PayScopeLiveActivityExpandedContent(context: context)
                .activityBackgroundTint(liveAccentColor(from: context.state.themeAccentRawValue).opacity(0.18))
                .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    PayScopeLiveActivityDynamicIslandCenterContent(context: context)
                }

                DynamicIslandExpandedRegion(.bottom, priority: 1) {
                    PayScopeLiveActivityDynamicIslandBottomContent(context: context)
                }
            } compactLeading: {
                if context.state.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                } else {
                    Image(systemName: context.state.shiftCategoryIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                }
            } compactTrailing: {
                if context.state.isCompleted {
                    Text(context.state.nextShiftDurationSeconds > 0 ? hhmmString(from: context.state.nextShiftDurationSeconds) : "--:--")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                } else {
                    Text(timeString(context.attributes.timelineEnd))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                }
            } minimal: {
                Image(systemName: context.state.isCompleted ? "checkmark.circle.fill" : context.state.shiftCategoryIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
            }
            .keylineTint(liveAccentColor(from: context.state.themeAccentRawValue))
        }
    }
}

private struct PayScopeLiveActivityExpandedContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    var body: some View {
        PayScopeLiveActivityMainView(context: context)
            .padding(16)
    }
}

private struct PayScopeLiveActivityDynamicIslandCenterContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveAccentColor(from: context.state.themeAccentRawValue)
    }

    var body: some View {
        if context.state.isCompleted {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gut gemacht")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text("\(currencyString(cents: context.state.completedPayCents)) · \(hhmmString(from: context.state.workedTodaySeconds))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                RemainingTimerText(end: context.attributes.timelineEnd)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PayScopeLiveActivityDynamicIslandBottomContent: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    private var accent: Color {
        liveAccentColor(from: context.state.themeAccentRawValue)
    }

    var body: some View {
        if context.state.isCompleted {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                Text(nextShiftText(start: context.state.nextShiftStart, durationSeconds: context.state.nextShiftDurationSeconds))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(
                    timerInterval: context.attributes.timelineStart...context.attributes.timelineEnd,
                    countsDown: false,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .progressViewStyle(.linear)
                .tint(accent)

                HStack(alignment: .firstTextBaseline) {
                    WorkedTimerText(
                        start: context.state.workedReferenceStart,
                        end: context.attributes.timelineEnd
                    )
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(timeString(context.attributes.timelineStart)) - \(timeString(context.attributes.timelineEnd))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension PayScope_WidgetsAttributes {
    fileprivate static var preview: PayScope_WidgetsAttributes {
        PayScope_WidgetsAttributes(
            title: "Arbeit heute",
            timelineStart: Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: .now) ?? .now,
            timelineEnd: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now
        )
    }
}

extension PayScope_WidgetsAttributes.ContentState {
    fileprivate static var morning: PayScope_WidgetsAttributes.ContentState {
        PayScope_WidgetsAttributes.ContentState(
            workedTodaySeconds: 2 * 3600 + 20 * 60,
            workedReferenceStart: .now.addingTimeInterval(-(2 * 3600 + 20 * 60)),
            shiftCategoryIcon: "briefcase.fill",
            themeAccentRawValue: "blue",
            isCompleted: false,
            completedPayCents: 0,
            nextShiftStart: nil,
            nextShiftDurationSeconds: 0
        )
    }

    fileprivate static var afternoon: PayScope_WidgetsAttributes.ContentState {
        PayScope_WidgetsAttributes.ContentState(
            workedTodaySeconds: 6 * 3600 + 40 * 60,
            workedReferenceStart: .now.addingTimeInterval(-(6 * 3600 + 40 * 60)),
            shiftCategoryIcon: "square.and.pencil",
            themeAccentRawValue: "green",
            isCompleted: true,
            completedPayCents: 18640,
            nextShiftStart: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            nextShiftDurationSeconds: 8 * 3600
        )
    }
}

#Preview("Notification", as: .content, using: PayScope_WidgetsAttributes.preview) {
    PayScope_WidgetsLiveActivity()
} contentStates: {
    PayScope_WidgetsAttributes.ContentState.morning
    PayScope_WidgetsAttributes.ContentState.afternoon
}

private struct PayScopeLiveActivityMainView: View {
    let context: ActivityViewContext<PayScope_WidgetsAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(context.state.isCompleted ? "Gut gemacht" : context.attributes.title)
                .font(.headline)
                .foregroundStyle(context.state.isCompleted ? liveAccentColor(from: context.state.themeAccentRawValue) : .primary)

            if context.state.isCompleted {
                Text("Heute hast du \(currencyString(cents: context.state.completedPayCents)) mit \(hhmmString(from: context.state.workedTodaySeconds)) Arbeit erzielt.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Color.accentColor)
                    Text(nextShiftText(start: context.state.nextShiftStart, durationSeconds: context.state.nextShiftDurationSeconds))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        RemainingTimerText(end: context.attributes.timelineEnd)
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(liveAccentColor(from: context.state.themeAccentRawValue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer()
                        VStack{
                            Spacer()
                            Text("\(timeString(context.attributes.timelineStart)) - \(timeString(context.attributes.timelineEnd))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(
                        timerInterval: context.attributes.timelineStart...context.attributes.timelineEnd,
                        countsDown: false
                    )
                    .tint(liveAccentColor(from: context.state.themeAccentRawValue))

                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}

private struct RemainingTimerText: View {
    let end: Date

    var body: some View {
        if end > .now {
            Text(timerInterval: Date()...end, countsDown: true, showsHours: true)
        } else {
            Text("00:00:00")
        }
    }
}

private struct WorkedTimerText: View {
    let start: Date
    let end: Date

    var body: some View {
        if end > .now {
            Text(timerInterval: start...end, countsDown: false, showsHours: true)
        } else {
            Text(hhmmssString(from: max(0, Int(end.timeIntervalSince(start)))))
        }
    }
}

private func liveAccentColor(from rawValue: String) -> Color {
    switch rawValue {
    case "blue": return .blue
    case "green": return .green
    case "purple": return .purple
    case "orange": return .orange
    case "pink": return .pink
    default: return .accentColor
    }
}

private func hhmmString(from seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    return String(format: "%02d:%02d", hours, minutes)
}

private func hhmmssString(from seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    let secs = safe % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
}

private func currencyString(cents: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale.current
    return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "-"
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func nextShiftText(start: Date?, durationSeconds: Int) -> String {
    guard let start else { return "Nächste Schicht: noch nicht geplant" }
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "dd.MM."
    let timeFormatter = DateFormatter()
    timeFormatter.timeStyle = .short
    return "Nächste Schicht: \(dayFormatter.string(from: start)) ab \(timeFormatter.string(from: start)) für \(hhmmString(from: durationSeconds))"
}
