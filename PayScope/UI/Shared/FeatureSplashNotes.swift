import SwiftUI
import Notelet

enum FeatureSplashNotes {
    static let version = "payscope-feature-splash-v1"
    static let storageKey = "payscope.featureSplash.v1.seen"

    static let notes: [NoteletVersionNotes] = [
        NoteletVersionNotes(
            version: version,
            items: [
                .list(
                    title: "Schichten hinzufügen",
                    rows: [
                        .init(
                            symbolSystemName: "calendar.badge.plus",
                            title: "Tag antippen",
                            description: "Öffne einen Kalendertag und trage Start, Ende, Pause und Kategorie ein."
                        ),
                        .init(
                            symbolSystemName: "pencil",
                            title: "Schnell bearbeiten",
                            description: "Bestehende Einträge lassen sich direkt aus der Tagesansicht ändern."
                        ),
                        .init(
                            symbolSystemName: "trash",
                            title: "Gezielt löschen",
                            description: "Löschen sitzt im Tagesblatt, damit versehentliche Long-Press-Aktionen wegfallen."
                        )
                    ]
                ),
                .list(
                    title: "Statistiken",
                    rows: [
                        .init(
                            symbolSystemName: "chart.bar.xaxis",
                            title: "Monat im Blick",
                            description: "Wechsle den Monat und vergleiche Stunden, Lohn und Tagestypen."
                        ),
                        .init(
                            symbolSystemName: "calendar",
                            title: "Gleicher Monatsregler",
                            description: "Kalender und Statistik teilen sich dieselbe Monatsauswahl."
                        ),
                        .init(
                            symbolSystemName: "eurosign.circle",
                            title: "Lohnwerte prüfen",
                            description: "Die Auswertungen nutzen dieselben Regeln wie deine Tagesberechnung."
                        )
                    ]
                ),
                .list(
                    title: "Trinkgeld",
                    rows: [
                        .init(
                            symbolSystemName: "eurosign.circle.fill",
                            title: "Monatssumme öffnen",
                            description: "Der Trinkgeld-Button im Kalender führt zur Monatsliste."
                        ),
                        .init(
                            symbolSystemName: "plus",
                            title: "Beträge hinzufügen",
                            description: "Erfasse Trinkgeld pro Tag und passe Einträge später wieder an."
                        ),
                        .init(
                            symbolSystemName: "square.and.arrow.up",
                            title: "Export inklusive",
                            description: "Bei Monatsauswertungen kann Trinkgeld mit ausgegeben werden."
                        )
                    ]
                ),
                .list(
                    title: "Heute",
                    rows: [
                        .init(
                            symbolSystemName: "sun.max.fill",
                            title: "Aktuelle Schicht",
                            description: "Die Heute-Ansicht zeigt Fortschritt, verbleibende Zeit und laufenden Lohn."
                        ),
                        .init(
                            symbolSystemName: "timer",
                            title: "Live aktualisiert",
                            description: "Während einer Schicht werden Zeit und Fortschritt automatisch nachgeführt."
                        ),
                        .init(
                            symbolSystemName: "target",
                            title: "Sollzeit vergleichen",
                            description: "Tages- und Wochenwerte zeigen, wo du gerade stehst."
                        )
                    ]
                ),
                .list(
                    title: "Widgets",
                    rows: [
                        .init(
                            symbolSystemName: "rectangle.on.rectangle",
                            title: "Lock Screen",
                            description: "Widgets zeigen Status, nächste Schicht und Ganztagseinstellungen."
                        ),
                        .init(
                            symbolSystemName: "livephoto",
                            title: "Live Activity",
                            description: "Geplante Schichten können automatisch als Live Activity starten."
                        ),
                        .init(
                            symbolSystemName: "arrow.clockwise",
                            title: "Sofort aktualisieren",
                            description: "In den Einstellungen kannst du Widgets manuell neu laden."
                        )
                    ]
                )
            ]
        )
    ]
}
