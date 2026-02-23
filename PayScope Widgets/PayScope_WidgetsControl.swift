//
//  PayScope_WidgetsControl.swift
//  PayScope Widgets
//
//  Created by Dyonisos Fergadiotis on 18.02.26.
//

import AppIntents
import ActivityKit
import SwiftUI
import WidgetKit

struct PayScope_WidgetsControl: ControlWidget {
    static let kind: String = "DyonisosFergadiotis.PayScope.PayScope Widgets"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Live Activity",
                isOn: value.isRunning,
                action: StartTimerIntent(value.name)
            ) { isRunning in
                Label(isRunning ? "Aktiv" : "Start", systemImage: "timeline.selection")
            }
        }
        .displayName("PayScope Live")
        .description("Startet oder beendet die Live Activity direkt aus dem Control Center.")
    }
}

extension PayScope_WidgetsControl {
    struct Value {
        var isRunning: Bool
        var name: String
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: TimerConfiguration) -> Value {
            PayScope_WidgetsControl.Value(isRunning: false, name: configuration.timerName)
        }

        func currentValue(configuration: TimerConfiguration) async throws -> Value {
            let isRunning = !Activity<PayScope_WidgetsAttributes>.activities.isEmpty
            return PayScope_WidgetsControl.Value(isRunning: isRunning, name: configuration.timerName)
        }
    }
}

struct TimerConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Timer Name Configuration"

    @Parameter(title: "Timer Name", default: "Timer")
    var timerName: String
}

struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "PayScope Live Activity"

    @Parameter(title: "Timer Name")
    var name: String

    @Parameter(title: "Timer is running")
    var value: Bool

    init() {}

    init(_ name: String) {
        self.name = name
    }

    func perform() async throws -> some IntentResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .result()
        }

        if value {
            await startLiveActivity()
        } else {
            await stopLiveActivity()
        }

        return .result()
    }

    private func startLiveActivity() async {
        let now = Date()
        let end = now.addingTimeInterval(8 * 3600)
        let attributes = PayScope_WidgetsAttributes(
            title: name.isEmpty ? "Schicht" : name,
            timelineStart: now,
            timelineEnd: end
        )
        let content = ActivityContent(
            state: PayScope_WidgetsAttributes.ContentState(
                workedTodaySeconds: 0,
                workedReferenceStart: now,
                shiftCategoryIcon: "briefcase.fill",
                themeAccentRawValue: "system",
                isCompleted: false,
                completedPayCents: 0,
                nextShiftStart: nil,
                nextShiftDurationSeconds: 0
            ),
            staleDate: end
        )

        for activity in Activity<PayScope_WidgetsAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        _ = try? Activity<PayScope_WidgetsAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    private func stopLiveActivity() async {
        for activity in Activity<PayScope_WidgetsAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
