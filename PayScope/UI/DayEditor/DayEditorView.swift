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
            .navigationTitle(WageWiseFormatters.day.string(from: date))
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
            }
            .onChange(of: selectedDate) { _, newValue in
                load(for: newValue)
            }
            .onChange(of: selectedType) { _, _ in
                if isApplyingLoad { return }
                applyAutoCreditedSegmentIfNeeded()
            }
        }
        .wageWiseSheetSurface(accent: settings.themeAccent.color)
    }

    @ToolbarContentBuilder
    private var shiftComposerToolBar : some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            HStack {
                toolbarMetricPill(value: WageWiseFormatters.hhmmString(seconds: totalNetSeconds), title: "Dauer")
            }
            .frame(maxWidth: .infinity)
        }
        
        ToolbarSpacer(.flexible,placement: .bottomBar)
        
        ToolbarItem(placement: .bottomBar) {
            HStack {
                toolbarMetricPill(value: WageWiseFormatters.currencyString(cents: totalGrossPayCents), title: "Brutto")
            }
            .frame(maxWidth: .infinity)
        }
        
        ToolbarSpacer(.flexible,placement: .bottomBar)
        
        ToolbarItem(placement: .bottomBar) {
            HStack {
                toolbarMetricPill(value: WageWiseFormatters.hhmmString(seconds: totalBreakMinutes * 60), title: "Pause")
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
        /*.padding(.horizontal, 12)
        .padding(.vertical, 5)*/
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

            Text("Timeline ist die Übersicht, Details pro Segment darunter.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if editSegments.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.title2)
                        .foregroundStyle(settings.themeAccent.color)
                    Text("Noch keine Segmente")
                        .font(.subheadline.weight(.semibold))
                    Text("Starte mit einem Segment und forme dann Start und Ende.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        addDefaultSegment()
                    } label: {
                        Label("Segment hinzufügen", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.wageWisePrimary(accent: settings.themeAccent.color))
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(settings.themeAccent.color.opacity(0.35))
                )
            }

            ForEach($editSegments, id: \.id) { $segment in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Start")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        DatePicker(
                            "",
                            selection: timeBinding(segment: $segment, isStart: true),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .fixedSize()

                        Text(segment.durationLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(settings.themeAccent.color)
                            .fixedSize()

                        Text("Ende")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        DatePicker(
                            "",
                            selection: timeBinding(segment: $segment, isStart: false),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .fixedSize()
                    }
                    .padding(.horizontal, 2)

                    if let error = segment.validationMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(settings.themeAccent.color.opacity(0.24), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        editSegments.removeAll { $0.id == segment.id }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }

            if !isCreditedType {
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
            } else {
                Text("Für diesen Typ wird keine Pause berücksichtigt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                    .frame(minHeight: 90)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.thinMaterial)
                    )
            } else {
                Button {
                    showNotesEditor = true
                } label: {
                    Label("Notizen", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.wageWisePrimary(accent: settings.themeAccent.color))
            }
        }
    }

    private var totalNetSeconds: Int {
        max(0, totalGrossSeconds - (totalBreakMinutes * 60))
    }

    private var totalGrossSeconds: Int {
        editSegments.reduce(0) { $0 + (max(0, $1.grossDurationMinutes) * 60) }
    }

    private var isCreditedType: Bool {
        selectedType == .vacation || selectedType == .holiday || selectedType == .sick
    }

    private var previewComputation: ComputationResult {
        let preview = DayEntry(date: selectedDate.startOfDayLocal(), type: selectedType, notes: notes)
        let clampedBreakSeconds = isCreditedType ? 0 : max(0, min(totalBreakMinutes * 60, totalGrossSeconds))
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
        )
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
        editSegments.append(EditableSegment(startMinute: start, endMinute: end))
    }

    private var isSaveValid: Bool {
        editSegments.allSatisfy { $0.validationMessage == nil } && breakValidationMessage == nil
    }

    private var breakValidationMessage: String? {
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
            editSegments = existing.segments.map {
                let rawStart = minuteOfDay(from: $0.start)
                let rawEnd = minuteOfDay(from: $0.end)
                let clampedStart = max(timelineBounds.lowerBound, min(timelineBounds.upperBound - 1, rawStart))
                let clampedEnd = min(timelineBounds.upperBound, max(clampedStart + 1, rawEnd))
                return EditableSegment(startMinute: clampedStart, endMinute: clampedEnd)
            }
            totalBreakMinutes = max(0, existing.segments.reduce(0) { $0 + max(0, $1.breakSeconds) } / 60)
            isPauseCustom = totalBreakMinutes != automaticBreakMinutes(forDurationMinutes: totalGrossSeconds / 60)
            applyAutoCreditedSegmentIfNeeded(force: false)
        } else {
            selectedType = .work
            notes = ""
            showNotesEditor = false
            editSegments = []
            totalBreakMinutes = 0
            isPauseCustom = false
        }
    }

    private func applyAutoCreditedSegmentIfNeeded(force: Bool = true) {
        guard selectedType == .vacation || selectedType == .holiday || selectedType == .sick else { return }
        guard force || editSegments.isEmpty else { return }

        let probe = DayEntry(date: selectedDate.startOfDayLocal(), type: selectedType)
        let result = service.creditedResult(for: probe, allEntries: allEntries, settings: settings)
        let seconds: Int
        switch result {
        case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
            seconds = valueSeconds
        case .error:
            seconds = 0
        }

        let startMinute = timelineBounds.lowerBound
        let roundedMinutes = max(0, Int((Double(seconds) / 60.0).rounded()))
        let endMinute = min(24 * 60, startMinute + roundedMinutes)
        totalBreakMinutes = 0
        isPauseCustom = false
        editSegments = endMinute > startMinute ? [EditableSegment(startMinute: startMinute, endMinute: endMinute)] : []
    }

    private func save() {
        let dayDate = selectedDate.startOfDayLocal()
        let target = allEntries.first(where: { $0.date.isSameLocalDay(as: dayDate) }) ?? {
            let newEntry = DayEntry(date: dayDate)
            modelContext.insert(newEntry)
            return newEntry
        }()

        target.date = dayDate
        target.type = selectedType
        target.notes = notes
        target.manualWorkedSeconds = nil
        target.segments.removeAll()

        let clampedBreakSeconds = max(0, min(totalBreakMinutes * 60, totalGrossSeconds))
        var didAssignBreak = false

        for segment in editSegments {
            guard let start = dateAtMinute(segment.startMinute), let end = dateAtMinute(segment.endMinute) else { continue }
            let breakSeconds = didAssignBreak ? 0 : clampedBreakSeconds
            target.segments.append(TimeSegment(start: start, end: end, breakSeconds: breakSeconds))
            didAssignBreak = true
        }

        // Recompute following auto-managed credited days (vacation/holiday/sick) when history changed.
        refreshFollowingAutoCreditedEntries(changedFrom: dayDate)

        modelContext.persistIfPossible()
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
            let result = service.creditedResult(for: day, allEntries: allEntries, settings: settings)
            let seconds: Int
            switch result {
            case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
                seconds = valueSeconds
            case .error:
                seconds = 0
            }
            applyAutoCreditedSegment(for: day, seconds: seconds)
        }
    }

    private func isAutoManagedCreditedEntry(_ day: DayEntry) -> Bool {
        guard day.manualWorkedSeconds == nil else { return false }
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
        guard endMinute > startMinute else { return }
        guard
            let start = dateAtMinute(startMinute, on: day.date),
            let end = dateAtMinute(endMinute, on: day.date)
        else { return }
        day.segments.append(TimeSegment(start: start, end: end, breakSeconds: 0))
    }

    private func automaticBreakMinutes(forDurationMinutes minutes: Int) -> Int {
        if minutes > 9 * 60 { return 45 }
        if minutes > 6 * 60 { return 30 }
        return 0
    }

    private func timeBinding(segment: Binding<EditableSegment>, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minute = isStart ? segment.wrappedValue.startMinute : segment.wrappedValue.endMinute
                return dateFromMinute(minute)
            },
            set: { newDate in
                let minute = minuteOfDay(from: newDate)
                var value = segment.wrappedValue
                if isStart {
                    value.startMinute = max(timelineBounds.lowerBound, min(value.endMinute - 1, minute))
                } else {
                    value.endMinute = min(timelineBounds.upperBound, max(value.startMinute + 1, minute))
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

    private func dateFromMinute(_ minute: Int) -> Date {
        let clamped = max(0, min((24 * 60) - 1, minute))
        let h = clamped / 60
        let m = clamped % 60
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: selectedDate.startOfDayLocal())
            ?? selectedDate.startOfDayLocal()
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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.secondarySystemBackground).opacity(0.78),
                                accent.opacity(glow ? 0.15 : 0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(glow ? 0.45 : 0.24), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: accent.opacity(glow ? 0.24 : 0.12), radius: glow ? 16 : 8, x: 0, y: glow ? 8 : 4)
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
        if endMinute <= startMinute {
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

private struct MultiSegmentTimelinePreview: View {
    let segments: [EditableSegment]
    let accent: Color
    let bounds: ClosedRange<Int>

    private var tickMinutes: [Int] {
        let step = 120
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
        bounds.lowerBound % 60 != 0 || bounds.upperBound % 60 != 0 || tickMinutes.contains { $0 % 60 != 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(CGFloat(1), geo.size.width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(.tertiarySystemFill), accent.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 20)
                    .allowsHitTesting(false)

                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.75))
                        .frame(
                            width: max(2, x(for: segment.endMinute, width: width) - x(for: segment.startMinute, width: width)),
                            height: 20
                        )
                        .offset(x: x(for: segment.startMinute, width: width))
                        .shadow(color: accent.opacity(0.35), radius: 6, x: 0, y: 0)
                        .allowsHitTesting(false)
                }

                ForEach(Array(tickMinutes.enumerated()), id: \.offset) { _, tick in
                    Rectangle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 1, height: 20)
                        .offset(x: x(for: tick, width: width))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 32)

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
        .frame(height: 14)
    }

    private var labelWidth: CGFloat {
        useMinutePrecision ? 42 : 36
    }

    private func visibleTicks(for width: CGFloat) -> [Int] {
        guard tickMinutes.count > 2 else { return tickMinutes }

        let minSpacing = labelWidth + 4
        var visible: [Int] = []
        let first = tickMinutes.first ?? bounds.lowerBound
        let last = tickMinutes.last ?? bounds.upperBound

        visible.append(first)
        var lastX = x(for: first, width: width)
        let lastTickX = x(for: last, width: width)

        for tick in tickMinutes.dropFirst().dropLast() {
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
                    Button {
                        breakMinutes = max(0, breakMinutes - 5)
                        isPauseCustom = true
                    } label: {
                        Label("-5", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.wageWiseSecondary(accent: accent))

                    Button {
                        breakMinutes = min(180, breakMinutes + 5)
                        isPauseCustom = true
                    } label: {
                        Label("+5", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.wageWisePrimary(accent: accent))
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
                .buttonStyle(.wageWiseSecondary(accent: accent))
            }
        }
    }
}
