import FabBar
import SwiftUI
import SwiftData

struct OnboardingContainerView: View {
    @Bindable var settings: Settings
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                OnboardingSplashView(accent: settings.themeAccent.color)
                    .transition(.opacity.combined(with: .scale))
            } else {
                OnboardingFlowView(settings: settings)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showSplash)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            showSplash = false
        }
    }
}

private struct OnboardingSplashView: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.4), accent.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Circle()
                    .fill(
                        LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 120, height: 120)
                    .overlay(Image(systemName: "clock.badge.checkmark.fill").font(.system(size: 48)).foregroundStyle(.white))

                Text("PayScope")
                    .font(.system(.largeTitle, design: .rounded).bold())

                Text("Zeit erfassen. Lohn verstehen.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

private struct OnboardingFlowView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var settings: Settings

    @State private var step: OnboardingStep = .overview
    @State private var furthestUnlockedStepIndex = 0
    @State private var hourlyRate = ""
    @State private var monthlySalary = ""
    @State private var weeklyHours = ""
    @State private var holidayCountryCode = "DE"
    @State private var holidaySubdivisionCode = ""
    @State private var shouldCreateFirstShift = false
    @State private var firstShiftDate = Date()
    @State private var firstShiftStartTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var firstShiftEndTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var firstShiftBreakMinutes = "30"
    @State private var firstShiftTip = ""

    private let localStore = LocalDayEntryStore.shared
    private var pageCount: Int { OnboardingStep.allCases.count }

    var body: some View {
        ZStack {
            stepContent
                .id(step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsFallbackControls {
                fallbackNavigationControls
            }
        }
        .payScopeBackground(accent: settings.themeAccent.color)
        .tint(settings.themeAccent.color)
        .animation(.smooth(duration: 0.24, extraBounce: 0.08), value: step)
        .fabBar(
            selection: stepSelection,
            tabs: onboardingTabs,
            action: FabBarAction(
                systemImage: "arrow.right",
                accessibilityLabel: "Weiter oder Onboarding abschließen",
                action: advanceStep
            )
        )
        .onAppear {
            hourlyRate = settings.hourlyRateCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            monthlySalary = settings.monthlySalaryCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            weeklyHours = settings.weeklyTargetSeconds.map { String(format: "%.1f", Double($0) / 3600) } ?? ""
            holidayCountryCode = settings.holidayCountryCode ?? "DE"
            holidaySubdivisionCode = settings.holidaySubdivisionCode ?? ""
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .overview:
            overviewPage
        case .pay:
            paySetupPage
        case .schedule:
            schedulePage
        case .firstShift:
            firstShiftPage
        case .rules:
            rulesPage
        case .appearance:
            captureAndThemePage
        }
    }

    private var overviewPage: some View {
        OnboardingPageShell(
            title: "Schnelles Setup",
            subtitle: "Wir richten die wichtigsten Einstellungen direkt jetzt ein.",
            step: currentStepIndex + 1,
            total: pageCount,
            icon: "slider.horizontal.3",
            accent: settings.themeAccent.color,
            isCurrentStepValid: isStepValid
        ) {
            VStack(alignment: .leading, spacing: 12) {
                bullet("Bezahlungsmodell und Betrag")
                bullet("Arbeitstage und wöchentliche Sollstunden")
                bullet("Optional direkt eine erste Schicht eintippen")
                bullet("Feiertage, Region und 13-Wochen-Regeln")
                bullet("Kalenderdarstellung und Akzentfarbe")
            }
        }
    }

    private var paySetupPage: some View {
        OnboardingPageShell(
            title: "Bezahlung",
            subtitle: "Diese Angaben sind für die Lohnberechnung erforderlich.",
            step: currentStepIndex + 1,
            total: pageCount,
            icon: "eurosign.circle",
            accent: settings.themeAccent.color,
            isCurrentStepValid: isStepValid
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Lohnmodus", selection: Binding(get: { settings.payMode }, set: { settings.payMode = $0 })) {
                    ForEach(PayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settings.payMode == .hourly {
                    TextField("Stundenlohn (z. B. 23,50)", text: $hourlyRate)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    if !hourlyRate.isEmpty && parseMoneyToCents(hourlyRate) == nil {
                        Text("Bitte einen gültigen Stundenlohn eingeben.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } else {
                    TextField("Monatsgehalt (z. B. 3500,00)", text: $monthlySalary)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    if !monthlySalary.isEmpty && parseMoneyToCents(monthlySalary) == nil {
                        Text("Bitte ein gültiges Monatsgehalt eingeben.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var schedulePage: some View {
        OnboardingPageShell(
            title: "Arbeitszeit",
            subtitle: "Lege fest, wie deine Woche gerechnet werden soll.",
            step: currentStepIndex + 1,
            total: pageCount,
            icon: "calendar",
            accent: settings.themeAccent.color,
            isCurrentStepValid: isStepValid
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Stepper(
                    "Arbeitstage pro Woche: \(settings.scheduledWorkdaysCount)",
                    value: Binding(
                        get: { settings.scheduledWorkdaysCount },
                        set: { settings.scheduledWorkdaysCount = $0 }
                    ),
                    in: 1...7
                )

                Text("Feiertage werden mit der Sollzeit pro Arbeitstag gutgeschrieben.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Wöchentliche Sollstunden (optional)", text: $weeklyHours)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)

                if !weeklyHours.isEmpty, parseHoursToSeconds(weeklyHours) == nil {
                    Text("Sollstunden müssen eine gültige Zahl sein.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var firstShiftPage: some View {
        OnboardingPageShell(
            title: "Erste Daten",
            subtitle: "Optional kannst du direkt eine erste Schicht speichern.",
            step: currentStepIndex + 1,
            total: pageCount,
            icon: "square.and.pencil",
            accent: settings.themeAccent.color,
            isCurrentStepValid: isStepValid
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Erste Schicht speichern", isOn: $shouldCreateFirstShift)

                if shouldCreateFirstShift {
                    DatePicker("Datum", selection: $firstShiftDate, displayedComponents: .date)
                    DatePicker("Start", selection: $firstShiftStartTime, displayedComponents: .hourAndMinute)
                    DatePicker("Ende", selection: $firstShiftEndTime, displayedComponents: .hourAndMinute)

                    TextField("Pause in Minuten", text: $firstShiftBreakMinutes)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)

                    TextField("Trinkgeld optional (z. B. 12,50)", text: $firstShiftTip)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)

                    if let summary = firstShiftSummaryText {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let message = firstShiftValidationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Du kannst diesen Schritt überspringen und später im Kalender starten.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rulesPage: some View {
        OnboardingPageShell(
            title: "Regeln & Feiertage",
            subtitle: "Region und Regeln steuern Urlaub, Feiertage und Kranktage.",
            step: currentStepIndex + 1,
            total: pageCount,
            icon: "checkmark.shield",
            accent: settings.themeAccent.color,
            isCurrentStepValid: isStepValid
        ) {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Land (ISO, z. B. DE)", text: $holidayCountryCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                TextField("Bundesland (optional, z. B. BY)", text: $holidaySubdivisionCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Text("Feiertage werden über die API geladen und im Kalender separat markiert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !isHolidayCountryCodeValid {
                    Text("Bitte einen gültigen ISO-Ländercode mit 2 Buchstaben angeben.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Divider()

                Text("Bei aktivierter Regel werden die letzten 13 gleichen Wochentage geprüft.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Toggle("Urlaub mit 13-Wochen-Regel", isOn: vacationLookbackBinding)
                Toggle("Feiertag mit 13-Wochen-Regel", isOn: holidayLookbackBinding)

                Toggle("Fehlende Referenzen als 0 zählen", isOn: Binding(get: { settings.countMissingAsZero }, set: { settings.countMissingAsZero = $0 }))
                Text("Aus: fehlende Einträge bleiben offen, bis Daten vorhanden sind.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Strenge Historie erforderlich", isOn: Binding(get: { settings.strictHistoryRequired }, set: { settings.strictHistoryRequired = $0 }))
                Text("Ein: fehlende Rückblick-Tage erzeugen einen Fehler.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var captureAndThemePage: some View {
        OnboardingPageShell(
            title: "Erfassung & Ansicht",
            subtitle: "Lege Kalenderdarstellung und Akzentfarbe fest.",
            step: currentStepIndex + 1,
            total: pageCount,
            icon: "paintpalette",
            accent: settings.themeAccent.color,
            isCurrentStepValid: isStepValid
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Zellanzeige im Kalender", selection: calendarDisplayModeBinding) {
                    ForEach(CalendarCellDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text("Akzentfarbe")
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                    ForEach(ThemeAccent.allCases) { accent in
                        Button {
                            settings.themeAccent = accent
                        } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 36, height: 36)
                                Text(accent.label)
                                    .font(.footnote)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .payScopeGlassControl(
                                accent: accent.color,
                                cornerRadius: 14,
                                tintOpacity: settings.themeAccent == accent ? 0.11 : 0.045
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(settings.themeAccent.color)
            Text(text)
                .font(.body)
        }
    }

    private var isStepValid: Bool {
        switch step {
        case .overview:
            return true
        case .pay:
            if settings.payMode == .hourly {
                return parseMoneyToCents(hourlyRate).map { $0 > 0 } ?? false
            }
            return parseMoneyToCents(monthlySalary).map { $0 > 0 } ?? false
        case .schedule:
            if weeklyHours.isEmpty { return true }
            return parseHoursToSeconds(weeklyHours) != nil
        case .firstShift:
            return firstShiftValidationMessage == nil
        case .rules:
            return isHolidayCountryCodeValid
        case .appearance:
            return true
        }
    }

    private func persistCurrentStep() {
        if let value = parseMoneyToCents(hourlyRate), settings.payMode == .hourly {
            settings.hourlyRateCents = value
            settings.monthlySalaryCents = nil
        }
        if let value = parseMoneyToCents(monthlySalary), settings.payMode == .monthly {
            settings.monthlySalaryCents = value
            settings.hourlyRateCents = nil
        }
        settings.weeklyTargetSeconds = parseHoursToSeconds(weeklyHours)
        settings.holidayCountryCode = normalizedHolidayCountryCode
        settings.holidaySubdivisionCode = normalizedHolidaySubdivisionCode
        persistSettingsLocally()
    }

    private func advanceStep() {
        guard isStepValid else { return }
        persistCurrentStep()

        if step == .appearance {
            finishOnboarding()
            return
        }

        guard let nextStep = OnboardingStep(rawValue: currentStepIndex + 1) else { return }
        furthestUnlockedStepIndex = max(furthestUnlockedStepIndex, nextStep.rawValue)
        step = nextStep
    }

    private func finishOnboarding() {
        let firstShiftEntry = shouldCreateFirstShift ? makeFirstShiftEntry() : nil

        if let firstShiftEntry {
            localStore.save(firstShiftEntry)
        }

        settings.hasCompletedOnboarding = true
        settings.updatedAt = Date()
        UserDefaults.standard.set(true, forKey: "payscope.onboarding.completed.sticky")
        try? modelContext.save()

        Task {
            try? await cloudKitService.saveSettings(settings)
            if let firstShiftEntry {
                try? await cloudKitService.saveDayEntry(firstShiftEntry)
            }
        }
    }

    private func navigate(to newStep: OnboardingStep) {
        let targetIndex = newStep.rawValue
        if targetIndex <= furthestUnlockedStepIndex {
            persistCurrentStep()
            step = newStep
            return
        }

        guard targetIndex == currentStepIndex + 1, isStepValid else { return }
        persistCurrentStep()
        furthestUnlockedStepIndex = max(furthestUnlockedStepIndex, targetIndex)
        step = newStep
    }

    private var stepSelection: Binding<OnboardingStep> {
        Binding(
            get: { step },
            set: { navigate(to: $0) }
        )
    }

    private var onboardingTabs: [FabBarTab<OnboardingStep>] {
        OnboardingStep.allCases.map { step in
            FabBarTab(value: step, title: step.shortTitle, systemImage: step.systemImage)
        }
    }

    private var currentStepIndex: Int {
        step.rawValue
    }

    private var showsFallbackControls: Bool {
        horizontalSizeClass != .compact
    }

    private var fallbackNavigationControls: some View {
        HStack(spacing: 12) {
            Button("Zurück") {
                guard currentStepIndex > 0, let previous = OnboardingStep(rawValue: currentStepIndex - 1) else { return }
                navigate(to: previous)
            }
            .buttonStyle(.bordered)
            .disabled(currentStepIndex == 0)

            Button(step == .appearance ? "Fertig" : "Weiter") {
                advanceStep()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isStepValid)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var vacationLookbackBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveVacationCreditingMode == .lookback13Weeks },
            set: { newValue in
                settings.vacationCreditingMode = newValue ? .lookback13Weeks : .fixedValue
                if !newValue, settings.vacationFixedSeconds == nil {
                    settings.vacationFixedSeconds = suggestedFixedVacationSeconds
                }
                persistSettingsLocally()
            }
        )
    }

    private var holidayLookbackBinding: Binding<Bool> {
        Binding(
            get: { settings.effectiveHolidayCreditingMode == .lookback13Weeks },
            set: { newValue in
                settings.holidayCreditingMode = newValue ? .lookback13Weeks : .fixedValue
                if !newValue, settings.holidayFixedSeconds == nil {
                    settings.holidayFixedSeconds = suggestedFixedHolidaySeconds
                }
                persistSettingsLocally()
            }
        )
    }

    private func persistSettingsLocally() {
        settings.updatedAt = Date()
        try? modelContext.save()
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

    private func parseMoneyToCents(_ text: String) -> Int? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private func parseHoursToSeconds(_ text: String) -> Int? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let hours = Double(normalized), hours >= 0 else { return nil }
        return Int((hours * 3600).rounded())
    }

    private func parseMinutes(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        guard let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }

    private var isHolidayCountryCodeValid: Bool {
        normalizedHolidayCountryCode.count == 2
    }

    private var normalizedHolidayCountryCode: String {
        holidayCountryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var normalizedHolidaySubdivisionCode: String? {
        let value = holidaySubdivisionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return value.isEmpty ? nil : value
    }

    private var calendarDisplayModeBinding: Binding<CalendarCellDisplayMode> {
        Binding(
            get: { settings.calendarCellDisplayMode ?? .dot },
            set: { settings.calendarCellDisplayMode = $0 }
        )
    }

    private var firstShiftValidationMessage: String? {
        guard shouldCreateFirstShift else { return nil }
        guard parseMinutes(firstShiftBreakMinutes) != nil else {
            return "Bitte eine gültige Pause in Minuten eingeben."
        }
        if !firstShiftTip.isEmpty && parseMoneyToCents(firstShiftTip) == nil {
            return "Bitte ein gültiges Trinkgeld eingeben."
        }
        guard let range = firstShiftTimeRange else {
            return "Start und Ende dürfen nicht gleich sein."
        }
        let duration = Int(range.end.timeIntervalSince(range.start))
        if let breakMinutes = parseMinutes(firstShiftBreakMinutes), breakMinutes * 60 >= duration {
            return "Die Pause muss kürzer als die Schicht sein."
        }
        return nil
    }

    private var firstShiftSummaryText: String? {
        guard shouldCreateFirstShift, let range = firstShiftTimeRange else { return nil }
        let breakSeconds = (parseMinutes(firstShiftBreakMinutes) ?? 0) * 60
        let duration = max(0, Int(range.end.timeIntervalSince(range.start)) - breakSeconds)
        let durationText = PayScopeFormatters.hhmmString(seconds: duration)
        let daySuffix = Calendar.current.isDate(range.start, inSameDayAs: range.end) ? "" : " (+1)"
        return "Wird als Arbeitstag mit \(durationText) gespeichert. Ende\(daySuffix)."
    }

    private var firstShiftTimeRange: (start: Date, end: Date)? {
        let calendar = Calendar.current
        let startMinute = minuteOfDay(from: firstShiftStartTime, calendar: calendar)
        let endMinute = minuteOfDay(from: firstShiftEndTime, calendar: calendar)
        guard startMinute != endMinute else { return nil }

        let start = combinedDate(day: firstShiftDate, time: firstShiftStartTime, calendar: calendar)
        var end = combinedDate(day: firstShiftDate, time: firstShiftEndTime, calendar: calendar)
        if endMinute < startMinute {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(24 * 60 * 60)
        }
        return end > start ? (start, end) : nil
    }

    private func makeFirstShiftEntry() -> DayEntry? {
        guard let range = firstShiftTimeRange else { return nil }
        let entry = DayEntry(date: firstShiftDate, updatedAt: Date(), type: .work)
        entry.shiftStart = range.start
        entry.shiftEnd = range.end
        entry.breakSeconds = (parseMinutes(firstShiftBreakMinutes) ?? 0) * 60
        if let tipCents = parseMoneyToCents(firstShiftTip), tipCents > 0 {
            entry.tipAmountCents = tipCents
        }
        return entry
    }

    private func minuteOfDay(from date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func combinedDate(day: Date, time: Date, calendar: Calendar) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var components = DateComponents()
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return calendar.date(from: components) ?? day.startOfDayLocal()
    }
}

private enum OnboardingStep: Int, CaseIterable, Hashable, Identifiable {
    case overview
    case pay
    case schedule
    case firstShift
    case rules
    case appearance

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .overview: return "Start"
        case .pay: return "Lohn"
        case .schedule: return "Zeit"
        case .firstShift: return "Daten"
        case .rules: return "Regel"
        case .appearance: return "Stil"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "sparkles"
        case .pay: return "eurosign.circle.fill"
        case .schedule: return "calendar.badge.clock"
        case .firstShift: return "square.and.pencil"
        case .rules: return "checkmark.shield.fill"
        case .appearance: return "paintpalette.fill"
        }
    }
}

private struct OnboardingPageShell<Content: View>: View {
    let title: String
    let subtitle: String
    let step: Int
    let total: Int
    let icon: String
    let accent: Color
    let isCurrentStepValid: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(accent)
                        .frame(width: 30, height: 30)
                        .payScopeLiquidGlassIcon(accent: accent, tintOpacity: 0.12, shadowOpacity: 0.06)

                    Text("Schritt \(step) von \(total)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                Text(title)
                    .font(.system(.title, design: .rounded).bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(step), total: Double(total))
                    .tint(accent)

                content
                    .padding(14)
                    .payScopeSurface(accent: accent, cornerRadius: 18, emphasis: 0.28)

                if !isCurrentStepValid {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text("Bitte fülle die markierten Angaben aus, bevor du weitergehst.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, -4)
                }
            }
            .padding(24)
        }
        .fabBarSafeAreaPadding()
    }
}
