import SwiftUI
import CloudKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedInitialManualCloudRefresh") private var hasCompletedInitialManualCloudRefresh = false

    @State private var settings: Settings?
    @State private var isExpanded = false
    @State private var isRefreshing = false
    @State private var isLoadingSettingsFromICloud = false
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

    private var isBusyWithCloud: Bool {
        isRefreshing || isLoadingSettingsFromICloud
    }

    var body: some View {
        Group {
            if let resolvedSettings = settings {
                VStack(spacing: 10) {
                    CalendarMonthView(
                        settings: resolvedSettings,
                        entries: cloudEntries,
                        netConfigs: cloudNetWageConfigs,
                        holidays: cloudHolidayDays,
                        onSelectionChange: { isExpanded in
                            withAnimation(.easeInOut(duration: 0.22)) {
                                self.isExpanded = isExpanded
                            }
                        }
                    )

                    //syncStatusBar
                    breakBufferStatusBar(settings: resolvedSettings)
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
            Task {
                bootstrapIfNeeded()
                await loadSnapshotFromLocalCache()

                guard !hasInitialized else { return }
                hasInitialized = true

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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label {
                    Text(syncStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: isBusyWithCloud ? "arrow.triangle.2.circlepath.circle.fill" : "icloud")
                        .foregroundStyle(isBusyWithCloud ? accentColor : .secondary)
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
                .disabled(isBusyWithCloud)
            }

            Button {
                Task { await loadSettingsFromICloud() }
            } label: {
                HStack(spacing: 6) {
                    if isLoadingSettingsFromICloud {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                    }
                    Text("Einstellungen in iCloud laden")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusyWithCloud)
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
        if isLoadingSettingsFromICloud {
            return "Prüfe iCloud-Einstellungen..."
        }
        if isRefreshing {
            return "Aktualisiere iCloud-Daten..."
        }
        if let lastRefreshDate {
            return "Zuletzt aktualisiert: \(Formatters.time.string(from: lastRefreshDate))"
        }
        return "Lokaler Cache aktiv"
    }

    private func breakBufferStatusBar(settings: Settings) -> some View {
        let isAlwaysOn = settings.effectiveAlwaysApplyFifteenMinuteBuffer

        return HStack(spacing: 8) {
            Image(systemName: isAlwaysOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isAlwaysOn ? accentColor : .secondary)
            Text("15-Min-Puffer: \(isAlwaysOn ? "immer an" : "nur bei 6h/9h")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
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

    @MainActor
    private func loadSettingsFromICloud() async {
        guard !isRefreshing, !isLoadingSettingsFromICloud else { return }

        isLoadingSettingsFromICloud = true
        defer { isLoadingSettingsFromICloud = false }

        do {
            let snapshot = normalizeSnapshot(try await CloudKitReadService.shared.fetchSnapshot())
            guard let iCloudPayload = snapshot.settings else {
                refreshHint = "Error: Keine iCloud-Einstellungen gefunden"
                return
            }

            let iCloudSettings = makeSettings(from: iCloudPayload)
            let localSettings = settings ?? Settings()
            let differenceCount = settingsDifferenceCount(local: localSettings, iCloud: iCloudSettings)

            if differenceCount > 0 {
                applySnapshot(snapshot)
                lastAppliedSnapshot = snapshot
                await LocalCloudSnapshotStore.shared.save(snapshot: snapshot)

                let noun = differenceCount == 1 ? "Einstellung" : "Einstellungen"
                refreshHint = "\(differenceCount) \(noun) aus iCloud übernommen (iOS-Stand)"
            } else {
                refreshHint = "Einstellungen sind bereits wie auf iOS"
            }

            lastRefreshDate = Date()
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
    }

    private func settingsDifferenceCount(local: Settings, iCloud: Settings) -> Int {
        var differences = 0

        if local.hasCompletedOnboarding != iCloud.hasCompletedOnboarding { differences += 1 }
        if local.payMode != iCloud.payMode { differences += 1 }
        if local.hourlyRateCents != iCloud.hourlyRateCents { differences += 1 }
        if local.monthlySalaryCents != iCloud.monthlySalaryCents { differences += 1 }
        if local.weeklyTargetSeconds != iCloud.weeklyTargetSeconds { differences += 1 }
        if local.vacationLookbackCount != iCloud.vacationLookbackCount { differences += 1 }
        if local.vacationCreditingMode != iCloud.vacationCreditingMode { differences += 1 }
        if local.vacationFixedSeconds != iCloud.vacationFixedSeconds { differences += 1 }
        if local.countMissingAsZero != iCloud.countMissingAsZero { differences += 1 }
        if local.strictHistoryRequired != iCloud.strictHistoryRequired { differences += 1 }
        if local.holidayCreditingMode != iCloud.holidayCreditingMode { differences += 1 }
        if local.holidayFixedSeconds != iCloud.holidayFixedSeconds { differences += 1 }
        if local.scheduledWorkdaysCount != iCloud.scheduledWorkdaysCount { differences += 1 }
        if local.themeAccent != iCloud.themeAccent { differences += 1 }
        if local.calendarCellDisplayMode != iCloud.calendarCellDisplayMode { differences += 1 }
        if local.calendarHoursBreakMode != iCloud.calendarHoursBreakMode { differences += 1 }
        if local.showCalendarWeekNumbers != iCloud.showCalendarWeekNumbers { differences += 1 }
        if local.showCalendarWeekHours != iCloud.showCalendarWeekHours { differences += 1 }
        if local.showCalendarWeekPay != iCloud.showCalendarWeekPay { differences += 1 }
        if local.alwaysApplyFifteenMinuteBuffer != iCloud.alwaysApplyFifteenMinuteBuffer { differences += 1 }
        if local.holidayCountryCode != iCloud.holidayCountryCode { differences += 1 }
        if local.holidaySubdivisionCode != iCloud.holidaySubdivisionCode { differences += 1 }
        if local.autoSetHolidayCategory != iCloud.autoSetHolidayCategory { differences += 1 }
        if local.markPaidHolidays != iCloud.markPaidHolidays { differences += 1 }
        if local.paidHolidayWeekdayMask != iCloud.paidHolidayWeekdayMask { differences += 1 }
        if local.netWageTaxPercent != iCloud.netWageTaxPercent { differences += 1 }
        if local.netPensionPercent != iCloud.netPensionPercent { differences += 1 }
        if local.netMonthlyAllowanceEuro != iCloud.netMonthlyAllowanceEuro { differences += 1 }
        if local.netBonusesCSV != iCloud.netBonusesCSV { differences += 1 }

        return differences
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
            creditedOverrideSeconds: payload.creditedOverrideSeconds,
            shiftStart: payload.shiftStart,
            shiftEnd: payload.shiftEnd,
            breakSeconds: payload.breakSeconds,
            alwaysApplyFifteenMinuteBuffer: payload.alwaysApplyFifteenMinuteBuffer
        )

        if payload.type == .work,
           let start = payload.shiftStart,
           let end = payload.shiftEnd,
           end > start {
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
        resolved.alwaysApplyFifteenMinuteBuffer = incoming.alwaysApplyFifteenMinuteBuffer
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
        if lhs.breakSeconds != rhs.breakSeconds {
            return (lhs.breakSeconds ?? -1) < (rhs.breakSeconds ?? -1)
        }
        let lhsFlag = lhs.alwaysApplyFifteenMinuteBuffer == true ? 1 : 0
        let rhsFlag = rhs.alwaysApplyFifteenMinuteBuffer == true ? 1 : 0
        return lhsFlag < rhsFlag
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
