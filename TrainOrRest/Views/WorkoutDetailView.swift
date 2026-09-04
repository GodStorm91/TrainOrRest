import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    @Bindable var workout: PlannedWorkout
    @Query private var activities: [CompletedActivity]
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Query private var mileageEntries: [ShoeMileageEntry]
    @Query private var storedShoePreferences: [RunningShoePreferences]
    @Query private var googleLinks: [GoogleCalendarEventLink]
    @Query private var googleConnections: [GoogleCalendarConnection]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @EnvironmentObject private var runSchedule: RunScheduleController
    @State private var smartCandidates: [SchedulingCandidate] = []
    @State private var smartSchedulingMessage: String?
    @State private var isFindingSmartTime = false
    @State private var isChoosingSmartTime = false
    @State private var selectedCandidateID: String?
    @State private var customStartTime: Date?
    @State private var customValidation: CustomTimeValidation?
    @State private var keepSelectedTimeFixed = false
    @State private var isShowingRunScheduleSetup = false
    @State private var isApplyingSmartTime = false
    @State private var smartApplyResult: SmartSchedulingApplyResult?
    @State private var smartOperationKey = UUID().uuidString
    @State private var isChoosingShoe = false

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        List {
            Section {
                LabeledContent(language.plan.date, value: workout.date.formatted(.dateTime.year().month(.wide).day().weekday(.wide).locale(language.uiLocale)))
                LabeledContent(language.plan.workout, value: workout.kind.map(language.name) ?? language.genericRunLabel)
                LabeledContent(language.plan.distance, value: Formatters.kilometers(workout.distanceKm * 1000))
                if let band = workout.paceBand {
                    LabeledContent(language.plan.pace, value: Formatters.paceBand(band))
                }
                if let seconds = workout.expectedDurationSeconds {
                    LabeledContent(language.durationLabel, value: Formatters.duration(seconds))
                }
                Text(workout.details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let scheduleUpdatedAt = workout.scheduleUpdatedAt, workout.scheduleUpdatedFrom == "googleCalendar" {
                Section(language.plan.scheduleHistory) {
                    LabeledContent(language.plan.scheduledFrom, value: "Google Calendar")
                    LabeledContent(language.plan.updated, value: "\(language.shortDate(scheduleUpdatedAt)) \(language.time(scheduleUpdatedAt))")
                }
            }

            if isNotVisibleInGoogleCalendar {
                Section {
                    Label(language.plan.notShownInGoogleCalendar, systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(Theme.warn)
                    Text(language.plan.workoutStillInPlan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        googleCalendar.addBackToGoogleCalendar(workoutID: workout.uuid)
                    } label: {
                        Label(language.plan.addBackToGoogleCalendar, systemImage: "calendar.badge.plus")
                    }
                }
            }

            if let matched = matchedActivity {
                Section(language.plan.completedRunSection) {
                    NavigationLink {
                        ActivityDetailView(activity: matched)
                    } label: {
                        ActivityRow(activity: matched)
                    }
                }
            }

            Section(language.plan.gear) {
                Button {
                    isChoosingShoe = true
                } label: {
                    WorkoutShoeRow(
                        shoe: assignedShoe,
                        source: workout.shoeAssignmentSource,
                        isNearMileageRange: assignedShoe.map(isNearMileageRange) ?? false
                    )
                }
                .buttonStyle(.plain)
                if assignedShoe?.status == .retired {
                    Text(language.plan.retiredShoeNotice)
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            }

            Section(language.plan.runSchedule) {
                RunScheduleCard(
                    language: language,
                    needsSetup: runSchedule.needsWeatherSetup,
                    isLoading: runSchedule.isRefreshingWeather,
                    failure: runSchedule.weatherUserMessage,
                    weather: scheduledWeather,
                    onSetup: { isShowingRunScheduleSetup = true },
                    onRetry: { Task { await runSchedule.refreshWeather(force: true) } }
                )
                if smartSchedulingEnabled {
                    if isTimed(workout.date) {
                        scheduledSmartSchedulingSummary
                    } else if smartCandidates.isEmpty {
                        Button {
                            Task { await refreshSmartCandidates() }
                        } label: {
                            Label(isFindingSmartTime ? language.plan.findingTime : language.plan.findTime, systemImage: "sparkles")
                        }
                        .accessibilityLabel(language.plan.findTimeAccessibility)
                        .disabled(isFindingSmartTime)
                    } else {
                        bestSmartSchedulingCard
                    }
                    if let smartSchedulingMessage {
                        Text(smartSchedulingMessage)
                            .font(.caption)
                            .foregroundStyle(smartCandidates.isEmpty ? Theme.warn : Theme.good)
                    }
                }
            }

            Section(language.plan.status) {
                statusButtons
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(language.shortDate(workout.date))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isChoosingSmartTime) {
            SmartSchedulingTimeSheet(
                workout: workout,
                candidates: smartCandidates,
                language: language,
                selectedCandidateID: $selectedCandidateID,
                customStartTime: $customStartTime,
                customValidation: $customValidation,
                keepSelectedTimeFixed: $keepSelectedTimeFixed,
                isApplying: isApplyingSmartTime,
                applyResult: smartApplyResult,
                onValidateCustomTime: validateCustomTime,
                onApply: { Task { await applySelectedSmartTime() } },
                onUndo: undoSmartTime,
                onDone: finishSmartSchedulingSheet,
                onCancel: { isChoosingSmartTime = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(isApplyingSmartTime)
        }
        .sheet(isPresented: $isChoosingShoe) {
            ShoePickerSheet(
                workoutType: ShoeWorkoutType.normalized(from: workout.kind),
                shoes: shoes,
                mileageEntries: mileageEntries,
                recommendedShoeID: automaticShoeID,
                allowsAutomaticSelection: true,
                onSelect: { shoe in
                    workout.shoeID = shoe?.id
                    workout.shoeAssignmentSource = shoe == nil ? .none : .manual
                    try? modelContext.save()
                },
                onAutomatic: {
                    applyAutomaticShoe()
                    try? modelContext.save()
                }
            )
        }
        .sheet(isPresented: $isShowingRunScheduleSetup) {
            RunScheduleSetupSheet()
        }
        .onAppear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: true)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: false)
        }
        .task {
            await runSchedule.refreshWeather()
            if smartSchedulingEnabled && !isTimed(workout.date) {
                await refreshSmartCandidates()
            }
        }
    }

    private var matchedActivity: CompletedActivity? {
        guard let uuid = workout.matchedActivityUUID else { return nil }
        return activities.first { $0.hkUUID == uuid }
    }

    private var assignedShoe: RunningShoe? {
        guard let shoeID = workout.shoeID else { return nil }
        return shoes.first { $0.id == shoeID }
    }

    private var shoePreferences: RunningShoePreferences {
        storedShoePreferences.first ?? RunningShoePreferences()
    }

    private var automaticShoeID: UUID? {
        ShoeAssignmentService.selectShoeForWorkout(
            workoutType: ShoeWorkoutType.normalized(from: workout.kind),
            activeShoes: shoes,
            preferences: shoePreferences,
            existingShoeID: nil,
            existingAssignmentSource: .none,
            mileageEntries: mileageEntries
        ).shoeID
    }

    private func applyAutomaticShoe() {
        if storedShoePreferences.isEmpty {
            modelContext.insert(shoePreferences)
        }
        workout.shoeID = nil
        workout.shoeAssignmentSource = .none
        ShoeAssignmentService.applySelection(
            to: workout,
            shoes: shoes,
            preferences: shoePreferences,
            entries: mileageEntries
        )
    }

    private func isNearMileageRange(_ shoe: RunningShoe) -> Bool {
        ShoeWearStatusService.isNearRetirement(
            shoe,
            ledger: mileageEntries,
            thresholdPercent: shoePreferences.nearRetirementThresholdPercent
        )
    }

    private var isNotVisibleInGoogleCalendar: Bool {
        googleLinks.contains {
            $0.localEntityID == workout.uuid && $0.syncState == .notVisibleInGoogleCalendar
        }
    }

    private var smartSchedulingEnabled: Bool {
        googleConnections.first?.smartSchedulingEnabled == true
    }
    private var scheduledSlotEnd: Date {
        Calendar.current.date(
            byAdding: .second,
            value: Int(SmartSchedulingEngine().requiredWorkoutDurationSeconds(for: workout)),
            to: workout.date
        ) ?? workout.date
    }

    private var scheduledWeather: SlotWeather? {
        guard isTimed(workout.date), !runSchedule.needsWeatherSetup else { return nil }
        return runSchedule.slotWeather(start: workout.date, end: scheduledSlotEnd)
    }

    private var bestSmartCandidate: SchedulingCandidate? {
        smartCandidates.first
    }

    private var bestSmartSchedulingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(language.plan.bestAvailableSlot, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            if let candidate = bestSmartCandidate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.longDate(candidate.startTime))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(timeRange(candidate.startTime, candidate.endTime))
                        .font(.headline)
                    ForEach(userFacingReasons(for: candidate), id: \.self) { reason in
                        Label(reason, systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        openSmartSchedulingSheet(selecting: candidate)
                    } label: {
                        Label(language.plan.chooseAnotherTime, systemImage: "clock")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await applySmartCandidate(candidate) }
                    } label: {
                        Label(language.plan.useTime(timeText(candidate.startTime)), systemImage: "checkmark.circle.fill")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var scheduledSmartSchedulingSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(language.plan.scheduled, systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.semibold))
            let end = Calendar.current.date(
                byAdding: .second,
                value: Int(SmartSchedulingEngine().requiredWorkoutDurationSeconds(for: workout)),
                to: workout.date
            ) ?? workout.date
            Text(timeRange(workout.date, end))
                .font(.headline)
            if let weather = scheduledWeather {
                Label(weather.summary(language: language), systemImage: weather.glyph.systemImage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(RunScheduleCard.color(for: weather.glyph))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(language.plan.syncedWhenAvailable, systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await refreshSmartCandidates() }
                openSmartSchedulingSheet(selecting: nil)
            } label: {
                Label(language.plan.changeTime, systemImage: "clock.arrow.circlepath")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func refreshSmartCandidates() async {
        guard !isFindingSmartTime else { return }
        isFindingSmartTime = true
        smartSchedulingMessage = nil
        defer { isFindingSmartTime = false }
        let calendarCandidates = await googleCalendar.refreshedSmartSchedulingCandidates(for: workout, sameDayOnly: true, allowLockedWorkoutUpdate: true)
        smartCandidates = runSchedule.showsWeatherOverlay
            ? runSchedule.rank(calendarCandidates).map(\.candidate)
            : calendarCandidates
        if smartCandidates.isEmpty {
            smartSchedulingMessage = language.plan.noSuitableTime(workout.date)
        } else {
            smartSchedulingMessage = nil
        }
    }

    private func openSmartSchedulingSheet(selecting candidate: SchedulingCandidate?) {
        if smartCandidates.isEmpty {
            Task { await refreshSmartCandidates() }
        }
        selectedCandidateID = candidate?.id ?? smartCandidates.first?.id
        customStartTime = nil
        customValidation = nil
        smartApplyResult = nil
        keepSelectedTimeFixed = false
        smartOperationKey = UUID().uuidString
        isChoosingSmartTime = true
    }

    private func selectedCandidate() -> SchedulingCandidate? {
        smartCandidates.first { $0.id == selectedCandidateID } ?? smartCandidates.first
    }

    private func validateCustomTime(_ start: Date) {
        customStartTime = start
        selectedCandidateID = nil
        customValidation = googleCalendar.validateSmartSchedulingTime(workoutID: workout.uuid, start: start)
    }

    private func applySelectedSmartTime() async {
        guard !isApplyingSmartTime else { return }
        let candidate = selectedCandidate()
        let start = customValidation?.requestedStart ?? candidate?.startTime
        guard let start else { return }
        isApplyingSmartTime = true
        defer { isApplyingSmartTime = false }
        let result = await googleCalendar.applySmartSchedulingTime(
            workoutID: workout.uuid,
            start: start,
            keepTimeFixed: keepSelectedTimeFixed,
            expectedWorkoutVersion: candidate?.workoutVersion,
            candidateAvailabilityTimestamp: customValidation?.availabilitySourceTimestamp ?? candidate?.availabilitySourceTimestamp,
            idempotencyKey: smartOperationKey
        )
        smartApplyResult = result
        if case .completed = result.status {
            smartCandidates = []
            smartSchedulingMessage = language.plan.workoutScheduledFor(timeText(start))
        } else if case .queued = result.status {
            smartCandidates = []
            smartSchedulingMessage = language.plan.workoutScheduledPendingSync
        }
    }

    private func applySmartCandidate(_ candidate: SchedulingCandidate) async {
        guard !isApplyingSmartTime else { return }
        selectedCandidateID = candidate.id
        customStartTime = nil
        customValidation = nil
        smartApplyResult = nil
        keepSelectedTimeFixed = false
        let operationKey = UUID().uuidString
        smartOperationKey = operationKey
        isChoosingSmartTime = true
        isApplyingSmartTime = true
        defer { isApplyingSmartTime = false }
        let result = await googleCalendar.applySmartSchedulingTime(
            workoutID: workout.uuid,
            start: candidate.startTime,
            keepTimeFixed: false,
            expectedWorkoutVersion: candidate.workoutVersion,
            candidateAvailabilityTimestamp: candidate.availabilitySourceTimestamp,
            idempotencyKey: operationKey
        )
        smartApplyResult = result
        if case .completed = result.status {
            smartCandidates = []
            smartSchedulingMessage = language.plan.workoutScheduledFor(timeText(candidate.startTime))
        } else if case .queued = result.status {
            smartCandidates = []
            smartSchedulingMessage = language.plan.workoutScheduledPendingSync
        }
    }

    private func undoSmartTime() {
        guard let operationID = smartApplyResult?.operationID else { return }
        smartApplyResult = googleCalendar.undoSmartSchedulingOperation(operationID)
        smartCandidates = []
    }

    private func finishSmartSchedulingSheet() {
        isChoosingSmartTime = false
        smartApplyResult = nil
        selectedCandidateID = nil
        customValidation = nil
    }

    private func isTimed(_ date: Date) -> Bool {
        RunScheduleTime.isTimed(date)
    }

    private func timeText(_ date: Date) -> String {
        language.time(date)
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        "\(timeText(start))-\(timeText(end))"
    }

    private func userFacingReasons(for candidate: SchedulingCandidate) -> [String] {
        let natural = candidate.reasons.filter { !$0.localizedCaseInsensitiveContains("minute window") }
        return Array((natural.isEmpty ? [language.plan.noCalendarConflicts] : natural.map(language.plan.schedulingMessage)).prefix(3))
    }

    private var statusButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    statusButton(status: .done, tint: Theme.good)
                    statusButton(status: .skipped, tint: Theme.warn)
                    statusButton(status: .planned, tint: Theme.accent)
                }
                VStack(alignment: .leading, spacing: 8) {
                    statusButton(status: .done, tint: Theme.good)
                    statusButton(status: .skipped, tint: Theme.warn)
                    statusButton(status: .planned, tint: Theme.accent)
                }
            }
            .buttonStyle(.bordered)

            Text(statusHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusButton(status: WorkoutStatus, tint: Color) -> some View {
        Button(language.name(status)) {
            workout.status = status
            // Resetting to planned withdraws the manual decision, so auto-
            // matching may apply again; done/skip stays user-owned.
            workout.manuallyOverridden = status != .planned
            if status != .done {
                workout.matchedActivityUUID = nil
            }
            NotificationCenter.default.post(name: .planDidChange, object: nil)
        }
        .tint(tint)
        .disabled(workout.status == status || isChoosingSmartTime)
        .frame(maxWidth: .infinity)
    }

    private var statusHelpText: String {
        language.plan.statusHelp(workout.status)
    }
}

private struct SmartSchedulingTimeSheet: View {
    @Bindable var workout: PlannedWorkout
    let candidates: [SchedulingCandidate]
    let language: CoachLanguage
    @Binding var selectedCandidateID: String?
    @Binding var customStartTime: Date?
    @Binding var customValidation: CustomTimeValidation?
    @Binding var keepSelectedTimeFixed: Bool
    let isApplying: Bool
    let applyResult: SmartSchedulingApplyResult?
    let onValidateCustomTime: (Date) -> Void
    let onApply: () -> Void
    let onUndo: () -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var isChoosingCustomTime = false
    @State private var pickerDate = Date()

    private var selectedCandidate: SchedulingCandidate? {
        candidates.first { $0.id == selectedCandidateID } ?? candidates.first
    }

    private var activeStart: Date? {
        customValidation?.requestedStart ?? selectedCandidate?.startTime
    }

    private var activeEnd: Date? {
        customValidation?.calculatedEnd ?? selectedCandidate?.endTime
    }

    private var canApply: Bool {
        if isApplying || applyResult != nil { return false }
        if let customValidation {
            return customValidation.allowsScheduling
        }
        return selectedCandidate?.isValid == true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let applyResult {
                        resultView(applyResult)
                    } else {
                        header
                        if isChoosingCustomTime {
                            customTimePicker
                        } else {
                            candidateList
                            Button {
                                openCustomTime()
                            } label: {
                                Label(language.plan.chooseCustomTime, systemImage: "slider.horizontal.3")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                        validationSummary
                        fixedToggle
                    }
                }
                .padding()
                .torReadableColumn()
            }
            .background(Theme.bg)
            .navigationTitle(applyResult == nil ? language.plan.chooseStartTime : language.plan.workoutScheduledTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if applyResult == nil {
                    actionBar
                }
            }
        }
        .onAppear {
            pickerDate = activeStart ?? workout.date
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(workout.kind.map(language.name) ?? language.plan.workout) · \(String(format: "%.1f", workout.distanceKm)) km")
                .font(.headline)
            Text(language.longDate(workout.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(language.plan.estimatedDuration(durationMinutes))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow(language.plan.availableTimes).tracking(1.6)
            if candidates.isEmpty {
                ContentUnavailableView(
                    language.plan.noSuitableTimeFound,
                    systemImage: "clock.badge.exclamationmark",
                    description: Text(language.plan.needsClearWindow)
                )
                Button {
                    onCancel()
                } label: {
                    Label(language.plan.chooseAnotherDay, systemImage: "calendar")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else {
                ForEach(candidates) { candidate in
                    candidateRow(candidate)
                }
            }
        }
    }

    private func candidateRow(_ candidate: SchedulingCandidate) -> some View {
        let selected = selectedCandidateID == candidate.id && customValidation == nil
        return Button {
            customValidation = nil
            customStartTime = nil
            selectedCandidateID = candidate.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.faint)
                    .frame(width: 28, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(timeRange(candidate.startTime, candidate.endTime))
                            .font(.headline)
                        if selected {
                            Text(language.plan.selected)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        } else if candidate.isRecommended {
                            Text(language.plan.recommended)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.good)
                        }
                    }
                    ForEach(candidate.reasons.prefix(2), id: \.self) { reason in
                        Text(language.plan.schedulingMessage(reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidate.warnings.prefix(1), id: \.self) { warning in
                        Text(language.plan.schedulingMessage(warning))
                            .font(.caption)
                            .foregroundStyle(Theme.warn)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel(for: candidate, selected: selected))
        }
        .buttonStyle(.plain)
    }

    private var customTimePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            TorEyebrow(language.plan.customStartTime).tracking(1.6)
            DatePicker(
                language.plan.startTime,
                selection: $pickerDate,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .onChange(of: pickerDate) { _, newValue in
                let start = time(onWorkoutDateMatching: newValue)
                pickerDate = start
                onValidateCustomTime(start)
            }
            if let activeEnd {
                LabeledContent(language.plan.estimatedEnd, value: timeText(activeEnd))
            }
            Text(language.plan.requiredWindow(durationMinutes))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var validationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let customValidation {
                validationBlock(customValidation)
            } else if let selectedCandidate {
                Text(language.plan.timeAvailability(timeText(selectedCandidate.startTime), available: true))
                    .font(.headline)
                ForEach(selectedCandidate.reasons.prefix(3), id: \.self) { reason in
                    Label(language.plan.schedulingMessage(reason), systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(selectedCandidate.warnings.prefix(2), id: \.self) { warning in
                    Text(language.plan.schedulingMessage(warning))
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func validationBlock(_ validation: CustomTimeValidation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.plan.timeAvailability(timeText(validation.requestedStart), available: validation.allowsScheduling))
                .font(.headline)
                .foregroundStyle(validation.allowsScheduling ? Theme.good : Theme.warn)
            if validation.allowsScheduling {
                Text(language.plan.workoutTimeRange(timeRange(validation.requestedStart, validation.calculatedEnd)))
                    .font(.subheadline.weight(.semibold))
                ForEach(validation.reasons.prefix(3), id: \.self) { reason in
                    Label(language.plan.schedulingMessage(reason), systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(validation.warnings.prefix(2), id: \.self) { warning in
                    Text(language.plan.schedulingMessage(warning))
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            } else {
                ForEach(validation.conflicts.prefix(2), id: \.self) { conflict in
                    Text(language.plan.schedulingMessage(conflict))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !validation.nearestAlternatives.isEmpty {
                    Text(language.plan.nearestAvailableOptions)
                        .font(.subheadline.weight(.semibold))
                    ForEach(validation.nearestAlternatives.prefix(2)) { candidate in
                        Button(timeRange(candidate.startTime, candidate.endTime)) {
                            isChoosingCustomTime = false
                            customValidation = nil
                            customStartTime = nil
                            selectedCandidateID = candidate.id
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var fixedToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(language.plan.keepTimeFixed, isOn: $keepSelectedTimeFixed)
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel(language.plan.keepTimeFixedAccessibility)
            Text(language.plan.keepTimeFixedDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                cancelAction
                applyAction
            }
            VStack(alignment: .leading, spacing: 8) {
                cancelAction
                applyAction
            }
        }
        .padding()
        .torReadableColumn()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var cancelAction: some View {
        Button(isChoosingCustomTime ? language.backLabel : language.plan.cancel) {
            if isChoosingCustomTime {
                isChoosingCustomTime = false
            } else {
                onCancel()
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var applyAction: some View {
        Button {
            if isChoosingCustomTime, customValidation == nil {
                onValidateCustomTime(time(onWorkoutDateMatching: pickerDate))
            } else {
                onApply()
            }
        } label: {
            if isApplying {
                Label(language.plan.schedulingWorkout, systemImage: "hourglass")
            } else if isChoosingCustomTime, customValidation == nil {
                Label(language.plan.checkTime(timeText(time(onWorkoutDateMatching: pickerDate))), systemImage: "checkmark.shield")
            } else {
                Label(activeStart.map { language.plan.scheduleAt(timeText($0)) } ?? language.plan.schedule, systemImage: "checkmark.circle.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isApplying || (!canApply && !(isChoosingCustomTime && customValidation == nil)))
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func resultView(_ result: SmartSchedulingApplyResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch result.status {
            case .completed, .queued:
                Label(language.plan.workoutScheduledTitle, systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.good)
                if let start = result.scheduledStart, let end = result.scheduledEnd {
                    Text("\(workout.kind.map(language.name) ?? language.plan.workout)\n\(language.longDate(workout.date))\n\(timeRange(start, end))")
                        .font(.headline)
                }
                Text(language.plan.schedulingMessage(result.googleCalendarMessage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Button(language.plan.undo) { onUndo() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        Button(language.plan.done) { onDone() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Button(language.plan.undo) { onUndo() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        Button(language.plan.done) { onDone() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            case .stale(let validation):
                validationBlock(validation)
                Button(language.plan.refreshOptions) { onCancel() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            case .failed(let message):
                Label(language.plan.couldNotScheduleWorkout, systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(Theme.warn)
                Text(language.plan.schedulingMessage(message))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(language.plan.keepCurrent) { onDone() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private var durationMinutes: Int {
        Int((SmartSchedulingEngine().requiredWorkoutDurationSeconds(for: workout) / 60).rounded())
    }

    private func openCustomTime() {
        isChoosingCustomTime = true
        pickerDate = activeStart ?? workout.date
        onValidateCustomTime(time(onWorkoutDateMatching: pickerDate))
    }

    private func time(onWorkoutDateMatching source: Date) -> Date {
        let calendar = Calendar.current
        let sourceParts = calendar.dateComponents([.hour, .minute], from: source)
        let dayParts = calendar.dateComponents([.year, .month, .day], from: workout.date)
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: dayParts.year,
            month: dayParts.month,
            day: dayParts.day,
            hour: sourceParts.hour,
            minute: sourceParts.minute
        )) ?? workout.date
    }

    private func timeText(_ date: Date) -> String {
        language.time(date)
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        "\(timeText(start))-\(timeText(end))"
    }

    private func accessibilityLabel(for candidate: SchedulingCandidate, selected: Bool) -> String {
        language.plan.candidateAccessibility(
            range: timeRange(candidate.startTime, candidate.endTime),
            recommended: candidate.isRecommended,
            selected: selected
        )
    }
}
