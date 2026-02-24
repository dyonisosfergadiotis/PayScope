import SwiftUI
import SwiftData

struct SettingsTabView: View {
    @Bindable var settings: Settings
    @AppStorage("dayEditorShiftShortcut1") private var shiftShortcut1 = ""
    @AppStorage("dayEditorShiftShortcut2") private var shiftShortcut2 = ""
    @AppStorage("dayEditorShiftShortcut3") private var shiftShortcut3 = ""
    @AppStorage("dayEditorShiftShortcutName1") private var shiftShortcutName1 = ""
    @AppStorage("dayEditorShiftShortcutName2") private var shiftShortcutName2 = ""
    @AppStorage("dayEditorShiftShortcutName3") private var shiftShortcutName3 = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Arbeitszeit") {
                    NavigationLink {
                        PaySettingsView(settings: settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Bezahlung",
                            subtitle: paySummary,
                            systemImage: "eurosign.circle"
                        )
                    }

                    NavigationLink {
                        WorkweekSettingsView(settings: settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Arbeitswoche",
                            subtitle: workweekSummary,
                            systemImage: "calendar.badge.clock"
                        )
                    }

                    NavigationLink {
                        RulesSettingsView(settings: settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Regeln",
                            subtitle: rulesSummary,
                            systemImage: "checklist"
                        )
                    }

                    NavigationLink {
                        ShiftShortcutsSettingsView()
                    } label: {
                        SettingsMenuRow(
                            title: "Schicht-Shortcuts",
                            subtitle: shiftShortcutSummary,
                            systemImage: "clock.badge.checkmark"
                        )
                    }
                }

                Section("Darstellung") {
                    NavigationLink {
                        AppearanceSettingsView(settings: settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Design",
                            subtitle: settings.themeAccent.label,
                            systemImage: "paintpalette"
                        )
                    }

                    NavigationLink {
                        CalendarTimelineSettingsView(settings: settings)
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
                        HolidayImportSettingsView(settings: settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Feiertage (API)",
                            subtitle: holidaySummary,
                            systemImage: "flag"
                        )
                    }

                    NavigationLink {
                        ExportSettingsView(settings: settings)
                    } label: {
                        SettingsMenuRow(
                            title: "Export",
                            subtitle: "CSV nach Monat",
                            systemImage: "square.and.arrow.up"
                        )
                    }

                    NavigationLink {
                        ICloudSyncSettingsView(settings: settings)
                    } label: {
                        SettingsMenuRow(
                            title: "iCloud-Sync",
                            subtitle: "Nur hochladen oder runterladen",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }

                Section("Info") {
                    NavigationLink {
                        AppInfoSettingsView()
                    } label: {
                        SettingsMenuRow(
                            title: "Über App & Dev",
                            subtitle: appInfoSummary,
                            systemImage: "info.circle"
                        )
                    }
                }

            }
            .navigationTitle("Einstellungen")
        }
    }

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

    private var workweekSummary: String {
        let hoursText: String
        if let weeklyTargetSeconds = settings.weeklyTargetSeconds {
            hoursText = PayScopeFormatters.hoursString(seconds: weeklyTargetSeconds)
        } else {
            hoursText = "kein Sollwert"
        }
        return "\(settings.weekStart.label) · \(hoursText)"
    }

    private var rulesSummary: String {
        let vacationMode: String
        switch settings.effectiveVacationCreditingMode {
        case .lookback13Weeks:
            vacationMode = "Urlaub: 13-Wochen"
        case .fixedValue:
            let fixed = PayScopeFormatters.hhmmString(seconds: settings.effectiveVacationFixedSeconds)
            vacationMode = "Urlaub: fix \(fixed)"
        }
        let strict = settings.strictHistoryRequired ? "strikt" : "flexibel"
        let missing = settings.countMissingAsZero ? "Lücken=0" : "Lücken offen"
        return "\(vacationMode) · \(strict) · \(missing)"
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
        let paidBadge = settings.effectiveMarkPaidHolidays ? " · bezahlt markiert" : ""
        return "\(country) · \(subdivision)\(paidBadge)"
    }

    private var appInfoSummary: String {
        let info = AppInfoSnapshot.current
        return "\(info.developerName) · \(info.versionBuild)"
    }

    private var shiftShortcutSummary: String {
        let first = summaryLabelForShiftShortcut(raw: shiftShortcut1, index: 0, name: shiftShortcutName1)
        let second = summaryLabelForShiftShortcut(raw: shiftShortcut2, index: 1, name: shiftShortcutName2)
        let third = summaryLabelForShiftShortcut(raw: shiftShortcut3, index: 2, name: shiftShortcutName3)
        return "\(first) · \(second) · \(third)"
    }
}

private struct PaySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: Settings
    @State private var moneyInput = ""

    var body: some View {
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
                    guard let value = parseMoneyToCents(moneyInput) else { return }
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
        .navigationTitle("Bezahlung")
        .onAppear {
            syncMoneyInput()
        }
        .onChange(of: settings.payMode) { _, _ in
            syncMoneyInput()
            modelContext.persistIfPossible()
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

private struct WorkweekSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: Settings
    @State private var weeklyHoursInput = ""

    var body: some View {
        Form {
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
                    Stepper(
                        "Arbeitstage pro Woche: \(settings.scheduledWorkdaysCount)",
                        value: $settings.scheduledWorkdaysCount,
                        in: 1...7
                    )
                }
            }
        }
        .navigationTitle("Arbeitswoche")
        .onAppear {
            weeklyHoursInput = settings.weeklyTargetSeconds.map { String(format: "%.1f", Double($0) / 3600) } ?? ""
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
    }
}

private struct RulesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: Settings
    @State private var fixedVacationHoursInput = ""

    var body: some View {
        Form {
            Section("Urlaub") {
                Picker("Urlaubsmodus", selection: vacationCreditingModeBinding) {
                    ForEach(VacationCreditingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if vacationCreditingModeBinding.wrappedValue == .fixedValue {
                    HStack(spacing: 8) {
                        TextField("Fester Wert in Stunden (z. B. 8,0)", text: $fixedVacationHoursInput)
                            .keyboardType(.decimalPad)

                        Button("Festen Wert übernehmen") {
                            guard let seconds = parseHoursToSeconds(fixedVacationHoursInput) else { return }
                            settings.vacationFixedSeconds = seconds
                            modelContext.persistIfPossible()
                        }
                        .disabled(parseHoursToSeconds(fixedVacationHoursInput) == nil)
                    }

                    if !fixedVacationHoursInput.isEmpty && parseHoursToSeconds(fixedVacationHoursInput) == nil {
                        Text("Bitte einen gültigen Stundenwert eingeben.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Text("Aktuell: \(PayScopeFormatters.hhmmString(seconds: settings.effectiveVacationFixedSeconds))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("13-Wochen-Regel") {
                Toggle("Strenge Historie erforderlich", isOn: $settings.strictHistoryRequired)
                Toggle("Fehlende Tage als 0 zählen", isOn: $settings.countMissingAsZero)
            }
        }
        .navigationTitle("Regeln")
        .onAppear {
            syncVacationHoursInput()
        }
        .onChange(of: settings.strictHistoryRequired) { _, _ in
            modelContext.persistIfPossible()
        }
        .onChange(of: settings.countMissingAsZero) { _, _ in
            modelContext.persistIfPossible()
        }
        .onChange(of: settings.vacationFixedSeconds) { _, newValue in
            fixedVacationHoursInput = newValue.map {
                String(format: "%.1f", Double($0) / 3600.0)
            } ?? String(format: "%.1f", Double(settings.effectiveVacationFixedSeconds) / 3600.0)
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
                modelContext.persistIfPossible()
            }
        )
    }

    private var suggestedFixedVacationSeconds: Int {
        if let weeklyTargetSeconds = settings.weeklyTargetSeconds {
            return max(0, weeklyTargetSeconds / max(1, min(7, settings.scheduledWorkdaysCount)))
        }
        return 8 * 3600
    }

    private func syncVacationHoursInput() {
        let seconds = settings.vacationFixedSeconds ?? settings.effectiveVacationFixedSeconds
        fixedVacationHoursInput = String(format: "%.1f", Double(seconds) / 3600.0)
    }
}

private struct AppearanceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section("Design") {
                Picker("Akzentfarbe", selection: $settings.themeAccent) {
                    ForEach(ThemeAccent.allCases) { accent in
                        Text(accent.label).tag(accent)
                    }
                }
            }
        }
        .navigationTitle("Design")
        .onChange(of: settings.themeAccent) { _, _ in
            modelContext.persistIfPossible()
        }
    }
}

private struct CalendarTimelineSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section("Kalender") {
                Picker("Zellanzeige", selection: calendarDisplayModeBinding) {
                    ForEach(CalendarCellDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if calendarDisplayModeBinding.wrappedValue == .hours {
                    Picker("Stundenanzeige", selection: calendarHoursBreakModeBinding) {
                        ForEach(CalendarHoursBreakMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("Kalenderwochen anzeigen", isOn: showCalendarWeekNumbersBinding)
                Toggle("Wochenstunden anzeigen", isOn: showCalendarWeekHoursBinding)
                Toggle("Wochengeld anzeigen", isOn: showCalendarWeekPayBinding)
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
        }
        .navigationTitle("Kalender & Timeline")
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

    private var calendarHoursBreakModeBinding: Binding<CalendarHoursBreakMode> {
        Binding(
            get: { settings.effectiveCalendarHoursBreakMode },
            set: {
                settings.calendarHoursBreakMode = $0
                modelContext.persistIfPossible()
            }
        )
    }

    private var showCalendarWeekNumbersBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowCalendarWeekNumbers },
            set: {
                settings.showCalendarWeekNumbers = $0
                modelContext.persistIfPossible()
            }
        )
    }

    private var showCalendarWeekHoursBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowCalendarWeekHours },
            set: {
                settings.showCalendarWeekHours = $0
                modelContext.persistIfPossible()
            }
        )
    }

    private var showCalendarWeekPayBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveShowCalendarWeekPay },
            set: {
                settings.showCalendarWeekPay = $0
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
    @AppStorage("dayEditorShiftShortcut1") private var shiftShortcut1 = ""
    @AppStorage("dayEditorShiftShortcut2") private var shiftShortcut2 = ""
    @AppStorage("dayEditorShiftShortcut3") private var shiftShortcut3 = ""
    @AppStorage("dayEditorShiftShortcutName1") private var shiftShortcutName1 = ""
    @AppStorage("dayEditorShiftShortcutName2") private var shiftShortcutName2 = ""
    @AppStorage("dayEditorShiftShortcutName3") private var shiftShortcutName3 = ""

    var body: some View {
        Form {
            Section("Schicht-Shortcuts") {
                shortcutRow(
                    title: "Shortcut 1",
                    name: shortcutNameBinding(for: 0),
                    range: effectiveShortcutRange(for: 0),
                    onAdjustStart: { adjustShortcut(index: 0, isStart: true, deltaMinutes: -15) },
                    onAdjustStartIncrease: { adjustShortcut(index: 0, isStart: true, deltaMinutes: 15) },
                    onAdjustEnd: { adjustShortcut(index: 0, isStart: false, deltaMinutes: -15) },
                    onAdjustEndIncrease: { adjustShortcut(index: 0, isStart: false, deltaMinutes: 15) },
                    onReset: { resetShortcut(index: 0) }
                )

                shortcutRow(
                    title: "Shortcut 2",
                    name: shortcutNameBinding(for: 1),
                    range: effectiveShortcutRange(for: 1),
                    onAdjustStart: { adjustShortcut(index: 1, isStart: true, deltaMinutes: -15) },
                    onAdjustStartIncrease: { adjustShortcut(index: 1, isStart: true, deltaMinutes: 15) },
                    onAdjustEnd: { adjustShortcut(index: 1, isStart: false, deltaMinutes: -15) },
                    onAdjustEndIncrease: { adjustShortcut(index: 1, isStart: false, deltaMinutes: 15) },
                    onReset: { resetShortcut(index: 1) }
                )

                shortcutRow(
                    title: "Shortcut 3",
                    name: shortcutNameBinding(for: 2),
                    range: effectiveShortcutRange(for: 2),
                    onAdjustStart: { adjustShortcut(index: 2, isStart: true, deltaMinutes: -15) },
                    onAdjustStartIncrease: { adjustShortcut(index: 2, isStart: true, deltaMinutes: 15) },
                    onAdjustEnd: { adjustShortcut(index: 2, isStart: false, deltaMinutes: -15) },
                    onAdjustEndIncrease: { adjustShortcut(index: 2, isStart: false, deltaMinutes: 15) },
                    onReset: { resetShortcut(index: 2) }
                )
            }

            Section {
                Text("Alle Änderungen werden automatisch per iCloud synchronisiert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Schicht-Shortcuts")
    }

    @ViewBuilder
    private func shortcutRow(
        title: String,
        name: Binding<String>,
        range: ShiftShortcutRange,
        onAdjustStart: @escaping () -> Void,
        onAdjustStartIncrease: @escaping () -> Void,
        onAdjustEnd: @escaping () -> Void,
        onAdjustEndIncrease: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text("\(formatMinute(range.startMinute))-\(formatMinute(range.endMinute))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("Name (optional)", text: name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            shortcutMinuteControl(
                title: "Start",
                value: range.startMinute,
                onDecrease: onAdjustStart,
                onIncrease: onAdjustStartIncrease
            )

            shortcutMinuteControl(
                title: "Ende",
                value: range.endMinute,
                onDecrease: onAdjustEnd,
                onIncrease: onAdjustEndIncrease
            )

            Button("Standard wiederherstellen") {
                onReset()
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

    private func effectiveShortcutRange(for index: Int) -> ShiftShortcutRange {
        let raw: String
        switch index {
        case 0: raw = shiftShortcut1
        case 1: raw = shiftShortcut2
        default: raw = shiftShortcut3
        }

        return parseShiftShortcutRange(raw: raw) ?? defaultShiftShortcutRange(index: index)
    }

    private func adjustShortcut(index: Int, isStart: Bool, deltaMinutes: Int) {
        var range = effectiveShortcutRange(for: index)

        if isStart {
            range.startMinute = max(0, min(24 * 60 - 15, range.startMinute + deltaMinutes))
            range.endMinute = max(range.startMinute + 15, range.endMinute)
        } else {
            range.endMinute = max(range.startMinute + 15, min(24 * 60, range.endMinute + deltaMinutes))
        }

        setShortcutRange(range, index: index)
    }

    private func resetShortcut(index: Int) {
        setShortcutRange(defaultShiftShortcutRange(index: index), index: index)
    }

    private func shortcutNameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                switch index {
                case 0: return shiftShortcutName1
                case 1: return shiftShortcutName2
                default: return shiftShortcutName3
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                switch index {
                case 0:
                    shiftShortcutName1 = trimmed
                case 1:
                    shiftShortcutName2 = trimmed
                default:
                    shiftShortcutName3 = trimmed
                }
            }
        )
    }

    private func setShortcutRange(_ range: ShiftShortcutRange, index: Int) {
        let rawValue = "\(range.startMinute)-\(range.endMinute)"
        switch index {
        case 0:
            shiftShortcut1 = rawValue
        case 1:
            shiftShortcut2 = rawValue
        default:
            shiftShortcut3 = rawValue
        }
    }
}

private struct HolidayImportSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: Settings

    @State private var holidayImportInfo = ""
    @State private var isImportingHolidays = false

    private let holidayImporter = HolidayImportService()

    var body: some View {
        Form {
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

            Section("Markierung") {
                Toggle("Bezahlte Feiertage markieren", isOn: markPaidHolidaysBinding)

                if settings.effectiveMarkPaidHolidays {
                    HStack(spacing: 10) {
                        ForEach(orderedWeekdays, id: \.weekday) { item in
                            let isSelected = settings.isPaidHolidayWeekday(weekday: item.weekday)
                            Button {
                                settings.paidHolidayWeekdayMask = settings.updatingPaidHolidayWeekdayMask(
                                    weekday: item.weekday,
                                    isSelected: !isSelected
                                )
                                modelContext.persistIfPossible()
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
                            .accessibilityLabel("\(item.label) als bezahlten Feiertagstag")
                            .accessibilityValue(isSelected ? "ausgewählt" : "nicht ausgewählt")
                        }
                    }

                    Text("Nur API-Feiertage auf ausgewählten Tagen erhalten die bezahlte Markierung.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Feiertage")
    }

    private var holidayCountryBinding: Binding<String> {
        Binding(
            get: {
                normalizeHolidayCode(settings.holidayCountryCode ?? "").nilIfEmpty ?? "DE"
            },
            set: { newValue in
                settings.holidayCountryCode = normalizeHolidayCode(newValue).nilIfEmpty ?? "DE"
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

    private var markPaidHolidaysBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveMarkPaidHolidays },
            set: { isEnabled in
                settings.markPaidHolidays = isEnabled
                modelContext.persistIfPossible()
            }
        )
    }

    private var orderedWeekdays: [(weekday: Int, label: String)] {
        let orderedWeekdays = settings.weekStart == .sunday
            ? [1, 2, 3, 4, 5, 6, 7]
            : [2, 3, 4, 5, 6, 7, 1]

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
        modelContext.persistIfPossible()

        do {
            let count = try await holidayImporter.importHolidays(
                year: year,
                countryCode: normalizedCountry,
                subdivisionCode: normalizedSubdivision,
                modelContext: modelContext
            )
            holidayImportInfo = "\(count) Feiertage für \(year) importiert."
        } catch {
            holidayImportInfo = error.localizedDescription
        }
    }
}

private struct ExportSettingsView: View {
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]
    @Bindable var settings: Settings

    @State private var exportMonthNumber = Calendar.current.component(.month, from: Date())
    @State private var exportYear = Calendar.current.component(.year, from: Date())
    @State private var csvPayload = ""
    @State private var showShare = false

    private let exporter = CSVExporter()

    var body: some View {
        Form {
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
                    csvPayload = exporter.csvForMonth(
                        entries: entries,
                        month: selectedExportMonthDate,
                        settings: settings
                    )
                    showShare = !csvPayload.isEmpty
                }
            }
        }
        .navigationTitle("Export")
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [csvPayload])
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
}

private struct ICloudSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayEntry.date) private var entries: [DayEntry]
    @Query(sort: \NetWageMonthConfig.monthStart) private var netWageConfigs: [NetWageMonthConfig]
    @Query(sort: \HolidayCalendarDay.date) private var holidayDays: [HolidayCalendarDay]
    @Bindable var settings: Settings

    @State private var syncInfo = ""

    var body: some View {
        Form {
            Section("Force Sync") {
                Button("Nur hochladen (lokal -> iCloud)") {
                    ICloudSettingsSync.export(
                        settings: settings,
                        entries: entries,
                        netWageConfigs: netWageConfigs,
                        holidayDays: holidayDays
                    )
                    syncInfo = "Lokale Nutzerdaten wurden nach iCloud hochgeladen."
                }

                Button("Nur runterladen (iCloud -> lokal)") {
                    if ICloudSettingsSync.forceSyncDownIntoStore(
                        settings: settings,
                        localEntries: entries,
                        localNetWageConfigs: netWageConfigs,
                        localHolidayDays: holidayDays,
                        modelContext: modelContext
                    ) {
                        modelContext.persistIfPossible()
                        syncInfo = "Nutzerdaten aus iCloud wurden lokal übernommen."
                    } else {
                        syncInfo = "Keine iCloud-Daten gefunden."
                    }
                }
            }

            if !syncInfo.isEmpty {
                Section {
                    Text(syncInfo)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("iCloud-Sync")
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
