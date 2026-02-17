# PayScope

Die professionelle Arbeitszeit- und Lohnübersicht für iOS – erfasse Arbeitstage präzise, verwalte Pausen intelligent und behalte deine Vergütung in Echtzeit im Blick.

- iOS: 17+
- Swift: 5.9+
- SwiftUI: ✓
- SwiftData: ✓
- Xcode: 26+

## Inhaltsverzeichnis
- [Überblick](#überblick)
- [Funktionen](#funktionen)
- [Screens & UX](#screens--ux)
- [Schnellstart](#schnellstart)
- [Architektur](#architektur)
- [Datenmodell](#datenmodell)
- [Geschäftsregeln](#geschäftsregeln)
- [Konfiguration](#konfiguration)
- [Bauen & Ausführen](#bauen--ausführen)
- [Testen](#testen)
- [Lokalisierung & Barrierefreiheit](#lokalisierung--barrierefreiheit)
- [Persistenz](#persistenz)
- [Projektstruktur](#projektstruktur)
- [Erweiterbarkeit & Roadmap](#erweiterbarkeit--roadmap)
- [Bekannte Einschränkungen](#bekannte-einschränkungen)
- [Datenschutz](#datenschutz)
- [Lizenz](#lizenz)
- [Danksagungen](#danksagungen)
- [Support & Beiträge](#support--beiträge)

## Überblick
PayScope ist eine moderne iOS-App zur Erfassung von Arbeitszeiten und zur Berechnung deiner Vergütung. Der Tageseditor unterstützt mehrteilige Arbeitssegmente, eine automatische sowie manuelle Pausenverwaltung, manuelle Gesamtdauererfassung und „angerechnete“ Tagestypen wie Urlaub, Feiertag oder Krank. Eine Timeline-Vorschau visualisiert den Tag, während Live-Metriken (Dauer, Brutto, Pause) jederzeit sichtbar sind. Änderungen an einem Tag können automatisch nachfolgende, automatisch verwaltete angerechnete Tage aktualisieren.

Wesentliche Bausteine in der UI sind der Segment-Editor, der Pausen-Inline-Editor, der Notizbereich und die untere Toolbar mit Kennzahlen. Die Berechnung der Vergütung erfolgt über eine zentrale `CalculationService`-Komponente.

## Funktionen
- Tageseditor mit Timeline-Vorschau und Segmentbearbeitung (Start/Ende je Segment)
- Automatische und benutzerdefinierte Pausenverwaltung mit Validierung
- Manueller Erfassungsmodus (Dauer HH:MM) ohne Pausenabzug
- Tagestypen mit Icon/Tint und automatischer Anrechnung für Nicht-Arbeitstage (z. B. Urlaub, Feiertag, Krank)
- Live-Metriken in der unteren Toolbar: Dauer, Bruttovergütung, Pause
- Notizen-Editor mit Material-Optik
- Automatische Neuberechnung nachfolgender, automatisch verwalteter angerechneter Einträge bei Änderungen
- Konfigurierbare Timeline-Grenzen über `Settings` (Min-/Max-Minuten)

## Screens & UX
- Obere Timeline: `MultiSegmentTimelinePreview` zeigt Segmente und Stundenmarken.
- Segmente-Panel: Hinzufügen/Entfernen von Segmenten, Start-/Endzeit über kompakte `DatePicker` je Segment, Dauerhinweis und Validierung.
- Pausen-Inline-Editor: Schnelle Anpassung in 1- oder 5-Minuten-Schritten und „Auto“-Vorschlag.
- Notizen: Ein-/ausblendbarer Editor für Textnotizen zum Tag.
- Toolbar-Metriken: Anzeige von Netto-Dauer, Bruttobetrag und Pausen (je nach Modus/Tagestyp).
- Zugänglichkeit: Wichtige Aktionen sind mit Accessibility-Labels versehen (z. B. „Schließen“, „Speichern“, „Tagestyp“).

## Schnellstart
1. Projekt in Xcode öffnen und ein Ziel (Simulator oder Gerät) wählen.
2. App starten. Wähle ein Datum über den kompakten `DatePicker` in der Navigation.
3. Tagestyp wählen (z. B. Arbeit, Urlaub, Feiertag, Krank).
4. Arbeitssegmente anlegen und Zeiten anpassen – oder in den manuellen Modus wechseln, um eine Gesamtdauer zu erfassen.
5. Bei Arbeitstagen Pausen automatisch vorschlagen lassen oder manuell anpassen.
6. Live-Metriken prüfen und „Speichern“ tippen.

## Architektur
- UI: SwiftUI (`NavigationStack`, Toolbars, Material-Styles, kompakte `DatePicker`).
- Persistenz: SwiftData via `@Query` und `@Environment(\.modelContext)`.
- Zustand: `@State` für View-Zustand und `@Bindable` für `Settings`.
- Domäne: `DayEntry`, `TimeSegment`, `DayType`.
- Service: `CalculationService` für Geschäftslogik (`dayComputation`, `creditedResult`).
- Formatierung: `WageWiseFormatters` für Datum, Zeit und Währung.

Beispiel: Speichern eines Arbeitstags mit Segmenten und Pausen
```swift
// Clamping der Pausen auf die Bruttodauer
let clampedBreakSeconds = (selectedType == .work) ? max(0, min(totalBreakMinutes * 60, totalGrossSeconds)) : 0
var didAssignBreak = false

// Segmente neu aufbauen und die Pause nur einmal vergeben
target.segments.removeAll()
for segment in editSegments {
    guard let start = dateAtMinute(segment.startMinute),
          let end = dateAtMinute(segment.endMinute) else { continue }
    let breakSeconds = didAssignBreak ? 0 : clampedBreakSeconds
    target.segments.append(TimeSegment(start: start, end: end, breakSeconds: breakSeconds))
    didAssignBreak = true
}

// Manueller Modus speichert stattdessen die Gesamtdauer und keine Segmente
if isManualEntry {
    target.manualWorkedSeconds = max(0, manualWorkedSeconds)
    target.segments = []
} else {
    target.manualWorkedSeconds = nil
}

modelContext.persistIfPossible()
