import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudKitService: CloudKitService
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
                            subtitle: paySummary,
                            systemImage: "eurosign.circle"
                        )
                    }

                    NavigationLink {
                        NetDefaultsSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Netto-Standardwerte",
                            subtitle: netDefaultsSummary,
                            systemImage: "percent"
                        )
                    }

                    NavigationLink {
                        WorkweekSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Arbeitswoche",
                            subtitle: workweekSummary,
                            systemImage: "calendar.badge.clock"
                        )
                    }

                    NavigationLink {
                        WeeklyTargetSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Wochenstunden",
                            subtitle: weeklyHoursSummary,
                            systemImage: "clock"
                        )
                    }

                    NavigationLink {
                        RulesSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Berechnungsregeln",
                            subtitle: rulesSummary,
                            systemImage: "slider.horizontal.3"
                        )
                    }

                    NavigationLink {
                        ShiftShortcutsSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Schichtvorlagen",
                            subtitle: shiftShortcutSummary,
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
                            subtitle: appearanceSummary,
                            systemImage: "paintpalette"
                        )
                    }

                    NavigationLink {
                        CalendarTimelineSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Kalender & Timeline",
                            subtitle: timelineSummary,
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
                            subtitle: holidaySummary,
                            systemImage: "flag"
                        )
                    }

                    NavigationLink {
                        ExportSettingsView(settings: $settings)
                    } label: {
                        SettingsMenuRow(
                            title: "CSV-Export",
                            subtitle: "Monatsdaten teilen oder archivieren",
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
                            subtitle: appInfoSummary,
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

    // MARK: - Summaries (use settings)

    private var paySummary: String {
        switch settings.payMode {
        case .hourly:
            if let cents = settings.hourlyRateCents {
                return "Stündlich · \(PayScopeFormatters.currencyString(cents: cents))"
            }
            return "Stündlich"
        case .monthly:
            if let cents = settings.monthlySalaryCents {
                return "Monatlich · \(PayScopeFormatters.currencyString(cents: cents))"
            }
            return "Monatlich"
        }
    }

    private var netDefaultsSummary: String {
        let taxText = settings.netWageTaxPercent.map { String(format: "%.2f%%", $0).replacingOccurrences(of: ".", with: ",") } ?? "Lohnsteuer -"
        let pensionText = settings.netPensionPercent.map { String(format: "%.2f%%", $0).replacingOccurrences(of: ".", with: ",") } ?? "Rente -"
        let bonusCount = (settings.netBonusesCSV ?? "")
            .split(separator: ";")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return "\(taxText) · \(pensionText) · Zuschläge: \(bonusCount)"
    }

    private var workweekSummary: String {
        "Montag als Wochenstart · \(settings.scheduledWorkdaysCount) Tagewoche"
    }

    private var weeklyHoursSummary: String {
        let hoursText: String
        if let weeklyTargetSeconds = settings.weeklyTargetSeconds {
            hoursText = PayScopeFormatters.hoursString(seconds: weeklyTargetSeconds)
        } else {
            hoursText = "kein Sollwert"
        }
        return hoursText
    }

    private var rulesSummary: String {
        let vacationMode: String
        switch settings.effectiveVacationCreditingMode {
        case .lookback13Weeks:
            vacationMode = "Urlaub: 13-Wochen"
        case .fixedValue:
            let fixed = PayScopeFormatters.hhmmString(seconds: settings.effectiveVacationFixedSeconds)
            vacationMode = "Urlaub: Fix \(fixed)"
        }
        let holidayMode: String
        switch settings.effectiveHolidayCreditingMode {
        case .lookback13Weeks:
            holidayMode = "Feiertag: 13-Wochen"
        case .fixedValue, .weeklyTargetDistributed, .zero:
            let fixed = PayScopeFormatters.hhmmString(seconds: settings.effectiveHolidayFixedSeconds)
            holidayMode = "Feiertag: Fix \(fixed)"
        }
        let strict = settings.strictHistoryRequired ? "strikt" : "flexibel"
        let missing = settings.countMissingAsZero ? "Lückenlos" : "Mit Lücken"
        return "\(vacationMode) · \(holidayMode) · \(strict) · \(missing)"
    }

    private var appearanceSummary: String {
        "\(settings.themeAccent.label)"
    }

    private var timelineSummary: String {
        let mode = settings.calendarCellDisplayMode ?? .dot
        let minMinute = settings.timelineMinMinute ?? 6 * 60
        let maxMinute = settings.timelineMaxMinute ?? 22 * 60
        var weekItems: [String] = []
        if settings.effectiveShowCalendarWeekNumbers {
            weekItems.append("KW")
        }
        if settings.effectiveShowCalendarWeekHours {
            weekItems.append("W-Std")
        }
        if settings.effectiveShowCalendarWeekPay {
            weekItems.append("W-Geld")
        }
        let weekSuffix = weekItems.isEmpty ? "" : " · \(weekItems.joined(separator: "+"))"
        if mode == .hours {
            return "\(mode.label) (\(settings.effectiveCalendarHoursBreakMode.label)) · \(formatMinute(minMinute))-\(formatMinute(maxMinute))\(weekSuffix)"
        }
        return "\(mode.label) · \(formatMinute(minMinute))-\(formatMinute(maxMinute))\(weekSuffix)"
    }

    private var holidaySummary: String {
        let countryCode = settings.holidayCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let country = countryCode.isEmpty ? "DE" : countryCode
        let subdivision = settings.holidaySubdivisionCode ?? "alle Regionen"
        let selectedDayCount = (1...7).filter { settings.isPaidHolidayWeekday(weekday: $0) }.count
        let autoShiftSuffix = selectedDayCount == 0 ? " · keine Auto-Feiertagsschicht" : " · Auto-Feiertag an \(selectedDayCount) Tagen"
        return "\(country) · \(subdivision)\(autoShiftSuffix)"
    }

    private var appInfoSummary: String {
        let info = AppInfoSnapshot.current
        return "\(info.developerName) · \(info.versionBuild)"
    }

    private var shiftShortcutSummary: String {
        //let first = summaryLabelForShiftShortcut(raw: settings.shiftShortcut1, index: 0, name: settings.shiftShortcutName1 ?? "")
       // let second = summaryLabelForShiftShortcut(raw: settings.shiftShortcut2, index: 1, name: settings.shiftShortcutName2 ?? "")
        //let third = summaryLabelForShiftShortcut(raw: settings.shiftShortcut3, index: 2, name: settings.shiftShortcutName3 ?? "")
        //return "\(first) · \(second) · \(third)"
        return "Shortcuts für Schichten bearbeiten"
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

private struct CalendarTimelineSettingsView: View {
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

                Toggle("Kalenderwochen", isOn: showCalendarWeekNumbersBinding)
                Toggle("Wochenstunden", isOn: showCalendarWeekHoursBinding)
                Toggle("Wochenverdienst", isOn: showCalendarWeekPayBinding)
            }

            Section(header: Text("Timeline-Zeitfenster"),
            footer: Text("Begrenzt den sichtbaren Tagesbereich in der Timeline.")){
                minuteWindowControl(
                    title: "Früheste Zeit",
                    value: timelineMinBinding,
                    step: 15,
                    lower: 0,
                    upper: max(0, timelineMaxBinding.wrappedValue - 60)
                )
                minuteWindowControl(
                    title: "Späteste Zeit",
                    value: timelineMaxBinding,
                    step: 15,
                    lower: min(24 * 60, timelineMinBinding.wrappedValue + 60),
                    upper: 24 * 60
                )
            }
        }
        .navigationTitle("Kalender & Timeline")
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

    private var timelineMinBinding: Binding<Int> {
        Binding(
            get: { settings.timelineMinMinute ?? 6 * 60 },
            set: { newValue in
                let clamped = max(0, min(newValue, 23 * 60))
                let currentMax = settings.timelineMaxMinute ?? 22 * 60
                settings.timelineMinMinute = min(clamped, currentMax - 60)
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

    private var timelineMaxBinding: Binding<Int> {
        Binding(
            get: { settings.timelineMaxMinute ?? 22 * 60 },
            set: { newValue in
                let clamped = max(60, min(newValue, 24 * 60))
                let currentMin = settings.timelineMinMinute ?? 6 * 60
                settings.timelineMaxMinute = max(clamped, currentMin + 60)
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    @ViewBuilder
    private func minuteWindowControl(
        title: String,
        value: Binding<Int>,
        step: Int,
        lower: Int,
        upper: Int
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                value.wrappedValue = max(lower, value.wrappedValue - step)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)

            Text(formatMinute(value.wrappedValue))
                .font(.subheadline.bold())
                .frame(minWidth: 58)

            Button {
                value.wrappedValue = min(upper, value.wrappedValue + step)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
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
            draftStartMinute = max(0, min(24 * 60 - 15, draftStartMinute + deltaMinutes))
            draftEndMinute = max(draftStartMinute + 15, draftEndMinute)
        } else {
            draftEndMinute = max(draftStartMinute + 15, min(24 * 60, draftEndMinute + deltaMinutes))
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

private struct ExportSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    @State private var exportMonthNumber = Calendar.current.component(.month, from: Date())
    @State private var exportYear = Calendar.current.component(.year, from: Date())
    @State private var csvPayload = ""
    @State private var showShare = false
    @State private var showFileImporter = false
    @State private var showImportSheet = false
    @State private var importedRows: [ShiftCSVImportRowDraft] = []
    @State private var skippedImportRows = 0
    @State private var importInfoMessage: String?
    @State private var importErrorMessage: String?
    @State private var isSavingImportRows = false

    private let exporter = CSVExporter()

    var body: some View {
        Form {
            Section(header: Text("CSV-Export"),footer:Text("Der Export enthält alle Tage des gewählten Monats inklusive Kategorien und Zeiten.")) {
                HStack {
                    Picker("Monat", selection: $exportMonthNumber) {
                        ForEach(1...12, id: \.self) { month in
                            Text(Calendar.current.monthSymbols[month - 1]).tag(month)
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
                        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedExportMonthDate)) ?? selectedExportMonthDate
                        let end = Calendar.current.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? Date()
                        let fetched = (try? await cloudKitService.fetchDayEntries(in: DateInterval(start: start, end: end))) ?? []
                        csvPayload = exporter.csvForMonth(entries: fetched, month: selectedExportMonthDate, settings: settings)
                        showShare = !csvPayload.isEmpty
                    }
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
        .navigationTitle("CSV-Export")
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [csvPayload])
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

        for row in importedRows {
            guard row.hasValidTimeRange else {
                skipped += 1
                continue
            }

            let dayStart = row.date.startOfDayLocal()
            guard
                let start = Calendar.current.date(byAdding: .minute, value: row.startMinute, to: dayStart),
                let end = Calendar.current.date(byAdding: .minute, value: row.endMinute, to: dayStart),
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
                saved += 1
            } catch {
                importErrorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
                return false
            }
        }

        NotificationCenter.default.post(name: .dayEntriesDidChange, object: nil)
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
                                selection: minuteBinding(minute: $row.endMinute, date: $row.date),
                                displayedComponents: .hourAndMinute
                            )

                            Stepper("Pause: \(row.breakMinutes) min", value: $row.breakMinutes, in: 0...720, step: 5)
                        } else {
                            LabeledContent("Datum", value: dayText(row.date))
                            LabeledContent("Start", value: minuteText(row.startMinute))
                            LabeledContent("Ende", value: minuteText(row.endMinute))
                            LabeledContent("Pause", value: "\(row.breakMinutes) min")
                        }
                    }
                    .padding(.vertical, 4)
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

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
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
    let clampedStart = max(0, min(24 * 60 - 15, range.startMinute))
    let clampedEnd = max(clampedStart + 15, min(24 * 60, range.endMinute))
    return ShiftShortcutRange(startMinute: clampedStart, endMinute: clampedEnd)
}

private func summaryLabelForShiftShortcut(raw: String, index: Int, name: String) -> String {
    let range = parseShiftShortcutRange(raw: raw) ?? defaultShiftShortcutRange(index: index)
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let rangeText = "\(formatMinute(range.startMinute))-\(formatMinute(range.endMinute))"
    if trimmedName.isEmpty {
        return rangeText
    }
    return "\(trimmedName) \(rangeText)"
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
    let h = minute / 60
    let m = minute % 60
    return String(format: "%02d:%02d", h, m)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
