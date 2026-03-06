# CloudKit Sync Verifikations-Checkliste

## 1. CloudKit Schema Deployment Status

**Zu prüfen im Xcode CloudKit Dashboard:**

- [ ] Öffne dein Xcode Projekt
- [ ] CloudKit Console: https://icloud.developer.apple.com/dashboard
- [ ] Wähle deine App aus (PayScope)
- [ ] **Development Environment:**
  - [ ] Gehe zu "Schema"
  - [ ] Alle deine CustomZone Typen sind dort sichtbar (DayEntry, Settings, NetWageMonthConfig, HolidayCalendarDay, etc.)
  - [ ] Wenn die Liste leer oder unvollständig ist → **Schema wurde nicht deployed. Das ist das Hauptproblem.**
- [ ] **Production Environment:**
  - [ ] Gleiches überprüfen wie Development
  - [ ] Muss auch dort vollständig sein für App Store Builds

**Falls Schema nicht deployed:**
- Xcode öffnen, dein Projekt auswählen
- Product → Scheme → Edit Scheme → CloudKit Container konfiguriert?
- Dann: Xcode: Window → CloudKit Console → Schema → "Deploy Schema to Production"
- Warten bis Status "Deployed" ist

---

## 2. iCloud Account & CloudKit Availability

**Auf deinem Test-Gerät (iPhone/Simulator):**

- [ ] Einstellungen → Apple ID → iCloud → Prüfe: Bist du eingeloggt? (Falls Simulator: Simulator → Weiterleitung → Demo iCloud einschalten?)
- [ ] Einstellungen → Apple ID → iCloud → CloudKit prüfen: Aktiviert?
- [ ] Starte PayScope App

**Im CloudKit Diagnostics Tab (wenn vorhanden):**
- [ ] Prüfe den "Account Status" Anzeige
- [ ] Sollte **"available"** anzeigen, nicht "restricted", "unavailable" oder "notDetermined"
- [ ] Wenn nicht: Das ist dein unmittelbares Problem

---

## 3. Automatisches Persistieren testen

**Keine Notifications abhören – SwiftData ist deklarativ:**

- [ ] Öffne PayScope, erstelle einen neuen DayEntry (z.B. einen neuen Arbeitstag)
- [ ] Speichere (füge hinzu / schließe Editor)
- [ ] **Warte 10-15 Sekunden** – CloudKit benötigt Zeit zur Synch
- [ ] Öffne CloudKit Console: https://icloud.developer.apple.com/dashboard
- [ ] Wähle Development → Private Database
- [ ] Filtere nach "DayEntry"
- [ ] **Ist dein neuer Eintrag dort sichtbar?**
  - Ja → Sync funktioniert
  - Nein → Weitergehen zu Punkt 4

---

## 4. Lokale vs. Remote Daten Unterscheidung

**In der App oder im Code-Debugger prüfen:**

- [ ] Beende PayScope vollständig (Hintergrund-Prozess killen)
- [ ] Gehe offline (Flugmodus an ODER Netzwerk aus)
- [ ] Starte PayScope neu
- [ ] Erstelle einen neuen DayEntry
- [ ] Speichere
- [ ] **Ist der Eintrag noch sichtbar?** → Ja = lokal funktioniert
- [ ] Gehe online (Flugmodus aus)
- [ ] **Warte 10-15 Sekunden**
- [ ] Öffne CloudKit Console wieder
- [ ] **Ist der Eintrag dort aufgetaucht?** 
  - Ja → Offline Buffering funktioniert
  - Nein → Problema bei CloudKit Connection

---

## 5. Multi-Device Sync testen

**Wenn du Zugang zu zwei Geräten hast:**

- [ ] Gerät A: PayScope öffnen, neuen DayEntry erstellen mit eindeutiger Beschreibung (z.B. "TEST-2026-02-25")
- [ ] Gerät A: Speichern, warten 15 Sekunden
- [ ] Gerät B: PayScope öffnen (oder neuladen, wenn schon offen)
- [ ] **Ist der Eintrag von Gerät A sofort sichtbar?**
  - Ja → Multi-Device Sync funktioniert perfekt
  - Nein oder verzögert → CloudKit synchronisiert nicht alle Felder korrekt

---

## 6. NSManagedObjectContextDidSave Notifications aktiv?

**Code-Ebene überprüfen:**

```
grep -r "NSManagedObjectContextDidSave" /Users/dyonisosfergadiotis/Projekte/PayScope/
```

- [ ] Wenn Treffer gefunden werden:
  - Diese müssen **vollständig entfernt** werden
  - SwiftData triggert diese Notifications nicht zuverlässig
  - Jede Reaktion darauf ist ein Phantom Event

---

## 7. isUsingCloudKit Wahrheitswert Prüfung

**Code-Ebene überprüfen:**

```
grep -r "isUsingCloudKit" /Users/dyonisosfergadiotis/Projekte/PayScope/
```

- [ ] Wo wird `isUsingCloudKit = true` gesetzt?
- [ ] Wird vorher `CKContainer.default().accountStatus` abgefragt?
  - Ja → Gut
  - Nein → Das ist falsch, muss repariert werden

---

## 8. CloudKit Container Identifier korrekt?

**Im Code überprüfen:**

```
grep -r "iCloud\.com\." /Users/dyonisosfergadiotis/Projekte/PayScope/ --include="*.swift"
```

- [ ] Deine App Bundle ID und Container ID müssen sich entsprechen
- [ ] Muster: `iCloud.com.example.bundleid` oder `iCloud.bundleid`
- [ ] Diese Container ID muss auch im CloudKit Dashboard unter der App registriert sein

---

## 9. Settings / Einstellungen synchronisieren?

**Funktionale Prüfung:**

- [ ] Ändere eine Einstellung in PayScope (z.B. Theme, Sprache)
- [ ] Warte 10 Sekunden
- [ ] Öffne ein zweites Gerät (oder Simulator)
- [ ] **Ist die Einstellung dort auch geändert?**
  - Ja → Settings Sync läuft
  - Nein → Settings Model ist nicht in CloudKit Schema oder nicht korrekt annotiert

---

## 10. Diagnose View Output

**Wenn ein CloudKit Diagnostics View existiert:**

- [ ] Öffne den Diagnostics Tab in PayScope
- [ ] Prüfe auf folgende Felder:
  - `Account Status: available` (nicht restricted, unavailable)
  - `Total Records in Private DB: > 0` (nach ersten Daten)
  - `Last Sync: < 30 seconds ago` (regelmäßige Updates)
  - Keine Error Messages
- [ ] Teste nach Änderungen: Neuer Sync-Zeitstempel?
  - Ja → CloudKit Connection aktiv
  - Nein → CloudKit Sync pausiert

---

## Zusammenfassung der häufigsten Fehler

| Problem | Zeichen | Lösung |
|---------|---------|--------|
| Schema nicht deployed | CloudKit Console zeigt leer | Im Dashboard: Deploy Schema zu Development + Production |
| Account nicht verfügbar | Diagnostics zeigt "unavailable" | iCloud Login prüfen, CloudKit aktivieren |
| NSManagedObjectContextDidSave noch aktiv | Phantom Events, falsche Zustände | Alle Observer entfernen |
| isUsingCloudKit zu früh true | Funktioniert lokal, aber nicht in CloudKit Console | cloudKit accountStatus abfragen bevor true gesetzt wird |
| Multi-Device Sync faul | Eintrag auf Device A, nicht sichtbar auf Device B | CloudKit Schema überprüfen, warten 30+ Sekunden |

---

## Nächste Schritte

1. **Diese Checkliste abarbeiten** – dauert ca. 5-10 Minuten
2. **Fehler notieren** – welche Punkte schlagen fehl?
3. **Bericht geben** – dann können wir gezielt Code-Reparaturen vornehmen

