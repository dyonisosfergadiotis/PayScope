import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudKitService: CloudKitService
    @ObservedObject private var appleCalendarSync = AppleCalendarSyncService.shared
    @State private var settings: Settings
    @State private var showResetConfirmation = false
    @State private var showResetResultAlert = false
    @State private var resetResultMessage = ""

    init(settings: Settings) {
        _settings = State(initialValue: settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Arbeit") {
                    NavigationLink {
                        PaySettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Vergütung",
                            subtitle: "Abrechnungsmodell und Gehaltswert einstellen",
                            systemImage: "eurosign.circle"
                        )
                    }

                    NavigationLink {
                        NetDefaultsSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Netto-Standardwerte",
                            subtitle: "Abgaben und Zuschläge für Netto-Berechnungen verwalten",
                            systemImage: "percent"
                        )
                    }

                    NavigationLink {
                        TipsSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Trinkgeld",
                            subtitle: tipsSettingsSubtitle,
                            systemImage: "eurosign.circle"
                        )
                    }

                    NavigationLink {
                        WorkweekSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Arbeitswoche",
                            subtitle: "Wochenbeginn und Arbeitstage pro Woche festlegen",
                            systemImage: "calendar.badge.clock"
                        )
                    }

                    NavigationLink {
                        WeeklyTargetSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Wochenstunden",
                            subtitle: "Sollstunden pro Woche hinterlegen",
                            systemImage: "clock"
                        )
                    }

                    NavigationLink {
                        RulesSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Berechnungsregeln",
                            subtitle: "Gutschriften und Referenzlogik konfigurieren",
                            systemImage: "slider.horizontal.3"
                        )
                    }

                    NavigationLink {
                        ShiftShortcutsSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Schichtvorlagen",
                            subtitle: "Namen und Zeiten für schnelle Schichten bearbeiten",
                            systemImage: "clock.badge"
                        )
                    }
                }

                Section("Darstellung") {
                    NavigationLink {
                        AppearanceSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Erscheinungsbild",
                            subtitle: "Akzentfarbe der App auswählen",
                            systemImage: "paintpalette"
                        )
                    }

                    NavigationLink {
                        CalendarSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Kalender",
                            subtitle: "Kalenderzellen und Wocheninfos anpassen",
                            systemImage: "rectangle.3.group"
                        )
                    }
                }

                Section("Daten") {
                    NavigationLink {
                        HolidayImportSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Feiertage",
                            subtitle: "Region, Import und automatische Markierung einstellen",
                            systemImage: "flag"
                        )
                    }

                    NavigationLink {
                        AppleCalendarSettingsView(settings: settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Apple Kalender",
                            subtitle: appleCalendarSubtitle,
                            systemImage: "calendar.badge.plus"
                        )
                    }

                    NavigationLink {
                        ExportSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Export",
                            subtitle: "Monatsdaten als CSV, Text oder PDF teilen",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                }

                Section("App") {
                    NavigationLink {
                        AppInfoSettingsView()
                    } label: {
                        SettingsMenuRow(
                            title: "Info & Entwickler",
                            subtitle: "App-Version und Entwicklerangaben ansehen",
                            systemImage: "info.circle"
                        )
                    }

                    Button("App zurücksetzen", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .confirmationDialog(
                "Lokale App-Daten zurücksetzen?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Nur lokal zurücksetzen", role: .destructive) {
                    resetLocalAppData()
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Löscht nur lokale Daten auf diesem Gerät. iCloud-Daten bleiben unverändert.")
            }
            .alert("App zurückgesetzt", isPresented: $showResetResultAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resetResultMessage)
            }
        }
    }

    private var tipsSettingsSubtitle: String {
        guard settings.effectiveShowTipsButton else {
            return "Trinkgeld-Button ausgeblendet"
        }
        return settings.effectiveShowTipsButtonAmount ? "Button zeigt Monatsbetrag" : "Button ohne Monatsbetrag"
    }

    private var appleCalendarSubtitle: String {
        appleCalendarSync.isEnabled
            ? "Automatischer Export ist aktiv"
            : "Schichten in Apple Kalender exportieren"
    }

    private func resetLocalAppData() {
        LocalDayEntryStore.shared.resetAll()

        let defaults = Settings(key: "singleton", updatedAt: .distantPast)
        settings.applyValues(from: defaults)
        settings.key = "singleton"
        settings.updatedAt = .distantPast

        clearLocalEntities(of: TimeSegment.self)
        clearLocalEntities(of: DayEntry.self)
        clearLocalEntities(of: HolidayCalendarDay.self)
        clearLocalEntities(of: NetWageMonthConfig.self)
        LocalTipEntryStore.shared.resetAll()

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        do {
            try modelContext.save()
            resetResultMessage = "Lokale App-Daten wurden gelöscht. iCloud-Daten bleiben erhalten. Bitte die App einmal komplett schließen und neu öffnen."
        } catch {
            resetResultMessage = "Lokale Daten konnten nicht vollständig gelöscht werden: \(error.localizedDescription)"
        }
        showResetResultAlert = true
    }

    private func clearLocalEntities<Model: PersistentModel>(of type: Model.Type) {
        let descriptor = FetchDescriptor<Model>()
        let objects = (try? modelContext.fetch(descriptor)) ?? []
        for object in objects {
            modelContext.delete(object)
        }
    }
}

// MARK: - Subviews and helpers (unchanged logic, use Binding<Settings>)

private struct PaySettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings
    @State private var moneyInput = ""

    var body: some View {
        Form {
            Section(
                header: Text("Vergütung"),
                footer: Text("Bestimmt, wie dein Gehalt berechnet wird.")
            ) {
                Picker("Abrechnungsmodell", selection: Binding(get: { settings.payMode }, set: { new in
                    settings.payMode = new
                    Task { try? await cloudKitService.saveSettings(settings) }
                })) {
                    ForEach(PayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                HStack{
                    TextField(settings.payMode == .hourly ? "Stundenlohn in Euro" : "Monatsgehalt in Euro", text: $moneyInput)
                        .keyboardType(.decimalPad)
                    
                    Button {
                        guard let value = parseMoneyToCents(moneyInput) else { return }
                        if settings.payMode == .hourly {
                            settings.hourlyRateCents = value
                            settings.monthlySalaryCents = nil
                        } else {
                            settings.monthlySalaryCents = value
                            settings.hourlyRateCents = nil
                        }
                        Task { try? await cloudKitService.saveSettings(settings) }
                    }label:{
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Vergütung")
        .onAppear {
            syncMoneyInput()
        }
        .onChange(of: settings.payMode) { _, _ in
            syncMoneyInput()
            Task { try? await cloudKitService.saveSettings(settings) }
        }
    }

    private func syncMoneyInput() {
        if settings.payMode == .hourly {
            moneyInput = settings.hourlyRateCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        } else {
            moneyInput = settings.monthlySalaryCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        }
    }
}

private struct NetDefaultsSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    @State private var wageTaxText = ""
    @State private var pensionText = ""
    @State private var bonusTexts: [String] = []
    @State private var newBonusText = ""

    var body: some View {
        Form {
            Section(
                header: Text("Abgaben (%)"),
                footer: Text("Diese Werte dienen als Standard für die Netto-Berechnung.")
            ) {
                HStack {
                    TextField("Lohnsteuer", text: $wageTaxText)
                        .keyboardType(.decimalPad)
                    Text("%")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Rentenversicherung", text: $pensionText)
                        .keyboardType(.decimalPad)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Zuschläge (€)") {
                if bonusTexts.isEmpty {
                    Text("Noch keine Zuschläge.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(bonusTexts.enumerated()), id: \.offset) { idx, _ in
                        HStack {
                            TextField("Zuschlag \(idx + 1)", text: bindingForBonus(at: idx))
                                .keyboardType(.decimalPad)
                            Text("€")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                bonusTexts.remove(at: idx)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    TextField("Neuer Zuschlag", text: $newBonusText)
                        .keyboardType(.decimalPad)
                    Text("€")
                        .foregroundStyle(.secondary)
                    Button("Hinzufügen") {
                        guard !newBonusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let formatted = formatForDisplay(from: newBonusText)
                        bonusTexts.append(formatted ?? newBonusText)
                        newBonusText = ""
                    }
                }
            }
        }
        .navigationTitle("Netto-Standardwerte")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Speichern")
            }
        }
        .onAppear {
            wageTaxText = formattedPercent(settings.netWageTaxPercent)
            pensionText = formattedPercent(settings.netPensionPercent)
            bonusTexts = (settings.netBonusesCSV ?? "")
                .split(separator: ";")
                .map { formatForDisplay(from: String($0)) ?? String($0) }
        }
    }

    private func bindingForBonus(at index: Int) -> Binding<String> {
        Binding(
            get: { bonusTexts[index] },
            set: { bonusTexts[index] = $0 }
        )
    }

    private func formattedPercent(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func normalizedDouble(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private func formatForDisplay(from text: String) -> String? {
        guard let value = normalizedDouble(from: text) else { return nil }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func save() {
        let wageTax = normalizedDouble(from: wageTaxText)
        let pension = normalizedDouble(from: pensionText)
        let bonusesCSV = bonusTexts
            .compactMap { normalizedDouble(from: $0) }
            .map { String(format: "%.2f", $0) }
            .joined(separator: ";")

        settings.netWageTaxPercent = wageTax
        settings.netPensionPercent = pension
        settings.netBonusesCSV = bonusesCSV.isEmpty ? nil : bonusesCSV

        wageTaxText = formatForDisplay(from: wageTaxText) ?? ""
        pensionText = formatForDisplay(from: pensionText) ?? ""
        bonusTexts = bonusTexts.map { formatForDisplay(from: $0) ?? $0 }

        Task { try? await cloudKitService.saveSettings(settings) }
    }
}

private struct TipsSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section(
                header: Text("Trinkgeld"),
                footer: Text("Steuert, ob der Trinkgeld-Button im Kalender erscheint und ob er den Monatsbetrag anzeigt.")
            ) {
                Toggle("Trinkgeld anzeigen", isOn: showTipsButtonBinding)

                if settings.effectiveShowTipsButton {
                    Toggle("Monatsbetrag im Button", isOn: showTipsButtonAmountBinding)
                }
            }
        }
        .navigationTitle("Trinkgeld")
    }

    private var showTipsButtonBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowTipsButton },
            set: {
                settings.showTipsButton = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var showTipsButtonAmountBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowTipsButtonAmount },
            set: {
                settings.showTipsButtonAmount = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }
}

private struct WorkweekSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section(
                header: Text("Arbeitswoche"),
                footer: Text("Steuert Sollzeit und den Standardwert für feste Feiertagsgutschrift.")
            ) {
                HStack {
                    Text("Wochenbeginn")
                    Spacer()
                    Text("Montag")
                        .foregroundStyle(.secondary)
                }

                Stepper(
                    "Arbeitstage pro Woche: \(settings.scheduledWorkdaysCount)",
                    value: Binding(
                        get: { settings.scheduledWorkdaysCount },
                        set: { newValue in
                            settings.scheduledWorkdaysCount = newValue
                            Task { try? await cloudKitService.saveSettings(settings) }
                        }
                    ),
                    in: 1...7
                )
            }
        }
        .navigationTitle("Arbeitswoche")
        .onAppear {
            var didNormalize = false
            if settings.weekStart != .monday {
                settings.weekStart = .monday
                didNormalize = true
            }
            if didNormalize {
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        }
    }
}

private struct WeeklyTargetSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings
    @State private var weeklyHoursInput = ""

    var body: some View {
        Form {
            Section(
                header: Text("Wochenstunden"),
                footer: Text("Steuert Sollzeit und Feiertagsgutschrift.")
            ) {
                
                HStack{
                    TextField("Sollstunden pro Woche", text: $weeklyHoursInput)
                        .keyboardType(.decimalPad)
                    
                    if !weeklyHoursInput.isEmpty && parseHoursToSeconds(weeklyHoursInput) == nil {
                        Text("Bitte einen gültigen Stundenwert eingeben.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button {
                        settings.weeklyTargetSeconds = parseHoursToSeconds(weeklyHoursInput)
                        Task { try? await cloudKitService.saveSettings(settings) }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Wochenstunden")
        .onAppear {
            weeklyHoursInput = settings.weeklyTargetSeconds.map { String(format: "%.1f", Double($0) / 3600) } ?? ""
        }
        .onChange(of: settings.weeklyTargetSeconds) { _, newValue in
            weeklyHoursInput = newValue.map { String(format: "%.1f", Double($0) / 3600) } ?? ""
        }
    }
}

private struct RulesSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings
    @State private var fixedVacationHoursInput = ""
    @State private var fixedHolidayHoursInput = ""

    var body: some View {
        Form {
            Section(
                header: Text("Urlaubsgutschrift"),
                footer: Text("Wähle Stundenbasiert oder festen Wert.")
            ) {
                Picker("Berechnungsart", selection: vacationCreditingModeBinding) {
                    ForEach(VacationCreditingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if vacationCreditingModeBinding.wrappedValue == .fixedValue {
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            text: $fixedVacationHoursInput,
                            prompt: Text(originalVacationHoursPlaceholder).foregroundStyle(.secondary)
                        )
                            .keyboardType(.decimalPad)

                        Button {
                            guard let seconds = parseHoursToSeconds(fixedVacationHoursInput) else { return }
                            settings.vacationFixedSeconds = seconds
                            Task { try? await cloudKitService.saveSettings(settings) }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .disabled(parseHoursToSeconds(fixedVacationHoursInput) == nil)
                    }
                }

                if !fixedVacationHoursInput.isEmpty && parseHoursToSeconds(fixedVacationHoursInput) == nil {
                    Text("Bitte einen gültigen Stundenwert eingeben.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section(
                header: Text("Feiertagsgutschrift"),
                footer: Text("Wähle festen Wert oder 13-Wochen-Regel wie bei Urlaub.")
            ) {
                Picker("Berechnungsart", selection: holidayCreditingModeBinding) {
                    ForEach(HolidayCreditingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if holidayCreditingModeBinding.wrappedValue == .fixedValue {
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            text: $fixedHolidayHoursInput,
                            prompt: Text(originalHolidayHoursPlaceholder).foregroundStyle(.secondary)
                        )
                            .keyboardType(.decimalPad)

                        Button {
                            guard let seconds = parseHoursToSeconds(fixedHolidayHoursInput) else { return }
                            settings.holidayFixedSeconds = seconds
                            Task { try? await cloudKitService.saveSettings(settings) }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .disabled(parseHoursToSeconds(fixedHolidayHoursInput) == nil)
                    }
                }

                if !fixedHolidayHoursInput.isEmpty && parseHoursToSeconds(fixedHolidayHoursInput) == nil {
                    Text("Bitte einen gültigen Stundenwert eingeben.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section(
                header: Text("13-Wochen-Logik"),
                footer: Text("Gilt für Urlaub, Feiertag und Krank bei 13-Wochen-Regel.")
            ) {
                Toggle("Lückenlose Historie erzwingen", isOn: strictHistoryBinding)
                Toggle("Fehlende Referenztage als 0 zählen", isOn: countMissingAsZeroBinding)
            }
        }
        .navigationTitle("Berechnungsregeln")
        .onAppear {
            syncVacationHoursInput()
            syncHolidayHoursInput()
        }
        .onChange(of: settings.strictHistoryRequired) { _, _ in
            Task { try? await cloudKitService.saveSettings(settings) }
        }
        .onChange(of: settings.countMissingAsZero) { _, _ in
            Task { try? await cloudKitService.saveSettings(settings) }
        }
        .onChange(of: settings.vacationFixedSeconds) { _, newValue in
            fixedVacationHoursInput = newValue.map {
                String(format: "%.1f", Double($0) / 3600.0)
            } ?? String(format: "%.1f", Double(settings.effectiveVacationFixedSeconds) / 3600.0)
        }
        .onChange(of: settings.holidayFixedSeconds) { _, newValue in
            fixedHolidayHoursInput = newValue.map {
                String(format: "%.1f", Double($0) / 3600.0)
            } ?? String(format: "%.1f", Double(settings.effectiveHolidayFixedSeconds) / 3600.0)
        }
    }

    private var vacationCreditingModeBinding: Binding<VacationCreditingMode> {
        Binding(
            get: { settings.effectiveVacationCreditingMode },
            set: { newValue in
                settings.vacationCreditingMode = newValue
                if newValue == .fixedValue, settings.vacationFixedSeconds == nil {
                    let defaultSeconds = suggestedFixedVacationSeconds
                    settings.vacationFixedSeconds = defaultSeconds
                    fixedVacationHoursInput = String(format: "%.1f", Double(defaultSeconds) / 3600.0)
                }
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var strictHistoryBinding: Binding<Bool> {
        Binding(
            get: { settings.strictHistoryRequired },
            set: { newValue in
                settings.strictHistoryRequired = newValue
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var countMissingAsZeroBinding: Binding<Bool> {
        Binding(
            get: { settings.countMissingAsZero },
            set: { newValue in
                settings.countMissingAsZero = newValue
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var holidayCreditingModeBinding: Binding<HolidayCreditingMode> {
        Binding(
            get: { settings.effectiveHolidayCreditingMode },
            set: { newValue in
                settings.holidayCreditingMode = newValue
                if newValue == .fixedValue, settings.holidayFixedSeconds == nil {
                    let defaultSeconds = suggestedFixedHolidaySeconds
                    settings.holidayFixedSeconds = defaultSeconds
                    fixedHolidayHoursInput = String(format: "%.1f", Double(defaultSeconds) / 3600.0)
                }
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var suggestedFixedVacationSeconds: Int {
        if let weeklyTargetSeconds = settings.weeklyTargetSeconds {
            return max(0, weeklyTargetSeconds / max(1, min(7, settings.scheduledWorkdaysCount)))
        }
        return 8 * 3600
    }

    private var suggestedFixedHolidaySeconds: Int {
        if let weeklyTargetSeconds = settings.weeklyTargetSeconds {
            return max(0, weeklyTargetSeconds / max(1, min(7, settings.scheduledWorkdaysCount)))
        }
        return 8 * 3600
    }

    private var originalVacationHoursPlaceholder: String {
        String(format: "%.1f", Double(settings.effectiveVacationFixedSeconds) / 3600.0)
    }

    private var originalHolidayHoursPlaceholder: String {
        String(format: "%.1f", Double(settings.effectiveHolidayFixedSeconds) / 3600.0)
    }

    private func syncVacationHoursInput() {
        let seconds = settings.vacationFixedSeconds ?? settings.effectiveVacationFixedSeconds
        fixedVacationHoursInput = String(format: "%.1f", Double(seconds) / 3600.0)
    }

    private func syncHolidayHoursInput() {
        let seconds = settings.holidayFixedSeconds ?? settings.effectiveHolidayFixedSeconds
        fixedHolidayHoursInput = String(format: "%.1f", Double(seconds) / 3600.0)
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section(
                header: Text("Erscheinungsbild"),
                footer: Text("Die Akzentfarbe wird in Kalender, Charts und Buttons verwendet.")) {
                HStack {
                    Text("Akzentfarbe")
                    Spacer()
                    Menu {
                        ForEach(ThemeAccent.allCases) { accent in
                            Button {
                                settings.themeAccent = accent
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 10, height: 10)
                                    Text(accent.label)
                                        .foregroundStyle(accent.color)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(settings.themeAccent.color)
                                .frame(width: 10, height: 10)
                            Text(settings.themeAccent.label)
                                .foregroundStyle(settings.themeAccent.color.opacity(0.6))
                        }
                    }
                }
            }
        }
        .navigationTitle("Erscheinungsbild")
        .onChange(of: settings.themeAccent) { _, _ in
            Task { try? await cloudKitService.saveSettings(settings) }
        }
    }
}

private struct CalendarSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section(
                header: Text("Kalenderdarstellung"),
                footer: Text("Diese Einstellungen beeinflussen, wie sich der Kalender zeigt.")) {
                Picker("Tageszelle", selection: calendarDisplayModeBinding) {
                    ForEach(CalendarCellDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if calendarDisplayModeBinding.wrappedValue == .hours {
                    Picker("Stundenvergleich", selection: calendarHoursBreakModeBinding) {
                        ForEach(CalendarHoursBreakMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Picker("Monatsübersicht", selection: calendarSummaryDisplayModeBinding) {
                    ForEach(CalendarSummaryDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Kalenderwochen", isOn: showCalendarWeekNumbersBinding)
                Toggle("Wochenstunden", isOn: showCalendarWeekHoursBinding)
                Toggle("Wochenverdienst", isOn: showCalendarWeekPayBinding)
            }

            Section(
                header: Text("Live Activity"),
                footer: Text("Wenn aktiv, startet PayScope eine Live Activity für den aktuellen Arbeitstag.")
            ) {
                Toggle("Zeige Live Activity", isOn: showLiveActivityBinding)
            }
        }
        .navigationTitle("Kalender")
    }

    private var calendarDisplayModeBinding: Binding<CalendarCellDisplayMode> {
        Binding(
            get: { settings.calendarCellDisplayMode ?? .dot },
            set: {
                settings.calendarCellDisplayMode = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var calendarHoursBreakModeBinding: Binding<CalendarHoursBreakMode> {
        Binding(
            get: { settings.effectiveCalendarHoursBreakMode },
            set: {
                settings.calendarHoursBreakMode = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var calendarSummaryDisplayModeBinding: Binding<CalendarSummaryDisplayMode> {
        Binding(
            get: { settings.effectiveCalendarSummaryDisplayMode },
            set: {
                settings.calendarSummaryDisplayMode = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var showCalendarWeekNumbersBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowCalendarWeekNumbers },
            set: {
                settings.showCalendarWeekNumbers = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var showCalendarWeekHoursBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowCalendarWeekHours },
            set: {
                settings.showCalendarWeekHours = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var showCalendarWeekPayBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowCalendarWeekPay },
            set: {
                settings.showCalendarWeekPay = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var showLiveActivityBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowLiveActivity },
            set: {
                settings.showLiveActivity = $0
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }
}

private struct ShiftShortcutsSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings
    @State private var editingNameIndex: Int?
    @State private var editingTimeIndex: Int?
    @State private var draftName = ""
    @State private var draftStartMinute = 0
    @State private var draftEndMinute = 0

    var body: some View {
        Form {
            Section(
                header: Text("Schichtvorlagen"),
                footer: Text("Name und Zeiten pro Vorlage verwalten.")
            ) {
                shortcutRow(title: "Vorlage 1", index: 0)
                shortcutRow(title: "Vorlage 2", index: 1)
                shortcutRow(title: "Vorlage 3", index: 2)
            }
        }
        .navigationTitle("Schichtvorlagen")
    }

    @ViewBuilder
    private func shortcutRow(
        title: String,
        index: Int
    ) -> some View {
        let range = effectiveShortcutRange(for: index)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if editingNameIndex == index {
                    TextField("Name, z. B. Frühschicht", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    Button {
                        saveShortcutName(index: index)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                } else {
                    Text(displayName(for: index, fallback: title))
                        .font(.headline)
                    Spacer()
                    Button {
                        beginEditingName(index: index)
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }

            if editingTimeIndex == index {
                VStack(spacing: 8) {
                    shortcutMinuteControl(
                        title: "Start",
                        value: draftStartMinute,
                        onDecrease: { adjustDraftTime(isStart: true, deltaMinutes: -15) },
                        onIncrease: { adjustDraftTime(isStart: true, deltaMinutes: 15) }
                    )
                    shortcutMinuteControl(
                        title: "Ende",
                        value: draftEndMinute,
                        onDecrease: { adjustDraftTime(isStart: false, deltaMinutes: -15) },
                        onIncrease: { adjustDraftTime(isStart: false, deltaMinutes: 15) }
                    )
                }

                HStack {
                    Spacer()
                    Button {
                        saveShortcutTime(index: index)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            } else {
                HStack {
                    Text("\(formatMinute(range.startMinute)) - \(formatMinute(range.endMinute))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        beginEditingTime(index: index)
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }

            Button("Standardwerte") {
                resetShortcut(index: index)
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private func shortcutMinuteControl(
        title: String,
        value: Int,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                onDecrease()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)

            Text(formatMinute(value))
                .font(.subheadline.bold())
                .frame(minWidth: 58)

            Button {
                onIncrease()
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private func displayName(for index: Int, fallback: String) -> String {
        let rawName: String
        switch index {
        case 0: rawName = settings.shiftShortcutName1 ?? ""
        case 1: rawName = settings.shiftShortcutName2 ?? ""
        default: rawName = settings.shiftShortcutName3 ?? ""
        }

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func effectiveShortcutRange(for index: Int) -> ShiftShortcutRange {
        let raw: String
        switch index {
        case 0: raw = settings.shiftShortcut1
        case 1: raw = settings.shiftShortcut2
        default: raw = settings.shiftShortcut3
        }

        return parseShiftShortcutRange(raw: raw) ?? defaultShiftShortcutRange(index: index)
    }

    private func resetShortcut(index: Int) {
        setShortcutRange(defaultShiftShortcutRange(index: index), index: index)
    }

    private func beginEditingName(index: Int) {
        editingTimeIndex = nil
        editingNameIndex = index
        draftName = displayName(for: index, fallback: "")
    }

    private func saveShortcutName(index: Int) {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch index {
        case 0:
            settings.shiftShortcutName1 = trimmed.nilIfEmpty
        case 1:
            settings.shiftShortcutName2 = trimmed.nilIfEmpty
        default:
            settings.shiftShortcutName3 = trimmed.nilIfEmpty
        }
        editingNameIndex = nil
        Task { try? await cloudKitService.saveSettings(settings) }
    }

    private func beginEditingTime(index: Int) {
        editingNameIndex = nil
        editingTimeIndex = index
        let range = effectiveShortcutRange(for: index)
        draftStartMinute = range.startMinute
        draftEndMinute = range.endMinute
    }

    private func adjustDraftTime(isStart: Bool, deltaMinutes: Int) {
        if isStart {
            let duration = max(15, draftEndMinute - draftStartMinute)
            let upperStart = min(ShiftTimeRange.minutesPerDay - 1, ShiftTimeRange.maxEndMinuteOffset - duration)
            draftStartMinute = max(0, min(upperStart, draftStartMinute + deltaMinutes))
            draftEndMinute = min(
                ShiftTimeRange.maxEndMinuteOffset,
                min(draftStartMinute + ShiftTimeRange.maxDurationMinutes, draftStartMinute + duration)
            )
        } else {
            let upperEnd = min(ShiftTimeRange.maxEndMinuteOffset, draftStartMinute + ShiftTimeRange.maxDurationMinutes)
            draftEndMinute = max(draftStartMinute + 15, min(upperEnd, draftEndMinute + deltaMinutes))
        }
    }

    private func saveShortcutTime(index: Int) {
        setShortcutRange(
            ShiftShortcutRange(startMinute: draftStartMinute, endMinute: draftEndMinute),
            index: index
        )
        editingTimeIndex = nil
    }

    private func setShortcutRange(_ range: ShiftShortcutRange, index: Int) {
        let rawValue = "\(range.startMinute)-\(range.endMinute)"
        switch index {
        case 0:
            settings.shiftShortcut1 = rawValue
            Task { try? await cloudKitService.saveSettings(settings) }
        case 1:
            settings.shiftShortcut2 = rawValue
            Task { try? await cloudKitService.saveSettings(settings) }
        default:
            settings.shiftShortcut3 = rawValue
            Task { try? await cloudKitService.saveSettings(settings) }
        }
    }
}

private struct HolidayImportSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    @State private var holidayImportInfo = ""
    @State private var isImportingHolidays = false
    @State private var isDeletingHolidays = false
    @State private var showDeleteHolidayConfirmation = false

    private let holidayImporter = HolidayImportService()

    var body: some View {
        Form {
            Section(header: Text("Region & Import"),footer: Text("Importierte Feiertage werden als Kalendereinträge in iCloud gespeichert.")) {
                TextField("Land (ISO, z. B. DE)", text: holidayCountryBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                TextField("Bundesland/Kanton (optional, z. B. BY)", text: holidaySubdivisionBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button {
                    Task {
                        await importHolidaysForCurrentYear()
                    }
                } label: {
                    if isImportingHolidays {
                        ProgressView()
                    } else {
                        Text("Feiertage für aktuelles Jahr laden")
                    }
                }
                .disabled(isImportingHolidays)

                Button(role: .destructive) {
                    showDeleteHolidayConfirmation = true
                } label: {
                    if isDeletingHolidays {
                        ProgressView()
                    } else {
                        Text("Alle importierten Feiertage löschen")
                    }
                }
                .disabled(isImportingHolidays || isDeletingHolidays)

                if !holidayImportInfo.isEmpty {
                    Text(holidayImportInfo)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("Automatische Markierung"),footer:Text("API-Feiertage werden im Kalender gelb markiert. Nur auf ausgewählten Tagen wird beim Öffnen automatisch eine Feiertagsschicht gesetzt.")) {
                HStack(spacing: 10) {
                    ForEach(orderedWeekdays, id: \.weekday) { item in
                        let isSelected = settings.isPaidHolidayWeekday(weekday: item.weekday)
                        Button {
                            settings.paidHolidayWeekdayMask = settings.updatingPaidHolidayWeekdayMask(
                                weekday: item.weekday,
                                isSelected: !isSelected
                            )
                            Task { try? await cloudKitService.saveSettings(settings) }
                        } label: {
                            Text(item.label)
                                .font(.caption2.weight(.bold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(isSelected ? .white : .primary)
                                .background(
                                    Circle()
                                        .fill(isSelected ? settings.themeAccent.color : Color(.tertiarySystemFill))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(
                                            isSelected ? settings.themeAccent.color.opacity(0.3) : Color.secondary.opacity(0.32),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.label) als Auto-Feiertagsschicht")
                        .accessibilityValue(isSelected ? "ausgewählt" : "nicht ausgewählt")
                    }
                }
            }
        }
        .navigationTitle("Feiertage")
        .confirmationDialog(
            "Alle importierten Feiertage löschen?",
            isPresented: $showDeleteHolidayConfirmation,
            titleVisibility: .visible
        ) {
            Button("Alle löschen", role: .destructive) {
                Task {
                    await deleteAllImportedHolidays()
                }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Dadurch werden alle importierten Feiertage aus iCloud entfernt.")
        }
    }

    private var holidayCountryBinding: Binding<String> {
        Binding(
            get: {
                normalizeHolidayCode(settings.holidayCountryCode ?? "").nilIfEmpty ?? "DE"
            },
            set: { newValue in
                settings.holidayCountryCode = normalizeHolidayCode(newValue).nilIfEmpty ?? "DE"
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var holidaySubdivisionBinding: Binding<String> {
        Binding(
            get: { settings.holidaySubdivisionCode ?? "" },
            set: { newValue in
                settings.holidaySubdivisionCode = normalizeHolidayCode(newValue).nilIfEmpty
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var orderedWeekdays: [(weekday: Int, label: String)] {
        let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

        return orderedWeekdays.map { weekday in
            (weekday: weekday, label: weekdayShortLabel(weekday))
        }
    }

    private func weekdayShortLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "So"
        case 2: return "Mo"
        case 3: return "Di"
        case 4: return "Mi"
        case 5: return "Do"
        case 6: return "Fr"
        case 7: return "Sa"
        default: return "?"
        }
    }

    private func importHolidaysForCurrentYear() async {
        isImportingHolidays = true
        defer { isImportingHolidays = false }

        let year = Calendar.current.component(.year, from: Date())
        let normalizedCountry = normalizeHolidayCode(settings.holidayCountryCode ?? "").nilIfEmpty ?? "DE"
        let normalizedSubdivision = normalizeHolidayCode(settings.holidaySubdivisionCode ?? "").nilIfEmpty
        settings.holidayCountryCode = normalizedCountry
        settings.holidaySubdivisionCode = normalizedSubdivision
        Task { try? await cloudKitService.saveSettings(settings) }

        do {
            let days = try await holidayImporter.fetchHolidayCalendarDays(year: year, countryCode: normalizedCountry, subdivisionCode: normalizedSubdivision)
            try await cloudKitService.replaceHolidayDays(
                days,
                countryCode: normalizedCountry,
                subdivisionCode: normalizedSubdivision,
                year: year
            )
            let cleanedMarkers = try await cloudKitService.clearStaleHolidayMarkers(
                validHolidayDates: Set(days.map { $0.date.startOfDayLocal() }),
                year: year
            )
            if cleanedMarkers > 0 {
                holidayImportInfo = "\(days.count) Feiertage für \(year) importiert. \(cleanedMarkers) alte Feiertags-Markierungen entfernt."
            } else {
                holidayImportInfo = "\(days.count) Feiertage für \(year) importiert."
            }
        } catch {
            holidayImportInfo = error.localizedDescription
        }
    }

    private func deleteAllImportedHolidays() async {
        isDeletingHolidays = true
        defer { isDeletingHolidays = false }

        do {
            let deletedCount = try await cloudKitService.deleteHolidayDays()
            if deletedCount > 0 {
                holidayImportInfo = "\(deletedCount) importierte Feiertage gelöscht."
            } else {
                holidayImportInfo = "Keine importierten Feiertage gefunden."
            }
        } catch {
            holidayImportInfo = error.localizedDescription
        }
    }
}

private struct AppleCalendarSettingsView: View {
    @ObservedObject private var syncService = AppleCalendarSyncService.shared
    let settings: Settings
    @State private var showRemoveConfirmation = false

    var body: some View {
        Form {
            Section(
                header: Text("Apple Kalender"),
                footer: Text("PayScope erstellt einen eigenen Kalender und aktualisiert Schichten beim Speichern, Importieren und Löschen.")
            ) {
                Toggle("Automatisch exportieren", isOn: calendarSyncBinding)
                    .disabled(syncService.isSyncing)

                LabeledContent("Status", value: syncService.authorizationStatusLabel)
                LabeledContent("Kalender", value: syncService.calendarDisplayName)
            }

            Section(
                header: Text("Kalenderfarbe"),
                footer: Text("Die Farbe wird auf den von PayScope angelegten Apple Kalender angewendet.")
            ) {
                Picker("Farbe", selection: calendarAccentBinding) {
                    ForEach(ThemeAccent.allCases) { accent in
                        HStack {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 12, height: 12)
                            Text(accent.label)
                        }
                        .tag(accent)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(
                header: Text("Eintragstypen"),
                footer: Text("Nur aktivierte Kategorien werden in den Apple Kalender übernommen.")
            ) {
                ForEach(DayType.allCases) { type in
                    Toggle(isOn: includedTypeBinding(for: type)) {
                        Label(type.label, systemImage: type.icon)
                    }
                    .disabled(syncService.isSyncing)
                }
            }

            Section("Synchronisieren") {
                Button {
                    Task {
                        await exportAllLocalShifts()
                    }
                } label: {
                    Label("Alle lokalen Schichten exportieren", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!syncService.isEnabled || syncService.isSyncing)

                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Label("Exportierte Einträge entfernen", systemImage: "trash")
                }
                .disabled(syncService.isSyncing)

                if syncService.isSyncing {
                    ProgressView("Kalender wird aktualisiert...")
                }

                if let lastSyncSummary = syncService.lastSyncSummary {
                    Text(lastSyncSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let lastErrorMessage = syncService.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Apple Kalender")
        .task {
            syncService.refreshAuthorizationStatus()
        }
        .confirmationDialog(
            "Exportierte PayScope-Termine entfernen?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Entfernen", role: .destructive) {
                Task {
                    do {
                        try await syncService.removeAllExportedEvents()
                    } catch {
                        syncService.refreshAuthorizationStatus()
                    }
                }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Entfernt nur Termine, die PayScope im Apple Kalender angelegt hat. Deine Schichten in PayScope bleiben erhalten.")
        }
    }

    private var calendarSyncBinding: Binding<Bool> {
        Binding(
            get: { syncService.isEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        do {
                            try await syncService.enableAndSync(entries: LocalDayEntryStore.shared.loadAll(), settings: settings)
                        } catch {
                        }
                    }
                } else {
                    syncService.disableSync()
                }
            }
        )
    }

    private var calendarAccentBinding: Binding<ThemeAccent> {
        Binding(
            get: { syncService.calendarAccent },
            set: { accent in
                Task {
                    await syncService.setCalendarAccent(accent)
                }
            }
        )
    }

    private func includedTypeBinding(for type: DayType) -> Binding<Bool> {
        Binding(
            get: { syncService.includedEntryTypes.contains(type) },
            set: { isIncluded in
                Task {
                    await syncService.setIncludedEntryType(
                        type,
                        isIncluded: isIncluded,
                        entries: LocalDayEntryStore.shared.loadAll(),
                        settings: settings
                    )
                }
            }
        )
    }

    private func exportAllLocalShifts() async {
        await syncService.sync(entries: LocalDayEntryStore.shared.loadAll(), settings: settings)
    }
}

private struct ExportSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    @State private var exportMonthNumber = Calendar.current.component(.month, from: Date())
    @State private var exportYear = Calendar.current.component(.year, from: Date())
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showFileImporter = false
    @State private var showImportSheet = false
    @State private var importedRows: [ShiftCSVImportRowDraft] = []
    @State private var skippedImportRows = 0
    @State private var importInfoMessage: String?
    @State private var importErrorMessage: String?
    @State private var isSavingImportRows = false
    @State private var isPreparingExport = false
    @State private var exportErrorMessage: String?

    private let csvExporter = CSVExporter()
    private let textExporter = ShiftTextExporter()
    private let pdfExporter = ShiftPDFExporter()
    private static let germanMonthSymbols: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        return calendar.monthSymbols
    }()

    var body: some View {
        Form {
            Section(header: Text("Export"), footer: Text("Der Export enthält alle Tage des gewählten Monats inklusive Kategorien, Zeiten, Summen und Trinkgeld.")) {
                HStack {
                    Picker("Monat", selection: $exportMonthNumber) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Self.germanMonthSymbols[month - 1]).tag(month)
                        }
                    }
                    Picker("Jahr", selection: $exportYear) {
                        ForEach(selectableYears, id: \.self) { year in
                            Text("\(year)").tag(year)
                        }
                    }
                }

                Button("CSV erstellen") {
                    Task {
                        await shareCSVExport()
                    }
                }
                .disabled(isPreparingExport)

                Button("Text exportieren") {
                    Task {
                        await shareTextExport()
                    }
                }
                .disabled(isPreparingExport)

                Button("PDF exportieren") {
                    Task {
                        await sharePDFExport()
                    }
                }
                .disabled(isPreparingExport)

                if isPreparingExport {
                    ProgressView()
                }

                if let exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section(header: Text("CSV-Import"), footer: Text("Der Import garantiert keine Datenverluste.")) {
                Button("CSV auswählen") {
                    showFileImporter = true
                }

                if let importInfoMessage {
                    Text(importInfoMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let importErrorMessage {
                    Text(importErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Export")
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: handleFileImportSelection
        )
        .sheet(isPresented: $showImportSheet) {
            ShiftCSVImportSheet(
                rows: $importedRows,
                isSaving: isSavingImportRows,
                onSave: { await saveImportedRows() }
            )
        }
    }

    private var selectableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 5)...(current + 5))
    }

    private var selectedExportMonthDate: Date {
        let comps = DateComponents(year: exportYear, month: exportMonthNumber, day: 1)
        return Calendar.current.date(from: comps) ?? Date()
    }

    private var selectedExportInterval: DateInterval {
        let start = selectedExportMonthDate.startOfMonthLocal()
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? start
        return DateInterval(start: start, end: end)
    }

    private var selectedExportLookupInterval: DateInterval {
        let exportInterval = selectedExportInterval
        let lookbackDays = max(1, settings.vacationLookbackCount) * 7
        let start = Calendar.current.date(
            byAdding: .day,
            value: -lookbackDays,
            to: exportInterval.start
        ) ?? exportInterval.start.addingTimeInterval(TimeInterval(-lookbackDays * 24 * 60 * 60))
        return DateInterval(start: start.startOfDayLocal(), end: exportInterval.end)
    }

    @MainActor
    private func shareCSVExport() async {
        await prepareShare {
            let data = await loadExportData()
            let payload = csvExporter.csvForMonth(entries: data.entries, month: selectedExportMonthDate, settings: settings)
            return payload.isEmpty ? [] : [payload]
        }
    }

    @MainActor
    private func shareTextExport() async {
        await prepareShare {
            let data = await loadExportData()
            let payload = textExporter.textForMonth(
                entries: data.entries,
                tips: data.tips,
                month: selectedExportMonthDate,
                settings: settings
            )
            return [payload]
        }
    }

    @MainActor
    private func sharePDFExport() async {
        await prepareShare {
            let data = await loadExportData()
            let url = try pdfExporter.pdfURLForMonth(
                entries: data.entries,
                tips: data.tips,
                month: selectedExportMonthDate,
                settings: settings
            )
            return [url]
        }
    }

    @MainActor
    private func prepareShare(_ builder: @escaping () async throws -> [Any]) async {
        isPreparingExport = true
        exportErrorMessage = nil
        defer { isPreparingExport = false }

        do {
            let items = try await builder()
            shareItems = items
            showShare = !items.isEmpty
        } catch {
            exportErrorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func loadExportData() async -> (entries: [DayEntry], tips: [TipEntry]) {
        let interval = selectedExportInterval
        let lookupInterval = selectedExportLookupInterval
        let localEntries = LocalDayEntryStore.shared.loadAll(in: lookupInterval)
        let localTips = LocalTipEntryStore.shared.loadAll(in: interval)
        let deletedDaysByKey = Dictionary(
            LocalDayEntryStore.shared.loadDeletionTombstones().map { (dayKey($0.date), $0.lastModified) },
            uniquingKeysWith: { current, incoming in incoming > current ? incoming : current }
        )
        let deletedTipsByID = Dictionary(
            LocalTipEntryStore.shared.loadDeletionTombstones().map { ($0.id, $0.lastModified) },
            uniquingKeysWith: { current, incoming in incoming > current ? incoming : current }
        )
        let remoteEntries = ((try? await cloudKitService.fetchDayEntries(in: lookupInterval)) ?? []).filter { entry in
            guard let deletedAt = deletedDaysByKey[dayKey(entry.date)] else { return true }
            return deletedAt < entry.updatedAt
        }
        let remoteTips = ((try? await cloudKitService.fetchTipEntries(in: interval)) ?? []).filter { tip in
            guard let deletedAt = deletedTipsByID[tip.id] else { return true }
            return deletedAt < tip.updatedAt
        }

        if !remoteEntries.isEmpty {
            LocalDayEntryStore.shared.upsertMany(remoteEntries, notify: false)
        }
        if !remoteTips.isEmpty {
            LocalTipEntryStore.shared.upsertMany(remoteTips)
        }

        return (
            entries: mergeEntriesByLocalDayKeepingNewest(local: localEntries, remote: remoteEntries),
            tips: mergeTipEntriesKeepingNewest(local: localTips, remote: remoteTips)
        )
    }

    private func mergeEntriesByLocalDayKeepingNewest(local: [DayEntry], remote: [DayEntry]) -> [DayEntry] {
        let byDay = Dictionary(
            (local + remote).map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        return byDay.values.sorted { $0.date < $1.date }
    }

    private func mergeTipEntriesKeepingNewest(local: [TipEntry], remote: [TipEntry]) -> [TipEntry] {
        let byID = Dictionary(
            (local + remote).map { ($0.id, $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        return byID.values.sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            return $0.updatedAt < $1.updatedAt
        }
    }

    private func dayKey(_ date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    private func handleFileImportSelection(_ result: Result<[URL], Error>) {
        importErrorMessage = nil
        importInfoMessage = nil

        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result {
                importErrorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
            }
            return
        }

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let csv = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
            guard let csv else {
                importErrorMessage = "Datei konnte nicht als CSV-Text gelesen werden."
                return
            }

            let parseResult = ShiftCSVTransfer.parse(csv: csv)
            guard !parseResult.rows.isEmpty else {
                importErrorMessage = "Keine importierbaren Schichten gefunden."
                return
            }

            importedRows = parseResult.rows
            skippedImportRows = parseResult.skippedRows
            showImportSheet = true
        } catch {
            importErrorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveImportedRows() async -> Bool {
        guard !importedRows.isEmpty else { return false }

        isSavingImportRows = true
        defer { isSavingImportRows = false }

        var saved = 0
        var skipped = skippedImportRows
        var persistedEntries: [DayEntry] = []

        for row in importedRows {
            guard row.hasValidTimeRange else {
                skipped += 1
                continue
            }

            let dayStart = row.date.startOfDayLocal()
            guard
                let start = Calendar.current.date(byAdding: .minute, value: row.startMinute, to: dayStart),
                let end = Calendar.current.date(byAdding: .minute, value: row.endMinuteOffset, to: dayStart),
                end > start
            else {
                skipped += 1
                continue
            }

            let entry = DayEntry(date: dayStart, updatedAt: Date(), type: row.dayType, notes: "")
            switch row.dayType {
            case .work:
                entry.shiftStart = start
                entry.shiftEnd = end
                entry.breakSeconds = max(0, row.breakMinutes) * 60
                entry.manualWorkedSeconds = nil
                entry.creditedOverrideSeconds = nil
            case .manual:
                entry.shiftStart = nil
                entry.shiftEnd = nil
                entry.breakSeconds = nil
                let workedSeconds = max(0, Int(end.timeIntervalSince(start)) - (max(0, row.breakMinutes) * 60))
                entry.manualWorkedSeconds = workedSeconds
                entry.creditedOverrideSeconds = nil
            case .vacation, .holiday, .sick:
                entry.shiftStart = nil
                entry.shiftEnd = nil
                entry.breakSeconds = nil
                entry.manualWorkedSeconds = nil
                entry.creditedOverrideSeconds = nil
            }

            do {
                try await cloudKitService.saveDayEntry(entry)
                persistedEntries.append(entry)
                saved += 1
            } catch {
                importErrorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
                return false
            }
        }

        LocalDayEntryStore.shared.upsertMany(persistedEntries)
        await AppleCalendarSyncService.shared.sync(
            entries: persistedEntries,
            allEntries: LocalDayEntryStore.shared.loadAll(),
            settings: settings
        )
        importInfoMessage = "\(saved) Schichten gespeichert" + (skipped > 0 ? " · \(skipped) übersprungen" : "")
        importErrorMessage = nil
        return true
    }
}

private struct ShiftCSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var rows: [ShiftCSVImportRowDraft]
    let isSaving: Bool
    let onSave: () async -> Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: row.categoryIcon)
                                .frame(width: 22)
                            Text(row.dayType.label)
                                .font(.headline)
                            Spacer()
                            Button {
                                row.isEditing.toggle()
                            } label: {
                                Image(systemName: row.isEditing ? "pencil.slash" : "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                removeRow(id: row.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }

                        if row.isEditing {
                            Picker("Kategorie", selection: $row.dayType) {
                                ForEach(DayType.allCases) { type in
                                    Label(type.label, systemImage: type.icon).tag(type)
                                }
                            }
                            .onChange(of: row.dayType) { _, newType in
                                row.categoryIcon = newType.icon
                            }

                            DatePicker("Datum", selection: $row.date, displayedComponents: .date)

                            DatePicker(
                                "Start",
                                selection: minuteBinding(minute: $row.startMinute, date: $row.date),
                                displayedComponents: .hourAndMinute
                            )

                            DatePicker(
                                "Ende",
                                selection: endMinuteBinding(row: $row),
                                displayedComponents: .hourAndMinute
                            )

                            Stepper("Pause: \(row.breakMinutes) min", value: $row.breakMinutes, in: 0...720, step: 5)
                        } else {
                            LabeledContent("Datum", value: dayText(row.date))
                            LabeledContent("Start", value: minuteText(row.startMinute))
                            LabeledContent("Ende", value: endMinuteText(row))
                            LabeledContent("Pause", value: "\(row.breakMinutes) min")
                        }
                    }
                    .padding(.vertical, 4)
                    .foregroundStyle(row.hasValidTimeRange ? .primary : .secondary)
                }
            }
            .navigationTitle("Schichten importieren")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            let didSave = await onSave()
                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(rows.isEmpty || isSaving)
                }
            }
        }
    }

    private func removeRow(id: UUID) {
        rows.removeAll { $0.id == id }
    }

    private func dayText(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func minuteText(_ minute: Int) -> String {
        let clamped = max(0, min(23 * 60 + 59, minute))
        let hour = clamped / 60
        let minutePart = clamped % 60
        return String(format: "%02d:%02d", hour, minutePart)
    }

    private func endMinuteText(_ row: ShiftCSVImportRowDraft) -> String {
        let suffix = row.effectiveEndDayOffset > 0 ? " (+1)" : ""
        return "\(minuteText(row.endMinute))\(suffix)"
    }

    private func minuteBinding(minute: Binding<Int>, date: Binding<Date>) -> Binding<Date> {
        Binding(
            get: {
                let dayStart = date.wrappedValue.startOfDayLocal()
                return Calendar.current.date(byAdding: .minute, value: minute.wrappedValue, to: dayStart) ?? dayStart
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let total = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                minute.wrappedValue = max(0, min(23 * 60 + 59, total))
            }
        )
    }

    private func endMinuteBinding(row: Binding<ShiftCSVImportRowDraft>) -> Binding<Date> {
        Binding(
            get: {
                let dayStart = row.wrappedValue.date.startOfDayLocal()
                return Calendar.current.date(byAdding: .minute, value: row.wrappedValue.endMinuteOffset, to: dayStart) ?? dayStart
            },
            set: { newValue in
                let dayStart = row.wrappedValue.date.startOfDayLocal()
                let offset = Calendar.current.dateComponents([.minute], from: dayStart, to: newValue).minute
                    ?? Int(newValue.timeIntervalSince(dayStart) / 60)
                let clamped = max(0, min(ShiftTimeRange.maxEndMinuteOffset, offset))
                row.wrappedValue.endMinute = ShiftTimeRange.normalizedClockMinute(clamped)
                row.wrappedValue.endDayOffset = clamped >= ShiftTimeRange.minutesPerDay ? 1 : 0
            }
        )
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

private struct AppInfoSettingsView: View {
    private let info = AppInfoSnapshot.current

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Name", value: info.appName)
                LabeledContent("Version", value: info.version)
                LabeledContent("Build", value: info.build)
            }

            Section("Entwickler") {
                LabeledContent("Name") {
                    Link(info.developerName, destination: info.developerWebsiteURL)
                }
            }
        }
        .navigationTitle("Info")
    }
}

private struct AppInfoSnapshot {
    let appName: String
    let version: String
    let build: String
    let developerName: String
    let developerWebsiteURL: URL

    var versionBuild: String {
        "Version \(version) (\(build))"
    }

    static var current: AppInfoSnapshot {
        let info = Bundle.main.infoDictionary ?? [:]
        let appName = (info["CFBundleDisplayName"] as? String)?.nilIfEmpty
            ?? (info["CFBundleName"] as? String)?.nilIfEmpty
            ?? "PayScope"
        let version = (info["CFBundleShortVersionString"] as? String)?.nilIfEmpty ?? "1.0"
        let build = (info["CFBundleVersion"] as? String)?.nilIfEmpty ?? "1"
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "Unbekannt"
        let developerName = developerName(from: bundleIdentifier)

        return AppInfoSnapshot(
            appName: appName,
            version: version,
            build: build,
            developerName: developerName,
            developerWebsiteURL: URL(string: "https://www.dyonisosfergadiotis.de")!
        )
    }

    private static func developerName(from bundleIdentifier: String) -> String {
        guard let rawOwner = bundleIdentifier.split(separator: ".").first, !rawOwner.isEmpty else {
            return "Unbekannt"
        }

        let spaced = String(rawOwner)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return spaced.nilIfEmpty ?? "Unbekannt"
    }
}

private struct SettingsMenuRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    private var normalizedSubtitle: String {
        subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !normalizedSubtitle.isEmpty {
                    Text(normalizedSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ShiftShortcutRange {
    var startMinute: Int
    var endMinute: Int
}

private struct ShiftShortcutRangePayload: Decodable {
    let startMinute: Int
    let endMinute: Int
}

private func defaultShiftShortcutRange(index: Int) -> ShiftShortcutRange {
    switch index {
    case 0:
        return ShiftShortcutRange(startMinute: 6 * 60, endMinute: 14 * 60)
    case 1:
        return ShiftShortcutRange(startMinute: 9 * 60, endMinute: 17 * 60)
    default:
        return ShiftShortcutRange(startMinute: 14 * 60, endMinute: 22 * 60)
    }
}

private func parseShiftShortcutRange(raw: String) -> ShiftShortcutRange? {
    if let data = raw.data(using: .utf8),
       let payload = try? JSONDecoder().decode(ShiftShortcutRangePayload.self, from: data) {
        return clampShiftShortcutRange(
            ShiftShortcutRange(
                startMinute: payload.startMinute,
                endMinute: payload.endMinute
            )
        )
    }

    let parts = raw.split(separator: "-")
    guard parts.count == 2,
          let startMinute = Int(parts[0]),
          let endMinute = Int(parts[1]) else {
        return nil
    }

    return clampShiftShortcutRange(
        ShiftShortcutRange(startMinute: startMinute, endMinute: endMinute)
    )
}

private func clampShiftShortcutRange(_ range: ShiftShortcutRange) -> ShiftShortcutRange {
    let clampedStart = max(0, min(ShiftTimeRange.minutesPerDay - 1, range.startMinute))
    let normalizedEnd = range.endMinute <= clampedStart
        ? range.endMinute + ShiftTimeRange.minutesPerDay
        : range.endMinute
    let upperEnd = min(ShiftTimeRange.maxEndMinuteOffset, clampedStart + ShiftTimeRange.maxDurationMinutes)
    let clampedEnd = max(clampedStart + 15, min(upperEnd, normalizedEnd))
    return ShiftShortcutRange(startMinute: clampedStart, endMinute: clampedEnd)
}

private func parseMoneyToCents(_ text: String) -> Int? {
    let normalized = text.replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized), value >= 0 else { return nil }
    return Int((value * 100).rounded())
}

private func parseHoursToSeconds(_ text: String) -> Int? {
    let normalized = text.replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized), value >= 0 else { return nil }
    return Int((value * 3600).rounded())
}

private func normalizeHolidayCode(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}

private func formatMinute(_ minute: Int) -> String {
    ShiftTimeRange.displayMinute(minute)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
