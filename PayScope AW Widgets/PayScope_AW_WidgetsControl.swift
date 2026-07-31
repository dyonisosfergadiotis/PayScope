//
//  PayScope_AW_WidgetsControl.swift
//  PayScope AW Widgets
//
//  Created by Dyonisos Fergadiotis on 25.06.26.
//

import AppIntents
import SwiftUI
import WidgetKit

struct PayScope_AW_WidgetsControl: ControlWidget {
    static let kind: String = "DyonisosFergadiotis.PayScope.watchkitapp.PayScope AW Widgets"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Schicht starten",
                isOn: value.isRunning,
                action: StartTimerIntent(value.name)
            ) { isRunning in
                Label(isRunning ? "Aktiv" : "Inaktiv", systemImage: "timer")
            }
        }
        .displayName("Schicht")
        .description("Startet oder stoppt eine PayScope-Schicht.")
    }
}

extension PayScope_AW_WidgetsControl {
    struct Value {
        var isRunning: Bool
        var name: String
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: TimerConfiguration) -> Value {
            PayScope_AW_WidgetsControl.Value(isRunning: false, name: configuration.timerName)
        }

        func currentValue(configuration: TimerConfiguration) async throws -> Value {
            let isRunning = true // Check if the timer is running
            return PayScope_AW_WidgetsControl.Value(isRunning: isRunning, name: configuration.timerName)
        }
    }
}

struct TimerConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Schicht-Konfiguration"

    @Parameter(title: "Schichtname", default: "Schicht")
    var timerName: String
}

struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Schicht starten"

    @Parameter(title: "Schichtname")
    var name: String

    @Parameter(title: "Schicht läuft")
    var value: Bool

    init() {}

    init(_ name: String) {
        self.name = name
    }

    func perform() async throws -> some IntentResult {
        // Start the timer…
        return .result()
    }
}
