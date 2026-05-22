# Git Branches

`main` bleibt die stabile Release-Basis. Neue Arbeit bekommt einen sprechenden Branch mit dem Prefix `codex/`.

## Aktueller Arbeitsbranch

- `codex/payscope-integration-1-6-3`: aktueller Gesamtstand mit iOS-App, Mac-App, Widgets, Launchscreen, Icons und Xcode-Konfiguration.

## Benannte Fachbranches fuer die naechsten Aufteilungen

- `codex/ios-ui-calendar-editor`: iOS-UI, Kalender, Tageseditor, Einstellungen, Statistik, Heute-Ansicht und Theme.
- `codex/core-tips-calculation-export`: Datenmodelle, Berechnung, Trinkgeld, CloudKit-/Kalender-Sync, Export und Tests.
- `codex/widgets-live-activity-control-center`: Widgets, Live Activity, AppIntents und Control-Center-Aktionen.
- `codex/mac-app-sync`: Mac-App, Kalenderansicht, Menu-Bar-Icon und CloudKit-Lesedienst.
- `codex/launchscreen-icons`: Launchscreen-Assets, Splash-View und App-Icon-Dateien.
- `codex/xcode-project-config`: Xcode-Projektdatei, SwiftPM-Pins und geteilte Schemes.

## Regeln

- Keine direkte Feature-Arbeit auf `main`.
- Vor riskanten Umbauten zuerst einen Branch vom aktuellen `main` erstellen.
- Xcode-Userdaten und lokale Build-Ausgaben bleiben unversioniert.
