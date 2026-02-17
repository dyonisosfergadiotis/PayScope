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

                Text("WageWise")
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
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: Settings

    @State private var page = 0
    @State private var hourlyRate = ""
    @State private var monthlySalary = ""
    @State private var weeklyHours = ""
    @State private var holidayCountryCode = "DE"
    @State private var holidaySubdivisionCode = ""
    @State private var timelineMinMinute = 6 * 60
    @State private var timelineMaxMinute = 22 * 60

    private let pageCount = 6

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $page) {
                overviewPage.tag(0)
                paySetupPage.tag(1)
                workweekPage.tag(2)
                holidayRegionPage.tag(3)
                rulesPage.tag(4)
                captureAndThemePage.tag(5)
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
                    } else {
                        page += 1
                    }
                    modelContext.persistIfPossible()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isPageValid)
                .accessibilityLabel(page == pageCount - 1 ? "Onboarding abschließen" : "Weiter")
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .wageWiseBackground(accent: settings.themeAccent.color)
        .onAppear {
            hourlyRate = settings.hourlyRateCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            monthlySalary = settings.monthlySalaryCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            weeklyHours = settings.weeklyTargetSeconds.map { String(format: "%.1f", Double($0) / 3600) } ?? ""
            holidayCountryCode = settings.holidayCountryCode ?? "DE"
            holidaySubdivisionCode = settings.holidaySubdivisionCode ?? ""
            timelineMinMinute = settings.timelineMinMinute ?? 6 * 60
            timelineMaxMinute = settings.timelineMaxMinute ?? 22 * 60
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
                bullet("Arbeitswoche und Sollstunden")
                bullet("Land/Bundesland für Feiertage")
                bullet("Regeln für 13-Wochen-Berechnung")
                bullet("Timeline und Kalenderdarstellung")
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
                Picker("Lohnmodus", selection: $settings.payMode) {
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
            subtitle: "Basis für Sollzeit und Feiertagsgutschrift.",
            step: page + 1,
            total: pageCount,
            icon: "calendar",
            accent: settings.themeAccent.color
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Wochenstart", selection: $settings.weekStart) {
                    ForEach(WeekStart.allCases) { start in
                        Text(start.label).tag(start)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Wöchentliche Sollstunden (optional)", text: $weeklyHours)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)

                Picker("Feiertagsmodus", selection: $settings.holidayCreditingMode) {
                    ForEach(HolidayCreditingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if settings.holidayCreditingMode == .weeklyTargetDistributed {
                    Stepper("Arbeitstage pro Woche: \(settings.scheduledWorkdaysCount)", value: $settings.scheduledWorkdaysCount, in: 1...7)
                }

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

                Text("Feiertage werden über die API geladen und im Kalender grau markiert.")
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
            subtitle: "Steuert, wie Urlaub/Krank ohne Schätzungen berechnet wird.",
            step: page + 1,
            total: pageCount,
            icon: "checkmark.shield",
            accent: settings.themeAccent.color
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Für jeden Urlaubs- oder Krankheitstag werden die letzten 13 gleichen Wochentage geprüft.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Toggle("Fehlende Referenzen als 0 zählen", isOn: $settings.countMissingAsZero)
                Text("Aus: fehlende Einträge bleiben offen, bis Daten vorhanden sind.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Strenge Historie erforderlich", isOn: $settings.strictHistoryRequired)
                Text("Ein: fehlende Rückblick-Tage erzeugen einen Fehler.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var captureAndThemePage: some View {
        OnboardingPageShell(
            title: "Erfassung & Ansicht",
            subtitle: "Lege Timeline-Fenster und Kalenderdarstellung fest.",
            step: page + 1,
            total: pageCount,
            icon: "paintpalette",
            accent: settings.themeAccent.color
        ) {
            VStack(alignment: .leading, spacing: 14) {
                minuteWindowControl(
                    title: "Frühester Start",
                    value: $timelineMinMinute,
                    step: 15,
                    lower: 0,
                    upper: max(0, timelineMaxMinute - 60)
                )
                minuteWindowControl(
                    title: "Spätestes Ende",
                    value: $timelineMaxMinute,
                    step: 15,
                    lower: min(24 * 60, timelineMinMinute + 60),
                    upper: 24 * 60
                )

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
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(settings.themeAccent == accent ? accent.color.opacity(0.2) : Color(.secondarySystemBackground))
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
        case 2:
            if weeklyHours.isEmpty { return true }
            return parseHoursToSeconds(weeklyHours) != nil
        case 3:
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
        settings.timelineMinMinute = timelineMinMinute
        settings.timelineMaxMinute = timelineMaxMinute
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
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(accent.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(24)
        }
    }
}
