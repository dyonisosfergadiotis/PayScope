import SwiftUI
import CloudKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedInitialManualCloudRefresh") private var hasCompletedInitialManualCloudRefresh = false

    @State private var settings: Settings?
    @State private var isExpanded = false
    @State private var isRefreshing = false
    @State private var hasInitialized = false
    @State private var lastRefreshDate: Date?
    @State private var refreshHint: String?
    @State private var lastAppliedSnapshot: CloudSnapshot?

    @State private var cloudEntries: [DayEntry] = []
    @State private var cloudNetWageConfigs: [NetWageMonthConfig] = []
    @State private var cloudHolidayDays: [HolidayCalendarDay] = []

    private let compactWindowHeight: CGFloat = 560
    private let expandedWindowHeight: CGFloat = 620

    private var accentColor: Color {
        settings?.themeAccent.color ?? .accentColor
    }

    private var targetWindowHeight: CGFloat {
        isExpanded ? expandedWindowHeight : compactWindowHeight
    }

    var body: some View {
        Group {
            if settings != nil {
                VStack(spacing: 10) {
                    CalendarMonthView(
                        settings: settings,
                        entries: cloudEntries,
                        netConfigs: cloudNetWageConfigs,
                        holidays: cloudHolidayDays,
                        onSelectionChange: { isExpanded in
                            withAnimation(.easeInOut(duration: 0.22)) {
                                self.isExpanded = isExpanded
                            }
                        }
                    )
                }
                .padding(10)
                .frame(width: 380, height: targetWindowHeight, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
                .animation(.easeInOut(duration: 0.22), value: isExpanded)
            } else {
                ProgressView("PayScope wird vorbereitet...")
            }
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true

            Task {
                bootstrapIfNeeded()
                await loadSnapshotFromLocalCache()
                let shouldRunManualInitialRefresh = !hasCompletedInitialManualCloudRefresh
                let didRefreshSucceed = await refreshFromICloud(triggeredByUser: shouldRunManualInitialRefresh)
                if shouldRunManualInitialRefresh && didRefreshSucceed {
                    hasCompletedInitialManualCloudRefresh = true
                }
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { _ = await refreshFromICloud(triggeredByUser: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarSnapshotDidReload)) { notification in
            Task {
                if let snapshot = notification.object as? CloudSnapshot {
                    let normalized = normalizeSnapshot(snapshot)
                    lastAppliedSnapshot = normalized
                    applySnapshot(normalized)
                    lastRefreshDate = Date()
                } else {
                    await loadSnapshotFromLocalCache()
                }
                refreshHint = "iCloud-Daten neu geladen"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarSnapshotReloadFailed)) { notification in
            let detail = (notification.object as? Error)?
                .localizedDescription
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            refreshHint = detail.isEmpty
                ? "Error: Cloud-Reload fehlgeschlagen"
                : "Error: \(detail)"
        }
    }

    private var syncStatusBar: some View {
        HStack(spacing: 10) {
            Label {
                Text(syncStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } icon: {
                Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "icloud")
                    .foregroundStyle(isRefreshing ? accentColor : .secondary)
            }

            Spacer()

            Button {
                Task { _ = await refreshFromICloud(triggeredByUser: true) }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .controlSize(.small)
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var syncStatusText: String {
        if let refreshHint {
            return refreshHint
        }
        if isRefreshing {
            return "Aktualisiere iCloud-Daten..."
        }
        if let lastRefreshDate {
            return "Zuletzt aktualisiert: \(Formatters.time.string(from: lastRefreshDate))"
        }
        return "Lokaler Cache aktiv"
    }

    private func bootstrapIfNeeded() {
        guard settings == nil else { return }
        settings = Settings()
        refreshHint = "Lokaler Cache aktiv"
    }

    @MainActor
    private func loadSnapshotFromLocalCache() async {
        guard let envelope = await LocalCloudSnapshotStore.shared.load() else { return }
        let normalized = normalizeSnapshot(envelope.snapshot)
        lastAppliedSnapshot = normalized
        applySnapshot(normalized)
        lastRefreshDate = envelope.savedAt
        refreshHint = "Lokaler Cache aktiv"
    }

    @MainActor
    private func refreshFromICloud(triggeredByUser: Bool) async -> Bool {
        guard !isRefreshing else { return false }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = normalizeSnapshot(try await CloudKitReadService.shared.fetchSnapshot())

            if lastAppliedSnapshot != snapshot {
                applySnapshot(snapshot)
                lastAppliedSnapshot = snapshot
                await LocalCloudSnapshotStore.shared.save(snapshot: snapshot)
                refreshHint = nil
            } else if triggeredByUser {
                refreshHint = "Keine neuen Änderungen in iCloud"
            }

            lastRefreshDate = Date()
            return true
        } catch let error as CloudKitReadServiceError {
            refreshHint = "Error: \(error.localizedDescription)"
        } catch let error as CKError {
            let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            refreshHint = detail.isEmpty
                ? "Error: CloudKit-Fehler"
                : "Error: \(detail)"
        } catch {
            let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            refreshHint = detail.isEmpty
                ? "Error: Lokaler Cache bleibt aktiv"
                : "Error: \(detail)"
        }
        return false
    }

    private func applySnapshot(_ snapshot: CloudSnapshot) {
        let resolvedSettings = makeSettings(from: snapshot.settings)
        settings = resolvedSettings

        cloudEntries = snapshot.dayEntries
            .map(makeDayEntry)
            .sorted(by: { $0.date < $1.date })

        cloudNetWageConfigs = snapshot.netWageConfigs
            .map(makeNetWageConfig)
            .sorted(by: { $0.monthStart < $1.monthStart })

        cloudHolidayDays = snapshot.holidays
            .filter { holidayMatchesSettings($0, settings: resolvedSettings) }
            .map(makeHoliday)
            .sorted(by: { $0.date < $1.date })
    }

    private func makeDayEntry(from payload: CloudSnapshot.DayEntryPayload) -> DayEntry {
        let entry = DayEntry(
            date: payload.date.startOfDayUTC(),
            type: payload.type,
            notes: payload.notes,
            segments: [],
            manualWorkedSeconds: payload.manualWorkedSeconds,
            creditedOverrideSeconds: payload.creditedOverrideSeconds
        )

        if let start = payload.shiftStart, let end = payload.shiftEnd, end > start {
            entry.segments = [
                TimeSegment(start: start, end: end, breakSeconds: max(0, payload.breakSeconds ?? 0))
            ]
        }

        return entry
    }

    private func makeNetWageConfig(from payload: CloudSnapshot.NetWageConfigPayload) -> NetWageMonthConfig {
        NetWageMonthConfig(
            monthStart: payload.monthStart,
            wageTaxPercent: payload.wageTaxPercent,
            pensionPercent: payload.pensionPercent,
            monthlyAllowanceEuro: payload.monthlyAllowanceEuro,
            bonusesCSV: payload.bonusesCSV
        )
    }

    private func makeHoliday(from payload: CloudSnapshot.HolidayPayload) -> HolidayCalendarDay {
        HolidayCalendarDay(
            date: payload.date,
            localName: payload.localName,
            countryCode: payload.countryCode,
            subdivisionCode: payload.subdivisionCode,
            sourceYear: payload.sourceYear
        )
    }

    private func holidayMatchesSettings(_ holiday: CloudSnapshot.HolidayPayload, settings: Settings) -> Bool {
        let targetCountry = normalizeCode(settings.holidayCountryCode) ?? "DE"
        let targetSubdivision = normalizeCode(settings.holidaySubdivisionCode)
        guard normalizeCode(holiday.countryCode) == targetCountry else {
            return false
        }

        let holidaySubdivision = normalizeCode(holiday.subdivisionCode)
        guard let targetSubdivision else {
            return true
        }
        return holidaySubdivision == nil || holidaySubdivision == targetSubdivision
    }

    private func normalizeCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func makeSettings(from payload: CloudSnapshot.SettingsPayload?) -> Settings {
        guard let incoming = payload else {
            return settings ?? Settings()
        }

        let resolved = Settings()
        resolved.hasCompletedOnboarding = incoming.hasCompletedOnboarding
        resolved.payMode = incoming.payMode
        resolved.hourlyRateCents = incoming.hourlyRateCents
        resolved.monthlySalaryCents = incoming.monthlySalaryCents
        resolved.weeklyTargetSeconds = incoming.weeklyTargetSeconds
        resolved.weekStart = incoming.weekStart
        resolved.vacationLookbackCount = incoming.vacationLookbackCount
        resolved.vacationCreditingMode = incoming.vacationCreditingMode
        resolved.vacationFixedSeconds = incoming.vacationFixedSeconds
        resolved.countMissingAsZero = incoming.countMissingAsZero
        resolved.strictHistoryRequired = incoming.strictHistoryRequired
        resolved.holidayCreditingMode = incoming.holidayCreditingMode
        resolved.holidayFixedSeconds = incoming.holidayFixedSeconds
        resolved.scheduledWorkdaysCount = incoming.scheduledWorkdaysCount
        resolved.themeAccent = incoming.themeAccent
        resolved.calendarCellDisplayMode = incoming.calendarCellDisplayMode
        resolved.calendarHoursBreakMode = incoming.calendarHoursBreakMode
        resolved.showCalendarWeekNumbers = incoming.showCalendarWeekNumbers
        resolved.showCalendarWeekHours = incoming.showCalendarWeekHours
        resolved.showCalendarWeekPay = incoming.showCalendarWeekPay
        resolved.timelineMinMinute = incoming.timelineMinMinute
        resolved.timelineMaxMinute = incoming.timelineMaxMinute
        resolved.holidayCountryCode = incoming.holidayCountryCode
        resolved.holidaySubdivisionCode = incoming.holidaySubdivisionCode
        resolved.autoSetHolidayCategory = incoming.autoSetHolidayCategory
        resolved.markPaidHolidays = incoming.markPaidHolidays
        resolved.paidHolidayWeekdayMask = incoming.paidHolidayWeekdayMask
        resolved.netWageTaxPercent = incoming.netWageTaxPercent
        resolved.netPensionPercent = incoming.netPensionPercent
        resolved.netMonthlyAllowanceEuro = incoming.netMonthlyAllowanceEuro
        resolved.netBonusesCSV = incoming.netBonusesCSV
        return resolved
    }

    private func normalizeSnapshot(_ snapshot: CloudSnapshot) -> CloudSnapshot {
        let sortedEntries = snapshot.dayEntries.sorted(by: compareDayEntryPayloads)
        let sortedConfigs = snapshot.netWageConfigs.sorted(by: compareNetConfigPayloads)
        let sortedHolidays = snapshot.holidays.sorted(by: compareHolidayPayloads)

        return CloudSnapshot(
            settings: snapshot.settings,
            dayEntries: sortedEntries,
            netWageConfigs: sortedConfigs,
            holidays: sortedHolidays
        )
    }

    private func compareDayEntryPayloads(_ lhs: CloudSnapshot.DayEntryPayload, _ rhs: CloudSnapshot.DayEntryPayload) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.updatedAt != rhs.updatedAt { return (lhs.updatedAt ?? .distantPast) < (rhs.updatedAt ?? .distantPast) }
        if lhs.type != rhs.type { return lhs.type.rawValue < rhs.type.rawValue }
        if lhs.notes != rhs.notes { return lhs.notes < rhs.notes }
        if lhs.manualWorkedSeconds != rhs.manualWorkedSeconds {
            return (lhs.manualWorkedSeconds ?? -1) < (rhs.manualWorkedSeconds ?? -1)
        }
        if lhs.creditedOverrideSeconds != rhs.creditedOverrideSeconds {
            return (lhs.creditedOverrideSeconds ?? -1) < (rhs.creditedOverrideSeconds ?? -1)
        }
        if lhs.shiftStart != rhs.shiftStart {
            return (lhs.shiftStart ?? .distantPast) < (rhs.shiftStart ?? .distantPast)
        }
        if lhs.shiftEnd != rhs.shiftEnd {
            return (lhs.shiftEnd ?? .distantPast) < (rhs.shiftEnd ?? .distantPast)
        }
        return (lhs.breakSeconds ?? -1) < (rhs.breakSeconds ?? -1)
    }

    private func compareNetConfigPayloads(_ lhs: CloudSnapshot.NetWageConfigPayload, _ rhs: CloudSnapshot.NetWageConfigPayload) -> Bool {
        if lhs.monthStart != rhs.monthStart { return lhs.monthStart < rhs.monthStart }
        if lhs.wageTaxPercent != rhs.wageTaxPercent {
            return (lhs.wageTaxPercent ?? -1) < (rhs.wageTaxPercent ?? -1)
        }
        if lhs.pensionPercent != rhs.pensionPercent {
            return (lhs.pensionPercent ?? -1) < (rhs.pensionPercent ?? -1)
        }
        if lhs.monthlyAllowanceEuro != rhs.monthlyAllowanceEuro {
            return (lhs.monthlyAllowanceEuro ?? -1) < (rhs.monthlyAllowanceEuro ?? -1)
        }
        return lhs.bonusesCSV < rhs.bonusesCSV
    }

    private func compareHolidayPayloads(_ lhs: CloudSnapshot.HolidayPayload, _ rhs: CloudSnapshot.HolidayPayload) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.countryCode != rhs.countryCode { return lhs.countryCode < rhs.countryCode }
        if lhs.subdivisionCode != rhs.subdivisionCode {
            return (lhs.subdivisionCode ?? "") < (rhs.subdivisionCode ?? "")
        }
        if lhs.localName != rhs.localName { return lhs.localName < rhs.localName }
        return lhs.sourceYear < rhs.sourceYear
    }
}

#if os(macOS)
#Preview("macOS – Light") {
    ContentView()
        .environment(\.colorScheme, .light)
}

#Preview("macOS – Dark") {
    ContentView()
        .environment(\.colorScheme, .dark)
}
#else
#Preview {
    ContentView()
}
#endif
