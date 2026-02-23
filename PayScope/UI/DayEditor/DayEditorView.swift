import SwiftUI
import SwiftData

struct DayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayEntry.date) private var allEntries: [DayEntry]

    let date: Date
    @Bindable var settings: Settings

    @State private var selectedType: DayType = .work
    @State private var notes = ""
    @State private var showNotesEditor = false
    @State private var editSegments: [EditableSegment] = []
    @State private var totalBreakMinutes = 0
    @State private var isPauseCustom = false
    @State private var isApplyingLoad = false
    @State private var selectedDate = Date().startOfDayLocal()
    @State private var manualWorkedSeconds: Int = 0
    @State private var creditedOverrideSeconds: Int?
    @State private var editingShortcutIndex: Int?
    @State private var shortcutDraftStartMinute: Int = 9 * 60
    @State private var shortcutDraftEndMinute: Int = 17 * 60
    @State private var selectedSheetDetent: PresentationDetent = .fraction(0.55)

    @AppStorage("dayEditorShiftShortcut1") private var shiftShortcut1 = ""
    @AppStorage("dayEditorShiftShortcut2") private var shiftShortcut2 = ""
    @AppStorage("dayEditorShiftShortcut3") private var shiftShortcut3 = ""

    private let service = CalculationService()

    private var timelineBounds: ClosedRange<Int> {
        let minValue = max(0, min(settings.timelineMinMinute ?? 6 * 60, 23 * 60))
        let maxValue = max(minValue + 60, min(settings.timelineMaxMinute ?? 22 * 60, 24 * 60))
        return minValue...maxValue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    topTimeline
                    segmentsPanel
                    notesButtonPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle(PayScopeFormatters.day.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        DatePicker(
                            "",
                            selection: selectedDayBinding,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                        Menu {
                            ForEach(DayType.allCases) { type in
                                Button {
                                    selectedType = type
                                } label: {
                                    Label {
                                        Text(type.label)
                                            .foregroundStyle(type.tint)
                                    } icon: {
                                        Image(systemName: type.icon)
                                            .foregroundStyle(type.tint)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: selectedType.icon)
                                .foregroundStyle(selectedType.tint)
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityLabel("Tagestyp")
                    }
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
                load(for: selectedDate)
                selectedSheetDetent = defaultEditorDetent(for: selectedType)
            }
            .onChange(of: selectedDate) { _, newValue in
                load(for: newValue)
            }
            .onChange(of: selectedType) { oldType, _ in
                selectedSheetDetent = defaultEditorDetent(for: selectedType)
                if isApplyingLoad { return }
                if selectedType == .manual {
                    if oldType != .manual {
                        manualWorkedSeconds = max(0, totalNetSeconds)
                    }
                    creditedOverrideSeconds = nil
                    editSegments = []
                    totalBreakMinutes = 0
                    isPauseCustom = false
                    return
                }
                if isCreditedType {
                    totalBreakMinutes = 0
                    isPauseCustom = false
                    if !isCredited(oldType) {
                        creditedOverrideSeconds = nil
                    }
                    applyAutoCreditedSegmentIfNeeded(force: true)
                    return
                }
                if isCredited(oldType) {
                    creditedOverrideSeconds = nil
                }
                applyAutoCreditedSegmentIfNeeded()
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
            return [.fraction(0.55), .large]
        }
        return [.fraction(0.5), .large]
    }

    private func defaultEditorDetent(for type: DayType) -> PresentationDetent {
        type == .work ? .fraction(0.55) : .fraction(0.5)
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
                toolbarMetricPill(value: PayScopeFormatters.hhmmString(seconds: (usesManualDurationInput ? 0 : (selectedType == .work ? totalBreakMinutes * 60 : 0))), title: "Pause")
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

    private var topTimeline: some View {
        MultiSegmentTimelinePreview(
            segments: editSegments,
            accent: settings.themeAccent.color,
            bounds: timelineBounds
        )
        .padding(.vertical, 4)
    }

    private var segmentsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedType == .manual {
                Text("Manuell")
                    .font(.headline.weight(.semibold))
            }

            if usesManualDurationInput {
                // Manual duration editor HH:MM
                HStack(spacing: 12) {
                    Text("Dauer")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    // Simple steppers for hours and minutes
                    ManualDurationEditor(seconds: $manualWorkedSeconds, accent: settings.themeAccent.color)
                }
                Text("Bei manueller Erfassung wird keine Pause abgezogen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !usesManualDurationInput && !isCreditedType {
                HStack {
                    Text("Segmente")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button {
                        addDefaultSegment()
                    } label: {
                        Label("Neu", systemImage: "plus.circle.fill")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }

                if editSegments.isEmpty {
                    VStack(spacing: 8) {
                        Button {
                            addDefaultSegment()
                        } label: {
                            Label("Segment hinzufügen", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.payScopePrimary(accent: settings.themeAccent.color))

                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { index in
                                Button {
                                    onShortcutTap(index: index)
                                } label: {
                                    Text(shortcutButtonLabel(for: index))
                                        .font(.footnote.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(settings.themeAccent.color)
                                )
                                .foregroundStyle(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(settings.themeAccent.color.opacity(0.25), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                List {
                    ForEach($editSegments, id: \.id) { $segment in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                HHMMMinuteInput(
                                    minuteOfDay: minuteBinding(segment: $segment, isStart: true),
                                    accent: settings.themeAccent.color
                                )
                                Spacer()

                                Text(segment.durationLabel)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(settings.themeAccent.color)
                                    .frame(minWidth: 72, alignment: .center)
                                
                                Spacer()
                                
                                HHMMMinuteInput(
                                    minuteOfDay: minuteBinding(segment: $segment, isStart: false),
                                    accent: settings.themeAccent.color
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)

                            if let error = segment.validationMessage {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(12)
                        .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 16, emphasis: 0.28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                removeSegment(segment.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                
                PauseInlineEditor(
                    breakMinutes: $totalBreakMinutes,
                    isPauseCustom: $isPauseCustom,
                    suggestedBreakMinutes: automaticBreakMinutes(forDurationMinutes: totalGrossSeconds / 60),
                    accent: settings.themeAccent.color
                )

                if let breakValidationMessage {
                    Text(breakValidationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if isCreditedType {
                VStack(alignment: .center, spacing: 10) {
                    Text("Dieser Typ wird automatisch mit der 13-Wochen-Regel berechnet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Schichtlänge: \(PayScopeFormatters.hhmmString(seconds: totalNetSeconds))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(settings.themeAccent.color)

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
                            applyAutoCreditedSegmentIfNeeded(force: true)
                        }
                        .buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
                    } else {
                        Button("Abweichung angeben") {
                            creditedOverrideSeconds = creditedBaselineSeconds()
                            applyAutoCreditedSegmentIfNeeded(force: true)
                        }
                        .buttonStyle(.payScopeSecondary(accent: settings.themeAccent.color))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .neoPanel(accent: settings.themeAccent.color)
    }

    private var notesButtonPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showNotesEditor {
                HStack {
                    Text("Notizen")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button {
                        notes = ""
                        showNotesEditor = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Notizen ausblenden")
                }

                TextEditor(text: $notes)
                    .frame(minHeight: 70)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .payScopeSurface(accent: settings.themeAccent.color, cornerRadius: 12, emphasis: 0.2)
            } else {
                Button {
                    showNotesEditor = true
                } label: {
                    Label("Notizen", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.payScopePrimary(accent: settings.themeAccent.color))
            }
        }
    }

    private var totalNetSeconds: Int {
        if usesManualDurationInput {
            return max(0, manualWorkedSeconds)
        }
        if selectedType == .work {
            return max(0, totalGrossSeconds - (totalBreakMinutes * 60))
        } else {
            return totalGrossSeconds
        }
    }

    private var totalGrossSeconds: Int {
        editSegments.reduce(0) { $0 + (max(0, $1.grossDurationMinutes) * 60) }
    }

    private var isCreditedType: Bool {
        selectedType == .vacation || selectedType == .holiday || selectedType == .sick
    }

    private var usesManualDurationInput: Bool {
        selectedType == .manual
    }

    private var previewComputation: ComputationResult {
        let preview = DayEntry(date: selectedDate.startOfDayLocal(), type: selectedType, notes: notes)
        preview.creditedOverrideSeconds = isCreditedType ? creditedOverrideSeconds.map { max(0, $0) } : nil
        if usesManualDurationInput {
            preview.manualWorkedSeconds = max(0, manualWorkedSeconds)
            preview.segments = []
            return service.dayComputation(for: preview, allEntries: allEntries, settings: settings)
        }
        let clampedBreakSeconds = (selectedType == .work) ? max(0, min(totalBreakMinutes * 60, totalGrossSeconds)) : 0
        var didAssignBreak = false

        preview.segments = editSegments.compactMap { segment in
            guard let start = dateAtMinute(segment.startMinute), let end = dateAtMinute(segment.endMinute) else { return nil }
            let breakSeconds = didAssignBreak ? 0 : clampedBreakSeconds
            didAssignBreak = true
            return TimeSegment(start: start, end: end, breakSeconds: breakSeconds)
        }

        return service.dayComputation(for: preview, allEntries: allEntries, settings: settings)
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

    private func addDefaultSegment() {
        let start = max(timelineBounds.lowerBound, 9 * 60)
        let end = max(start + 60, min(timelineBounds.upperBound, 17 * 60))
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            editSegments.append(EditableSegment(startMinute: start, endMinute: end))
        }
    }

    private func removeSegment(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            editSegments.removeAll { $0.id == id }
        }
        if editSegments.isEmpty {
            totalBreakMinutes = 0
            isPauseCustom = false
        }
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
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            editSegments.append(EditableSegment(startMinute: clamped.startMinute, endMinute: clamped.endMinute))
        }
    }

    private func saveShortcutDraft() {
        guard let index = editingShortcutIndex else { return }
        let shortcut = clampedShortcut(ShiftShortcut(startMinute: shortcutDraftStartMinute, endMinute: shortcutDraftEndMinute))
        setShortcut(shortcut, at: index)
        applyShortcut(shortcut)
        editingShortcutIndex = nil
    }

    private func shortcutButtonLabel(for index: Int) -> String {
        guard let shortcut = shiftShortcut(at: index) else {
            return "S\(index + 1) speichern"
        }
        return "\(formatMinute(shortcut.startMinute))-\(formatMinute(shortcut.endMinute))"
    }

    private func shiftShortcut(at index: Int) -> ShiftShortcut? {
        let raw: String
        switch index {
        case 0: raw = shiftShortcut1
        case 1: raw = shiftShortcut2
        case 2: raw = shiftShortcut3
        default: return nil
        }
        return ShiftShortcut(rawValue: raw)
    }

    private func setShortcut(_ shortcut: ShiftShortcut, at index: Int) {
        switch index {
        case 0: shiftShortcut1 = shortcut.rawValue
        case 1: shiftShortcut2 = shortcut.rawValue
        case 2: shiftShortcut3 = shortcut.rawValue
        default: return
        }
    }

    private func clampedShortcut(_ shortcut: ShiftShortcut) -> ShiftShortcut {
        let start = max(timelineBounds.lowerBound, min(timelineBounds.upperBound - 1, shortcut.startMinute))
        let end = min(timelineBounds.upperBound, max(start + 1, shortcut.endMinute))
        return ShiftShortcut(startMinute: start, endMinute: end)
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

    private var isSaveValid: Bool {
        if isCreditedType {
            return true
        }
        if usesManualDurationInput {
            return manualWorkedSeconds > 0
        }
        return editSegments.allSatisfy { $0.validationMessage == nil } && breakValidationMessage == nil
    }

    private var breakValidationMessage: String? {
        // Only validate breaks for work days
        guard selectedType == .work else { return nil }
        guard totalGrossSeconds > 0 else { return nil }
        if totalBreakMinutes < 0 {
            return "Pause darf nicht negativ sein."
        }
        if totalBreakMinutes * 60 > totalGrossSeconds {
            return "Pause ist länger als die gesamte Dauer."
        }
        return nil
    }

    private var selectedDayBinding: Binding<Date> {
        Binding(
            get: { selectedDate },
            set: { selectedDate = $0.startOfDayLocal() }
        )
    }

    private func load(for dayDate: Date) {
        isApplyingLoad = true
        defer { isApplyingLoad = false }

        if let existing = allEntries.first(where: { $0.date.isSameLocalDay(as: dayDate) }) {
            selectedType = existing.type
            notes = existing.notes
            showNotesEditor = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let fallbackManualFromSegments = max(
                0,
                existing.segments.reduce(0) { partial, segment in
                    let duration = max(0, Int(segment.end.timeIntervalSince(segment.start)))
                    return partial + max(0, duration - max(0, segment.breakSeconds))
                }
            )
            if selectedType == .manual {
                manualWorkedSeconds = max(0, existing.manualWorkedSeconds ?? fallbackManualFromSegments)
            } else if isCreditedType {
                manualWorkedSeconds = 0
                creditedOverrideSeconds = existing.creditedOverrideSeconds.map { max(0, $0) }
            } else {
                manualWorkedSeconds = 0
                creditedOverrideSeconds = nil
            }
            if usesManualDurationInput {
                editSegments = []
                totalBreakMinutes = 0
                isPauseCustom = false
            } else {
                if selectedType == .work, existing.segments.isEmpty, let legacyManualSeconds = existing.manualWorkedSeconds, legacyManualSeconds > 0 {
                    let startMinute = timelineBounds.lowerBound
                    let roundedMinutes = max(0, Int((Double(legacyManualSeconds) / 60.0).rounded()))
                    let endMinute = min(24 * 60, startMinute + roundedMinutes)
                    editSegments = [EditableSegment(startMinute: startMinute, endMinute: endMinute)]
                } else {
                    editSegments = existing.segments.map {
                        let rawStart = minuteOfDay(from: $0.start)
                        let rawEnd = minuteOfDay(from: $0.end)
                        let clampedStart = max(timelineBounds.lowerBound, min(timelineBounds.upperBound - 1, rawStart))
                        let clampedEnd = min(timelineBounds.upperBound, max(clampedStart, rawEnd))
                        return EditableSegment(startMinute: clampedStart, endMinute: clampedEnd)
                    }
                }
                totalBreakMinutes = max(0, existing.segments.reduce(0) { $0 + max(0, $1.breakSeconds) } / 60)
                isPauseCustom = totalBreakMinutes != automaticBreakMinutes(forDurationMinutes: totalGrossSeconds / 60)
                applyAutoCreditedSegmentIfNeeded(force: false)
            }
            if isCreditedType {
                applyAutoCreditedSegmentIfNeeded(force: true)
            }
        } else {
            selectedType = .work
            notes = ""
            showNotesEditor = false
            editSegments = []
            totalBreakMinutes = 0
            isPauseCustom = false
            manualWorkedSeconds = 0
            creditedOverrideSeconds = nil
        }
    }

    private func applyAutoCreditedSegmentIfNeeded(force: Bool = true) {
        guard isCreditedType else { return }
        guard force || editSegments.isEmpty else { return }
        let seconds = max(0, creditedOverrideSeconds ?? creditedBaselineSeconds())

        let startMinute = timelineBounds.lowerBound
        let roundedMinutes = max(0, Int((Double(seconds) / 60.0).rounded()))
        let endMinute = min(24 * 60, startMinute + roundedMinutes)
        totalBreakMinutes = 0
        isPauseCustom = false
        editSegments = [EditableSegment(startMinute: startMinute, endMinute: endMinute)]
    }

    private func save() {
        let dayDate = selectedDate.startOfDayLocal()
        let isTodaySave = dayDate.isSameLocalDay(as: Date().startOfDayLocal())
        let existing = allEntries.first(where: { $0.date.isSameLocalDay(as: dayDate) })
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if selectedType == .work, editSegments.isEmpty, trimmedNotes.isEmpty {
            if let existing {
                modelContext.delete(existing)
                refreshFollowingAutoCreditedEntries(changedFrom: dayDate)
                modelContext.persistIfPossible()

                if isTodaySave {
                    let entriesForSync = allEntries.filter { $0 !== existing }
                    Task { @MainActor in
                        await PayScopeLiveActivityManager.syncAtAppLaunch(
                            settings: settings,
                            entries: entriesForSync
                        )
                    }
                }
            }

            dismiss()
            return
        }

        let target = existing ?? {
            let newEntry = DayEntry(date: dayDate)
            modelContext.insert(newEntry)
            return newEntry
        }()

        target.date = dayDate
        target.type = selectedType
        target.notes = notes

        target.segments.removeAll()
        if isCreditedType {
            target.manualWorkedSeconds = nil
            target.creditedOverrideSeconds = creditedOverrideSeconds.map { max(0, $0) }
            let seconds = resolvedCreditedSeconds(for: target)
            applyAutoCreditedSegment(for: target, seconds: seconds)
        } else if usesManualDurationInput {
            target.creditedOverrideSeconds = nil
            target.manualWorkedSeconds = max(0, manualWorkedSeconds)
        } else {
            target.creditedOverrideSeconds = nil
            target.manualWorkedSeconds = nil
            let clampedBreakSeconds = (selectedType == .work) ? max(0, min(totalBreakMinutes * 60, totalGrossSeconds)) : 0
            var didAssignBreak = false
            for segment in editSegments {
                guard let start = dateAtMinute(segment.startMinute), let end = dateAtMinute(segment.endMinute) else { continue }
                let breakSeconds = didAssignBreak ? 0 : clampedBreakSeconds
                target.segments.append(TimeSegment(start: start, end: end, breakSeconds: breakSeconds))
                didAssignBreak = true
            }
        }

        // Recompute following auto-managed credited days (vacation/holiday/sick) when history changed.
        refreshFollowingAutoCreditedEntries(changedFrom: dayDate)

        modelContext.persistIfPossible()

        if isTodaySave {
            var entriesForSync = allEntries
            if !entriesForSync.contains(where: { $0 === target }) {
                entriesForSync.append(target)
            }
            Task { @MainActor in
                await PayScopeLiveActivityManager.syncAtAppLaunch(
                    settings: settings,
                    entries: entriesForSync
                )
            }
        }

        dismiss()
    }

    private func refreshFollowingAutoCreditedEntries(changedFrom changedDate: Date) {
        let candidates = allEntries
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
        guard !day.segments.isEmpty else { return true }
        guard day.segments.count == 1, let only = day.segments.first else { return false }
        guard only.breakSeconds == 0 else { return false }
        guard only.start.isSameLocalDay(as: day.date.startOfDayLocal()) else { return false }
        return minuteOfDay(from: only.start) == timelineBounds.lowerBound
    }

    private func applyAutoCreditedSegment(for day: DayEntry, seconds: Int) {
        day.segments.removeAll()
        let startMinute = timelineBounds.lowerBound
        let roundedMinutes = max(0, Int((Double(seconds) / 60.0).rounded()))
        let endMinute = min(24 * 60, startMinute + roundedMinutes)
        guard
            let start = dateAtMinute(startMinute, on: day.date),
            let end = dateAtMinute(endMinute, on: day.date)
        else { return }
        day.segments.append(TimeSegment(start: start, end: end, breakSeconds: 0))
    }

    private func automaticBreakMinutes(forDurationMinutes minutes: Int) -> Int {
        if minutes > (9 * 60) + 15 { return 45 }
        if minutes > (6 * 60) + 15 { return 30 }
        return 0
    }

    private var creditedOverrideBinding: Binding<Int> {
        Binding(
            get: { max(0, creditedOverrideSeconds ?? 0) },
            set: { creditedOverrideSeconds = max(0, $0) }
        )
    }

    private func creditedBaselineSeconds() -> Int {
        let probe = DayEntry(date: selectedDate.startOfDayLocal(), type: selectedType)
        let result = service.creditedResult(for: probe, allEntries: allEntries, settings: settings)
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
        let result = service.creditedResult(for: day, allEntries: allEntries, settings: settings)
        switch result {
        case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
            return valueSeconds
        case .error:
            return 0
        }
    }

    private func isCredited(_ type: DayType) -> Bool {
        type == .vacation || type == .holiday || type == .sick
    }

    private func minuteBinding(segment: Binding<EditableSegment>, isStart: Bool) -> Binding<Int> {
        Binding(
            get: {
                isStart ? segment.wrappedValue.startMinute : segment.wrappedValue.endMinute
            },
            set: { newMinute in
                var value = segment.wrappedValue
                if isStart {
                    value.startMinute = max(timelineBounds.lowerBound, min(value.endMinute - 1, newMinute))
                } else {
                    value.endMinute = min(timelineBounds.upperBound, max(value.startMinute + 1, newMinute))
                }
                if isCreditedType {
                    totalBreakMinutes = 0
                    isPauseCustom = false
                    segment.wrappedValue = value
                    return
                }
                let projectedGrossMinutes = editSegments.reduce(0) { partial, current in
                    let next = current.id == value.id ? value : current
                    return partial + max(0, next.grossDurationMinutes)
                }
                if !isPauseCustom {
                    totalBreakMinutes = automaticBreakMinutes(forDurationMinutes: projectedGrossMinutes)
                } else {
                    totalBreakMinutes = min(totalBreakMinutes, projectedGrossMinutes)
                }
                segment.wrappedValue = value
            }
        )
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

    init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]) else { return nil }
        self.startMinute = start
        self.endMinute = end
    }

    var rawValue: String {
        "\(startMinute)-\(endMinute)"
    }
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

private struct PauseInlineEditor: View {
    @Binding var breakMinutes: Int
    @Binding var isPauseCustom: Bool
    let suggestedBreakMinutes: Int
    let accent: Color

    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isEditing.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("Pause")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(breakMinutes) min")
                        .font(.subheadline.bold())
                    Image(systemName: "pencil")
                        .font(.caption.weight(.bold))
                }
            }
            .buttonStyle(.plain)

            if isEditing {
                HStack(spacing: 10) {
                    pauseStepButton(label: "-5", delta: -5)
                    pauseStepButton(label: "-1", delta: -1)
                    pauseStepButton(label: "+1", delta: 1)
                    pauseStepButton(label: "+5", delta: 5)
                }

                Button {
                    breakMinutes = suggestedBreakMinutes
                    isPauseCustom = false
                    isEditing = false
                } label: {
                    Label("Auto (\(suggestedBreakMinutes) min)", systemImage: "wand.and.stars")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.payScopeSecondary(accent: accent))
            }
        }
    }

    @ViewBuilder
    private func pauseStepButton(label: String, delta: Int) -> some View {
        Button {
            breakMinutes = max(0, min(180, breakMinutes + delta))
            isPauseCustom = true
        } label: {
            Text(label)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .foregroundStyle(delta > 0 ? .white : accent)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(delta > 0 ? accent.opacity(0.9) : accent.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(accent.opacity(delta > 0 ? 0.2 : 0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
    let accent: Color

    @State private var hourText = "00"
    @State private var minuteText = "00"

    var body: some View {
        HStack(spacing: 4) {
            TextField("hh", text: $hourText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
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
                    sync()
                }

            Text(":")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            TextField("mm", text: $minuteText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
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
                    sync()
                }
        }
        .onAppear { split() }
        .onChange(of: minuteOfDay) { _, _ in split() }
    }

    private func sanitizeDigits(_ value: String, maxLength: Int) -> String {
        String(value.filter(\.isNumber).suffix(maxLength))
    }

    private func sync() {
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

    var body: some View {
        HStack(spacing: 6) {
            TextField("hh", text: $hourText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
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
        .onChange(of: seconds) { _, _ in split() }
    }

    private func sanitizeDigits(_ value: String, maxLength: Int) -> String {
        String(value.filter(\.isNumber).suffix(maxLength))
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
    // Provide a temporary in-memory model container so @Query can resolve
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DayEntry.self, configurations: config)

    // Seed with a couple of example entries if desired
    let context = container.mainContext
    let today = Date().startOfDayLocal()
    let sample = DayEntry(date: today, type: .work)
    // Minimal segment so pay/preview has data
    if let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: today),
       let end = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: today) {
        sample.segments = [TimeSegment(start: start, end: end, breakSeconds: 30 * 60)]
    }
    context.insert(sample)

    // Basic settings instance
    var settings = Settings()
    settings.themeAccent = .blue

    return DayEditorView(
        date: today,
        settings: settings
    )
    .modelContainer(container)
}
