import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit
import ActivityKit
import WidgetKit

private enum SettingsRoute: Hashable {
    case pay
    case netDefaults
    case tips
    case workweek
    case weeklyTarget
    case appearance
    case calendar
    case export
    case appInfo
    case rules
    case shiftShortcuts
    case widgetsLiveActivity
    case holidays
    case appleCalendar
}

private struct SettingsSearchItem: Identifiable {
    let route: SettingsRoute
    let title: String
    let subtitle: String
    let systemImage: String
    let keywords: [String]

    var id: SettingsRoute { route }

    func matches(_ searchText: String) -> Bool {
        let queryTokens = Self.normalized(searchText)
            .split(separator: " ")
            .map(String.init)

        guard !queryTokens.isEmpty else { return false }

        let searchableText = Self.normalized(
            ([title, subtitle] + keywords).joined(separator: " ")
        )

        return queryTokens.allSatisfy { searchableText.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
    }
}

struct SettingsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudKitService: CloudKitService
    @ObservedObject private var appleCalendarSync = AppleCalendarSyncService.shared
    @State private var settings: Settings
    @State private var isAdvancedSettingsExpanded = false
    @State private var showResetConfirmation = false
    @State private var showResetResultAlert = false
    @State private var resetResultMessage = ""
    @State private var searchText = ""
    @State private var resetWarningFeedbackTrigger = 0
    @FocusState private var isSearchFocused: Bool

    init(settings: Settings) {
        _settings = State(initialValue: settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                settingsSearchResultsSection
                basicSettingsSections
                dataAndAppSettingsSection
                advancedSettingsSection
            }
            .navigationTitle("Einstellungen")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                settingsBottomSearchBar
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
            .sensoryFeedback(.warning, trigger: resetWarningFeedbackTrigger)
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

    private var settingsBottomSearchBar: some View {
        let shape = Capsule(style: .continuous)

        return HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(settings.themeAccent.color)

            TextField("Suchen", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .payScopePureGlassSurface(
            accent: settings.themeAccent.color,
            in: shape,
            tintOpacity: 0.075,
            shadowOpacity: 0.1,
            isInteractive: true
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var settingsSearchResultsSection: some View {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedSearchText.isEmpty {
            let results = settingsSearchItems.filter { $0.matches(trimmedSearchText) }

            Section("Treffer") {
                if results.isEmpty {
                    Label("Keine passenden Einstellungen", systemImage: "magnifyingglass")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { item in
                        settingsNavigationLink(
                            route: item.route,
                            title: item.title,
                            subtitle: item.subtitle,
                            systemImage: item.systemImage
                        )
                    }
                }
            }
        }
    }

    private func settingsNavigationLink(
        route: SettingsRoute,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        NavigationLink(value: route) {
            SettingsMenuRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage
            )
        }
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .pay:
            PaySettingsView(settings: $settings)
        case .netDefaults:
            NetDefaultsSettingsView(settings: $settings)
        case .tips:
            TipsSettingsView(settings: $settings)
        case .workweek:
            WorkweekSettingsView(settings: $settings)
        case .weeklyTarget:
            WeeklyTargetSettingsView(settings: $settings)
        case .appearance:
            AppearanceSettingsView(settings: $settings)
        case .calendar:
            CalendarSettingsView(settings: $settings)
        case .export:
            ExportSettingsView(settings: $settings)
        case .appInfo:
            AppInfoSettingsView()
        case .rules:
            RulesSettingsView(settings: $settings)
        case .shiftShortcuts:
            ShiftShortcutsSettingsView(settings: $settings)
        case .widgetsLiveActivity:
            WidgetLiveActivitySettingsView(settings: $settings)
        case .holidays:
            HolidayImportSettingsView(settings: $settings)
        case .appleCalendar:
            AppleCalendarSettingsView(settings: settings)
        }
    }

    private var settingsSearchItems: [SettingsSearchItem] {
        [
            SettingsSearchItem(
                route: .pay,
                title: "Vergütung",
                subtitle: "Abrechnungsmodell und Gehaltswert einstellen",
                systemImage: "eurosign.circle",
                keywords: ["Lohn", "Gehalt", "Stundenlohn", "Monatslohn", "Brutto", "Abrechnung"]
            ),
            SettingsSearchItem(
                route: .netDefaults,
                title: "Netto",
                subtitle: "Steuern, Abgaben, Freibetrag und Zuschläge hinterlegen",
                systemImage: "percent",
                keywords: ["Lohnsteuer", "Rente", "Rentenversicherung", "Abgaben", "Bonus", "Zuschläge"]
            ),
            SettingsSearchItem(
                route: .tips,
                title: "Trinkgeld",
                subtitle: tipsSettingsSubtitle,
                systemImage: "eurosign.circle",
                keywords: ["Tips", "Monatsbetrag", "Button", "Betrag"]
            ),
            SettingsSearchItem(
                route: .workweek,
                title: "Arbeitswoche",
                subtitle: "Arbeitstage pro Woche festlegen",
                systemImage: "calendar.badge.clock",
                keywords: ["Wochentage", "Arbeitstage", "Woche"]
            ),
            SettingsSearchItem(
                route: .weeklyTarget,
                title: "Wochenstunden",
                subtitle: "Sollstunden pro Woche hinterlegen",
                systemImage: "clock",
                keywords: ["Soll", "Ziel", "Stunden", "Wochenziel"]
            ),
            SettingsSearchItem(
                route: .appearance,
                title: "Erscheinungsbild",
                subtitle: "Akzentfarbe der App auswählen",
                systemImage: "paintpalette",
                keywords: ["Farbe", "Design", "Theme", "Akzent"]
            ),
            SettingsSearchItem(
                route: .calendar,
                title: "Kalender",
                subtitle: "Kalenderzellen und Wocheninfos anpassen",
                systemImage: "rectangle.3.group",
                keywords: ["Zellen", "Wochenstunden", "Wochenverdienst", "Kalenderwochen", "Anzeige"]
            ),
            SettingsSearchItem(
                route: .export,
                title: "Export",
                subtitle: "Monatsdaten als CSV, Text oder PDF teilen",
                systemImage: "square.and.arrow.up",
                keywords: ["CSV", "PDF", "Teilen", "Import", "Datei", "Monat"]
            ),
            SettingsSearchItem(
                route: .appInfo,
                title: "Info & Entwickler",
                subtitle: "App-Version und Entwicklerangaben ansehen",
                systemImage: "info.circle",
                keywords: ["Version", "Entwickler", "Impressum", "Kontakt"]
            ),
            SettingsSearchItem(
                route: .rules,
                title: "Berechnungsregeln",
                subtitle: "Pausen, Gutschriften und Referenzlogik konfigurieren",
                systemImage: "slider.horizontal.3",
                keywords: ["Pause", "Pausen", "Urlaub", "Feiertag", "Krank", "13 Wochen", "Historie", "Aushilfe", "Stundenkonto"]
            ),
            SettingsSearchItem(
                route: .shiftShortcuts,
                title: "Schichtvorlagen",
                subtitle: "Namen und Zeiten für schnelle Schichten bearbeiten",
                systemImage: "clock.badge",
                keywords: ["Vorlagen", "Shortcut", "Shortcuts", "Start", "Ende", "Schnell"]
            ),
            SettingsSearchItem(
                route: .widgetsLiveActivity,
                title: "Widgets und Live Activity",
                subtitle: "Lock-Screen-Widgets, Live Activity und Aktualisierung",
                systemImage: "rectangle.inset.filled.and.person.filled",
                keywords: ["Widget", "Widgets", "Live Activity", "Dynamic Island", "Lock Screen", "Aktualisieren"]
            ),
            SettingsSearchItem(
                route: .holidays,
                title: "Feiertage",
                subtitle: "Region, Import und automatische Markierung einstellen",
                systemImage: "flag",
                keywords: ["Feiertag", "Feiertage", "Region", "Bundesland", "Import", "Markierung"]
            ),
            SettingsSearchItem(
                route: .appleCalendar,
                title: "Apple Kalender",
                subtitle: appleCalendarSubtitle,
                systemImage: "calendar.badge.plus",
                keywords: ["Kalender", "Apple", "Export", "Synchronisieren", "Event", "Termin"]
            )
        ]
    }

    @ViewBuilder
    private var basicSettingsSections: some View {
        Section("Arbeit") {
            settingsNavigationLink(
                route: .pay,
                title: "Vergütung",
                subtitle: "Abrechnungsmodell und Gehaltswert einstellen",
                systemImage: "eurosign.circle"
            )

            settingsNavigationLink(
                route: .tips,
                title: "Trinkgeld",
                subtitle: tipsSettingsSubtitle,
                systemImage: "eurosign.circle"
            )

            settingsNavigationLink(
                route: .workweek,
                title: "Arbeitswoche",
                subtitle: "Arbeitstage pro Woche festlegen",
                systemImage: "calendar.badge.clock"
            )

            settingsNavigationLink(
                route: .weeklyTarget,
                title: "Wochenstunden",
                subtitle: "Sollstunden pro Woche hinterlegen",
                systemImage: "clock"
            )
        }

        Section("Darstellung") {
            settingsNavigationLink(
                route: .appearance,
                title: "Erscheinungsbild",
                subtitle: "Akzentfarbe der App auswählen",
                systemImage: "paintpalette"
            )

            settingsNavigationLink(
                route: .calendar,
                title: "Kalender",
                subtitle: "Kalenderzellen und Wocheninfos anpassen",
                systemImage: "rectangle.3.group"
            )
        }
    }

    @ViewBuilder
    private var dataAndAppSettingsSection: some View {
        Section("Daten & App") {
            settingsNavigationLink(
                route: .export,
                title: "Export",
                subtitle: "Monatsdaten als CSV, Text oder PDF teilen",
                systemImage: "square.and.arrow.up"
            )

            settingsNavigationLink(
                route: .appInfo,
                title: "Info & Entwickler",
                subtitle: "App-Version und Entwicklerangaben ansehen",
                systemImage: "info.circle"
            )
        }
    }

    @ViewBuilder
    private var advancedSettingsSection: some View {
        Section {
            DisclosureGroup("Erweitert", isExpanded: $isAdvancedSettingsExpanded) {
                settingsNavigationLink(
                    route: .rules,
                    title: "Berechnungsregeln",
                    subtitle: "Pausen, Gutschriften und Referenzlogik konfigurieren",
                    systemImage: "slider.horizontal.3"
                )

                settingsNavigationLink(
                    route: .shiftShortcuts,
                    title: "Schichtvorlagen",
                    subtitle: "Namen und Zeiten für schnelle Schichten bearbeiten",
                    systemImage: "clock.badge"
                )

                settingsNavigationLink(
                    route: .widgetsLiveActivity,
                    title: "Widgets und Live Activity",
                    subtitle: "Lock-Screen-Widgets, Live Activity und Aktualisierung",
                    systemImage: "rectangle.inset.filled.and.person.filled"
                )

                settingsNavigationLink(
                    route: .holidays,
                    title: "Feiertage",
                    subtitle: "Region, Import und automatische Markierung einstellen",
                    systemImage: "flag"
                )

                settingsNavigationLink(
                    route: .appleCalendar,
                    title: "Apple Kalender",
                    subtitle: appleCalendarSubtitle,
                    systemImage: "calendar.badge.plus"
                )

                Button("App zurücksetzen", role: .destructive) {
                    resetWarningFeedbackTrigger += 1
                    showResetConfirmation = true
                }
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

            Section("Netto") {
                NavigationLink {
                    NetDefaultsSettingsView(settings: $settings)
                } label: {
                    SettingsMenuRow(
                        title: "Lohnsteuerabgaben",
                        subtitle: "Abgaben und Zuschläge für Steuern verwalten",
                        systemImage: "percent"
                    )
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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    @State private var selectedMonth = Date().startOfMonthLocal()
    @State private var config = NetWageMonthConfig(monthStart: Date().startOfMonthLocal())
    @State private var wageTaxText = ""
    @State private var pensionText = ""
    @State private var bonusTexts: [String] = []
    @State private var newBonusText = ""
    @State private var showMonthPicker = false
    @State private var saveFeedbackTrigger = 0

    var body: some View {
        Form {
            Section("Monat") {
                Button {
                    showMonthPicker = true
                } label: {
                    HStack {
                        Text("Gültig für")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Self.monthYearFormatter.string(from: selectedMonth))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section(
                header: Text("Abgaben (%)"),
                footer: Text("Diese Werte gelten für den ausgewählten Monat.")
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
        .navigationTitle("Lohnsteuerangaben")
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
            loadConfig(for: selectedMonth)
        }
        .onChange(of: selectedMonth) { _, newValue in
            loadConfig(for: newValue)
        }
        .sensoryFeedback(.success, trigger: saveFeedbackTrigger)
        .sheet(isPresented: $showMonthPicker) {
            MonthYearPickerSheet(
                initialMonth: selectedMonth,
                yearRange: monthYearPickerRange,
                accent: settings.themeAccent.color
            ) { month in
                monthPickerBinding.wrappedValue = month
            }
        }
    }

    private var monthYearPickerRange: ClosedRange<Int> {
        let currentYear = Calendar.current.component(.year, from: Date())
        let selectedYear = Calendar.current.component(.year, from: selectedMonth)
        return min(currentYear, selectedYear) - 25...max(currentYear, selectedYear) + 25
    }

    private var monthPickerBinding: Binding<Date> {
        Binding(
            get: { selectedMonth },
            set: { newValue in
                selectedMonth = newValue.startOfMonthLocal()
            }
        )
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

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private func loadConfig(for month: Date) {
        let normalizedMonth = month.startOfMonthLocal()
        Task { @MainActor in
            let localConfigs = fetchLocalNetConfigs()
            let remoteConfigs = (try? await cloudKitService.fetchNetWageConfigs()) ?? []
            for config in remoteConfigs {
                upsertLocalNetConfig(config)
            }
            let configs = mergedNetConfigs(local: fetchLocalNetConfigs().isEmpty ? localConfigs : fetchLocalNetConfigs(), remote: remoteConfigs)
            guard selectedMonth.isSameLocalDay(as: normalizedMonth) else { return }

            let exactConfig = configs.first {
                $0.monthStart.isSameLocalDay(as: normalizedMonth)
            }

            let previousConfig = previousMonthConfig(
                for: normalizedMonth,
                in: configs
            )

            let nextConfig = exactConfig ?? NetWageMonthConfig(
                monthStart: normalizedMonth,
                wageTaxPercent: previousConfig?.wageTaxPercent ?? settings.netWageTaxPercent,
                pensionPercent: previousConfig?.pensionPercent ?? settings.netPensionPercent,
                monthlyAllowanceEuro: previousConfig?.monthlyAllowanceEuro ?? settings.netMonthlyAllowanceEuro,
                bonusesCSV: previousConfig?.bonusesCSV ?? settings.netBonusesCSV ?? ""
            )

            config = nextConfig
            loadFields(from: nextConfig)
        }
    }

    private func previousMonthConfig(for month: Date, in configs: [NetWageMonthConfig]) -> NetWageMonthConfig? {
        guard let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: month.startOfMonthLocal()) else {
            return nil
        }
        return configs.first {
            $0.monthStart.isSameLocalDay(as: previousMonth.startOfMonthLocal())
        }
    }

    private func loadFields(from config: NetWageMonthConfig) {
        wageTaxText = formattedPercent(config.wageTaxPercent)
        pensionText = formattedPercent(config.pensionPercent)
        bonusTexts = config.bonusesCSV
            .split(separator: ";")
            .map { formatForDisplay(from: String($0)) ?? String($0) }
    }

    private func save() {
        let wageTax = normalizedDouble(from: wageTaxText)
        let pension = normalizedDouble(from: pensionText)
        let bonusesCSV = bonusTexts
            .compactMap { normalizedDouble(from: $0) }
            .map { String(format: "%.2f", $0) }
            .joined(separator: ";")

        config.monthStart = selectedMonth.startOfMonthUTC()
        config.wageTaxPercent = wageTax
        config.pensionPercent = pension
        config.bonusesCSV = bonusesCSV
        upsertLocalNetConfig(config)

        wageTaxText = formatForDisplay(from: wageTaxText) ?? ""
        pensionText = formatForDisplay(from: pensionText) ?? ""
        bonusTexts = bonusTexts.map { formatForDisplay(from: $0) ?? $0 }
        saveFeedbackTrigger += 1

        Task { try? await cloudKitService.saveNetWageConfig(config) }
    }

    private func fetchLocalNetConfigs() -> [NetWageMonthConfig] {
        let descriptor = FetchDescriptor<NetWageMonthConfig>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func upsertLocalNetConfig(_ source: NetWageMonthConfig) {
        let normalizedMonth = source.monthStart.startOfMonthUTC()
        let existing = fetchLocalNetConfigs().first {
            netConfigMonthKey($0.monthStart) == netConfigMonthKey(normalizedMonth)
        }

        if let existing {
            existing.monthStart = normalizedMonth
            existing.wageTaxPercent = source.wageTaxPercent
            existing.pensionPercent = source.pensionPercent
            existing.monthlyAllowanceEuro = source.monthlyAllowanceEuro
            existing.bonusesCSV = source.bonusesCSV
        } else {
            modelContext.insert(
                NetWageMonthConfig(
                    monthStart: normalizedMonth,
                    wageTaxPercent: source.wageTaxPercent,
                    pensionPercent: source.pensionPercent,
                    monthlyAllowanceEuro: source.monthlyAllowanceEuro,
                    bonusesCSV: source.bonusesCSV
                )
            )
        }
        try? modelContext.save()
    }

    private func mergedNetConfigs(local: [NetWageMonthConfig], remote: [NetWageMonthConfig]) -> [NetWageMonthConfig] {
        var byMonth: [String: NetWageMonthConfig] = [:]
        for config in local {
            byMonth[netConfigMonthKey(config.monthStart)] = config
        }
        for config in remote {
            byMonth[netConfigMonthKey(config.monthStart)] = config
        }
        return byMonth.values.sorted { $0.monthStart < $1.monthStart }
    }

    private func netConfigMonthKey(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utc.dateComponents([.year, .month], from: date.startOfMonthUTC())
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }
}

private struct TipsSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section(
                header: Text("Trinkgeld"),
                footer: Text("Steuert, ob der Trinkgeld-Button im Kalender erscheint, die Trinkgeldansicht umschaltet und ob er den Monatsbetrag anzeigt.")
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
                header: Text("Pausen"),
                footer: Text("Wenn diese Option aus ist, werden eingetragene Pausen und automatische Mindestpausen nicht von Arbeitszeit und Lohn abgezogen.")
            ) {
                Toggle("Pausen berechnen", isOn: calculateBreaksBinding)
            }

            Section(
                header: Text("Aushilfemodus"),
                footer: Text("Wenn der Aushilfemodus aktiv ist, wird das Stundenkonto im Tab-Bereich ausgeblendet.")
            ) {
                Toggle("Aushilfemodus", isOn: aushilfeModeBinding)
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

    private var calculateBreaksBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveCalculateBreaks },
            set: { newValue in
                settings.calculateBreaks = newValue
                Task { try? await cloudKitService.saveSettings(settings) }
            }
        )
    }

    private var aushilfeModeBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveAushilfeModeEnabled },
            set: { newValue in
                settings.aushilfeModeEnabled = newValue
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
    @State private var selectedCategoryForPalette: DayType?

    private let categoryTypes = DayType.allCases

    var body: some View {
        Form {
            Section(
                header: Text("Erscheinungsbild"),
                footer: Text("Arbeit bleibt an die Akzentfarbe gebunden. Die anderen Kategorien werden als eigene Pastelltöne gespeichert.")) {
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

            Section("Schichtkategorien") {
                HStack(spacing: 0) {
                    ForEach(categoryTypes) { type in
                        Button {
                            guard type != .work else { return }
                            selectedCategoryForPalette = type
                        } label: {
                            Image(systemName: type.icon)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(categoryTint(for: type))
                                .frame(width: 44, height: 44)
                                .payScopeGlassControl(
                                    accent: categoryTint(for: type),
                                    cornerRadius: 14,
                                    tintOpacity: type == .work ? 0.065 : 0.105,
                                    isInteractive: type != .work
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(type.label)
                        .opacity(type == .work ? 0.82 : 1)
                        .popover(isPresented: categoryPaletteBinding(for: type),arrowEdge: .bottom) {
                            CategoryColorPaletteView(
                                type: type,
                                selectedColor: settings.categoryColorSelection(for: type),
                                accent: settings.themeAccent.color
                            ) { color in
                                settings.setCategoryColor(color, for: type)
                                selectedCategoryForPalette = nil
                                Task { try? await cloudKitService.saveSettings(settings) }
                            }
                            .presentationCompactAdaptation(.popover)
                        }

                        if type != categoryTypes.last {
                            Spacer(minLength: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Erscheinungsbild")
        .onChange(of: settings.themeAccent) { _, _ in
            Task { try? await cloudKitService.saveSettings(settings) }
        }
    }

    private func categoryTint(for type: DayType) -> Color {
        settings.categoryColor(for: type)
    }

    private func categoryPaletteBinding(for type: DayType) -> Binding<Bool> {
        Binding {
            selectedCategoryForPalette == type
        } set: { isPresented in
            if !isPresented, selectedCategoryForPalette == type {
                selectedCategoryForPalette = nil
            }
        }
    }
}

private struct CategoryColorPaletteView: View {
    let type: DayType
    let selectedColor: ShiftCategoryColor?
    let accent: Color
    let onSelect: (ShiftCategoryColor) -> Void

    private let columns = Array(repeating: GridItem(.fixed(42), spacing: 10), count: 5)
    private let paletteWidth: CGFloat = 280
    private var paletteContentWidth: CGFloat {
        paletteWidth - (PayScopeModalGeometry.popover.edgePadding * 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .foregroundStyle(type == .work ? accent : selectedColor?.color ?? accent)
                Text(type.label)
                    .font(.headline)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ShiftCategoryColor.allCases) { color in
                    let isSelected = selectedColor == color

                    Button {
                        onSelect(color)
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Circle()
                                    .stroke(Color.primary.opacity(isSelected ? 0.72 : 0.18), lineWidth: isSelected ? 2 : 1)
                            }
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.primary)
                                }
                            }
                    }
                    .buttonStyle(
                        PayScopeLiquidGlassPressButtonStyle(
                            accent: color.color,
                            shape: Circle(),
                            tintOpacity: 0.12,
                            pressedScale: 0.9
                        )
                    )
                    .accessibilityLabel(color.label)
                }
            }
        }
        .padding(16)
        .frame(width: paletteContentWidth)
        .payScopePopoverSurface(accent: accent)
    }
}

private struct CalendarSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section(
                header: Text("Kalenderdarstellung"),
                footer: Text("Die Zellansicht wird direkt im Kalender-Menü geändert.")) {
                    Toggle("Kalenderwochen", isOn: showCalendarWeekNumbersBinding)
                    Toggle("Wochenstunden", isOn: showCalendarWeekHoursBinding)
                    Toggle("Wochenverdienst", isOn: showCalendarWeekPayBinding)
                }
            
            Section(
                header: Text("Monatsinformationen"),
                footer: Text(calendarSummaryDisplayModeFooter)
        )
                {
                    Picker("Monatswert", selection: calendarSummaryDisplayModeBinding) {
                        ForEach(CalendarSummaryDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
            }
            .pickerStyle(.segmented)
        }
        }
        .navigationTitle("Kalender")
    }

    private var calendarSummaryDisplayModeFooter: String {
        switch settings.effectiveCalendarSummaryDisplayMode {
        case .net:
            return "Netto zeigt Schichtlohn plus Zuschläge abzüglich LS und RV."
        case .gross:
            return "Brutto zeigt Schichtlohn plus eingetragene Zuschläge vor Abzügen."
        case .shiftPay:
            return "Schichtlohn zeigt nur den berechneten Lohn aus deinen Schichten ohne Zuschläge und Abzüge."
        }
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
}

private struct WidgetLiveActivitySettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings
    @State private var lastWidgetRefreshDate: Date?
    @State private var widgetRefreshFeedbackTrigger = 0

    private static let refreshFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        Form {
            Section(
                header: Text("Live Activity"),
                footer: Text(liveActivityFooter)
            ) {
                Toggle("Automatisch starten", isOn: showLiveActivityBinding)
                Toggle("Nächste Schicht anzeigen", isOn: liveActivityShowsUpcomingShiftBinding)
                    .disabled(!settings.effectiveShowLiveActivity)
                Toggle("Pausenmodus anzeigen", isOn: liveActivityPauseModeEnabledBinding)
                    .disabled(!settings.effectiveShowLiveActivity)
            }

            Section(
                header: Text("Lock-Screen-Widgets"),
                footer: Text("Gilt für das rechteckige und das Inline-Widget.")
            ) {
                Toggle("Nächste Schicht anzeigen", isOn: widgetShowsNextShiftBinding)
                Toggle("Ganztagsstatus anzeigen", isOn: widgetShowsAllDayStatusBinding)
            }

            Section(
                header: Text("Darstellung"),
                footer: Text("Die Akzentfarbe wird auch für Widgets und Live Activity verwendet.")
            ) {
                HStack {
                    Text("Akzentfarbe")
                    Spacer()
                    Menu {
                        ForEach(ThemeAccent.allCases) { accent in
                            Button {
                                settings.themeAccent = accent
                                saveAndRefreshWidgets()
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

            Section("Aktualisierung") {
                Button {
                    refreshWidgets()
                } label: {
                    Label("Widgets jetzt aktualisieren", systemImage: "arrow.clockwise")
                }

                if let lastWidgetRefreshDate {
                    Text("Zuletzt aktualisiert: \(Self.refreshFormatter.string(from: lastWidgetRefreshDate))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Widgets und Live Activity")
        .sensoryFeedback(.success, trigger: widgetRefreshFeedbackTrigger)
    }

    private var liveActivityFooter: String {
        ActivityAuthorizationInfo().areActivitiesEnabled
            ? "PayScope startet die Live Activity für geplante Schichten automatisch."
            : "Live Activities sind in den iOS-Systemeinstellungen deaktiviert."
    }

    private var showLiveActivityBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowLiveActivity },
            set: {
                settings.showLiveActivity = $0
                saveAndRefreshWidgets()
            }
        )
    }

    private var liveActivityShowsUpcomingShiftBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveLiveActivityShowsUpcomingShift },
            set: {
                settings.liveActivityShowsUpcomingShift = $0
                saveAndRefreshWidgets()
            }
        )
    }

    private var liveActivityPauseModeEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveLiveActivityPauseModeEnabled },
            set: {
                settings.liveActivityPauseModeEnabled = $0
                saveAndRefreshWidgets()
            }
        )
    }

    private var widgetShowsNextShiftBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveWidgetShowsNextShift },
            set: {
                settings.widgetShowsNextShift = $0
                saveAndRefreshWidgets()
            }
        )
    }

    private var widgetShowsAllDayStatusBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveWidgetShowsAllDayStatus },
            set: {
                settings.widgetShowsAllDayStatus = $0
                saveAndRefreshWidgets()
            }
        )
    }

    private func saveAndRefreshWidgets() {
        Task { try? await cloudKitService.saveSettings(settings) }
        refreshWidgets()
    }

    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        lastWidgetRefreshDate = .now
        widgetRefreshFeedbackTrigger += 1
    }
}

private struct ShiftShortcutsSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings
    @State private var editingShortcut: ShiftShortcutEditDraft?

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
        .sheet(item: $editingShortcut) { draft in
            ShiftShortcutEditorSheet(
                draft: draft,
                accent: settings.themeAccent.color,
                onCancel: { editingShortcut = nil },
                onSave: saveShortcutDraft
            )
        }
    }

    @ViewBuilder
    private func shortcutRow(
        title: String,
        index: Int
    ) -> some View {
        let range = effectiveShortcutRange(for: index)

        HStack(alignment: .center, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(for: index, fallback: title))
                        .font(.headline)
                    Text(range.displayRange)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            Button {
                beginEditingShortcut(title: title, index: index)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(displayName(for: index, fallback: title)) bearbeiten")
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

    private func beginEditingShortcut(title: String, index: Int) {
        let range = effectiveShortcutRange(for: index)
        editingShortcut = ShiftShortcutEditDraft(
            index: index,
            title: title,
            name: displayName(for: index, fallback: ""),
            startMinute: range.startMinute,
            endMinute: range.endMinute,
            payload: range.payload,
            defaultRange: defaultShiftShortcutRange(index: index)
        )
    }

    private func saveShortcutDraft(_ draft: ShiftShortcutEditDraft) {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue = ShiftShortcutRange(
            startMinute: draft.startMinute,
            endMinute: draft.endMinute,
            payload: draft.payload
        ).rawValue
        switch draft.index {
        case 0:
            settings.shiftShortcut1 = rawValue
            settings.shiftShortcutName1 = trimmedName.nilIfEmpty
        case 1:
            settings.shiftShortcut2 = rawValue
            settings.shiftShortcutName2 = trimmedName.nilIfEmpty
        default:
            settings.shiftShortcut3 = rawValue
            settings.shiftShortcutName3 = trimmedName.nilIfEmpty
        }

        editingShortcut = nil
        Task { try? await cloudKitService.saveSettings(settings) }
    }
}

private struct ShiftShortcutEditorSheet: View {
    @State private var draft: ShiftShortcutEditDraft

    let accent: Color
    let onCancel: () -> Void
    let onSave: (ShiftShortcutEditDraft) -> Void

    init(
        draft: ShiftShortcutEditDraft,
        accent: Color,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ShiftShortcutEditDraft) -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.accent = accent
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name, z. B. Frühschicht", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Zeit") {
                    ShortcutMinuteControl(
                        title: "Start",
                        value: draft.startMinute,
                        accent: accent,
                        onDecrease: { adjustDraftTime(isStart: true, deltaMinutes: -15) },
                        onIncrease: { adjustDraftTime(isStart: true, deltaMinutes: 15) }
                    )
                    ShortcutMinuteControl(
                        title: "Ende",
                        value: draft.endMinute,
                        accent: accent,
                        onDecrease: { adjustDraftTime(isStart: false, deltaMinutes: -15) },
                        onIncrease: { adjustDraftTime(isStart: false, deltaMinutes: 15) }
                    )
                }

                Section {
                    Button("Standardwerte") {
                        draft.name = ""
                        draft.startMinute = draft.defaultRange.startMinute
                        draft.endMinute = draft.defaultRange.endMinute
                        draft.payload = nil
                    }
                }
            }
            .navigationTitle("\(draft.title) bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        onSave(draft)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func adjustDraftTime(isStart: Bool, deltaMinutes: Int) {
        if isStart {
            let duration = max(15, draft.endMinute - draft.startMinute)
            let upperStart = min(ShiftTimeRange.minutesPerDay - 1, ShiftTimeRange.maxEndMinuteOffset - duration)
            draft.startMinute = max(0, min(upperStart, draft.startMinute + deltaMinutes))
            draft.endMinute = min(
                ShiftTimeRange.maxEndMinuteOffset,
                min(draft.startMinute + ShiftTimeRange.maxDurationMinutes, draft.startMinute + duration)
            )
        } else {
            let upperEnd = min(ShiftTimeRange.maxEndMinuteOffset, draft.startMinute + ShiftTimeRange.maxDurationMinutes)
            draft.endMinute = max(draft.startMinute + 15, min(upperEnd, draft.endMinute + deltaMinutes))
        }
    }
}

private struct ShortcutMinuteControl: View {
    let title: String
    let value: Int
    let accent: Color
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: onDecrease) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)

            Text(formatMinute(value))
                .font(.subheadline.bold())
                .monospacedDigit()
                .frame(minWidth: 78)
                .foregroundStyle(accent)

            Button(action: onIncrease) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
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
                HStack(spacing: 12) {
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

private enum MonthExportPreviewContent {
    case text(String, isMonospaced: Bool)
    case pdf(URL)
}

private enum MonthExportFormat {
    case csv
    case text
    case pdf
}

private struct ExportMonthOption: Identifiable, Hashable {
    let year: Int
    let month: Int

    var id: String {
        String(format: "%04d-%02d", year, month)
    }

    var date: Date {
        let components = DateComponents(year: year, month: month, day: 1)
        return Calendar.current.date(from: components) ?? Date()
    }
}

private struct MonthExportPreview: Identifiable {
    let id = UUID()
    let format: MonthExportFormat
    let title: String
    let subtitle: String
    let detail: String
    let content: MonthExportPreviewContent
    let shareItems: [Any]
}

private struct MonthExportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let accent: Color

    @State private var preview: MonthExportPreview
    @State private var showShare = false

    init(preview: MonthExportPreview, accent: Color) {
        self.accent = accent
        self._preview = State(initialValue: preview)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewHeader
                Divider()
                previewBody
            }
            .safeAreaInset(edge: .bottom) {
                shareBar
            }
            .navigationTitle(preview.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: preview.shareItems)
                .presentationBackground(Color.clear)
        }
    }

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(preview.subtitle)
                .font(.headline.weight(.semibold))
            Text(preview.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var previewBody: some View {
        switch preview.content {
        case let .text(text, isMonospaced):
            ScrollView {
                Text(text.isEmpty ? "Keine exportierbaren Inhalte." : text)
                    .font(.system(.footnote, design: isMonospaced ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(.secondarySystemBackground))
        case let .pdf(url):
            PDFPreviewView(url: url)
                .background(Color(.secondarySystemBackground))
        }
    }

    private var shareBar: some View {
        VStack(spacing: 10) {
            Button {
                showShare = true
            } label: {
                Label("Teilen", systemImage: "square.and.arrow.up")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(preview.shareItems.isEmpty ? Color.secondary : accent)
                    .payScopeGlassControl(
                        accent: preview.shareItems.isEmpty ? Color.secondary : accent,
                        cornerRadius: 15,
                        tintOpacity: preview.shareItems.isEmpty ? 0.035 : 0.115,
                        isInteractive: !preview.shareItems.isEmpty
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(preview.shareItems.isEmpty)
            .opacity(preview.shareItems.isEmpty ? 0.58 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
    }
}

private struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context _: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context _: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
        uiView.autoScales = true
    }
}

private struct ExportFormatButton: View {
    let title: String
    let systemImage: String
    let accent: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            let controlAccent = isDisabled ? Color.secondary : accent

            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(isDisabled ? Color.secondary : accent.opacity(0.82))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.vertical, 8)
            .payScopeGlassControl(
                accent: controlAccent,
                cornerRadius: 14,
                tintOpacity: isDisabled ? 0.035 : 0.095,
                isInteractive: !isDisabled
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct ExportOptionToggleButton: View {
    let title: String
    let systemImage: String
    let accent: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(isOn ? accent : Color.secondary)
            .payScopeGlassControl(
                accent: accent,
                cornerRadius: 17,
                tintOpacity: isOn ? 0.105 : 0.035
            )
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ExportSettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Binding var settings: Settings

    @State private var exportMonthNumber = Calendar.current.component(.month, from: Date())
    @State private var exportYear = Calendar.current.component(.year, from: Date())
    @State private var availableExportMonths: [ExportMonthOption] = []
    @State private var exportPreview: MonthExportPreview?
    @State private var showFileImporter = false
    @State private var showImportSheet = false
    @State private var importedRows: [ShiftCSVImportRowDraft] = []
    @State private var skippedImportRows = 0
    @State private var importInfoMessage: String?
    @State private var importErrorMessage: String?
    @State private var isSavingImportRows = false
    @State private var isPreparingExport = false
    @State private var isLoadingExportMonths = false
    @State private var exportErrorMessage: String?
    @AppStorage("payscope.export.options.includeShiftTimes") private var includeShiftTimesInExport = true
    @AppStorage("payscope.export.options.includeBreaks") private var includeBreaksInExport = true
    @AppStorage("payscope.export.options.includePay") private var includePayInExport = true
    @AppStorage("payscope.export.options.includeNotesAndWarnings") private var includeNotesAndWarningsInExport = true

    private let csvExporter = CSVExporter()
    private let textExporter = ShiftTextExporter()
    private let pdfExporter = ShiftPDFExporter()
    private static let germanMonthSymbols: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        return calendar.monthSymbols
    }()
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var body: some View {
        Form {
            Section(header: Text("Export")) {
                exportWheelPickers
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                exportOptionButtons
                    .listRowInsets(EdgeInsets(top: 12, leading: 15, bottom: 15, trailing: 12))
            }
            
            
            
            Section( footer: Text("Exportiere deine Monatsdaten in verschiedenen Formaten.")) {
                HStack(spacing: 12) {
                    ExportFormatButton(title: "CSV", systemImage: "tablecells", accent: settings.themeAccent.color, isDisabled: isExportActionDisabled) {
                        Task { await previewCSVExport() }
                    }
                    ExportFormatButton(title: "Text", systemImage: "doc.text", accent: settings.themeAccent.color, isDisabled: isExportActionDisabled) {
                        Task { await previewTextExport() }
                    }
                    ExportFormatButton(title: "PDF", systemImage: "doc.richtext", accent: settings.themeAccent.color, isDisabled: isExportActionDisabled) {
                        Task { await previewPDFExport() }
                    }
                }
                .padding(.top, 6)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 10, trailing: 12))
                
                
            }
            
            Section(header: Text("CSV-Import"), footer: Text("Importiere und bearbeite Schichten aus CSV-Dateien.")) {
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
        .navigationTitle("Export & Import")
        .sheet(item: $exportPreview) { preview in
            MonthExportPreviewSheet(preview: preview, accent: settings.themeAccent.color)
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
        .onAppear {
            refreshAvailableExportMonthsFromLocalStores()
            Task { await refreshAvailableExportMonths() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dayEntriesDidChange)) { _ in
            refreshAvailableExportMonthsFromLocalStores()
            Task { await refreshAvailableExportMonths() }
        }
    }

    private var isExportActionDisabled: Bool {
        isPreparingExport || availableExportMonths.isEmpty
    }

    private var exportOptionButtons: some View {
        HStack(alignment: .center, spacing: 8) {
            ExportOptionToggleButton(
                title: "Zeiten",
                systemImage: "clock",
                accent: settings.themeAccent.color,
                isOn: $includeShiftTimesInExport
            )
            ExportOptionToggleButton(
                title: "Pause",
                systemImage: "pause.circle",
                accent: settings.themeAccent.color,
                isOn: $includeBreaksInExport
            )
            ExportOptionToggleButton(
                title: "Lohn",
                systemImage: "eurosign.circle",
                accent: settings.themeAccent.color,
                isOn: $includePayInExport
            )
        }
    }

    private var exportOptions: MonthExportOptions {
        MonthExportOptions(
            includeShiftTimes: includeShiftTimesInExport,
            includeBreaks: includeBreaksInExport,
            includePay: includePayInExport,
            includeTips: false,
            includeNotesAndWarnings: includeNotesAndWarningsInExport
        )
    }

    private var exportWheelPickers: some View {
        Group {
            if availableExportMonths.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: isLoadingExportMonths ? "arrow.triangle.2.circlepath" : "calendar.badge.exclamationmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(isLoadingExportMonths ? "Export-Monate werden geladen..." : "Noch keine Einträge zum Exportieren.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 4) {
                        Text("Monat")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Monat", selection: $exportMonthNumber) {
                            ForEach(selectableMonthsForExportYear, id: \.self) { month in
                                Text(Self.germanMonthSymbols[month - 1]).tag(month)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }

                    Divider()
                        .frame(height: 150)

                    VStack(spacing: 4) {
                        Text("Jahr")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Jahr", selection: $exportYear) {
                            ForEach(selectableYears, id: \.self) { year in
                                Text("\(year)").tag(year)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }
                }
                .frame(height: 178)
                .onChange(of: exportYear) { _, _ in
                    keepSelectedMonthAvailable()
                }
            }
        }
    }

    private var selectableYears: [Int] {
        Array(Set(availableExportMonths.map(\.year))).sorted()
    }

    private var selectableMonthsForExportYear: [Int] {
        availableExportMonths
            .filter { $0.year == exportYear }
            .map(\.month)
            .sorted()
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
    private func refreshAvailableExportMonths() async {
        guard !isLoadingExportMonths else { return }
        isLoadingExportMonths = true
        defer { isLoadingExportMonths = false }

        let interval = exportAvailabilityLookupInterval()
        let deletedDaysByKey = Dictionary(
            LocalDayEntryStore.shared.loadDeletionTombstones().map { (dayKey($0.date), $0.lastModified) },
            uniquingKeysWith: { current, incoming in incoming > current ? incoming : current }
        )
        let remoteEntries = ((try? await cloudKitService.fetchDayEntries(in: interval)) ?? []).filter { entry in
            guard let deletedAt = deletedDaysByKey[dayKey(entry.date)] else { return true }
            return deletedAt < entry.updatedAt
        }

        if !remoteEntries.isEmpty {
            LocalDayEntryStore.shared.upsertMany(remoteEntries.filter(\.isRealTrackedDay), notify: false)
        }

        updateAvailableExportMonths(
            entries: LocalDayEntryStore.shared.loadAll() + remoteEntries
        )
    }

    private func refreshAvailableExportMonthsFromLocalStores() {
        updateAvailableExportMonths(
            entries: LocalDayEntryStore.shared.loadAll()
        )
    }

    private func updateAvailableExportMonths(entries: [DayEntry]) {
        let entryDates = entries
            .filter(\.isRealTrackedDay)
            .map(\.date)
        let options = exportMonthOptions(from: entryDates)

        availableExportMonths = options
        guard let selected = selectedExportMonth(in: options) ?? options.last else { return }
        exportYear = selected.year
        exportMonthNumber = selected.month
    }

    private func selectedExportMonth(in options: [ExportMonthOption]) -> ExportMonthOption? {
        options.first { $0.year == exportYear && $0.month == exportMonthNumber }
    }

    private func keepSelectedMonthAvailable() {
        guard !selectableMonthsForExportYear.contains(exportMonthNumber),
              let month = selectableMonthsForExportYear.first
        else { return }

        exportMonthNumber = month
    }

    private func exportMonthOptions(from dates: [Date]) -> [ExportMonthOption] {
        let calendar = Calendar.current
        let options = dates.compactMap { date -> ExportMonthOption? in
            let components = calendar.dateComponents([.year, .month], from: date.startOfDayLocal())
            guard let year = components.year, let month = components.month else { return nil }
            return ExportMonthOption(year: year, month: month)
        }
        return Array(Set(options)).sorted {
            if $0.year != $1.year {
                return $0.year < $1.year
            }
            return $0.month < $1.month
        }
    }

    private func exportAvailabilityLookupInterval() -> DateInterval {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let localDates = LocalDayEntryStore.shared.loadAll().filter(\.isRealTrackedDay).map(\.date)
        let localYears = localDates.compactMap { calendar.dateComponents([.year], from: $0).year }
        let startYear = min(localYears.min() ?? currentYear - 5, currentYear - 5)
        let endYear = max(localYears.max() ?? currentYear + 5, currentYear + 5)
        let start = calendar.date(from: DateComponents(year: startYear, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: endYear + 1, month: 1, day: 1))?.addingTimeInterval(-1) ?? Date()
        return DateInterval(start: start, end: end)
    }

    @MainActor
    private func previewCSVExport() async {
        await prepareExportPreview {
            try await makeExportPreview(options: exportOptions, format: .csv)
        }
    }

    @MainActor
    private func previewTextExport() async {
        await prepareExportPreview {
            try await makeExportPreview(options: exportOptions, format: .text)
        }
    }

    @MainActor
    private func previewPDFExport() async {
        await prepareExportPreview {
            try await makeExportPreview(options: exportOptions, format: .pdf)
        }
    }

    private func makeExportPreview(options: MonthExportOptions, format: MonthExportFormat) async throws -> MonthExportPreview {
        switch format {
        case .csv:
            let data = await loadExportData()
            let payload = csvExporter.csvForMonth(
                entries: data.entries,
                tips: data.tips,
                month: selectedExportMonthDate,
                settings: settings,
                options: options
            )
            return MonthExportPreview(
                format: .csv,
                title: "CSV-Vorschau",
                subtitle: Self.monthYearFormatter.string(from: selectedExportMonthDate),
                detail: "Monatsübersicht als CSV",
                content: .text(payload, isMonospaced: true),
                shareItems: payload.isEmpty ? [] : [payload]
            )
        case .text:
            let data = await loadExportData()
            let payload = textExporter.textForMonth(
                entries: data.entries,
                tips: data.tips,
                month: selectedExportMonthDate,
                settings: settings,
                options: options
            )
            return MonthExportPreview(
                format: .text,
                title: "Text-Vorschau",
                subtitle: Self.monthYearFormatter.string(from: selectedExportMonthDate),
                detail: "Monatsübersicht als Text",
                content: .text(payload, isMonospaced: false),
                shareItems: [payload]
            )
        case .pdf:
            let data = await loadExportData()
            let url = try pdfExporter.pdfURLForMonth(
                entries: data.entries,
                tips: data.tips,
                month: selectedExportMonthDate,
                settings: settings,
                options: options
            )
            return MonthExportPreview(
                format: .pdf,
                title: "PDF-Vorschau",
                subtitle: Self.monthYearFormatter.string(from: selectedExportMonthDate),
                detail: {
                    let pageCount = PDFDocument(url: url)?.pageCount ?? 0
                    return pageCount > 0 ? "\(pageCount) Seiten" : "PDF"
                }(),
                content: .pdf(url),
                shareItems: [url]
            )
        }
    }

    @MainActor
    private func prepareExportPreview(_ builder: @escaping () async throws -> MonthExportPreview) async {
        isPreparingExport = true
        exportErrorMessage = nil
        defer { isPreparingExport = false }

        do {
            exportPreview = try await builder()
        } catch {
            exportErrorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func loadExportData() async -> (entries: [DayEntry], tips: [TipEntry]) {
        let lookupInterval = selectedExportLookupInterval
        let localEntries = LocalDayEntryStore.shared.loadAll(in: lookupInterval)
        let deletedDaysByKey = Dictionary(
            LocalDayEntryStore.shared.loadDeletionTombstones().map { (dayKey($0.date), $0.lastModified) },
            uniquingKeysWith: { current, incoming in incoming > current ? incoming : current }
        )
        let remoteEntries = ((try? await cloudKitService.fetchDayEntries(in: lookupInterval)) ?? []).filter { entry in
            guard let deletedAt = deletedDaysByKey[dayKey(entry.date)] else { return true }
            return deletedAt < entry.updatedAt
        }
        let realRemoteEntries = remoteEntries.filter(\.isRealTrackedDay)

        if !realRemoteEntries.isEmpty {
            LocalDayEntryStore.shared.upsertMany(realRemoteEntries, notify: false)
        }

        return (
            entries: mergeEntriesByLocalDayKeepingNewest(local: localEntries, remote: realRemoteEntries),
            tips: []
        )
    }

    private func mergeEntriesByLocalDayKeepingNewest(local: [DayEntry], remote: [DayEntry]) -> [DayEntry] {
        let byDay = Dictionary(
            (local + remote).map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                preferredEntryForSameDay(existing: existing, candidate: candidate)
            }
        )
        return byDay.values
            .filter(\.isRealTrackedDay)
            .sorted { $0.date < $1.date }
    }

    private func preferredEntryForSameDay(existing: DayEntry, candidate: DayEntry) -> DayEntry {
        if existing.isRealTrackedDay != candidate.isRealTrackedDay {
            return candidate.isRealTrackedDay ? candidate : existing
        }
        return candidate.updatedAt > existing.updatedAt ? candidate : existing
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
    var payload: ShiftShortcutRangePayload? = nil

    var displayRange: String {
        let range = ShiftTimeRange(startMinute: startMinute, endMinuteOffset: endMinute)
        return range?.displayRange() ?? "\(formatMinute(startMinute)) - \(formatMinute(endMinute))"
    }

    var rawValue: String {
        guard var payload else {
            return "\(startMinute)-\(endMinute)"
        }

        payload.startMinute = startMinute
        payload.endMinute = endMinute

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return "\(startMinute)-\(endMinute)"
        }
        return string
    }
}

private struct ShiftShortcutEditDraft: Identifiable {
    var index: Int
    var title: String
    var name: String
    var startMinute: Int
    var endMinute: Int
    var payload: ShiftShortcutRangePayload?
    var defaultRange: ShiftShortcutRange

    var id: Int { index }
}

private struct ShiftShortcutRangePayload: Codable {
    var startMinute: Int
    var endMinute: Int
    var dayTypeRaw: String?
    var segments: [ShiftShortcutRangeSegment]
    var breakMinutes: Int
    var manualWorkedSeconds: Int?
    var creditedOverrideSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case startMinute
        case endMinute
        case dayTypeRaw
        case segments
        case breakMinutes
        case manualWorkedSeconds
        case creditedOverrideSeconds
    }

    init(
        startMinute: Int,
        endMinute: Int,
        dayTypeRaw: String? = nil,
        segments: [ShiftShortcutRangeSegment] = [],
        breakMinutes: Int = 0,
        manualWorkedSeconds: Int? = nil,
        creditedOverrideSeconds: Int? = nil
    ) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.dayTypeRaw = dayTypeRaw
        self.segments = segments
        self.breakMinutes = breakMinutes
        self.manualWorkedSeconds = manualWorkedSeconds
        self.creditedOverrideSeconds = creditedOverrideSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        endMinute = try container.decode(Int.self, forKey: .endMinute)
        dayTypeRaw = try container.decodeIfPresent(String.self, forKey: .dayTypeRaw)
        segments = try container.decodeIfPresent([ShiftShortcutRangeSegment].self, forKey: .segments) ?? []
        breakMinutes = try container.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 0
        manualWorkedSeconds = try container.decodeIfPresent(Int.self, forKey: .manualWorkedSeconds)
        creditedOverrideSeconds = try container.decodeIfPresent(Int.self, forKey: .creditedOverrideSeconds)
    }
}

private struct ShiftShortcutRangeSegment: Codable, Equatable {
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
                endMinute: payload.endMinute,
                payload: payload
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
    return ShiftShortcutRange(startMinute: clampedStart, endMinute: clampedEnd, payload: range.payload)
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


#Preview("Settings") {
    let settings = Settings(
        hasCompletedOnboarding: true,
        payMode: .hourly,
        hourlyRateCents: 1450,
        weeklyTargetSeconds: 20 * 3600,
        holidayFixedSeconds: 8 * 3600,
        scheduledWorkdaysCount: 5,
        themeAccent: .teal,
        showCalendarWeekNumbers: true,
        showLiveActivity: true,
        shiftShortcut1: "540-1020",
        shiftShortcut2: "720-1080",
        shiftShortcut3: "1080-1440",
        shiftShortcutName1: "Früh",
        shiftShortcutName2: "Mitte",
        shiftShortcutName3: "Spät"
    )

    SettingsTabView(settings: settings)
        .environmentObject(CloudKitService.shared)
        .modelContainer(
            for: [
                Settings.self,
                DayEntry.self,
                HolidayCalendarDay.self,
                NetWageMonthConfig.self,
                TimeSegment.self
            ],
            inMemory: true
        )
}
