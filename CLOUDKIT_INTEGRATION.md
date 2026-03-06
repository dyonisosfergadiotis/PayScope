# CloudKit-Integration für PayScope

Diese Dokumentation zeigt auf, wie die CloudKit-Synchronisierung in PayScope integriert ist.

## Komponenten

### 1. CloudKitService (`Core/CloudKitService.swift`)
Der Hauptservice für alle CloudKit-Operationen. Er verwaltet:
- **Verbindung**: Zugriff auf private, öffentliche und shared CloudKit-Datenbanken
- **Speichern**: `saveDayEntry()`, `saveTimeSegment()`
- **Abrufen**: `fetchDayEntries()`, `fetchTimeSegments()`
- **Account-Status**: `checkAccountStatus()`

### 2. CloudKitViewModel (`Helpers/CloudKitViewModel.swift`)
Ein @MainActor final ViewModel für die SwiftUI-Integration:
- Verwaltet den Account-Status
- Koordiniert Sync-Operationen
- Behandelt Fehler und Logging

### 3. CloudKitOnboardingView (`UI/Onboarding/CloudKitOnboardingView.swift`)
Eine UI-Komponente für das Onboarding:
- Prüft iCloud-Verfügbarkeit
- Zeigt Account-Status an
- Optionale Einrichtung für neue Benutzer

## CloudKit Schema

Das Schema muss manuell im CloudKit Dashboard eingerichtet werden:

### Record Types

#### DayEntry
```
- date (DateTime, queryable, indexed)
- dayType (String)
- notes (String, optional)
- manualWorkedSeconds (Int64, optional)
- creditedOverrideSeconds (Int64, optional)
```

#### TimeSegment
```
- start (DateTime, queryable, indexed)
- end (DateTime, queryable, indexed)
- breakSeconds (Int64)
```

#### Settings
```
- payMode (String)
- hourlyRateCents (Int64, optional)
- monthlySalaryCents (Int64, optional)
- weeklyTargetSeconds (Int64, optional)
- weekStart (String)
- holidayCreditingMode (String)
- themeAccent (String)
```

## Integrations-Stellen

### 1. In RootView.swift - Onboarding hinzufügen
```swift
NavigationStack {
    if !viewModel.hasCompletedOnboarding {
        CloudKitOnboardingView()
    } else {
        ContentView()
    }
}
```

### 2. In Settings anzeigen - CloudKit Status
```swift
// In SettingsTabView.swift
Section("Synchronisierung") {
    @StateObject var cloudKitVM = CloudKitViewModel()
    
    HStack {
        Text("iCloud Status")
        Spacer()
        Text(cloudKitVM.accountStatus.description)
    }
    
    if let date = cloudKitVM.lastSyncDate {
        Text("Letzte Synchronisierung: \(date.formatted())")
            .font(.caption)
    }
}
```

### 3. Auto-Sync in Persistence
```swift
// Bei jeder Änderung könnte auto-synced werden:
@Environment(\.cloudKitViewModel) var cloudKitVM

// Nach dem Speichern:
Task {
    await cloudKitVM.syncDayEntries([entry])
}
```

## Fehlerbehandlung

CloudKit kann mehrere Fehler werfen:
- `CKError.notAuthenticated` - Benutzer nicht angemeldet
- `CKError.networkFailure` - Netzwerkproblem
- `CKError.serviceUnavailable` - CloudKit nicht verfügbar
- `CKError.quotaExceeded` - Speicher voll

Alle Fehler werden geloggt und in `syncError` des ViewModels gespeichert.

## Best Practices

1. **Konten-Check**: Immer `checkAccountStatus()` vor Sync-Operationen aufrufen
2. **Fehlerbehandlung**: Fehler sollten dem Benutzer angezeigt werden
3. **Background Sync**: Für großere Datenmengen async/await nutzen
4. **Konfliktlösung**: Bei Duplikaten wird die neueste Version verwendet
5. **Netzwerk**: Offline-First Ansatz - lokal speichern, dann syncer

## Testing

Die CloudKitService und CloudKitViewModel sollten für Unit-Tests mockbar sein:
```swift
protocol CloudKitServiceProtocol {
    func saveDayEntry(_ entry: DayEntry) async throws
    func fetchDayEntries(in interval: DateInterval) async throws -> [DayEntry]
}
```

## Schema-Deployment

1. Öffne das [CloudKit Dashboard](https://icloud.developer.apple.com/)
2. Wähle die App und das Projekt
3. Gehe zu "Signing and Capabilities" → CloudKit
4. Öffne das CloudKit Dashboard
5. Schema → Record Types → Erstelle die oben beschriebenen Typen
6. Schema → Indexes → Erstelle Indizes für queryable Felder
7. Deploye das Schema in Production mit Button "Deploy to Production"

## Development vs. Production

Während der Entwicklung nutzt die App automatisch die **Development**-Umgebung.
Vor TestFlight/App Store Release muss das Schema in die **Production**-Umgebung deployet werden.
