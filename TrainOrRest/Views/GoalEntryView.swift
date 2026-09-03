import SwiftData
import SwiftUI

/// Goal entry / editing. Shows a live feasibility verdict once inputs are
/// valid; on save the previous goal and plan are replaced.
struct GoalEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    @State private var distance: RaceDistance = .halfMarathon
    @State private var targetHours = 1
    @State private var targetMinutes = 45
    @State private var raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now) ?? .now
    @State private var selectedDays: Set<Weekday> = [.tuesday, .thursday, .saturday, .sunday]
    @State private var longRunDay: Weekday = .sunday

    // Cold-start fallback when history can't estimate fitness.
    @State private var fitness: FitnessProfile?
    @State private var comfortablePaceMinutes = 6
    @State private var comfortablePaceSeconds = 0
    @State private var manualWeeklyKm = 25.0

    @State private var saveError: String?
    @State private var isEditingExistingGoal = false
    @State private var isConfirmingRegeneration = false

    private let calendar = Calendar.current

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        NavigationStack {
            Form {
                raceSection
                availabilitySection
                if fitness == nil { coldStartSection }
                feasibilitySection
                if let saveError {
                    Section { Text(saveError).foregroundStyle(Theme.bad) }
                }
            }
            .navigationTitle(language.settings.raceGoalTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.saveLabel, action: requestSave).disabled(!isValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.cancelLabel) { dismiss() }
                }
            }
            .confirmationDialog(
                language.settings.overwriteCurrentPlan,
                isPresented: $isConfirmingRegeneration,
                titleVisibility: .visible
            ) {
                Button(language.settings.overwritePlan, role: .destructive, action: save)
                Button(language.cancelLabel, role: .cancel) {}
            } message: {
                Text(language.settings.overwritePlanMessage)
            }
            .task { load() }
        }
    }

    // MARK: - Sections

    private var raceSection: some View {
        Section(language.settings.raceSection) {
            Picker(language.settings.distance, selection: $distance) {
                ForEach(RaceDistance.allCases) { Text(language.name($0)).tag($0) }
            }
            HStack {
                Text(language.settings.targetTime)
                Spacer()
                Picker(language.settings.hours, selection: $targetHours) {
                    ForEach(0..<8, id: \.self) { Text(language.settings.hourPickerValue($0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                Picker(language.settings.minutes, selection: $targetMinutes) {
                    ForEach(0..<60, id: \.self) { Text(language.settings.minutePickerValue($0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
            }
            DatePicker(
                language.settings.raceDate,
                selection: $raceDate,
                in: calendar.date(byAdding: .day, value: 1, to: .now)!...,
                displayedComponents: .date
            )
            .environment(\.locale, language.uiLocale)
        }
    }

    private var availabilitySection: some View {
        Section {
            ForEach(Weekday.allCases, id: \.self) { day in
                Toggle(language.shortName(day), isOn: Binding(
                    get: { selectedDays.contains(day) },
                    set: { included in
                        if included {
                            selectedDays.insert(day)
                        } else if selectedDays.count > 3 {
                            selectedDays.remove(day)
                        }
                        if !selectedDays.contains(longRunDay), let fallback = selectedDays.sorted().last {
                            longRunDay = fallback
                        }
                    }
                ))
            }
            Picker(language.settings.longRunDay, selection: $longRunDay) {
                ForEach(selectedDays.sorted(), id: \.self) { Text(language.shortName($0)).tag($0) }
            }
        } header: {
            Text(language.settings.runningDays(selectedDays.count))
        } footer: {
            if selectedDays.count < 3 {
                Text(language.settings.minimumRunningDays).foregroundStyle(Theme.bad)
            }
        }
    }

    private var coldStartSection: some View {
        Section {
            HStack {
                Text(language.settings.comfortablePace)
                Spacer()
                Picker(language.settings.minutesAbbreviation, selection: $comfortablePaceMinutes) {
                    ForEach(3..<10, id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                Text(language.settings.timeSeparator)
                Picker(language.settings.secondsAbbreviation, selection: $comfortablePaceSeconds) {
                    ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", locale: language.uiLocale, $0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                Text(language.settings.paceUnit)
            }
            Stepper(
                language.settings.weeklyVolume(Int(manualWeeklyKm)),
                value: $manualWeeklyKm,
                in: 10...80,
                step: 5
            )
        } header: {
            Text(language.settings.currentFitness)
        } footer: {
            Text(language.settings.coldStartFitnessFooter)
        }
    }

    private var feasibilitySection: some View {
        Section(language.settings.feasibility) {
            if let assessment {
                HStack {
                    Image(systemName: assessment.verdict.symbolName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.settings.feasibilityVerdict(assessment.verdict)).font(.subheadline.weight(.semibold))
                        Text(language.settings.goalFitness(
                            goal: Int(assessment.goalVDOT.rounded()),
                            projected: Int(assessment.projectedVDOT.rounded())
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(assessment.verdict.color)
            } else {
                Text(language.settings.enterGoalDetails)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Derived state

    private var targetTimeSeconds: Double {
        Double(targetHours * 3600 + targetMinutes * 60)
    }

    private var effectiveFitness: FitnessProfile {
        fitness ?? FitnessEstimator.profile(
            comfortablePaceSecondsPerKm: Double(comfortablePaceMinutes * 60 + comfortablePaceSeconds),
            weeklyVolumeKm: manualWeeklyKm
        )
    }

    private var isValid: Bool {
        targetTimeSeconds > 0
            && (3...7).contains(selectedDays.count)
            && selectedDays.contains(longRunDay)
            && calendar.startOfDay(for: raceDate) > calendar.startOfDay(for: .now)
    }

    private var assessment: FeasibilityCheck.Assessment? {
        guard isValid else { return nil }
        return FeasibilityCheck.assess(
            goal: currentSpec, fitness: effectiveFitness, today: .now, calendar: calendar
        )
    }

    private var currentSpec: GoalSpec {
        GoalSpec(
            distance: distance,
            targetTimeSeconds: targetTimeSeconds,
            raceDate: raceDate,
            availableDays: selectedDays,
            longRunDay: longRunDay
        )
    }

    // MARK: - Actions

    private func load() {
        fitness = try? PlanStore.currentFitness(in: modelContext, today: .now, calendar: calendar)
        guard let existing = try? PlanStore.activeGoal(in: modelContext)?.spec else { return }
        isEditingExistingGoal = true
        distance = existing.distance
        targetHours = Int(existing.targetTimeSeconds) / 3600
        targetMinutes = (Int(existing.targetTimeSeconds) % 3600) / 60
        raceDate = max(existing.raceDate, calendar.date(byAdding: .day, value: 1, to: .now)!)
        selectedDays = existing.availableDays
        longRunDay = existing.longRunDay
    }

    private func requestSave() {
        if isEditingExistingGoal {
            isConfirmingRegeneration = true
        } else {
            save()
        }
    }

    private func save() {
        do {
            try PlanStore.replaceGoal(
                spec: currentSpec,
                fitness: effectiveFitness,
                today: .now,
                calendar: calendar,
                in: modelContext
            )
            NotificationCenter.default.post(name: .planDidChange, object: nil)
            dismiss()
        } catch {
            saveError = language.settings.couldNotSaveGoal(error.localizedDescription)
        }
    }
}

extension FeasibilityVerdict {

    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .stretch: "exclamationmark.triangle.fill"
        case .unrealistic: "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: Theme.good
        case .stretch: Theme.warn
        case .unrealistic: Theme.warn
        }
    }
}
