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
    @Bindable var settings: Settings

    @State private var page = 0
    @State private var hourlyRate = ""
    @State private var monthlySalary = ""
    @State private var weeklyHours = ""
    @State private var holidayCountryCode = "DE"
    @State private var holidaySubdivisionCode = ""

    private let pageCount = 7

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $page) {
                overviewPage.tag(0)
                paySetupPage.tag(1)
                workweekPage.tag(2)
                weeklyTargetPage.tag(3)
                holidayRegionPage.tag(4)
                rulesPage.tag(5)
                captureAndThemePage.tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            ProgressView(value: Double(page + 1), total: Double(pageCount))
                .padding(.horizontal)

            HStack {
                if page > 0 {
                    Button("Zurück") {
                        page -= 1
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button(page == pageCount - 1 ? "Fertig" : "Weiter") {
                        persistCurrentPage()
                        if page == pageCount - 1 {
                            settings.hasCompletedOnboarding = true
                            settings.updatedAt = Date()
                            UserDefaults.standard.set(true, forKey: "payscope.onboarding.completed.sticky")
                            try? modelContext.save()

                            Task {
                                try? await cloudKitService.saveSettings(settings)
                            }
                        } else {
                            page += 1
                        }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isPageValid)
                .accessibilityLabel(page == pageCount - 1 ? "Onboarding abschließen" : "Weiter")
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .payScopeBackground(accent: settings.themeAccent.color)
        .tint(settings.themeAccent.color)
        .onAppear {
            hourlyRate = settings.hourlyRateCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            monthlySalary = settings.monthlySalaryCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            weeklyHours = settings.weeklyTargetSeconds.map { String(format: "%.1f", Double($0) / 3600) } ?? ""
            holidayCountryCode = settings.holidayCountryCode ?? "DE"
            holidaySubdivisionCode = settings.holidaySubdivisionCode ?? ""
        }
    }

    private var overviewPage: some View {
        OnboardingPageShell(
            title: "Schnelles Setup",
            subtitle: "Wir richten die wichtigsten Einstellungen direkt jetzt ein.",
            step: page + 1,
            total: pageCount,
            icon: "slider.horizontal.3",
            accent: settings.themeAccent.color
        ) {
            VStack(alignment: .leading, spacing: 12) {
                bullet("Bezahlungsmodell und Betrag")
                bullet("Arbeitstage pro Woche")
                bullet("Wöchentliche Sollstunden")
                bullet("Land/Bundesland für Feiertage")
                bullet("Regeln für 13-Wochen-Berechnung")
                bullet("Kalenderdarstellung und Akzentfarbe")
            }
        }
    }

    private var paySetupPage: some View {
        OnboardingPageShell(
            title: "Bezahlung",
            subtitle: "Diese Angaben sind für die Lohnberechnung erforderlich.",
            step: page + 1,
            total: pageCount,
            icon: "eurosign.circle",
            accent: settings.themeAccent.color
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

    private var workweekPage: some View {
        OnboardingPageShell(
            title: "Arbeitswoche",
            subtitle: "Lege fest, wie viele Arbeitstage deine Woche hat.",
            step: page + 1,
            total: pageCount,
            icon: "calendar",
            accent: settings.themeAccent.color
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
            }
        }
    }

    private var weeklyTargetPage: some View {
        OnboardingPageShell(
            title: "Wochenstunden",
            subtitle: "Diese Sollzeit wird für Zielwerte und Feiertage genutzt.",
            step: page + 1,
            total: pageCount,
            icon: "clock",
            accent: settings.themeAccent.color
        ) {
            VStack(alignment: .leading, spacing: 14) {
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

    private var holidayRegionPage: some View {
        OnboardingPageShell(
            title: "Feiertage & Region",
            subtitle: "Land und Bundesland steuern den Feiertagsimport im Kalender.",
            step: page + 1,
            total: pageCount,
            icon: "globe.europe.africa",
            accent: settings.themeAccent.color
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
            }
        }
    }

    private var rulesPage: some View {
        OnboardingPageShell(
            title: "13-Wochen-Regeln",
            subtitle: "Steuert, wie Urlaub/Feiertag/Krank ohne Schätzungen berechnet wird.",
            step: page + 1,
            total: pageCount,
            icon: "checkmark.shield",
            accent: settings.themeAccent.color
        ) {
            VStack(alignment: .leading, spacing: 14) {
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
            step: page + 1,
            total: pageCount,
            icon: "paintpalette",
            accent: settings.themeAccent.color
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Zellanzeige im Kalender", selection: calendarDisplayModeBinding) {
                    ForEach(CalendarCellDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

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
                            .payScopeSurface(
                                accent: accent.color,
                                cornerRadius: 14,
                                emphasis: settings.themeAccent == accent ? 0.45 : 0.2
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

    private var isPageValid: Bool {
        switch page {
        case 0:
            return true
        case 1:
            if settings.payMode == .hourly {
                return parseMoneyToCents(hourlyRate).map { $0 > 0 } ?? false
            }
            return parseMoneyToCents(monthlySalary).map { $0 > 0 } ?? false
        case 3:
            if weeklyHours.isEmpty { return true }
            return parseHoursToSeconds(weeklyHours) != nil
        case 4:
            return isHolidayCountryCodeValid
        default:
            return true
        }
    }

    private func persistCurrentPage() {
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
}

private struct OnboardingPageShell<Content: View>: View {
    let title: String
    let subtitle: String
    let step: Int
    let total: Int
    let icon: String
    let accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(accent)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(accent.opacity(0.15))
                        )

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

                content
                    .padding(14)
                    .payScopeSurface(accent: accent, cornerRadius: 18, emphasis: 0.28)
            }
            .padding(24)
        }
    }
}
