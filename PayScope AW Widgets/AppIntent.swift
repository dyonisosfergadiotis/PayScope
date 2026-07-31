//
//  AppIntent.swift
//  PayScope AW Widgets
//
//  Created by Dyonisos Fergadiotis on 25.06.26.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Konfiguration" }
    static var description: IntentDescription { "Konfiguriert das PayScope-Widget." }

    @Parameter(title: "Lieblings-Emoji", default: "😃")
    var favoriteEmoji: String
}
