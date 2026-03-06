import SwiftUI

struct DayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudKitService: CloudKitService
    private let localStore = LocalDayEntryStore.shared

    @State private var allEntries: [DayEntry] = []
    @State private var localEntries: [DayEntry] = []
    @State private var netWageConfigs: [NetWageMonthConfig] = []
    @State private var holidayDays: [HolidayCalendarDay] = []

    let date: Date
    @Bindable var settings: Settings
    var onDaySaved: ((Date, DayEntry?) -> Void)? = nil

    @State private var selectedType: DayType = .work
    @State private var notes = ""

    @State private var startMinute: Int = 0
    @State private var endMinute: Int = 0
    @State private var hasStartMinute = false
    @State private var hasEndMinute = false
    @State private var manualBreakOverrideMinutes: Int?

    @State private var isApplyingLoad = false
    @State private var selectedDate = Date().startOfDayLocal()
    @State private var manualWorkedSeconds: Int = 0
    @State private var creditedOverrideSeconds: Int?
    @State private var editingShortcutIndex: Int?
    @State private var shortcutDraftStartMinute: Int = 9 * 60
    @State private var shortcutDraftEndMinute: Int = 17 * 60
    @State private var selectedSheetDetent: PresentationDetent = .fraction(0.72)
    @State private var hasAnimatedIn = false
    @State private var didRunEntryAnimation = false
    @State private var showDeleteConfirm = false
    @State private var isNotesEditorVisible = false
    @State private var isBreakEditorVisible = false

    private var settingsShortcut1: String { settings.shiftShortcut1 }
    private var settingsShortcut2: String { settings.shiftShortcut2 }
    private var settingsShortcut3: String { settings.shiftShortcut3 }
    private var settingsShortcutName1: String { settings.shiftShortcutName1 ?? "" }
    private var settingsShortcutName2: String { settings.shiftShortcutName2 ?? "" }
    private var settingsShortcutName3: String { settings.shiftShortcutName3 ?? "" }

    private let service = CalculationService()

    @State private var isLoading = false
    @State private var pendingLoadAfterCurrentCycle = false
    @State private var hasUnsavedUserChanges = false

    private var timelineBounds: ClosedRange<Int> {
        let minValue = max(0, min(settings.timelineMinMinute ?? 6 * 60, 23 * 60))
        let maxValue = max(minValue + 60, min(settings.timelineMaxMinute ?? 22 * 60, 24 * 60))
        return minValue...maxValue
    }

    private var allEntriesEffective: [DayEntry] {
        let merged = Dictionary(
            (localEntries + allEntries).map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        return merged.values.sorted { $0.date > $1.date }
    }
    
    private var hasExistingEntryForSelectedDate: Bool {
        allEntriesEffective.contains { $0.date.isSameLocalDay(as: selectedDate) }
    }

    private func dayKey(_ date: Date) -> String {
        let day = date.startOfDayLocal()
        let year = Calendar.current.component(.year, from: day)
        let month = Calendar.current.component(.month, from: day)
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MultiSegmentTimelinePreview(
                        segments: hasValidShiftRange ? [EditableSegment(startMinute: startMinute, endMinute: endMinute)] : [],
                        accent: settings.themeAccent.color,
                        bounds: timelineBounds
                    )
                    .padding(.vertical, 4)

                    shiftPanel

                    notesButtonPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .opacity(hasAnimatedIn ? 1 : 0)
            .offset(y: hasAnimatedIn ? 0 : 14)
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: hasAnimatedIn)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DatePicker(
                        "",
                        selection: selectedDayBinding,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityLabel("Datum auswählen")
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Schließen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(!hasExistingEntryForSelectedDate)
                    .accessibilityLabel("Löschen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!isSaveValid)
                    .accessibilityLabel("Speichern")
                }

                shiftComposerToolBar
            }
            .onAppear {
                selectedDate = date.startOfDayLocal()
                hasUnsavedUserChanges = false
                Task { await load(for: selectedDate) }
                setEditorDetent(defaultEditorDetent(for: selectedType), animated: false)
                if didRunEntryAnimation {
                    hasAnimatedIn = true
                } else {
                    hasAnimatedIn = false
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        hasAnimatedIn = true
                    }
                    didRunEntryAnimation = true
                }
            }
            .onChange(of: selectedDate) { _, newValue in
                hasUnsavedUserChanges = false
                Task { await load(for: newValue) }
            }
            .onChange(of: selectedType) { _, _ in
                if isApplyingLoad { return }
                hasUnsavedUserChanges = true
                if selectedType == .manual {
                    manualWorkedSeconds = max(0, manualWorkedSeconds)
                    creditedOverrideSeconds = nil
                    manualBreakOverrideMinutes = nil
                    isBreakEditorVisible = false
                } else if isCreditedType {
                    manualWorkedSeconds = 0
                    // keep creditedOverrideSeconds unchanged
                    manualBreakOverrideMinutes = nil
                    isBreakEditorVisible = false
                } else {
                    manualWorkedSeconds = 0
                    creditedOverrideSeconds = nil
                    clampManualBreakOverride()
                }
            }
            .onChange(of: startMinute) { _, _ in
                if !isApplyingLoad { hasUnsavedUserChanges = true }
                clampManualBreakOverride()
            }
            .onChange(of: endMinute) { _, _ in
                if !isApplyingLoad { hasUnsavedUserChanges = true }
                clampManualBreakOverride()
            }
            .onChange(of: hasStartMinute) { _, _ in
                if !isApplyingLoad { hasUnsavedUserChanges = true }
                clampManualBreakOverride()
            }
            .onChange(of: hasEndMinute) { _, _ in
                if !isApplyingLoad { hasUnsavedUserChanges = true }
                clampManualBreakOverride()
            }
            .onChange(of: manualWorkedSeconds) { _, _ in
                if !isApplyingLoad { hasUnsavedUserChanges = true }
            }
            .onChange(of: creditedOverrideSeconds) { _, _ in
                if !isApplyingLoad { hasUnsavedUserChanges = true }
            }
            .onChange(of: notes) { _, _ in
                if !isApplyingLoad { hasUnsavedUserChanges = true }
            }
            .onChange(of: manualBreakOverrideMinutes) { _, _ in
                if !isApplyingLoad { hasUnsavedUserChanges = true }
            }
            .onChange(of: entriesSignature) { _, _ in
                // Query results can arrive after .onAppear; only auto-reload while no local draft exists.
                if isApplyingLoad || hasLocalDraftData || hasUnsavedUserChanges { return }
                Task { await load(for: selectedDate) }
            }
            .alert("Tag löschen?", isPresented: $showDeleteConfirm) {
                Button("Löschen", role: .destructive) {
                    deleteCurrentDay()
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Dieser Tag wird dauerhaft entfernt.")
            }
        }
        .payScopeSheetSurface(accent: settings.themeAccent.color)
        .presentationDetents(editorDetents, selection: $selectedSheetDetent)
        .sheet(isPresented: isEditingShortcutBinding) {
            shortcutEditorSheet
        }
    }

    private var editorDetents: Set<PresentationDetent> {
        if selectedType == .work {
            return [.fraction(0.72), .large]
        }
        return [.fraction(0.66), .large]
    }

    private func defaultEditorDetent(for type: DayType) -> PresentationDetent {
        type == .work ? .fraction(0.72) : .fraction(0.66)
    }

    private func setEditorDetent(_ detent: PresentationDetent, animated: Bool) {
        if animated {
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.9)) {
                selectedSheetDetent = detent
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                selectedSheetDetent = detent
            }
        }
    }

    @ToolbarContentBuilder
    private var shiftComposerToolBar : some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            HStack {
                toolbarMetricPill(value: PayScopeFormatters.hhmmString(seconds: totalNetSeconds), title: "Dauer")
            }
            .frame(maxWidth: .infinity)
        }
        
        ToolbarSpacer(.flexible,placement: .bottomBar)
        
        ToolbarItem(placement: .bottomBar) {
            HStack {
                toolbarMetricPill(value: PayScopeFormatters.currencyString(cents: totalGrossPayCents), title: "Brutto")
            }
            .frame(maxWidth: .infinity)
        }
        
        ToolbarSpacer(.flexible,placement: .bottomBar)
        
        ToolbarItem(placement: .bottomBar) {
            HStack {
                toolbarMetricPill(value: PayScopeFormatters.hhmmString(seconds: (usesManualDurationInput ? 0 : (selectedType == .work ? breakMinutes * 60 : 0))), title: "Pause")
            }
            .frame(maxWidth: .infinity)
        }
            
        
    }

    private func toolbarMetricPill(value: String, title: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 86)
    }

    private var shiftPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(
                    selectedType == .work
                        ? (hasExistingEntryForSelectedDate ? "Schicht" : "Neue Schicht")
                        : selectedType.label
                )
                    .font(.headline.weight(.semibold))
                Spacer()
                shiftCategoryMenu
            }

            if selectedType == .manual {
                Text("Dauer wird manuell erfasst.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if usesManualDurationInput {
                HStack(spacing: 12) {
                    Text("Dauer")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    ManualDurationEditor(seconds: $manualWorkedSeconds, accent: settings.themeAccent.color)
                }
                Text("Bei manueller Erfassung wird keine Pause abgezogen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isCreditedType {
                VStack(alignment: .center, spacing: 10) {
                    Text(creditedComputationDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if creditedOverrideSeconds != nil {
                        HStack(spacing: 12) {
                            Text("Abweichung")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            HHMMInputDurationEditor(seconds: creditedOverrideBinding, accent: settings.themeAccent.color)
                        }
                        .frame(maxWidth: 320)

                        Text("Die Abweichung überschreibt den automatisch berechneten Wert.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Abweichung entfernen") {
                            creditedOverrideSeconds = nil
                        }
                        .buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
                    } else {
                        Button("Abweichung angeben") {
                            creditedOverrideSeconds = creditedBaselineSeconds()
                        }
                        .buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Work: start/end/break
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Start")
                            .font(.subheadline.weight(.semibold))
                        HHMMMinuteInput(minuteOfDay: $startMinute, hasValue: $hasStartMinute, accent: settings.themeAccent.color)
                        Spacer(minLength: 4)
                        Text(grossDurationBadgeLabel)
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .lineLimit(1)
                            .foregroundStyle(settings.themeAccent.color.opacity(0.7))
                            .frame(width: 52)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(settings.themeAccent.color.opacity(0.12))
                            )
                        Spacer(minLength: 4)
                        HHMMMinuteInput(minuteOfDay: $endMinute, hasValue: $hasEndMinute, accent: settings.themeAccent.color)
                        Text("Ende")
                            .font(.subheadline.weight(.semibold))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("Pause")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(breakMinutes) min")
                                .font(.subheadline.weight(.semibold))
                            Button {
                                openBreakEditor()
                            } label: {
                                Image(systemName: isBreakEditorVisible ? "xmark" : "pencil")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }

                        if isBreakEditorVisible {
                            HStack(spacing: 8) {
                                breakAdjustmentButton(title: "-10", delta: -10)
                                    .frame(maxWidth: .infinity)
                                breakAdjustmentButton(title: "-5", delta: -5)
                                    .frame(maxWidth: .infinity)
                                breakAdjustmentButton(title: "-1", delta: -1)
                                    .frame(maxWidth: .infinity)
                                Button("Auto") {
                                    manualBreakOverrideMinutes = nil
                                }
                                .buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
                                .frame(maxWidth: .infinity)
                                breakAdjustmentButton(title: "+1", delta: 1)
                                    .frame(maxWidth: .infinity)
                                breakAdjustmentButton(title: "+5", delta: 5)
                                    .frame(maxWidth: .infinity)
                                breakAdjustmentButton(title: "+10", delta: 10)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            HStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { index in
                                    Button(shortcutButtonLabel(for: index)) {
                                        onShortcutTap(index: index)
                                    }
                                    .buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }

                    if let error = shiftValidationMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .neoPanel(accent: settings.themeAccent.color)
    }

    private var notesButtonPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

            if !isNotesEditorVisible && trimmedNotes.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNotesEditorVisible = true
                    }
                } label: {
                    Label("Notizen", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tint(settings.themeAccent.color)
                }
                //.buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
            } else {
                HStack {
                    Text("Notizen")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    if !trimmedNotes.isEmpty {
                        Button("Leeren") {
                            notes = ""
                        }
                        .buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
                    } else {
                        Button("Ausblenden") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isNotesEditorVisible = false
                            }
                        }
                        //.buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
                    }
                }

                ZStack(alignment: .topLeading) {
                    if trimmedNotes.isEmpty {
                        Text("Optional: Kontext, Besonderheiten, Hinweise ...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 12, emphasis: 0.16)
                }
            }
        }
        .neoPanel(accent: settings.themeAccent.color)
    }

    private var totalNetSeconds: Int {
        switch previewComputation {
        case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
            return valueSeconds
        case .error:
            return 0
        }
    }

    private var totalGrossSeconds: Int {
        guard hasCompleteShiftTime else { return 0 }
        return max(0, (endMinute - startMinute) * 60)
    }

    private var grossDurationBadgeLabel: String {
        guard hasCompleteShiftTime else { return "--:--" }
        let minutes = max(0, endMinute - startMinute)
        let hoursPart = minutes / 60
        let minutePart = minutes % 60
        return String(format: "%02d:%02d", hoursPart, minutePart)
    }

    private var hasCompleteShiftTime: Bool {
        hasStartMinute && hasEndMinute
    }

    private var hasValidShiftRange: Bool {
        hasCompleteShiftTime && endMinute > startMinute
    }

    private var isCreditedType: Bool {
        selectedType == .vacation || selectedType == .holiday || selectedType == .sick
    }

    private var creditedComputationDescription: String {
        if selectedType == .vacation, settings.effectiveVacationCreditingMode == .fixedValue {
            return "Dieser Urlaubstag nutzt den festen Wert aus den Einstellungen."
        }
        if selectedType == .holiday, settings.effectiveHolidayCreditingMode == .fixedValue {
            return "Dieser Feiertag nutzt den festen Wert aus den Einstellungen."
        }
        return "Dieser Typ wird automatisch mit der 13-Wochen-Regel berechnet."
    }

    private var usesManualDurationInput: Bool {
        selectedType == .manual
    }

    private var hasLocalDraftData: Bool {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedType != .work { return true }
        if usesManualDurationInput {
            return manualWorkedSeconds > 0 || !trimmedNotes.isEmpty
        }
        return hasStartMinute || hasEndMinute || breakMinutes > 0 || !trimmedNotes.isEmpty
    }

    private var entriesSignature: Int {
        var hasher = Hasher()
        for day in allEntriesEffective {
            hasher.combine(day.date.timeIntervalSinceReferenceDate)
            hasher.combine(day.type.rawValue)
            hasher.combine(day.manualWorkedSeconds ?? -1)
            hasher.combine(day.creditedOverrideSeconds ?? -1)
            hasher.combine(day.notes)
            hasher.combine(day.shiftStart?.timeIntervalSinceReferenceDate ?? 0)
            hasher.combine(day.shiftEnd?.timeIntervalSinceReferenceDate ?? 0)
            hasher.combine(day.breakSeconds ?? -1)
        }
        return hasher.finalize()
    }

    private var previewComputation: ComputationResult {
        let preview = DayEntry(date: selectedDate.startOfDayLocal(), type: selectedType, notes: notes)
        preview.creditedOverrideSeconds = isCreditedType ? creditedOverrideSeconds.map { max(0, $0) } : nil
        if usesManualDurationInput {
            preview.manualWorkedSeconds = max(0, manualWorkedSeconds)
            return service.dayComputation(for: preview, allEntries: allEntriesEffective, settings: settings)
        }
        let clampedBreakSeconds = (selectedType == .work) ? max(0, min(breakMinutes * 60, totalGrossSeconds)) : 0
        if hasValidShiftRange, let start = dateAtMinute(startMinute), let end = dateAtMinute(endMinute), end > start {
            preview.shiftStart = start
            preview.shiftEnd = end
            preview.breakSeconds = clampedBreakSeconds
        }
        return service.dayComputation(for: preview, allEntries: allEntriesEffective, settings: settings)
    }

    private var totalGrossPayCents: Int {
        switch previewComputation {
        case let .ok(_, valueCents), let .warning(_, valueCents, _):
            return valueCents
        case .error:
            return 0
        }
    }

    private func metricBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 12, emphasis: 0.2)
    }

    private func segmentDataChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(settings.themeAccent.color.opacity(0.12))
        )
    }

    private var isSaveValid: Bool {
        if isCreditedType { return true }
        if usesManualDurationInput { return manualWorkedSeconds > 0 }
        // Work
        return hasValidShiftRange && breakMinutes * 60 <= totalGrossSeconds
    }

    private var shiftValidationMessage: String? {
        guard selectedType == .work else { return nil }
        guard hasCompleteShiftTime else { return nil }
        if endMinute <= startMinute { return "Ende muss nach Start liegen." }
        let gross = totalGrossSeconds
        if breakMinutes * 60 > gross { return "Pause ist länger als die gesamte Dauer." }
        return nil
    }

    private var selectedDayBinding: Binding<Date> {
        Binding(
            get: { selectedDate },
            set: { selectedDate = $0.startOfDayLocal() }
        )
    }

    private func isImportedHoliday(_ date: Date) -> Bool {
        let country = normalizedHolidayCode(settings.holidayCountryCode) ?? "DE"
        let subdivision = normalizedHolidayCode(settings.holidaySubdivisionCode)

        return holidayDays.contains { day in
            normalizedHolidayCode(day.countryCode) == country &&
            normalizedHolidayCode(day.subdivisionCode) == subdivision &&
            day.date.isSameLocalDay(as: date)
        }
    }

    private func normalizedHolidayCode(_ code: String?) -> String? {
        guard let code else { return nil }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func applyLoadedEntries(_ entries: [DayEntry], for dayDate: Date) {
        isApplyingLoad = true
        defer {
            isApplyingLoad = false
            hasUnsavedUserChanges = false
        }

        if let existing = entries.first(where: { $0.date.isSameLocalDay(as: dayDate) }) {
            selectedType = existing.type
            notes = existing.notes
            isNotesEditorVisible = !existing.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if selectedType == .manual {
                manualWorkedSeconds = max(0, existing.manualWorkedSeconds ?? 0)
                manualBreakOverrideMinutes = nil
                if let s = existing.shiftStart {
                    startMinute = minuteOfDay(from: s)
                    hasStartMinute = true
                } else {
                    hasStartMinute = false
                }
                if let e = existing.shiftEnd {
                    endMinute = minuteOfDay(from: e)
                    hasEndMinute = true
                } else {
                    hasEndMinute = false
                }
            } else if isCreditedType {
                manualWorkedSeconds = 0
                creditedOverrideSeconds = existing.creditedOverrideSeconds.map { max(0, $0) }
                manualBreakOverrideMinutes = nil
                hasStartMinute = false
                hasEndMinute = false
            } else {
                manualWorkedSeconds = 0
                creditedOverrideSeconds = nil
                if let s = existing.shiftStart {
                    startMinute = minuteOfDay(from: s)
                    hasStartMinute = true
                } else {
                    hasStartMinute = false
                }
                if let e = existing.shiftEnd {
                    endMinute = minuteOfDay(from: e)
                    hasEndMinute = true
                } else {
                    hasEndMinute = false
                }
                let storedBreakMinutes = max(0, existing.breakSeconds ?? 0) / 60
                inferManualBreakOverride(fromStoredBreakMinutes: storedBreakMinutes)
            }
        } else {
            selectedType = (isImportedHoliday(dayDate) && settings.isPaidHolidayWeekday(dayDate)) ? .holiday : .work
            notes = ""
            isNotesEditorVisible = false
            manualWorkedSeconds = 0
            creditedOverrideSeconds = nil
            hasStartMinute = false
            hasEndMinute = false
            manualBreakOverrideMinutes = nil
        }
    }

    private func reconcileLocalWithCloud(for day: Date) {
        // Merge cloud into local cache (LWW) without writing to cloud.
        let start = day.addingDays(-365)
        let end = day.addingDays(365)
        let cloudEntriesInRange = allEntries.filter { $0.date >= start && $0.date <= end }
        let localEntriesInRange = localEntries.filter { $0.date >= start && $0.date <= end }

        // Dictionary by day string for easy lookup
        func dayKeyForEntry(_ entry: DayEntry) -> String {
            PayScopeFormatters.day.string(from: entry.date)
        }

        var localDict: [String: DayEntry] = [:]
        for e in localEntriesInRange {
            let key = dayKeyForEntry(e)
            if let existing = localDict[key] {
                localDict[key] = e.updatedAt > existing.updatedAt ? e : existing
            } else {
                localDict[key] = e
            }
        }
        var cloudDict: [String: DayEntry] = [:]
        for e in cloudEntriesInRange {
            let key = dayKeyForEntry(e)
            if let existing = cloudDict[key] {
                cloudDict[key] = e.updatedAt > existing.updatedAt ? e : existing
            } else {
                cloudDict[key] = e
            }
        }

        let tombstonesByDay = Dictionary(
            localStore.loadDeletionTombstones().map { (dayKey($0.date), $0.lastModified) },
            uniquingKeysWith: { current, incoming in
                incoming > current ? incoming : current
            }
        )

        // Merge entries with latest-change-wins while respecting local delete tombstones.
        for key in Set(localDict.keys).union(cloudDict.keys) {
            let localEntry = localDict[key]
            let cloudEntry = cloudDict[key]

            if let cloudEntry = cloudEntry,
               let deletedAt = tombstonesByDay[key],
               deletedAt >= cloudEntry.updatedAt {
                continue
            }

            if localEntry == nil, let cloudEntry = cloudEntry {
                localStore.save(cloudEntry)
            } else if let localEntry = localEntry, let cloudEntry = cloudEntry {
                if cloudEntry.updatedAt > localEntry.updatedAt {
                    localStore.save(cloudEntry)
                }
            }
        }

        // Reload local entries after reconcile
        let localInterval = DateInterval(start: start, end: end)
        localEntries = localStore.loadAll(in: localInterval)
    }

    private func load(for dayDate: Date) async {
        if isLoading {
            pendingLoadAfterCurrentCycle = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            if pendingLoadAfterCurrentCycle {
                pendingLoadAfterCurrentCycle = false
                Task { await load(for: selectedDate) }
            }
        }

        // Load local entries synchronously first
        let start = dayDate.addingDays(-365)
        let end = dayDate.addingDays(365)
        let localInterval = DateInterval(start: start, end: end)
        localEntries = localStore.loadAll(in: localInterval)

        // Use local entries to populate UI initially
        applyLoadedEntries(localEntries, for: dayDate)

        // Then fetch from cloud and reconcile
        do {
            let fetchedEntries = try await cloudKitService.fetchDayEntries(in: localInterval)
            let tombstonesByDay = Dictionary(
                localStore.loadDeletionTombstones().map { (dayKey($0.date), $0.lastModified) },
                uniquingKeysWith: { current, incoming in
                    incoming > current ? incoming : current
                }
            )
            allEntries = fetchedEntries.filter { cloudEntry in
                guard let deletedAt = tombstonesByDay[dayKey(cloudEntry.date)] else { return true }
                return deletedAt < cloudEntry.updatedAt
            }
            let year = Calendar.current.component(.year, from: dayDate)
            holidayDays = (try? await cloudKitService.fetchHolidayDays(
                countryCode: normalizedHolidayCode(settings.holidayCountryCode) ?? "DE",
                subdivisionCode: normalizedHolidayCode(settings.holidaySubdivisionCode),
                year: year
            )) ?? []
            reconcileLocalWithCloud(for: dayDate)
            if !hasUnsavedUserChanges {
                applyLoadedEntries(allEntriesEffective, for: dayDate)
            }
        } catch {
            #if DEBUG
            print("Failed to load day data: \(error)")
            #endif
        }
    }

    private func save() {
        let dayDate = selectedDate.startOfDayLocal()
        // Compute UTC midnight for the same local civil day to avoid timezone shifts
        let utcDayDate: Date = {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: dayDate)
            return utc.date(from: comps) ?? dayDate
        }()

        let isTodaySave = dayDate.isSameLocalDay(as: Date().startOfDayLocal())
        let existing = allEntriesEffective.first(where: { $0.date.isSameLocalDay(as: dayDate) })
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // If work but invalid shift and no notes, treat as delete
        if selectedType == .work, (!hasValidShiftRange) && trimmedNotes.isEmpty {
            if existing != nil {
                let entriesAfterDelete = allEntriesEffective.filter { !$0.date.isSameLocalDay(as: dayDate) }
                hasUnsavedUserChanges = false
                onDaySaved?(dayDate, nil)
                dismiss()

                localStore.delete(on: dayDate)
                refreshFollowingAutoCreditedEntries(changedFrom: dayDate)

                if isTodaySave {
                    Task { @MainActor in
                        await PayScopeLiveActivityManager.syncAtAppLaunch(
                            settings: settings,
                            entries: entriesAfterDelete
                        )
                    }
                }

                Task {
                    do {
                        try await cloudKitService.deleteDayEntry(on: dayDate)
                    } catch {
                    }
                    await load(for: dayDate)
                }
            } else {
                hasUnsavedUserChanges = false
                onDaySaved?(dayDate, nil)
                dismiss()
            }
            return
        }

        let target = existing ?? DayEntry(date: utcDayDate)
        target.date = utcDayDate
        target.updatedAt = Date()
        target.type = selectedType
        target.notes = notes

        // Reset fields
        target.shiftStart = nil
        target.shiftEnd = nil
        target.breakSeconds = 0
        target.manualWorkedSeconds = nil
        target.creditedOverrideSeconds = nil

        if isCreditedType {
            // Credited: store override if provided; shift times remain empty
            target.creditedOverrideSeconds = creditedOverrideSeconds.map { max(0, $0) }
        } else if usesManualDurationInput {
            target.manualWorkedSeconds = max(0, manualWorkedSeconds)
        } else {
            // Work: whole shift
            if hasValidShiftRange, let start = dateAtMinute(startMinute), let end = dateAtMinute(endMinute), end > start {
                target.shiftStart = start
                target.shiftEnd = end
                target.breakSeconds = max(0, breakMinutes * 60)
            }
        }

        hasUnsavedUserChanges = false
        onDaySaved?(dayDate, target)
        dismiss()

        Task {
            refreshFollowingAutoCreditedEntries(changedFrom: dayDate)
            let mergedEntriesAfterSave = mergedEntriesReplacingDay(on: dayDate, with: target)

            do {
                // Cloud-first: iCloud is the primary source of truth.
                try await cloudKitService.saveDayEntry(target)
                localStore.save(target)
                await load(for: dayDate)
                if isTodaySave {
                    await PayScopeLiveActivityManager.syncAtAppLaunch(
                        settings: settings,
                        entries: mergedEntriesAfterSave
                    )
                }
            } catch {
                // Fallback for offline/unreachable CloudKit.
                localStore.save(target)
                if isTodaySave {
                    await PayScopeLiveActivityManager.syncAtAppLaunch(
                        settings: settings,
                        entries: mergedEntriesAfterSave
                    )
                }
                #if DEBUG
                print("CloudKit save failed, persisted locally as fallback: \(error)")
                #endif
            }
        }
    }

    private func deleteCurrentDay() {
        let dayDate = selectedDate.startOfDayLocal()
        let entriesAfterDelete = allEntriesEffective.filter { !$0.date.isSameLocalDay(as: dayDate) }
        hasUnsavedUserChanges = false
        onDaySaved?(dayDate, nil)

        // Delete from CloudKit
        Task {
            do {
                try await cloudKitService.deleteDayEntry(on: dayDate)
            } catch {
            }
            await load(for: selectedDate)
        }
        // Delete from local cache
        localStore.delete(on: dayDate)
        allEntries.removeAll { $0.date.isSameLocalDay(as: dayDate) }
        localEntries.removeAll { $0.date.isSameLocalDay(as: dayDate) }
        refreshFollowingAutoCreditedEntries(changedFrom: dayDate)

        // Update live activity if today
        if dayDate.isSameLocalDay(as: Date().startOfDayLocal()) {
            Task { @MainActor in
                await PayScopeLiveActivityManager.syncAtAppLaunch(
                    settings: settings,
                    entries: entriesAfterDelete
                )
            }
        }
        dismiss()
    }

    private func refreshFollowingAutoCreditedEntries(changedFrom changedDate: Date) {
        let candidates = allEntriesEffective
            .filter {
                $0.date > changedDate &&
                ($0.type == .vacation || $0.type == .holiday || $0.type == .sick) &&
                isAutoManagedCreditedEntry($0)
            }
            .sorted { $0.date < $1.date }

        for day in candidates {
            let seconds = resolvedCreditedSeconds(for: day)
            applyAutoCreditedSegment(for: day, seconds: seconds)
        }
    }

    private func isAutoManagedCreditedEntry(_ day: DayEntry) -> Bool {
        guard day.manualWorkedSeconds == nil else { return false }
        guard day.creditedOverrideSeconds == nil else { return false }
        guard day.type == .vacation || day.type == .holiday || day.type == .sick else { return false }
        return day.shiftStart == nil && day.shiftEnd == nil
    }

    private func applyAutoCreditedSegment(for day: DayEntry, seconds: Int) {
        _ = seconds
        day.manualWorkedSeconds = nil
        day.shiftStart = nil
        day.shiftEnd = nil
        day.breakSeconds = 0
    }

    private var creditedOverrideBinding: Binding<Int> {
        Binding(
            get: { max(0, creditedOverrideSeconds ?? 0) },
            set: { creditedOverrideSeconds = max(0, $0) }
        )
    }

    private func creditedBaselineSeconds() -> Int {
        let probe = DayEntry(date: selectedDate.startOfDayLocal(), type: selectedType)
        let result = service.dayComputation(for: probe, allEntries: allEntriesEffective, settings: settings)
        switch result {
        case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
            return valueSeconds
        case .error:
            return 0
        }
    }

    private func resolvedCreditedSeconds(for day: DayEntry) -> Int {
        if let override = day.creditedOverrideSeconds {
            return max(0, override)
        }
        let result = service.dayComputation(for: day, allEntries: allEntriesEffective, settings: settings)
        switch result {
        case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
            return valueSeconds
        case .error:
            return 0
        }
    }

    private func isEquivalentEntry(_ lhs: DayEntry, _ rhs: DayEntry) -> Bool {
        lhs.type == rhs.type &&
        lhs.notes == rhs.notes &&
        lhs.breakSeconds == rhs.breakSeconds &&
        lhs.manualWorkedSeconds == rhs.manualWorkedSeconds &&
        lhs.creditedOverrideSeconds == rhs.creditedOverrideSeconds &&
        lhs.shiftStart == rhs.shiftStart &&
        lhs.shiftEnd == rhs.shiftEnd
    }

    private func mergedEntriesReplacingDay(on dayDate: Date, with entry: DayEntry) -> [DayEntry] {
        var merged = allEntriesEffective.filter { !$0.date.isSameLocalDay(as: dayDate) }
        merged.append(entry)
        return merged.sorted { $0.date < $1.date }
    }

    private func isCredited(_ type: DayType) -> Bool {
        type == .vacation || type == .holiday || type == .sick
    }

    private func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func dateAtMinute(_ minute: Int) -> Date? {
        dateAtMinute(minute, on: selectedDate)
    }

    private func dateAtMinute(_ minute: Int, on baseDate: Date) -> Date? {
        let dayStart = baseDate.startOfDayLocal()
        if minute >= 24 * 60 {
            return Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
        }
        let h = max(0, minute / 60)
        let m = max(0, minute % 60)
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: dayStart)
    }

    private var isEditingShortcutBinding: Binding<Bool> {
        Binding(
            get: { editingShortcutIndex != nil },
            set: { isPresented in
                if !isPresented {
                    editingShortcutIndex = nil
                }
            }
        )
    }

    private var shortcutEditorSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("Start")
                        .font(.subheadline.weight(.semibold))
                    HHMMMinuteInput(minuteOfDay: $shortcutDraftStartMinute, accent: settings.themeAccent.color)
                }

                HStack(spacing: 8) {
                    Text("Ende")
                        .font(.subheadline.weight(.semibold))
                    HHMMMinuteInput(minuteOfDay: $shortcutDraftEndMinute, accent: settings.themeAccent.color)
                }

                Button("Shortcut speichern") {
                    saveShortcutDraft()
                }
                .buttonStyle(.payScopePrimary(accent: settings.themeAccent.color))
                .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(16)
            .navigationTitle("Schicht speichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") {
                        editingShortcutIndex = nil
                    }
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    private func onShortcutTap(index: Int) {
        if let shortcut = shiftShortcut(at: index) {
            applyShortcut(shortcut)
            return
        }
        let fallback = defaultShortcut(for: index)
        shortcutDraftStartMinute = fallback.startMinute
        shortcutDraftEndMinute = fallback.endMinute
        editingShortcutIndex = index
    }

    private func applyShortcut(_ shortcut: ShiftShortcut) {
        let clamped = clampedShortcut(shortcut)
        if clamped.isRichTemplate {
            applyShortcutTemplate(clamped)
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            startMinute = clamped.startMinute
            endMinute = clamped.endMinute
            hasStartMinute = true
            hasEndMinute = true
            manualBreakOverrideMinutes = nil
        }
    }

    private func saveShortcutDraft() {
        guard let index = editingShortcutIndex else { return }
        let fallbackShortcut = clampedShortcut(
            ShiftShortcut(startMinute: shortcutDraftStartMinute, endMinute: shortcutDraftEndMinute)
        )
        let shortcut = clampedShortcut(shortcutForCurrentDraft(fallback: fallbackShortcut))
        setShortcut(shortcut, at: index)
        applyShortcut(shortcut)
        editingShortcutIndex = nil
    }

    private func shortcutButtonLabel(for index: Int) -> String {
        let customName = shortcutName(for: index).trimmingCharacters(in: .whitespacesAndNewlines)
        if !customName.isEmpty {
            return customName
        }
        guard let shortcut = shiftShortcut(at: index) else {
            return "S\(index + 1) speichern"
        }
        return "\(formatMinute(shortcut.startMinute))-\(formatMinute(shortcut.endMinute))"
    }

    private func shortcutName(for index: Int) -> String {
        switch index {
        case 0: return settingsShortcutName1
        case 1: return settingsShortcutName2
        case 2: return settingsShortcutName3
        default: return ""
        }
    }

    private func shiftShortcut(at index: Int) -> ShiftShortcut? {
        let raw: String
        switch index {
        case 0: raw = settingsShortcut1
        case 1: raw = settingsShortcut2
        case 2: raw = settingsShortcut3
        default: return nil
        }
        return ShiftShortcut(rawValue: raw)
    }

    private func setShortcut(_ shortcut: ShiftShortcut, at index: Int) {
        switch index {
        case 0: settings.shiftShortcut1 = shortcut.rawValue
        case 1: settings.shiftShortcut2 = shortcut.rawValue
        case 2: settings.shiftShortcut3 = shortcut.rawValue
        default: return
        }
        Task { try? await cloudKitService.saveSettings(settings) }
    }

    private func shortcutForCurrentDraft(fallback: ShiftShortcut) -> ShiftShortcut {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let earliestStart = fallback.startMinute
        let latestEnd = fallback.endMinute
        let grossMinutes = max(0, latestEnd - earliestStart)
        let clampedBreakMinutes = selectedType == .work ? max(0, min(breakMinutes, grossMinutes)) : 0

        let shouldStoreRichTemplate = selectedType != .work || !trimmedNotes.isEmpty || clampedBreakMinutes > 0

        guard shouldStoreRichTemplate else {
            return ShiftShortcut(startMinute: earliestStart, endMinute: latestEnd)
        }

        let payload = ShiftShortcutPayload(
            startMinute: earliestStart,
            endMinute: latestEnd,
            dayTypeRaw: selectedType.rawValue,
            notes: notes,
            segments: [],
            breakMinutes: clampedBreakMinutes,
            manualWorkedSeconds: selectedType == .manual ? max(0, manualWorkedSeconds) : nil,
            creditedOverrideSeconds: isCredited(selectedType) ? creditedOverrideSeconds.map { max(0, $0) } : nil
        )
        return ShiftShortcut(startMinute: earliestStart, endMinute: latestEnd, payload: payload)
    }

    private func applyShortcutTemplate(_ shortcut: ShiftShortcut) {
        let targetType = shortcut.dayType ?? .work

        isApplyingLoad = true
        defer { isApplyingLoad = false }

        selectedType = targetType
        notes = shortcut.notes

        manualWorkedSeconds = 0
        creditedOverrideSeconds = nil

        if targetType == .manual {
            manualWorkedSeconds = max(0, shortcut.manualWorkedSeconds ?? 0)
            manualBreakOverrideMinutes = nil
            hasStartMinute = false
            hasEndMinute = false
            return
        }

        if isCredited(targetType) {
            creditedOverrideSeconds = shortcut.creditedOverrideSeconds.map { max(0, $0) }
            manualBreakOverrideMinutes = nil
            hasStartMinute = false
            hasEndMinute = false
            return
        }

        startMinute = shortcut.startMinute
        endMinute = shortcut.endMinute
        hasStartMinute = true
        hasEndMinute = true
        inferManualBreakOverride(fromStoredBreakMinutes: max(0, min(shortcut.breakMinutes, endMinute - startMinute)))
    }

    private func clampedShortcut(_ shortcut: ShiftShortcut) -> ShiftShortcut {
        func clampedRange(start: Int, end: Int) -> (start: Int, end: Int) {
            let clampedStart = max(timelineBounds.lowerBound, min(timelineBounds.upperBound - 1, start))
            let clampedEnd = min(timelineBounds.upperBound, max(clampedStart + 1, end))
            return (clampedStart, clampedEnd)
        }

        let fallbackRange = clampedRange(start: shortcut.startMinute, end: shortcut.endMinute)
        guard let payload = shortcut.payload else {
            return ShiftShortcut(startMinute: fallbackRange.start, endMinute: fallbackRange.end)
        }

        let earliestStart = fallbackRange.start
        let latestEnd = fallbackRange.end
        let dayType = (payload.dayTypeRaw.flatMap { DayType(rawValue: $0) }) ?? .work
        let grossMinutes = max(0, latestEnd - earliestStart)

        let normalizedPayload = ShiftShortcutPayload(
            startMinute: earliestStart,
            endMinute: latestEnd,
            dayTypeRaw: dayType.rawValue,
            notes: payload.notes,
            segments: [],
            breakMinutes: dayType == .work ? max(0, min(payload.breakMinutes, grossMinutes)) : 0,
            manualWorkedSeconds: dayType == .manual ? max(0, payload.manualWorkedSeconds ?? 0) : nil,
            creditedOverrideSeconds: isCredited(dayType) ? payload.creditedOverrideSeconds.map { max(0, $0) } : nil
        )

        return ShiftShortcut(
            startMinute: earliestStart,
            endMinute: latestEnd,
            payload: normalizedPayload
        )
    }

    private func defaultShortcut(for index: Int) -> ShiftShortcut {
        let defaults = [
            ShiftShortcut(startMinute: 6 * 60, endMinute: 14 * 60),
            ShiftShortcut(startMinute: 9 * 60, endMinute: 17 * 60),
            ShiftShortcut(startMinute: 14 * 60, endMinute: 22 * 60)
        ]
        return clampedShortcut(defaults[min(max(index, 0), defaults.count - 1)])
    }

    private func formatMinute(_ minute: Int) -> String {
        let clamped = max(0, min(24 * 60, minute))
        let h = clamped / 60
        let m = clamped % 60
        return String(format: "%02d:%02d", h, m)
    }

    private var shiftCategoryMenu: some View {
        Menu {
            ForEach(DayType.allCases) { type in
                Button {
                    selectedType = type
                } label: {
                    HStack {
                        Label(type.label, systemImage: type.icon)
                        Spacer()
                        if type == selectedType {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(selectedType.label, systemImage: selectedType.icon)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 118, alignment: .trailing)
        }
        .foregroundStyle(selectedType.tint(for: settings.themeAccent))
    }

    private func automaticBreakBaseMinutes(for grossMinutes: Int) -> Int {
        let sixHoursWithTolerance = 6 * 60 + 15
        let nineHoursWithTolerance = 9 * 60 + 15

        if grossMinutes <= sixHoursWithTolerance { return 0 }
        if grossMinutes <= nineHoursWithTolerance { return 30 }
        return 45
    }

    private func inferManualBreakOverride(fromStoredBreakMinutes storedBreakMinutes: Int) {
        let grossMinutes = hasCompleteShiftTime ? max(0, endMinute - startMinute) : 0
        let clampedStoredBreak = max(0, min(storedBreakMinutes, grossMinutes))
        let auto = automaticBreakBaseMinutes(for: grossMinutes)
        if clampedStoredBreak == auto {
            manualBreakOverrideMinutes = nil
        } else {
            manualBreakOverrideMinutes = clampedStoredBreak
        }
    }

    private func clampManualBreakOverride() {
        guard let manualBreakOverrideMinutes else { return }
        let grossMinutes = hasCompleteShiftTime ? max(0, endMinute - startMinute) : 0
        self.manualBreakOverrideMinutes = max(0, min(manualBreakOverrideMinutes, grossMinutes))
    }

    private func openBreakEditor() {
        isBreakEditorVisible.toggle()
    }

    private func adjustBreak(by deltaMinutes: Int) {
        let targetValue = breakMinutes + deltaMinutes
        let grossMinutes = hasCompleteShiftTime ? max(0, endMinute - startMinute) : 0
        let clampedValue = max(0, min(targetValue, grossMinutes))
        let autoValue = automaticBreakBaseMinutes(for: grossMinutes)
        manualBreakOverrideMinutes = (clampedValue == autoValue) ? nil : clampedValue
    }

    private func breakAdjustmentButton(title: String, delta: Int) -> some View {
        Button(title) {
            adjustBreak(by: delta)
        }
        .buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
    }

    private var breakMinutes: Int {
        guard selectedType == .work else { return 0 }
        let grossMinutes = hasCompleteShiftTime ? max(0, endMinute - startMinute) : 0
        if let manualBreakOverrideMinutes {
            return max(0, min(manualBreakOverrideMinutes, grossMinutes))
        }
        return min(grossMinutes, automaticBreakBaseMinutes(for: grossMinutes))
    }
}

private struct NeoPanelStyle: ViewModifier {
    let accent: Color
    let glow: Bool

    func body(content: Content) -> some View {
        content
            .padding(15)
            .payScopeSurface(accent: accent, cornerRadius: 22, emphasis: glow ? 0.62 : 0.4)
            .shadow(color: accent.opacity(glow ? 0.18 : 0.08), radius: glow ? 20 : 10, x: 0, y: glow ? 10 : 5)
    }
}

private extension View {
    func neoPanel(accent: Color, glow: Bool = false) -> some View {
        modifier(NeoPanelStyle(accent: accent, glow: glow))
    }
}

private struct EditableSegment: Identifiable {
    let id = UUID()
    var startMinute: Int
    var endMinute: Int

    var validationMessage: String? {
        if endMinute < startMinute {
            return "Ende muss nach Start liegen."
        }
        return nil
    }

    var grossDurationMinutes: Int {
        max(0, endMinute - startMinute)
    }

    var durationLabel: String {
        let h = grossDurationMinutes / 60
        let m = grossDurationMinutes % 60
        return String(format: "%02d:%02d h", h, m)
    }
}

private struct ShiftShortcut {
    let startMinute: Int
    let endMinute: Int
    let payload: ShiftShortcutPayload?

    init(startMinute: Int, endMinute: Int, payload: ShiftShortcutPayload? = nil) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.payload = payload
    }

    init?(rawValue: String) {
        if let data = rawValue.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ShiftShortcutPayload.self, from: data) {
            self.startMinute = payload.startMinute
            self.endMinute = payload.endMinute
            self.payload = payload
            return
        }

        let parts = rawValue.split(separator: "-")
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]) else { return nil }
        self.startMinute = start
        self.endMinute = end
        self.payload = nil
    }

    var rawValue: String {
        guard let payload else { return "\(startMinute)-\(endMinute)" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return "\(startMinute)-\(endMinute)"
        }
        return string
    }

    var isRichTemplate: Bool {
        payload != nil
    }

    var dayType: DayType? {
        guard let raw = payload?.dayTypeRaw else { return nil }
        return DayType(rawValue: raw)
    }

    var notes: String {
        payload?.notes ?? ""
    }

    var segments: [ShiftShortcutSegment] {
        payload?.segments ?? []
    }

    var breakMinutes: Int {
        max(0, payload?.breakMinutes ?? 0)
    }

    var manualWorkedSeconds: Int? {
        payload?.manualWorkedSeconds
    }

    var creditedOverrideSeconds: Int? {
        payload?.creditedOverrideSeconds
    }
}

private struct ShiftShortcutPayload: Codable, Equatable {
    let startMinute: Int
    let endMinute: Int
    let dayTypeRaw: String?
    let notes: String
    let segments: [ShiftShortcutSegment]
    let breakMinutes: Int
    let manualWorkedSeconds: Int?
    let creditedOverrideSeconds: Int?
}

private struct ShiftShortcutSegment: Codable, Equatable {
    let startMinute: Int
    let endMinute: Int
}

private struct MultiSegmentTimelinePreview: View {
    let segments: [EditableSegment]
    let accent: Color
    let bounds: ClosedRange<Int>

    private var labelTickMinutes: [Int] {
        makeTicks(step: 120)
    }

    private var hourTickMinutes: [Int] {
        makeTicks(step: 60)
    }

    private var dashedTickMinutes: [Int] {
        hourTickMinutes.filter { $0 != bounds.lowerBound && $0 != bounds.upperBound }
    }

    private func makeTicks(step: Int) -> [Int] {
        var ticks: [Int] = [bounds.lowerBound]
        var current = ((bounds.lowerBound + step - 1) / step) * step
        while current < bounds.upperBound {
            if current > bounds.lowerBound {
                ticks.append(current)
            }
            current += step
        }
        if ticks.last != bounds.upperBound {
            ticks.append(bounds.upperBound)
        }
        return ticks
    }

    private var useMinutePrecision: Bool {
        bounds.lowerBound % 60 != 0 || bounds.upperBound % 60 != 0 || labelTickMinutes.contains { $0 % 60 != 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(CGFloat(1), geo.size.width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: segments.isEmpty ? [
                                Color(.systemBackground).opacity(0.88),
                                accent.opacity(0.10),
                                accent.opacity(0.18)
                            ] : [
                                Color(.systemBackground).opacity(0.85),
                                accent.opacity(0.06),
                                accent.opacity(0.12)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .allowsHitTesting(false)

                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.9), accent.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .blendMode(.overlay)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(accent.opacity(0.35), lineWidth: 1)
                        )
                        .frame(
                            width: max(2, x(for: segment.endMinute, width: width) - x(for: segment.startMinute, width: width)),
                            height: 22
                        )
                        .offset(x: x(for: segment.startMinute, width: width))
                        .shadow(color: accent.opacity(0.28), radius: 6, x: 0, y: 2)
                        .allowsHitTesting(false)
                }

                ForEach(Array(dashedTickMinutes.enumerated()), id: \.offset) { _, tick in
                    Path { path in
                        let xPosition = x(for: tick, width: width)
                        path.move(to: CGPoint(x: xPosition, y: 2))
                        path.addLine(to: CGPoint(x: xPosition, y: 20))
                    }
                    .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 24)

        GeometryReader { geo in
            let width = max(CGFloat(1), geo.size.width)
            let labels = visibleTicks(for: width)

            ZStack(alignment: .leading) {
                ForEach(labels, id: \.self) { tick in
                    Text(formatMinute(tick))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .center)
                        .position(x: labelCenterX(for: tick, width: width), y: 7)
                }
            }
        }
        .frame(height: 10)
        .padding(.top, -2)
    }

    private var labelWidth: CGFloat {
        useMinutePrecision ? 42 : 36
    }

    private func visibleTicks(for width: CGFloat) -> [Int] {
        guard labelTickMinutes.count > 2 else { return labelTickMinutes }

        let minSpacing = labelWidth + 4
        var visible: [Int] = []
        let first = labelTickMinutes.first ?? bounds.lowerBound
        let last = labelTickMinutes.last ?? bounds.upperBound

        visible.append(first)
        var lastX = x(for: first, width: width)
        let lastTickX = x(for: last, width: width)

        for tick in labelTickMinutes.dropFirst().dropLast() {
            let currentX = x(for: tick, width: width)
            if currentX - lastX >= minSpacing && lastTickX - currentX >= (labelWidth / 2) {
                visible.append(tick)
                lastX = currentX
            }
        }

        if visible.last != last {
            visible.append(last)
        }
        return visible
    }

    private func labelCenterX(for minute: Int, width: CGFloat) -> CGFloat {
        let center = x(for: minute, width: width)
        let half = labelWidth / 2
        return min(max(half, center), max(half, width - half))
    }

    private func x(for minute: Int, width: CGFloat) -> CGFloat {
        let clamped = max(bounds.lowerBound, min(bounds.upperBound, minute))
        let span = max(1, bounds.upperBound - bounds.lowerBound)
        return width * CGFloat(clamped - bounds.lowerBound) / CGFloat(span)
    }

    private func formatMinute(_ minute: Int) -> String {
        let h = minute / 60
        let m = minute % 60
        if useMinutePrecision {
            return String(format: "%02d:%02d", h, m)
        }
        return String(format: "%02d:00", h)
    }
}

private struct ManualDurationEditor: View {
    @Binding var seconds: Int
    let accent: Color
    @State private var hours: Int = 0
    @State private var minutes: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Stepper(value: $hours, in: 0...24, step: 1) {
                Text("\(hours) h")
                    .font(.subheadline.weight(.semibold))
            }
            .onChange(of: hours) { _, _ in sync() }
            Stepper(value: $minutes, in: 0...59, step: 1) {
                Text("\(minutes) m")
                    .font(.subheadline.weight(.semibold))
            }
            .onChange(of: minutes) { _, _ in sync() }
        }
        .onAppear { split() }
        .onChange(of: seconds) { _, _ in split() }
    }

    private func sync() {
        seconds = max(0, hours * 3600 + minutes * 60)
    }

    private func split() {
        let s = max(0, seconds)
        hours = s / 3600
        minutes = (s % 3600) / 60
    }
}

private struct HHMMMinuteInput: View {
    @Binding var minuteOfDay: Int
    private var hasValue: Binding<Bool>?
    let accent: Color

    @State private var hourText = ""
    @State private var minuteText = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case hour
        case minute
    }

    init(minuteOfDay: Binding<Int>, accent: Color) {
        self._minuteOfDay = minuteOfDay
        self.hasValue = nil
        self.accent = accent
    }

    init(minuteOfDay: Binding<Int>, hasValue: Binding<Bool>, accent: Color) {
        self._minuteOfDay = minuteOfDay
        self.hasValue = hasValue
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("hh", text: $hourText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .hour)
                .frame(width: 38)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
                .onChange(of: hourText) { _, newValue in
                    let digits = sanitizeDigits(newValue, maxLength: 2)
                    if digits != newValue {
                        hourText = digits
                        return
                    }
                    if hasValue != nil {
                        hasValue?.wrappedValue = !(hourText.isEmpty && minuteText.isEmpty)
                    }
                    sync()
                }

            Text(":")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            TextField("mm", text: $minuteText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .minute)
                .frame(width: 38)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
                .onChange(of: minuteText) { _, newValue in
                    let digits = sanitizeDigits(newValue, maxLength: 2)
                    if digits != newValue {
                        minuteText = digits
                        return
                    }
                    if hasValue != nil {
                        hasValue?.wrappedValue = !(hourText.isEmpty && minuteText.isEmpty)
                    }
                    sync()
                }
        }
        .onAppear { split() }
        .onChange(of: minuteOfDay) { _, _ in
            guard focusedField == nil else { return }
            split()
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                if hasValue != nil {
                    hasValue?.wrappedValue = !(hourText.isEmpty && minuteText.isEmpty)
                }
                split()
            }
        }
    }

    private func sanitizeDigits(_ value: String, maxLength: Int) -> String {
        String(value.filter(\.isNumber).prefix(maxLength))
    }

    private func sync() {
        if let hasValue, !hasValue.wrappedValue {
            return
        }
        var hours = min(24, Int(hourText) ?? 0)
        var minutes = min(59, Int(minuteText) ?? 0)
        if hours == 24 {
            minutes = 0
        }
        if minutes < 0 {
            minutes = 0
        }
        if hours < 0 {
            hours = 0
        }
        minuteOfDay = max(0, min(24 * 60, (hours * 60) + minutes))
    }

    private func split() {
        if let hasValue, !hasValue.wrappedValue {
            hourText = ""
            minuteText = ""
            return
        }
        let clamped = max(0, min(24 * 60, minuteOfDay))
        let hours = min(24, clamped / 60)
        let minutes = (hours == 24) ? 0 : min(59, clamped % 60)
        hourText = String(format: "%02d", hours)
        minuteText = String(format: "%02d", minutes)
    }
}

private struct HHMMInputDurationEditor: View {
    @Binding var seconds: Int
    let accent: Color

    @State private var hourText = "00"
    @State private var minuteText = "00"
    @FocusState private var focusedField: Field?

    private enum Field {
        case hour
        case minute
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("hh", text: $hourText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .hour)
                .frame(width: 42)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
                .onChange(of: hourText) { _, newValue in
                    let digits = sanitizeDigits(newValue, maxLength: 2)
                    if digits != newValue {
                        hourText = digits
                        return
                    }
                    sync()
                }

            Text(":")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            TextField("mm", text: $minuteText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .minute)
                .frame(width: 42)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
                .onChange(of: minuteText) { _, newValue in
                    let digits = sanitizeDigits(newValue, maxLength: 2)
                    if digits != newValue {
                        minuteText = digits
                        return
                    }
                    sync()
                }
        }
        .onAppear { split() }
        .onChange(of: seconds) { _, _ in
            guard focusedField == nil else { return }
            split()
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                split()
            }
        }
    }

    private func sanitizeDigits(_ value: String, maxLength: Int) -> String {
        String(value.filter(\.isNumber).prefix(maxLength))
    }

    private func sync() {
        let hours = min(24, Int(hourText) ?? 0)
        let minutes = min(59, Int(minuteText) ?? 0)
        seconds = max(0, (hours * 3600) + (minutes * 60))
    }

    private func split() {
        let clamped = max(0, seconds)
        let hours = min(24, clamped / 3600)
        let minutes = min(59, (clamped % 3600) / 60)
        hourText = String(format: "%02d", hours)
        minuteText = String(format: "%02d", minutes)
    }
}

#Preview("Day Editor") {
    // Preview using minimal static data (SwiftData previews removed)
    let today = Date().startOfDayLocal()
    let settings = Settings()
    return DayEditorView(date: today, settings: settings, onDaySaved: nil)
}
