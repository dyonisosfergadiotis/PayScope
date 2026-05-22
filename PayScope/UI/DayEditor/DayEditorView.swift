import SwiftUI

struct DayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudKitService: CloudKitService
    private let localStore = LocalDayEntryStore.shared

    @State private var allEntries: [DayEntry] = []
    @State private var localEntries: [DayEntry] = []
    @State private var entryCache = DayEditorEntryCache()
    @State private var netWageConfigs: [NetWageMonthConfig] = []
    @State private var holidayDays: [HolidayCalendarDay] = []

    let date: Date
    @Bindable var settings: Settings
    var onDaySaved: ((Date, DayEntry?) -> Void)? = nil
    private let previewEntry: DayEntry?
    var calendarPreview: AnyView? = nil

    init(
        date: Date,
        settings: Settings,
        onDaySaved: ((Date, DayEntry?) -> Void)? = nil,
        previewEntry: DayEntry? = nil,
        calendarPreview: AnyView? = nil
    ) {
        self.date = date
        self.settings = settings
        self.onDaySaved = onDaySaved
        self.previewEntry = previewEntry
        self.calendarPreview = calendarPreview

        _selectedDate = State(initialValue: date.startOfDayLocal())

        guard let previewEntry else { return }

        _selectedType = State(initialValue: previewEntry.type)
        _manualWorkedSeconds = State(initialValue: max(0, previewEntry.manualWorkedSeconds ?? 0))
        _creditedOverrideSeconds = State(initialValue: previewEntry.creditedOverrideSeconds.map { max(0, $0) })

        if let shiftStart = previewEntry.shiftStart {
            _startMinute = State(initialValue: Self.previewMinuteOfDay(from: shiftStart))
            _hasStartMinute = State(initialValue: true)
        }

        if let shiftEnd = previewEntry.shiftEnd {
            _endMinute = State(initialValue: Self.previewMinuteOfDay(from: shiftEnd))
            _hasEndMinute = State(initialValue: true)
        }

        if previewEntry.type == .work {
            _manualBreakOverrideMinutes = State(initialValue: max(0, previewEntry.breakSeconds ?? 0) / 60)
        }
    }

    @State private var selectedType: DayType = .work

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
    @State private var isBreakEditorVisible = false
    @State private var categoryFeedbackTrigger = 0
    @State private var shortcutFeedbackTrigger = 0
    @State private var saveFeedbackTrigger = 0
    @State private var deleteFeedbackTrigger = 0

    private var settingsShortcut1: String { settings.shiftShortcut1 }
    private var settingsShortcut2: String { settings.shiftShortcut2 }
    private var settingsShortcut3: String { settings.shiftShortcut3 }
    private var settingsShortcutName1: String { settings.shiftShortcutName1 ?? "" }
    private var settingsShortcutName2: String { settings.shiftShortcutName2 ?? "" }
    private var settingsShortcutName3: String { settings.shiftShortcutName3 ?? "" }

    private let service = CalculationService()
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static func previewMinuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    @State private var isLoading = false
    @State private var pendingLoadAfterCurrentCycle = false
    @State private var hasUnsavedUserChanges = false

    private var timelineBounds: ClosedRange<Int> {
        let minValue = 0
        let maxValue = ShiftTimeRange.minutesPerDay
        return minValue...maxValue
    }

    private var allEntriesEffective: [DayEntry] {
        entryCache.effectiveEntries
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
        dayEditorRoot
            .dayEditorSheetSurface()
            .presentationDetents(editorDetents, selection: $selectedSheetDetent)
            .presentationDragIndicator(.visible)
            .sensoryFeedback(.selection, trigger: categoryFeedbackTrigger)
            .sensoryFeedback(.selection, trigger: shortcutFeedbackTrigger)
            .sensoryFeedback(.success, trigger: saveFeedbackTrigger)
            .sensoryFeedback(.warning, trigger: deleteFeedbackTrigger)
            .sheet(isPresented: isEditingShortcutBinding) {
                shortcutEditorSheet
            }
    }

    private var dayEditorRoot: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayEditorHeader
                dayEditorScrollContent
            }
            .opacity(hasAnimatedIn ? 1 : 0)
            .offset(y: hasAnimatedIn ? 0 : 14)
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: hasAnimatedIn)
            .navigationTitle(dayEditorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .bottomBar)
            .toolbar {
                dayEditorToolbar
            }
        }
        .onAppear(perform: handleAppear)
        .onChange(of: selectedDate) { _, newValue in handleSelectedDateChange(newValue) }
        .onChange(of: selectedType) { _, _ in handleSelectedTypeChange() }
        .onChange(of: startMinute) { _, _ in handleShiftTimeChange() }
        .onChange(of: endMinute) { _, _ in handleShiftTimeChange() }
        .onChange(of: hasStartMinute) { _, _ in handleShiftTimeChange() }
        .onChange(of: hasEndMinute) { _, _ in handleShiftTimeChange() }
        .onChange(of: manualWorkedSeconds) { _, _ in markUnsavedUserChanges() }
        .onChange(of: creditedOverrideSeconds) { _, _ in markUnsavedUserChanges() }
        .onChange(of: manualBreakOverrideMinutes) { _, _ in markUnsavedUserChanges() }
        .onChange(of: entriesSignature) { _, _ in handleEntriesSignatureChange() }
        .alert("Tag löschen?", isPresented: $showDeleteConfirm) {
            Button("Löschen", role: .destructive) {
                deleteCurrentDay()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Dieser Tag wird dauerhaft entfernt.")
        }
    }

    private var dayEditorScrollContent: some View {
        let geometry = PayScopeModalGeometry.sheet

        return ScrollView {
            VStack(spacing: 16) {
                shiftEditorContent
                if selectedType == .work {
                    shortcutPanel
                }
            }
            .padding(.horizontal, geometry.edgePadding)
            .padding(.top, geometry.edgePadding)
            .padding(.bottom, 24)
        }
    }

    @ToolbarContentBuilder
    private var dayEditorToolbar: some ToolbarContent {
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
        
        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                save()
            } label: {
                Image(systemName: "checkmark")
            }
            .disabled(!isSaveValid)
            .accessibilityLabel("Speichern")
        }
    }

    private func handleAppear() {
        selectedDate = date.startOfDayLocal()
        hasUnsavedUserChanges = false
        if previewEntry == nil {
            Task { await load(for: selectedDate) }
        }
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

    private func handleSelectedDateChange(_ newValue: Date) {
        hasUnsavedUserChanges = false
        Task { await load(for: newValue) }
    }

    private func handleSelectedTypeChange() {
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

    private func handleShiftTimeChange() {
        markUnsavedUserChanges()
        clampManualBreakOverride()
    }

    private func markUnsavedUserChanges() {
        if !isApplyingLoad {
            hasUnsavedUserChanges = true
        }
    }

    private func handleEntriesSignatureChange() {
        // Query results can arrive after .onAppear; only auto-reload while no local draft exists.
        if isLoading || isApplyingLoad || hasLocalDraftData || hasUnsavedUserChanges { return }
        Task { await load(for: selectedDate) }
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

    

    private var categoryAccent: Color {
        settings.categoryColor(for: selectedType)
    }

    private var dayNumberLabel: String {
        "\(Calendar.current.component(.day, from: selectedDate))"
    }

    private var weekdayLabel: String {
        Self.weekdayFormatter.string(from: selectedDate)
    }

    private var monthYearLabel: String {
        Self.monthYearFormatter.string(from: selectedDate)
    }

    private var dayEditorTitle: String {
        (previewEntry != nil || hasExistingEntryForSelectedDate) ? "Tag bearbeiten" : "Tag hinzufügen"
    }

    private var crossesIntoNextDay: Bool {
        shiftTimeRange?.crossesMidnight == true
    }

    private var dayEditorHeader: some View {
        let geometry = PayScopeModalGeometry.sheet

        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 12) {
                Text(dayNumberLabel)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(categoryAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .payScopeNumericTransition(value: dayNumberLabel)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                    Text( selectedType.label)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .payScopeTextTransition(value: weekdayLabel)
                    }.foregroundStyle(categoryAccent)


                    
                    Text(monthYearLabel)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                            .payScopeTextTransition(value: selectedType)

                                            
                }

                Spacer(minLength: 12)

                Text(weekdayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .payScopeTextTransition(value: monthYearLabel)
            }

            categorySelectorRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .payScopeGlassSurface(accent: categoryAccent, cornerRadius: geometry.innerCornerRadius, tintOpacity: 0.045, shadowOpacity: 0.055)
        .padding(.horizontal, geometry.edgePadding)
        .padding(.top, geometry.edgePadding)
    }

    private var categorySelectorRow: some View {
        HStack(spacing: 7) {
            ForEach(DayType.allCases) { type in
                Button {
                    if selectedType != type {
                        categoryFeedbackTrigger += 1
                    }
                    selectedType = type
                } label: {
                    Image(systemName: type.icon)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(
                    ShiftCategoryButtonStyle(
                        selectedAccent: categoryAccent,
                        categoryAccent: settings.categoryColor(for: type),
                        isSelected: type == selectedType
                    )
                )
                .accessibilityLabel(type.label)
            }
        }
    }

    @ViewBuilder
    private var shiftEditorContent: some View {
        if usesManualDurationInput {
            manualDurationPanel
        } else if isCreditedType {
            creditedDurationPanel
        } else {
            workTimePanel
        }
    }

    private var workTimePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 6) {
                timeEndpointColumn(
                    title: "Start",
                    minute: $startMinute,
                    hasValue: $hasStartMinute,
                    stackAlignment: .leading,
                    frameAlignment: .leading
                )

                VStack(spacing: 5) {
                        Text(grossDurationBadgeLabel + " h")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(categoryAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .payScopeNumericTransition(value: grossDurationBadgeLabel)

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: 50)

                timeEndpointColumn(
                    title: "Ende",
                    minute: $endMinute,
                    hasValue: $hasEndMinute,
                    stackAlignment: .trailing,
                    frameAlignment: .trailing
                )
            }

            breakEditorRow

            if let error = shiftValidationMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .neoPanel(accent: categoryAccent)
    }

    private func timeEndpointColumn(
        title: String,
        minute: Binding<Int>,
        hasValue: Binding<Bool>,
        stackAlignment: HorizontalAlignment,
        frameAlignment: Alignment
    ) -> some View {
        VStack(alignment: stackAlignment, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HHMMMinuteInput(
                minuteOfDay: minute,
                hasValue: hasValue,
                accent: categoryAccent,
                isProminent: true
            )
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var breakEditorRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(categoryAccent)

                Text("\(breakMinutes) min")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .payScopeNumericTransition(value: breakMinutes)

                Spacer()

                Button {
                    openBreakEditor()
                } label: {
                    Image(systemName: isBreakEditorVisible ? "xmark" : "pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .payScopeGlassControl(accent: categoryAccent, cornerRadius: 12, tintOpacity: 0.07)
                .accessibilityLabel(isBreakEditorVisible ? "Pausenbearbeitung schließen" : "Pause bearbeiten")
            }

            if isBreakEditorVisible {
                breakAdjustmentControls
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .payScopeGlassControl(accent: categoryAccent, cornerRadius: 16, tintOpacity: 0.045, isInteractive: false)
    }

    @ViewBuilder
    private var breakAdjustmentControls: some View {
        ViewThatFits {
            HStack(spacing: 6) {
                breakAdjustmentButton(title: "-10", delta: -10)
                breakAdjustmentButton(title: "-5", delta: -5)
                breakAdjustmentButton(title: "-1", delta: -1)
                automaticBreakButton
                breakAdjustmentButton(title: "+1", delta: 1)
                breakAdjustmentButton(title: "+5", delta: 5)
                breakAdjustmentButton(title: "+10", delta: 10)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                spacing: 6
            ) {
                breakAdjustmentButton(title: "-10", delta: -10)
                breakAdjustmentButton(title: "-5", delta: -5)
                breakAdjustmentButton(title: "-1", delta: -1)
                automaticBreakButton
                breakAdjustmentButton(title: "+1", delta: 1)
                breakAdjustmentButton(title: "+5", delta: 5)
                breakAdjustmentButton(title: "+10", delta: 10)
            }
        }
    }

    private var automaticBreakButton: some View {
        Button("Auto") {
            manualBreakOverrideMinutes = nil
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.bold))
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .payScopeGlassControl(accent: categoryAccent, cornerRadius: 11, tintOpacity: 0.055)
    }

    private var shortcutPanel: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Button {
                    onShortcutTap(index: index)
                } label: {
                    Text(shortcutButtonLabel(for: index))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(categoryAccent)
                .payScopeGlassControl(accent: categoryAccent, cornerRadius: 14, tintOpacity: 0.06)
            }
        }
        .neoPanel(accent: categoryAccent)
    }

    private var manualDurationPanel: some View {
        HStack(spacing: 14) {
            Image(systemName: selectedType.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(categoryAccent)
                .frame(width: 30)

            Text("Dauer")
                .font(.headline.weight(.semibold))

            Spacer(minLength: 8)

            HHMMInputDurationEditor(
                seconds: $manualWorkedSeconds,
                accent: categoryAccent,
                isProminent: true
            )
        }
        .neoPanel(accent: categoryAccent)
    }

    private var creditedDurationPanel: some View {
        let metrics = currentPreviewMetrics

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: selectedType.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(categoryAccent)
                    .frame(width: 30)

                Text(selectedType == .work ? selectedType.label : "Dauer")
                    .font(.headline.weight(.semibold))
                    .payScopeTextTransition(value: selectedType)

                Spacer()
            }

            HStack(spacing: 12) {
                if creditedOverrideSeconds != nil {
                    HHMMInputDurationEditor(
                        seconds: creditedOverrideBinding,
                        accent: categoryAccent,
                        isProminent: true
                    )
                } else {
                    durationDisplayPill(PayScopeFormatters.hhmmString(seconds: metrics.netSeconds))
                }

                Spacer(minLength: 8)

                Button {
                    if creditedOverrideSeconds == nil {
                        creditedOverrideSeconds = creditedBaselineSeconds()
                    } else {
                        creditedOverrideSeconds = nil
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(creditedOverrideSeconds == nil ? "Abweichung" : "Zurücksetzen")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Image(systemName: creditedOverrideSeconds == nil ? "pencil" : "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(minWidth: 112)
                    .frame(height: 38)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
                .payScopeGlassControl(accent: categoryAccent, cornerRadius: 14, tintOpacity: 0.075)
                .accessibilityLabel(creditedOverrideSeconds == nil ? "Dauer anpassen" : "Anpassung entfernen")
            }
        }
        .neoPanel(accent: categoryAccent)
    }

    private func durationDisplayPill(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .payScopeNumericTransition(value: value)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .payScopeGlassControl(accent: categoryAccent, cornerRadius: 16, tintOpacity: 0.08, isInteractive: false)
    }

    private var currentPreviewMetrics: DayEditorPreviewMetrics {
        let result = previewComputation
        let netSeconds: Int
        let grossPayCents: Int

        switch result {
        case let .ok(valueSeconds, valueCents), let .warning(valueSeconds, valueCents, _):
            netSeconds = valueSeconds
            grossPayCents = valueCents
        case .error:
            netSeconds = 0
            grossPayCents = 0
        }

        return DayEditorPreviewMetrics(
            netSeconds: netSeconds,
            grossPayCents: grossPayCents,
            pauseSeconds: usesManualDurationInput ? 0 : (selectedType == .work ? breakMinutes * 60 : 0)
        )
    }

    private var totalGrossSeconds: Int {
        totalGrossMinutes * 60
    }

    private var totalGrossMinutes: Int {
        shiftTimeRange?.durationMinutes ?? 0
    }

    private var grossDurationBadgeLabel: String {
        guard totalGrossMinutes > 0 else { return "--:--" }
        let hoursPart = totalGrossMinutes / 60
        let minutePart = totalGrossMinutes % 60
        return String(format: "%02d:%02d", hoursPart, minutePart)
    }

    private var hasCompleteShiftTime: Bool {
        hasStartMinute && hasEndMinute
    }

    private var hasValidShiftRange: Bool {
        shiftTimeRange != nil
    }

    private var shiftTimeRange: ShiftTimeRange? {
        guard hasCompleteShiftTime else { return nil }
        return ShiftTimeRange(
            startMinute: ShiftTimeRange.normalizedClockMinute(startMinute),
            endClockMinute: endMinute
        )
    }

    private var timelinePreviewSegments: [EditableSegment] {
        guard let range = shiftTimeRange else { return [] }

        if range.crossesMidnight {
            var segments = [
                EditableSegment(startMinute: range.startMinute, endMinute: ShiftTimeRange.minutesPerDay)
            ]

            if range.endMinuteOffset > ShiftTimeRange.minutesPerDay {
                segments.append(
                    EditableSegment(
                        startMinute: 0,
                        endMinute: range.endClockMinute,
                        isNextDay: true
                    )
                )
            }

            return segments
        }

        return [
            EditableSegment(startMinute: range.startMinute, endMinute: range.endMinuteOffset)
        ]
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
        if selectedType != .work { return true }
        if usesManualDurationInput {
            return manualWorkedSeconds > 0
        }
        return hasStartMinute || hasEndMinute || breakMinutes > 0
    }

    private var entriesSignature: Int {
        entryCache.signature
    }

    private func rebuildEntryCaches() {
        let merged = Dictionary(
            (localEntries + allEntries).map { (dayKey($0.date), $0) },
            uniquingKeysWith: { existing, candidate in
                candidate.updatedAt > existing.updatedAt ? candidate : existing
            }
        )
        let effectiveEntries = merged.values.sorted { $0.date > $1.date }

        entryCache = DayEditorEntryCache(
            effectiveEntries: effectiveEntries,
            entriesByDate: service.makeEntriesByDateLookup(from: effectiveEntries),
            signature: signature(for: effectiveEntries)
        )
    }

    private func signature(for entries: [DayEntry]) -> Int {
        var hasher = Hasher()
        for day in entries {
            hasher.combine(day.date.timeIntervalSinceReferenceDate)
            hasher.combine(day.type.rawValue)
            hasher.combine(day.manualWorkedSeconds ?? -1)
            hasher.combine(day.creditedOverrideSeconds ?? -1)
            hasher.combine(day.shiftStart?.timeIntervalSinceReferenceDate ?? 0)
            hasher.combine(day.shiftEnd?.timeIntervalSinceReferenceDate ?? 0)
            hasher.combine(day.breakSeconds ?? -1)
        }
        return hasher.finalize()
    }

    private var previewComputation: ComputationResult {
        let preview = DayEntry(date: selectedDate.startOfDayLocal(), type: selectedType)
        preview.creditedOverrideSeconds = isCreditedType ? creditedOverrideSeconds.map { max(0, $0) } : nil
        if usesManualDurationInput {
            preview.manualWorkedSeconds = max(0, manualWorkedSeconds)
            return service.dayComputation(for: preview, entriesByDate: entryCache.entriesByDate, settings: settings)
        }
        let clampedBreakSeconds = (selectedType == .work) ? max(0, min(breakMinutes * 60, totalGrossSeconds)) : 0
        if let range = shiftTimeRange,
           let start = range.startDate(on: selectedDate),
           let end = range.endDate(on: selectedDate) {
            preview.shiftStart = start
            preview.shiftEnd = end
            preview.breakSeconds = clampedBreakSeconds
        }
        return service.dayComputation(for: preview, entriesByDate: entryCache.entriesByDate, settings: settings)
    }

    private func metricBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.bold))
                .payScopeNumericTransition(value: value)
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
                .payScopeNumericTransition(value: value)
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
        guard hasValidShiftRange else { return "Start und Ende dürfen nicht gleich sein." }
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
        rebuildEntryCaches()
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
        rebuildEntryCaches()

        // Use local entries to populate UI initially
        applyLoadedEntries(allEntriesEffective, for: dayDate)

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

        // If work but invalid shift, treat as delete.
        if selectedType == .work, !hasValidShiftRange {
            if existing != nil {
                let entriesAfterDelete = allEntriesEffective.filter { !$0.date.isSameLocalDay(as: dayDate) }
                hasUnsavedUserChanges = false
                onDaySaved?(dayDate, nil)
                deleteFeedbackTrigger += 1
                dismiss()

                deleteLegacyTips(on: dayDate)
                localStore.delete(on: dayDate)
                allEntries.removeAll { $0.date.isSameLocalDay(as: dayDate) }
                localEntries.removeAll { $0.date.isSameLocalDay(as: dayDate) }
                rebuildEntryCaches()
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
                    await AppleCalendarSyncService.shared.deleteEvent(for: dayDate)
                    do {
                        try await cloudKitService.deleteDayEntry(on: dayDate)
                    } catch {
                        #if DEBUG
                        print("CloudKit delete failed, local tombstone kept for retry: \(error)")
                        #endif
                    }
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
        target.notes = ""

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
            if let range = shiftTimeRange,
               let start = range.startDate(on: selectedDate),
               let end = range.endDate(on: selectedDate) {
                target.shiftStart = start
                target.shiftEnd = end
                target.breakSeconds = max(0, breakMinutes * 60)
            }
        }

        hasUnsavedUserChanges = false
        onDaySaved?(dayDate, target)
        saveFeedbackTrigger += 1
        dismiss()

        localStore.save(target)

        Task {
            refreshFollowingAutoCreditedEntries(changedFrom: dayDate)
            let mergedEntriesAfterSave = mergedEntriesReplacingDay(on: dayDate, with: target)
            await AppleCalendarSyncService.shared.sync(
                entry: target,
                allEntries: mergedEntriesAfterSave,
                settings: settings
            )

            do {
                try await cloudKitService.saveDayEntry(target)
                localStore.save(target)
                if isTodaySave {
                    await PayScopeLiveActivityManager.syncAtAppLaunch(
                        settings: settings,
                        entries: mergedEntriesAfterSave
                    )
                }
            } catch {
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
        deleteFeedbackTrigger += 1

        // Delete from local cache
        deleteLegacyTips(on: dayDate)
        localStore.delete(on: dayDate)
        allEntries.removeAll { $0.date.isSameLocalDay(as: dayDate) }
        localEntries.removeAll { $0.date.isSameLocalDay(as: dayDate) }
        rebuildEntryCaches()
        refreshFollowingAutoCreditedEntries(changedFrom: dayDate)

        Task {
            await AppleCalendarSyncService.shared.deleteEvent(for: dayDate)
            do {
                try await cloudKitService.deleteDayEntry(on: dayDate)
            } catch {
                #if DEBUG
                print("CloudKit delete failed, local tombstone kept for retry: \(error)")
                #endif
            }
        }

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

    private func deleteLegacyTips(on date: Date) {
        let tipsForDay = LocalTipEntryStore.shared
            .loadAll()
            .filter { $0.date.isSameLocalDay(as: date) }
        guard !tipsForDay.isEmpty else { return }

        for tip in tipsForDay {
            LocalTipEntryStore.shared.delete(tip)
            Task {
                do {
                    try await cloudKitService.deleteTipEntry(tip)
                } catch {
                    #if DEBUG
                    print("CloudKit legacy tip delete failed, local tombstone kept for retry: \(error)")
                    #endif
                }
            }
        }
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
        let result = service.dayComputation(for: probe, entriesByDate: entryCache.entriesByDate, settings: settings)
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
        let result = service.dayComputation(for: day, entriesByDate: entryCache.entriesByDate, settings: settings)
        switch result {
        case let .ok(valueSeconds, _), let .warning(valueSeconds, _, _):
            return valueSeconds
        case .error:
            return 0
        }
    }

    private func isEquivalentEntry(_ lhs: DayEntry, _ rhs: DayEntry) -> Bool {
        lhs.type == rhs.type &&
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
        .payScopeSheetSurface(accent: settings.themeAccent.color)
    }

    private func onShortcutTap(index: Int) {
        shortcutFeedbackTrigger += 1
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
            endMinute = clamped.endClockMinute
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
        return clampedShortcut(shortcut).displayRange
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
        let earliestStart = fallback.startMinute
        let latestEnd = fallback.endMinute
        let grossMinutes = fallback.durationMinutes
        let clampedBreakMinutes = selectedType == .work ? max(0, min(breakMinutes, grossMinutes)) : 0

        let shouldStoreRichTemplate = selectedType != .work || clampedBreakMinutes > 0

        guard shouldStoreRichTemplate else {
            return ShiftShortcut(startMinute: earliestStart, endMinute: latestEnd)
        }

        let payload = ShiftShortcutPayload(
            startMinute: earliestStart,
            endMinute: latestEnd,
            dayTypeRaw: selectedType.rawValue,
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
        endMinute = shortcut.endClockMinute
        hasStartMinute = true
        hasEndMinute = true
        inferManualBreakOverride(fromStoredBreakMinutes: max(0, min(shortcut.breakMinutes, shortcut.durationMinutes)))
    }

    private func clampedShortcut(_ shortcut: ShiftShortcut) -> ShiftShortcut {
        let range = normalizedShortcutRange(start: shortcut.startMinute, end: shortcut.endMinute)
        guard let payload = shortcut.payload else {
            return ShiftShortcut(startMinute: range.startMinute, endMinute: range.endMinuteOffset)
        }

        let earliestStart = range.startMinute
        let latestEnd = range.endMinuteOffset
        let dayType = (payload.dayTypeRaw.flatMap { DayType(rawValue: $0) }) ?? .work
        let grossMinutes = range.durationMinutes

        let normalizedPayload = ShiftShortcutPayload(
            startMinute: earliestStart,
            endMinute: latestEnd,
            dayTypeRaw: dayType.rawValue,
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

    private func normalizedShortcutRange(start: Int, end: Int) -> ShiftTimeRange {
        let clampedStart = max(0, min(ShiftTimeRange.minutesPerDay - 1, ShiftTimeRange.normalizedClockMinute(start)))

        if end >= ShiftTimeRange.minutesPerDay,
           let range = ShiftTimeRange(
            startMinute: clampedStart,
            endMinuteOffset: min(end, ShiftTimeRange.maxEndMinuteOffset)
           ) {
            return range
        }

        if let range = ShiftTimeRange(startMinute: clampedStart, endClockMinute: end) {
            return range
        }

        let fallbackEnd = min(ShiftTimeRange.maxEndMinuteOffset, clampedStart + 60)
        return ShiftTimeRange(startMinute: clampedStart, endMinuteOffset: fallbackEnd)!
    }

    private func defaultShortcut(for index: Int) -> ShiftShortcut {
        let defaults = [
            ShiftShortcut(startMinute: 6 * 60, endMinute: 14 * 60),
            ShiftShortcut(startMinute: 9 * 60, endMinute: 17 * 60),
            ShiftShortcut(startMinute: 14 * 60, endMinute: 22 * 60)
        ]
        return clampedShortcut(defaults[min(max(index, 0), defaults.count - 1)])
    }

    private var shiftCategoryMenu: some View {
        Menu {
            ForEach(DayType.allCases) { type in
                Button {
                    if selectedType != type {
                        categoryFeedbackTrigger += 1
                    }
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
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .payScopeGlassControl(accent: settings.categoryColor(for: selectedType), cornerRadius: 14, tintOpacity: 0.1)
        }
        .foregroundStyle(settings.categoryColor(for: selectedType))
    }

    private func automaticBreakBaseMinutes(for grossMinutes: Int) -> Int {
        let sixHoursWithTolerance = 6 * 60 + 15
        let nineHoursWithTolerance = 9 * 60 + 15

        if grossMinutes <= sixHoursWithTolerance { return 0 }
        if grossMinutes <= nineHoursWithTolerance { return 30 }
        return 45
    }

    private func inferManualBreakOverride(fromStoredBreakMinutes storedBreakMinutes: Int) {
        let grossMinutes = totalGrossMinutes
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
        let grossMinutes = totalGrossMinutes
        self.manualBreakOverrideMinutes = max(0, min(manualBreakOverrideMinutes, grossMinutes))
    }

    private func openBreakEditor() {
        withAnimation(.snappy(duration: 0.18)) {
            isBreakEditorVisible.toggle()
        }
    }

    private func adjustBreak(by deltaMinutes: Int) {
        let targetValue = breakMinutes + deltaMinutes
        let grossMinutes = totalGrossMinutes
        let clampedValue = max(0, min(targetValue, grossMinutes))
        let autoValue = automaticBreakBaseMinutes(for: grossMinutes)
        manualBreakOverrideMinutes = (clampedValue == autoValue) ? nil : clampedValue
    }

    private func breakAdjustmentButton(title: String, delta: Int) -> some View {
        Button(title) {
            adjustBreak(by: delta)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.bold))
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .payScopeGlassControl(accent: categoryAccent, cornerRadius: 11, tintOpacity: 0.055)
    }

    private var breakMinutes: Int {
        guard selectedType == .work else { return 0 }
        let grossMinutes = totalGrossMinutes
        if let manualBreakOverrideMinutes {
            return max(0, min(manualBreakOverrideMinutes, grossMinutes))
        }
        return min(grossMinutes, automaticBreakBaseMinutes(for: grossMinutes))
    }
}

private struct ShiftCategoryButtonStyle: ButtonStyle {
    let selectedAccent: Color
    let categoryAccent: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPreviewingSelection = isSelected || configuration.isPressed
        let accent = isPreviewingSelection ? categoryAccent : selectedAccent

        configuration.label
            .foregroundStyle(accent)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .payScopeGlassControl(
                accent: accent,
                cornerRadius: 15,
                tintOpacity: isPreviewingSelection ? 0.12 : 0.028
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}

private struct NeoPanelStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let glow: Bool

    func body(content: Content) -> some View {
        let geometry = PayScopeModalGeometry.sheet
        let shape = RoundedRectangle(cornerRadius: geometry.innerCornerRadius, style: .continuous)
        let tint = accent.opacity(glow ? 0.095 : 0.045)

        content
            .padding(geometry.edgePadding)
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        shape
                            .fill(tint)
                    )
            )
            .glassEffect(.regular.tint(accent.opacity(glow ? 0.085 : 0.04)), in: shape)
            .overlay(
                shape
                    .stroke(.white.opacity(colorScheme == .light ? 0.32 : 0.2), lineWidth: 0.8)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape
                    .stroke(accent.opacity(glow ? 0.24 : 0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(colorScheme == .light ? 0.035 : 0.1), radius: 10, x: 0, y: 5)
    }
}

private extension View {
    func neoPanel(accent: Color, glow: Bool = false) -> some View {
        modifier(NeoPanelStyle(accent: accent, glow: glow))
    }

    func editorTimeInput(
        accent: Color,
        width: CGFloat,
        font: Font = .system(.subheadline, design: .rounded).weight(.semibold),
        verticalPadding: CGFloat = 7,
        cornerRadius: CGFloat = 10,
        tintOpacity: Double = 0.1
    ) -> some View {
        modifier(
            EditorTimeInputStyle(
                accent: accent,
                width: width,
                font: font,
                verticalPadding: verticalPadding,
                cornerRadius: cornerRadius,
                tintOpacity: tintOpacity
            )
        )
    }

    func dayEditorSheetSurface() -> some View {
        let geometry = PayScopeModalGeometry.sheet

        return scrollContentBackground(.hidden)
            .background(Color.clear.ignoresSafeArea())
            .presentationBackground(.clear)
            .presentationCornerRadius(geometry.outerCornerRadius)
    }
}

private struct EditorTimeInputStyle: ViewModifier {
    let accent: Color
    let width: CGFloat
    let font: Font
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let tintOpacity: Double

    func body(content: Content) -> some View {
        content
            .font(font)
            .frame(width: width)
            .padding(.vertical, verticalPadding)
            .payScopeGlassControl(accent: accent, cornerRadius: cornerRadius, tintOpacity: tintOpacity)
    }
}

private struct EditableSegment: Identifiable {
    let id: String
    var startMinute: Int
    var endMinute: Int
    var isNextDay: Bool

    init(startMinute: Int, endMinute: Int, isNextDay: Bool = false) {
        self.id = "\(startMinute)-\(endMinute)-\(isNextDay)"
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.isNextDay = isNextDay
    }

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

private struct DayEditorPreviewMetrics {
    let netSeconds: Int
    let grossPayCents: Int
    let pauseSeconds: Int
}

private struct DayEditorEntryCache {
    var effectiveEntries: [DayEntry] = []
    var entriesByDate: [Date: DayEntry] = [:]
    var signature: Int = 0
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

    var range: ShiftTimeRange? {
        if endMinute >= ShiftTimeRange.minutesPerDay {
            return ShiftTimeRange(
                startMinute: startMinute,
                endMinuteOffset: endMinute
            )
        }

        return ShiftTimeRange(
            startMinute: startMinute,
            endClockMinute: endMinute
        )
    }

    var endClockMinute: Int {
        range?.endClockMinute ?? ShiftTimeRange.normalizedClockMinute(endMinute)
    }

    var durationMinutes: Int {
        range?.durationMinutes ?? 0
    }

    var displayRange: String {
        range?.displayRange() ?? "\(ShiftTimeRange.displayMinute(startMinute))-\(ShiftTimeRange.displayMinute(endClockMinute))"
    }
}

private struct ShiftShortcutPayload: Codable, Equatable {
    let startMinute: Int
    let endMinute: Int
    let dayTypeRaw: String?
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
                    .fill(segments.isEmpty ? accent.opacity(0.08) : accent.opacity(0.06))
                    .frame(height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(accent.opacity(0.12), lineWidth: 0.5)
                    )
                    .allowsHitTesting(false)

                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let segmentStartX = x(for: segment.startMinute, width: width)
                    let segmentEndX = x(for: segment.endMinute, width: width)
                    let segmentWidth = max(2, segmentEndX - segmentStartX)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(segment.isNextDay ? accent.opacity(0.42) : accent.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(accent.opacity(segment.isNextDay ? 0.24 : 0.35), lineWidth: 1)
                        )
                        .overlay {
                            if segment.isNextDay, segmentWidth >= 28 {
                                Text("+1")
                                    .font(.caption2.weight(.black))
                                    .monospacedDigit()
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color(.systemBackground).opacity(0.72))
                                    )
                            }
                        }
                        .frame(
                            width: segmentWidth,
                            height: 22
                        )
                        .offset(x: segmentStartX)
                        .allowsHitTesting(false)
                }

                ForEach(Array(dashedTickMinutes.enumerated()), id: \.offset) { _, tick in
                    Path { path in
                        let xPosition = x(for: tick, width: width)
                        path.move(to: CGPoint(x: xPosition, y: 2))
                        path.addLine(to: CGPoint(x: xPosition, y: 20))
                    }
                    .stroke(Color(.separator).opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
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
        let clockMinute = ShiftTimeRange.normalizedClockMinute(minute)
        let h = clockMinute / 60
        let m = clockMinute % 60
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
        let nextSeconds = max(0, hours * 3600 + minutes * 60)
        if seconds != nextSeconds {
            seconds = nextSeconds
        }
    }

    private func split() {
        let s = max(0, seconds)
        let nextHours = s / 3600
        let nextMinutes = (s % 3600) / 60
        if hours != nextHours { hours = nextHours }
        if minutes != nextMinutes { minutes = nextMinutes }
    }
}

private struct HHMMMinuteInput: View {
    @Binding var minuteOfDay: Int
    private var hasValue: Binding<Bool>?
    let accent: Color
    let isProminent: Bool

    @State private var hourText = ""
    @State private var minuteText = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case hour
        case minute
    }

    init(minuteOfDay: Binding<Int>, accent: Color, isProminent: Bool = false) {
        self._minuteOfDay = minuteOfDay
        self.hasValue = nil
        self.accent = accent
        self.isProminent = isProminent
    }

    init(minuteOfDay: Binding<Int>, hasValue: Binding<Bool>, accent: Color, isProminent: Bool = false) {
        self._minuteOfDay = minuteOfDay
        self.hasValue = hasValue
        self.accent = accent
        self.isProminent = isProminent
    }

    var body: some View {
        HStack(spacing: isProminent ? 5 : 4) {
            TextField("hh", text: $hourText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .hour)
                .editorTimeInput(
                    accent: accent,
                    width: isProminent ? 42 : 38,
                    font: isProminent ? .system(size: 24, weight: .semibold, design: .rounded) : .system(.subheadline, design: .rounded).weight(.semibold),
                    verticalPadding: isProminent ? 10 : 7,
                    cornerRadius: isProminent ? 14 : 10,
                    tintOpacity: isProminent ? 0.09 : 0.1
                )
                .onChange(of: hourText) { _, newValue in
                    let digits = sanitizeDigits(newValue, maxLength: 2)
                    if digits != newValue {
                        hourText = digits
                        return
                    }
                    setHasValueIfNeeded(!(hourText.isEmpty && minuteText.isEmpty))
                    sync()
                }

            Text(":")
                .font(isProminent ? .title3.weight(.bold) : .subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            TextField("mm", text: $minuteText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .minute)
                .editorTimeInput(
                    accent: accent,
                    width: isProminent ? 42 : 38,
                    font: isProminent ? .system(size: 24, weight: .semibold, design: .rounded) : .system(.subheadline, design: .rounded).weight(.semibold),
                    verticalPadding: isProminent ? 10 : 7,
                    cornerRadius: isProminent ? 14 : 10,
                    tintOpacity: isProminent ? 0.09 : 0.1
                )
                .onChange(of: minuteText) { _, newValue in
                    let digits = sanitizeDigits(newValue, maxLength: 2)
                    if digits != newValue {
                        minuteText = digits
                        return
                    }
                    setHasValueIfNeeded(!(hourText.isEmpty && minuteText.isEmpty))
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
                setHasValueIfNeeded(!(hourText.isEmpty && minuteText.isEmpty))
                split()
            }
        }
    }

    private func sanitizeDigits(_ value: String, maxLength: Int) -> String {
        String(value.filter(\.isNumber).prefix(maxLength))
    }

    private func setHasValueIfNeeded(_ value: Bool) {
        guard let hasValue, hasValue.wrappedValue != value else { return }
        hasValue.wrappedValue = value
    }

    private func sync() {
        if let hasValue, !hasValue.wrappedValue {
            return
        }
        let rawHours = Int(hourText) ?? 0
        var hours = min(23, rawHours)
        var minutes = min(59, Int(minuteText) ?? 0)
        if rawHours >= 24 {
            hours = 0
            minutes = 0
        }
        if minutes < 0 {
            minutes = 0
        }
        if hours < 0 {
            hours = 0
        }
        let nextMinute = ShiftTimeRange.normalizedClockMinute((hours * 60) + minutes)
        if minuteOfDay != nextMinute {
            minuteOfDay = nextMinute
        }
    }

    private func split() {
        if let hasValue, !hasValue.wrappedValue {
            if !hourText.isEmpty { hourText = "" }
            if !minuteText.isEmpty { minuteText = "" }
            return
        }
        let clamped = max(0, min(ShiftTimeRange.minutesPerDay - 1, minuteOfDay))
        let hours = clamped / 60
        let minutes = min(59, clamped % 60)
        let nextHourText = String(format: "%02d", hours)
        let nextMinuteText = String(format: "%02d", minutes)
        if hourText != nextHourText { hourText = nextHourText }
        if minuteText != nextMinuteText { minuteText = nextMinuteText }
    }
}

private struct HHMMInputDurationEditor: View {
    @Binding var seconds: Int
    let accent: Color
    let isProminent: Bool

    @State private var hourText = "00"
    @State private var minuteText = "00"
    @FocusState private var focusedField: Field?

    private enum Field {
        case hour
        case minute
    }

    init(seconds: Binding<Int>, accent: Color, isProminent: Bool = false) {
        self._seconds = seconds
        self.accent = accent
        self.isProminent = isProminent
    }

    var body: some View {
        HStack(spacing: isProminent ? 5 : 6) {
            TextField("hh", text: $hourText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .hour)
                .editorTimeInput(
                    accent: accent,
                    width: isProminent ? 42 : 42,
                    font: isProminent ? .system(size: 24, weight: .semibold, design: .rounded) : .system(.subheadline, design: .rounded).weight(.semibold),
                    verticalPadding: isProminent ? 10 : 7,
                    cornerRadius: isProminent ? 14 : 10,
                    tintOpacity: isProminent ? 0.09 : 0.1
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
                .font(isProminent ? .title3.weight(.bold) : .subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            TextField("mm", text: $minuteText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .minute)
                .editorTimeInput(
                    accent: accent,
                    width: isProminent ? 42 : 42,
                    font: isProminent ? .system(size: 24, weight: .semibold, design: .rounded) : .system(.subheadline, design: .rounded).weight(.semibold),
                    verticalPadding: isProminent ? 10 : 7,
                    cornerRadius: isProminent ? 14 : 10,
                    tintOpacity: isProminent ? 0.09 : 0.1
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
        let nextSeconds = max(0, (hours * 3600) + (minutes * 60))
        if seconds != nextSeconds {
            seconds = nextSeconds
        }
    }

    private func split() {
        let clamped = max(0, seconds)
        let hours = min(24, clamped / 3600)
        let minutes = min(59, (clamped % 3600) / 60)
        let nextHourText = String(format: "%02d", hours)
        let nextMinuteText = String(format: "%02d", minutes)
        if hourText != nextHourText { hourText = nextHourText }
        if minuteText != nextMinuteText { minuteText = nextMinuteText }
    }
}

#Preview("Day Editor") {
    // Preview using minimal static data (SwiftData previews removed)
    let today = Date().startOfDayLocal()
    let settings = Settings()
    return DayEditorView(date: today, settings: settings, onDaySaved: nil)
}
