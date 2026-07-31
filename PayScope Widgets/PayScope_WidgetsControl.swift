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

struct PayScopeStartShiftControl: ControlWidget {
    static let kind = "DyonisosFergadiotis.PayScope.controls.startShift"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartShiftControlIntent()) {
                Label("Schicht starten", systemImage: "briefcase.fill")
            }
        }
        .displayName("Schicht starten")
        .description("Startet die heutige Schicht in PayScope.")
    }
}

struct PayScopeEndShiftControl: ControlWidget {
    static let kind = "DyonisosFergadiotis.PayScope.controls.endShift"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: EndShiftControlIntent()) {
                Label("Schicht beenden", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("Schicht beenden")
        .description("Beendet die aktuell laufende Schicht in PayScope.")
    }
}

struct PayScopeAddTipControl: ControlWidget {
    static let kind = "DyonisosFergadiotis.PayScope.controls.addTip"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AddTipControlIntent()) {
                Label("Trinkgeld", systemImage: "eurosign.circle.fill")
            }
        }
        .displayName("Trinkgeld hinzufügen")
        .description("Fragt nach dem genommenen Trinkgeld und fügt es in PayScope hinzu.")
    }
}

struct PayScopeMarkTodaySickControl: ControlWidget {
    static let kind = "DyonisosFergadiotis.PayScope.controls.markTodaySick"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MarkTodaySickControlIntent()) {
                Label("Krank", systemImage: "cross.case.fill")
            }
        }
        .displayName("Heute krank markieren")
        .description("Markiert den heutigen Tag in PayScope als krank.")
    }
}

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
                themeAccentRawValue: "blue",
                shiftCategoryColorRawValue: "blue",
                isTimedShift: true,
                isCompleted: false,
                completedPayCents: 0,
                nextShiftStart: nil,
                nextShiftDurationSeconds: 0,
                isPaused: false,
                pauseStartedAt: nil
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

enum PayScopeControlCenterActionKind: String, Codable {
    case startShift
    case endShift
    case startPause
    case endPause
    case addTip
    case markTodaySick
}

struct PayScopeControlCenterAction: Codable {
    var id: String
    var kind: PayScopeControlCenterActionKind
    var amountEuro: Double?
}

enum PayScopeControlCenterActionStore {
    private static let appGroupIdentifier = "group.DyonisosFergadiotis.PayScope"
    private static let pendingActionKey = "payscope.controlCenter.pendingAction.v1"

    static func savePendingAction(kind: PayScopeControlCenterActionKind, amountEuro: Double? = nil) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        let action = PayScopeControlCenterAction(
            id: UUID().uuidString,
            kind: kind,
            amountEuro: amountEuro
        )
        guard let data = try? JSONEncoder().encode(action) else { return }

        defaults.set(data, forKey: pendingActionKey)
        defaults.synchronize()
    }
}

private struct StartShiftControlIntent: AppIntent {
    static var title: LocalizedStringResource { "Schicht starten" }
    static var description: IntentDescription {
        IntentDescription("Startet die heutige Schicht in PayScope.")
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        PayScopeControlCenterActionStore.savePendingAction(kind: .startShift)
        return .result()
    }
}

private struct EndShiftControlIntent: AppIntent {
    static var title: LocalizedStringResource { "Schicht beenden" }
    static var description: IntentDescription {
        IntentDescription("Beendet die aktuell laufende Schicht in PayScope.")
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        PayScopeControlCenterActionStore.savePendingAction(kind: .endShift)
        return .result()
    }
}

struct StartPauseControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Pause starten" }
    static var description: IntentDescription {
        IntentDescription("Startet den Pausenmodus in PayScope.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        PayScopeControlCenterActionStore.savePendingAction(kind: .startPause)
        return .result()
    }
}

struct EndPauseControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Pause beenden" }
    static var description: IntentDescription {
        IntentDescription("Beendet den Pausenmodus in PayScope.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        PayScopeControlCenterActionStore.savePendingAction(kind: .endPause)
        return .result()
    }
}

private struct AddTipControlIntent: AppIntent {
    static var title: LocalizedStringResource { "Trinkgeld hinzufügen" }
    static var description: IntentDescription {
        IntentDescription("Fügt für heute Trinkgeld in PayScope hinzu.")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(
        title: "Betrag in Euro",
        requestValueDialog: "Wie viel Trinkgeld wurde genommen?"
    )
    var amount: Double

    init() {}

    func perform() async throws -> some IntentResult {
        PayScopeControlCenterActionStore.savePendingAction(kind: .addTip, amountEuro: amount)
        return .result()
    }
}

private struct MarkTodaySickControlIntent: AppIntent {
    static var title: LocalizedStringResource { "Heute krank markieren" }
    static var description: IntentDescription {
        IntentDescription("Markiert den heutigen Tag in PayScope als krank.")
    }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        PayScopeControlCenterActionStore.savePendingAction(kind: .markTodaySick)
        return .result()
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview("Rectangular Lock Screen (Real)", as: .accessoryRectangular) {
    PayScope_WidgetsRectangularLockScreen()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewLongDuration(date: .now)
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}

@available(iOS 18.0, *)
#Preview("Inline Lock Screen (Real)", as: .accessoryInline) {
    PayScope_WidgetsInlineLockScreen()
} timeline: {
    PayScopeRectangularEntry.previewActive(date: .now)
    PayScopeRectangularEntry.previewLongDuration(date: .now)
    PayScopeRectangularEntry.previewNextShift(date: .now)
    PayScopeRectangularEntry.previewEmpty(date: .now)
}
#endif
