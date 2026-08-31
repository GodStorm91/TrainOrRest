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
    @State private var smartCandidates: [SchedulingCandidate] = []
    @State private var smartSchedulingMessage: String?
    @State private var isFindingSmartTime = false
    @State private var isChoosingSmartTime = false
    @State private var selectedCandidateID: String?
    @State private var customStartTime: Date?
    @State private var customValidation: CustomTimeValidation?
    @State private var keepSelectedTimeFixed = false
    @State private var isApplyingSmartTime = false
    @State private var smartApplyResult: SmartSchedulingApplyResult?
    @State private var smartOperationKey = UUID().uuidString
    @State private var isChoosingShoe = false

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: workout.date.formatted(date: .complete, time: .omitted))
                LabeledContent("Workout", value: workout.kind?.displayName ?? workout.kindRaw)
                LabeledContent("Distance", value: Formatters.kilometers(workout.distanceKm * 1000))
                if let band = workout.paceBand {
                    LabeledContent("Pace", value: Formatters.paceBand(band))
                }
                Text(workout.details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let scheduleUpdatedAt = workout.scheduleUpdatedAt, workout.scheduleUpdatedFrom == "googleCalendar" {
                Section("Schedule history") {
                    LabeledContent("Scheduled from", value: "Google Calendar")
                    LabeledContent("Updated", value: scheduleUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if isNotVisibleInGoogleCalendar {
                Section {
                    Label("Not shown in Google Calendar", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(Theme.warn)
                    Text("This workout still exists in your TrainOrRest plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        googleCalendar.addBackToGoogleCalendar(workoutID: workout.uuid)
                    } label: {
                        Label("Add back to Google Calendar", systemImage: "calendar.badge.plus")
                    }
                }
            }

            if smartSchedulingEnabled {
                Section("Smart Scheduling") {
                    if isTimed(workout.date) {
                        scheduledSmartSchedulingSummary
                    } else if smartCandidates.isEmpty {
                        Button {
                            Task { await refreshSmartCandidates() }
                        } label: {
                            Label(isFindingSmartTime ? "Finding a time" : "Find a time", systemImage: "sparkles")
                        }
                        .accessibilityLabel("Find a time")
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

            if let matched = matchedActivity {
                Section("Completed Run") {
                    NavigationLink {
                        ActivityDetailView(activity: matched)
                    } label: {
                        ActivityRow(activity: matched)
                    }
                }
            }

            Section("Gear") {
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
                    Text("This workout uses a retired shoe.")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            }

            Section("Status") {
                statusButtons
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(workout.date.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isChoosingSmartTime) {
            SmartSchedulingTimeSheet(
                workout: workout,
                candidates: smartCandidates,
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
        .onAppear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: true)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: false)
        }
        .task {
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

    private var bestSmartCandidate: SchedulingCandidate? {
        smartCandidates.first
    }

    private var bestSmartSchedulingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Best available slot", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            if let candidate = bestSmartCandidate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.startTime.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
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
                        Label("Choose another time", systemImage: "clock")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await applySmartCandidate(candidate) }
                    } label: {
                        Label("Use \(timeText(candidate.startTime))", systemImage: "checkmark.circle.fill")
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
            Label("Scheduled", systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.semibold))
            let end = Calendar.current.date(
                byAdding: .second,
                value: Int(SmartSchedulingEngine().requiredWorkoutDurationSeconds(for: workout)),
                to: workout.date
            ) ?? workout.date
            Text(timeRange(workout.date, end))
                .font(.headline)
            Label("Synced with Google Calendar when connection is available", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await refreshSmartCandidates() }
                openSmartSchedulingSheet(selecting: nil)
            } label: {
                Label("Change time", systemImage: "clock.arrow.circlepath")
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
        smartCandidates = await googleCalendar.refreshedSmartSchedulingCandidates(for: workout, sameDayOnly: true, allowLockedWorkoutUpdate: true)
        if smartCandidates.isEmpty {
            smartSchedulingMessage = "No suitable time found on \(workout.date.formatted(.dateTime.weekday(.wide)))."
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
            smartSchedulingMessage = "Workout scheduled for \(timeText(start))."
        } else if case .queued = result.status {
            smartCandidates = []
            smartSchedulingMessage = "Workout scheduled. Google Calendar will update when online."
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
            smartSchedulingMessage = "Workout scheduled for \(timeText(candidate.startTime))."
        } else if case .queued = result.status {
            smartCandidates = []
            smartSchedulingMessage = "Workout scheduled. Google Calendar will update when online."
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
        !Calendar.current.isDate(date, equalTo: Calendar.current.startOfDay(for: date), toGranularity: .minute)
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        "\(timeText(start))-\(timeText(end))"
    }

    private func userFacingReasons(for candidate: SchedulingCandidate) -> [String] {
        let natural = candidate.reasons.filter { !$0.localizedCaseInsensitiveContains("minute window") }
        return Array((natural.isEmpty ? ["No calendar conflicts"] : natural).prefix(3))
    }

    private var statusButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusButton("Done", status: .done, tint: Theme.good)
                statusButton("Skipped", status: .skipped, tint: Theme.warn)
                statusButton("Planned", status: .planned, tint: Theme.accent)
            }
            .buttonStyle(.bordered)

            Text(statusHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusButton(_ label: String, status: WorkoutStatus, tint: Color) -> some View {
        Button(label) {
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
        switch workout.status {
        case .done:
            "Done is a manual completion and stays linked to this workout."
        case .skipped:
            "Skipped is a manual decision; the planner will not auto-match this workout."
        case .planned:
            "Planned clears the manual decision so future sync matching can apply again."
        }
    }
}

private struct SmartSchedulingTimeSheet: View {
    @Bindable var workout: PlannedWorkout
    let candidates: [SchedulingCandidate]
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
                                Label("Choose a custom time", systemImage: "slider.horizontal.3")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                        validationSummary
                        fixedToggle
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle(applyResult == nil ? "Choose start time" : "Workout scheduled")
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
            Text("\(workout.kind?.displayName ?? workout.kindRaw) · \(String(format: "%.1f", workout.distanceKm)) km")
                .font(.headline)
            Text(workout.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Estimated duration: \(durationMinutes) min")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow("Available times").tracking(1.6)
            if candidates.isEmpty {
                ContentUnavailableView(
                    "No suitable time found",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text("This workout needs a clear window plus buffers.")
                )
                Button {
                    onCancel()
                } label: {
                    Label("Choose another day", systemImage: "calendar")
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
                            Text("Selected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        } else if candidate.isRecommended {
                            Text("Recommended")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.good)
                        }
                    }
                    ForEach(candidate.reasons.prefix(2), id: \.self) { reason in
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidate.warnings.prefix(1), id: \.self) { warning in
                        Text(warning)
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
            TorEyebrow("Custom start time").tracking(1.6)
            DatePicker(
                "Start time",
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
                LabeledContent("Estimated end", value: timeText(activeEnd))
            }
            Text("Required window: \(durationMinutes) min workout + buffers")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var validationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let customValidation {
                validationBlock(customValidation)
            } else if let selectedCandidate {
                Text("\(timeText(selectedCandidate.startTime)) is available")
                    .font(.headline)
                ForEach(selectedCandidate.reasons.prefix(3), id: \.self) { reason in
                    Label(reason, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(selectedCandidate.warnings.prefix(2), id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func validationBlock(_ validation: CustomTimeValidation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(validation.allowsScheduling ? "\(timeText(validation.requestedStart)) is available" : "\(timeText(validation.requestedStart)) is not available")
                .font(.headline)
                .foregroundStyle(validation.allowsScheduling ? Theme.good : Theme.warn)
            if validation.allowsScheduling {
                Text("Workout \(timeRange(validation.requestedStart, validation.calculatedEnd))")
                    .font(.subheadline.weight(.semibold))
                ForEach(validation.reasons.prefix(3), id: \.self) { reason in
                    Label(reason, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(validation.warnings.prefix(2), id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            } else {
                ForEach(validation.conflicts.prefix(2), id: \.self) { conflict in
                    Text(conflict)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !validation.nearestAlternatives.isEmpty {
                    Text("Nearest available options")
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
            Toggle("Keep this time fixed", isOn: $keepSelectedTimeFixed)
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("Keep this scheduled time fixed")
            Text("Smart Scheduling will not suggest moving this workout during future schedule optimization.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(isChoosingCustomTime ? "Back" : "Cancel") {
                if isChoosingCustomTime {
                    isChoosingCustomTime = false
                } else {
                    onCancel()
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: 44)
            Button {
                if isChoosingCustomTime, customValidation == nil {
                    onValidateCustomTime(time(onWorkoutDateMatching: pickerDate))
                } else {
                    onApply()
                }
            } label: {
                if isApplying {
                    Label("Scheduling workout", systemImage: "hourglass")
                } else if isChoosingCustomTime, customValidation == nil {
                    Label("Check \(timeText(time(onWorkoutDateMatching: pickerDate)))", systemImage: "checkmark.shield")
                } else {
                    Label(activeStart.map { "Schedule at \(timeText($0))" } ?? "Schedule", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isApplying || (!canApply && !(isChoosingCustomTime && customValidation == nil)))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding()
        .background(.bar)
    }

    private func resultView(_ result: SmartSchedulingApplyResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch result.status {
            case .completed, .queued:
                Label("Workout scheduled", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.good)
                if let start = result.scheduledStart, let end = result.scheduledEnd {
                    Text("\(workout.kind?.displayName ?? "Workout")\n\(workout.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))\n\(timeRange(start, end))")
                        .font(.headline)
                }
                Text(result.googleCalendarMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Undo") { onUndo() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    Button("Done") { onDone() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            case .stale(let validation):
                validationBlock(validation)
                Button("Refresh options") { onCancel() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            case .failed(let message):
                Label("Could not schedule the workout", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(Theme.warn)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Keep current") { onDone() }
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
        date.formatted(date: .omitted, time: .shortened)
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        "\(timeText(start))-\(timeText(end))"
    }

    private func accessibilityLabel(for candidate: SchedulingCandidate, selected: Bool) -> String {
        [
            timeRange(candidate.startTime, candidate.endTime),
            "available",
            candidate.isRecommended ? "recommended" : nil,
            selected ? "selected" : nil
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
