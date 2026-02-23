# PayScope

PayScope ist eine iOS-App zur Zeiterfassung mit Lohnberechnung, Monatsauswertung, CSV-Export, Feiertagsimport und Live Activity.

## Features
- Tageserfassung mit Segmenten (Start/Ende), Notizen und Tagestypen (`work`, `manual`, `vacation`, `holiday`, `sick`)
- Automatische und manuelle Pausenlogik inkl. Validierung
- Lohnberechnung für Stundenlohn und Monatsgehalt
- Monatsübersicht mit Brutto-/Nettoauswertung
- Statistikansicht mit Tages- und Monatsverlauf
- CSV-Export pro Monat
- Feiertagsimport über die Nager-Date API
- Widget + Live Activity (`PayScope WidgetsExtension`)

## Tech Stack
- SwiftUI
- SwiftData
- ActivityKit / WidgetKit
- Charts (wenn verfügbar)
- XCTest

## Voraussetzungen
- Xcode (aktuelle Version, Projekt ist derzeit auf iOS Deployment Target `26.2` gesetzt)
- iOS Simulator oder Gerät passend zum Deployment Target

## Projekt starten
```bash
open PayScope.xcodeproj
```

Dann in Xcode:
1. Scheme `PayScope` wählen.
2. Simulator/Gerät wählen.
3. Run (`Cmd + R`).

## Tests ausführen
In Xcode:
- `Product > Test` (`Cmd + U`)

Oder per CLI:
```bash
xcodebuild test \
  -project PayScope.xcodeproj \
  -scheme PayScope \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Architektur (Kurzüberblick)
- `PayScope/PayScopeApp.swift`: App-Entry, SwiftData-Container, Live-Activity-Sync
- `PayScope/UI/RootView.swift`: Einstieg in Onboarding oder Hauptansicht
- `PayScope/UI/Tabs/CalendarTabView.swift`: Hauptscreen mit Kalender, Monatsmetriken, Day Editor
- `PayScope/UI/Tabs/SettingsTabView.swift`: Konfiguration, Export, Feiertagsimport
- `PayScope/UI/Tabs/StatsTabView.swift`: Kennzahlen und Charts
- `PayScope/Core/CalculationService.swift`: zentrale Arbeitszeit-/Lohn-Logik
- `PayScope/Core/Models.swift`: SwiftData-Modelle (`DayEntry`, `TimeSegment`, `Settings`, `HolidayCalendarDay`, `NetWageMonthConfig`)

## Geschäftslogik
- Arbeitszeit kann aus Segmenten oder manuell (`manualWorkedSeconds`) kommen.
- Für Arbeitstage greift Pausenvalidierung und eine gesetzliche Mindestpausenlogik.
- Urlaub/Krank/Feiertag können über eine 13-Wochen-Rückschau bewertet werden.
- Fehlende Historie wird aktuell als `0` in die Rückschau einbezogen.

## Daten & Datenschutz
- Daten werden lokal via SwiftData gespeichert.
- Es gibt keine eigene Backend-Infrastruktur in diesem Repo.
- Netzwerkzugriff wird nur für den Feiertagsimport verwendet (`https://date.nager.at/...`).

## Projektstruktur
```text
PayScope/
  Core/
  Export/
  Helpers/
  UI/
PayScope Widgets/
PayScopeTests/
PayScope.xcodeproj
```

## Hinweise
- App-Texte und UX sind aktuell primär auf Deutsch ausgelegt.
- Eine `LICENSE`-Datei ist im Repository aktuell nicht enthalten.
