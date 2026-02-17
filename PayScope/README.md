# WageWise

**WageWise – Arbeitszeit- und Lohntracker für iOS**  
Verwalte deine täglichen Arbeitszeiten, Pausen und Löhne einfach und übersichtlich.

---

## Badges

- iOS Version: 17+
- Swift: 6.0+
- SwiftUI: 6.0+
- SwiftData: aktuell
- Xcode Version: 26+

---

## Inhaltsverzeichnis

- [Übersicht](#übersicht)  
- [Features](#features)  
- [Screens und Nutzererlebnis](#screens-und-nutzererlebnis)  
- [Architektur](#architektur)  
- [Datenmodell](#datenmodell)  
- [Business-Regeln](#business-regeln)  
- [Konfiguration](#konfiguration)  
- [Build und Ausführung](#build-und-ausführung)  
- [Testing](#testing)  
- [Internationalisierung & Barrierefreiheit](#internationalisierung--barrierefreiheit)  
- [Persistenz Hinweise](#persistenz-hinweise)  
- [Erweiterbarkeit & Roadmap](#erweiterbarkeit--roadmap)  
- [Datenschutz](#datenschutz)  
- [Lizenz](#lizenz)  
- [Danksagungen](#danksagungen)  

---

## Übersicht

WageWise ist eine intuitive iOS-App zur präzisen Erfassung und Nachverfolgung von Arbeitszeiten und Löhnen. Der Kern liegt im `DayEditorView`, der einen mehrsegmentigen Tageseditor zur Verfügung stellt. Nutzer können manuelle Eingaben tätigen oder automatische Pausenverwaltung nutzen. Tagesarten wie Urlaub, Feiertag oder Krank können mit entsprechender Gutschrift ausgewählt werden. Eine übersichtliche Timeline mit Ticks zeigt alle Segmente, Notizen sind mit Inline-Material-Design eingebunden. Die App berechnet in Echtzeit Nettoarbeitsdauer und Bruttolohn.

---

## Features

- **Tageditor mit Timeline-Vorschau:** Visualisiert mehrere Zeitsegmente mit Start- und Endzeit-Pickern pro Segment.  
- **Automatische und individuelle Pausenverwaltung:** Pausen werden validiert und automatisch eingesetzt, können aber auch manuell angepasst werden.  
- **Manueller Modus:** Eingabe der Arbeitszeit über Stunden- und Minuten-Stepper ohne Pausenabzug.  
- **Tagesarten:** Unterschiedliche Typen (Arbeit, Urlaub, Feiertag, Krank) mit Tönung und Symbolen. Nicht-Arbeitstage werden automatisch mit einer Gutschrift versehen.  
- **Live-Metriken:** Dauer, Bruttolohn und Pausenzeit werden in der unteren Toolbar dynamisch angezeigt.  
- **Notiz-Editor:** Inline-Styling im Material-Design, um Tage mit zusätzlichen Informationen zu versehen.  
- **Automatische Nachberechnung:** Nach Änderungen werden folgende automatisch verwaltete Tage neu berechnet.  
- **Konfigurierbare Timeline-Grenzen:** Minimal- und Maximalzeiten sind über die Einstellungen anpassbar.  

---

## Screens und Nutzererlebnis

Die App bietet eine klare Struktur: Oben befindet sich die Timeline mit Ticks und Segmenten, darunter das Segmentpanel mit Start- und Endzeit-Pickern. Pausen werden direkt inline angepasst. Das Notizenfeld bietet Material-Style Eingabe. Die Toolbar am unteren Rand zeigt Live-Daten zu Dauer, Bruttolohn und Pausen. Alle Elemente sind mit Accessibility-Labels versehen, DatePicker nutzen in kompaktem Stil die native iOS-Bedienbarkeit.

---

## Architektur

WageWise basiert auf modernen Apple-Technologien:  

- **SwiftUI**: Fortschrittliche UI mit `NavigationStack` und `Toolbar` für Navigation und Aktionselemente.  
- **SwiftData**: Persistenz mit `@Model` für Datenobjekte, `@Query` für Abfragen und `@Environment(\.modelContext)` für Kontextverwaltung.  
- **Zustandsverwaltung**: `@State` für View-States, `@Bindable` für `Settings`.  
- **Berechnungslogik**: `CalculationService` kapselt Business-Logik, z.B. `dayComputation` und `creditedResult`.  
- **Domain-Modelle**: `DayEntry` und `TimeSegment` als zentrale Datenstrukturen sowie `DayType` Enum für Tagesarten.  
- **Formatierung**: Einheitliches Formatieren über `WageWiseFormatters`.  

### Beispiel: High-Level Speicher-Flow

```swift
var segments = dayEntry.segments
// Beispielhafte Berechnung der Pausenzeit für Segmente
let breakSeconds = CalculationService.computeBreakSeconds(for: segments) 
// Erstellen eines neuen Segments mit berechneter Pause
let newSegments = segments.map { segment in
    TimeSegment(start: segment.start, end: segment.end, breakSeconds: breakSeconds)
}

// Aktualisieren der Entry-Segmente
dayEntry.segments = newSegments
// Persistieren des Kontexts
modelContext.persistIfPossible()
