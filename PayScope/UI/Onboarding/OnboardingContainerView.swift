import SwiftUI
import SwiftData

struct OnboardingContainerView: View {
    @Bindable var settings: Settings
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                OnboardingSplashView()
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
    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue.opacity(0.4), .mint.opacity(0.25), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Circle()
                    .fill(
                        LinearGradient(colors: [.blue, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
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

    private let pageCount = 5

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                paySetupPage.tag(1)
                workweekPage.tag(2)
                rulePage.tag(3)
                themePage.tag(4)
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
        }
    }

    private var welcomePage: some View {
        OnboardingPageShell(title: "Willkommen bei WageWise", subtitle: "Verstehe Stunden, Lohn und Gutschriften ohne Schätzwerte.") {
            VStack(alignment: .leading, spacing: 12) {
                bullet("Tägliche Erfassung mit klaren Typen für Arbeit, Urlaub und Krank")
                bullet("Strenge 13-Wochen-Regel für verlässliche Gutschriften")
                bullet("Wochen- und Monatssummen mit Warnungen und Fehlern")
            }
        }
    }

    private var paySetupPage: some View {
        OnboardingPageShell(title: "Bezahlung", subtitle: "Wähle dein Lohnmodell und gib einen gültigen Betrag ein.") {
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
        OnboardingPageShell(title: "Arbeitswoche", subtitle: "Lege Wochenstart und Sollzeiten fest.") {
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

    private var rulePage: some View {
        OnboardingPageShell(title: "13-Wochen-Regel", subtitle: "Urlaub und Krankheit nutzen die Historie gleicher Wochentage.") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Für jeden Urlaubs- oder Krankheitstag prüft WageWise die letzten 13 gleichen Wochentage. Im strengen Modus führen fehlende Daten zu einem Fehler, ohne Schätzung.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Toggle("Fehlende Referenzen als 0 zählen", isOn: $settings.countMissingAsZero)
                Text("Wenn deaktiviert, bleiben fehlende Einträge offen, bis du sie erstellst.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Strenge Historie erforderlich", isOn: $settings.strictHistoryRequired)
                Text("Wenn aktiviert, erzeugt jeder fehlende Rückblick-Tag einen Fehler.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var themePage: some View {
        OnboardingPageShell(title: "Design", subtitle: "Wähle deine Akzentfarbe.") {
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
}

private struct OnboardingPageShell<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(colors: [.blue.opacity(0.35), .mint.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(height: 120)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 36)).foregroundStyle(.white))

                Text(title)
                    .font(.system(.title, design: .rounded).bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                content
            }
            .padding(24)
        }
    }
}
