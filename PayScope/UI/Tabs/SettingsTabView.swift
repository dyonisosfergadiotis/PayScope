import SwiftUI
import SwiftData

struct SettingsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: Settings
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]

    @State private var weeklyHoursInput = ""
    @State private var moneyInput = ""
    @State private var exportMonthNumber = Calendar.current.component(.month, from: Date())
    @State private var exportYear = Calendar.current.component(.year, from: Date())
    @State private var csvPayload = ""
    @State private var showShare = false
    @State private var holidayImportInfo = ""
    @State private var isImportingHolidays = false

    private let exporter = CSVExporter()
    private let holidayImporter = HolidayImportService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Bezahlung") {
                    Picker("Modus", selection: $settings.payMode) {
                        ForEach(PayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    TextField(settings.payMode == .hourly ? "Stundenlohn" : "Monatsgehalt", text: $moneyInput)
                        .keyboardType(.decimalPad)

                    if !moneyInput.isEmpty && parseMoneyToCents(moneyInput) == nil {
                        Text("Bitte einen gültigen Betrag eingeben.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Betrag übernehmen") {
                        if let value = parseMoneyToCents(moneyInput) {
                            if settings.payMode == .hourly {
                                settings.hourlyRateCents = value
                                settings.monthlySalaryCents = nil
                            } else {
                                settings.monthlySalaryCents = value
                                settings.hourlyRateCents = nil
                            }
                            modelContext.persistIfPossible()
                        }
                    }
                }

                Section("Arbeitswoche") {
                    Picker("Wochenstart", selection: $settings.weekStart) {
                        ForEach(WeekStart.allCases) { start in
                            Text(start.label).tag(start)
                        }
                    }

                    TextField("Wöchentliche Sollstunden", text: $weeklyHoursInput)
                        .keyboardType(.decimalPad)

                    Button("Sollstunden übernehmen") {
                        settings.weeklyTargetSeconds = parseHoursToSeconds(weeklyHoursInput)
                        modelContext.persistIfPossible()
                    }

                    Picker("Feiertagsgutschrift", selection: $settings.holidayCreditingMode) {
                        ForEach(HolidayCreditingMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    if settings.holidayCreditingMode == .weeklyTargetDistributed {
                        Stepper("Arbeitstage pro Woche: \(settings.scheduledWorkdaysCount)", value: $settings.scheduledWorkdaysCount, in: 1...7)
                    }
                }

                Section("13-Wochen-Regel") {
                    Toggle("Strenge Historie erforderlich", isOn: $settings.strictHistoryRequired)
                    Toggle("Fehlende Tage als 0 zählen", isOn: $settings.countMissingAsZero)
                }

                Section("Design") {
                    Picker("Akzentfarbe", selection: $settings.themeAccent) {
                        ForEach(ThemeAccent.allCases) { accent in
                            Text(accent.label).tag(accent)
                        }
                    }
                }

                Section("Kalender") {
                    Picker("Zellanzeige", selection: calendarDisplayModeBinding) {
                        ForEach(CalendarCellDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section("Feiertage (API)") {
                    TextField("Land (ISO, z. B. DE)", text: holidayCountryBinding)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Bundesland (optional, z. B. BY)", text: holidaySubdivisionBinding)
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
                            Text("Feiertage für aktuelles Jahr importieren")
                        }
                    }
                    .disabled(isImportingHolidays)

                    if !holidayImportInfo.isEmpty {
                        Text(holidayImportInfo)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Timeline-Fenster") {
                    minuteWindowControl(
                        title: "Frühester Start",
                        value: timelineMinBinding,
                        step: 15,
                        lower: 0,
                        upper: max(0, timelineMaxBinding.wrappedValue - 60)
                    )
                    minuteWindowControl(
                        title: "Spätestes Ende",
                        value: timelineMaxBinding,
                        step: 15,
                        lower: min(24 * 60, timelineMinBinding.wrappedValue + 60),
                        upper: 24 * 60
                    )
                }

                Section("Export") {
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
                    Button("CSV exportieren") {
                        csvPayload = exporter.csvForMonth(entries: entries, month: selectedExportMonthDate, settings: settings)
                        showShare = !csvPayload.isEmpty
                    }
                }

                Section("Debug") {
                    Button("Onboarding zurücksetzen") {
                        settings.hasCompletedOnboarding = false
                        modelContext.persistIfPossible()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Einstellungen")
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [csvPayload])
            }
            .onAppear {
                if settings.payMode == .hourly {
                    moneyInput = settings.hourlyRateCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
                } else {
                    moneyInput = settings.monthlySalaryCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
                }
                weeklyHoursInput = settings.weeklyTargetSeconds.map { String(format: "%.1f", Double($0) / 3600) } ?? ""
            }
            .onDisappear {
                modelContext.persistIfPossible()
            }
            .onChange(of: settings.payMode) { _, _ in
                modelContext.persistIfPossible()
            }
            .onChange(of: settings.weekStart) { _, _ in
                modelContext.persistIfPossible()
            }
            .onChange(of: settings.holidayCreditingMode) { _, _ in
                modelContext.persistIfPossible()
            }
            .onChange(of: settings.scheduledWorkdaysCount) { _, _ in
                modelContext.persistIfPossible()
            }
            .onChange(of: settings.strictHistoryRequired) { _, _ in
                modelContext.persistIfPossible()
            }
            .onChange(of: settings.countMissingAsZero) { _, _ in
                modelContext.persistIfPossible()
            }
            .onChange(of: settings.themeAccent) { _, _ in
                modelContext.persistIfPossible()
            }
        }
        .wageWiseSheetSurface(accent: settings.themeAccent.color)
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

    private var selectableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 5)...(current + 5))
    }

    private var selectedExportMonthDate: Date {
        let comps = DateComponents(year: exportYear, month: exportMonthNumber, day: 1)
        return Calendar.current.date(from: comps) ?? Date()
    }

    private var calendarDisplayModeBinding: Binding<CalendarCellDisplayMode> {
        Binding(
            get: { settings.calendarCellDisplayMode ?? .dot },
            set: {
                settings.calendarCellDisplayMode = $0
                modelContext.persistIfPossible()
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
                modelContext.persistIfPossible()
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
                modelContext.persistIfPossible()
            }
        )
    }

    private var holidayCountryBinding: Binding<String> {
        Binding(
            get: { settings.holidayCountryCode ?? "DE" },
            set: { newValue in
                settings.holidayCountryCode = normalizeHolidayCode(newValue)
                modelContext.persistIfPossible()
            }
        )
    }

    private var holidaySubdivisionBinding: Binding<String> {
        Binding(
            get: { settings.holidaySubdivisionCode ?? "" },
            set: { newValue in
                settings.holidaySubdivisionCode = normalizeHolidayCode(newValue).nilIfEmpty
                modelContext.persistIfPossible()
            }
        )
    }

    private func importHolidaysForCurrentYear() async {
        isImportingHolidays = true
        defer { isImportingHolidays = false }

        let year = Calendar.current.component(.year, from: Date())
        do {
            let count = try await holidayImporter.importHolidays(
                year: year,
                countryCode: settings.holidayCountryCode,
                subdivisionCode: settings.holidaySubdivisionCode,
                modelContext: modelContext
            )
            holidayImportInfo = "\(count) Feiertage für \(year) importiert."
        } catch {
            holidayImportInfo = "Feiertage konnten nicht importiert werden."
        }
    }

    private func normalizeHolidayCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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

    private func formatMinute(_ minute: Int) -> String {
        let h = minute / 60
        let m = minute % 60
        return String(format: "%02d:%02d", h, m)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
