import SwiftData
import SwiftUI

/// Goal entry / editing. Shows a live feasibility verdict once inputs are
/// valid; on save the previous goal and plan are replaced.
struct GoalEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            Form {
                raceSection
                availabilitySection
                if fitness == nil { coldStartSection }
                feasibilitySection
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Race Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { load() }
        }
    }

    // MARK: - Sections

    private var raceSection: some View {
        Section("Race") {
            Picker("Distance", selection: $distance) {
                ForEach(RaceDistance.allCases) { Text($0.displayName).tag($0) }
            }
            HStack {
                Text("Target time")
                Spacer()
                Picker("Hours", selection: $targetHours) {
                    ForEach(0..<8, id: \.self) { Text("\($0) h").tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                Picker("Minutes", selection: $targetMinutes) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d m", $0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
            }
            DatePicker(
                "Race date",
                selection: $raceDate,
                in: calendar.date(byAdding: .day, value: 1, to: .now)!...,
                displayedComponents: .date
            )
        }
    }

    private var availabilitySection: some View {
        Section {
            ForEach(Weekday.allCases, id: \.self) { day in
                Toggle(day.shortName, isOn: Binding(
                    get: { selectedDays.contains(day) },
                    set: { included in
                        if included {
                            selectedDays.insert(day)
                        } else if selectedDays.count > 3 {
                            selectedDays.remove(day) // keep the 3-day minimum
                        }
                        if !selectedDays.contains(longRunDay), let fallback = selectedDays.sorted().last {
                            longRunDay = fallback
                        }
                    }
                ))
            }
            Picker("Long run day", selection: $longRunDay) {
                ForEach(selectedDays.sorted(), id: \.self) { Text($0.shortName).tag($0) }
            }
        } header: {
            Text("Running Days (\(selectedDays.count)/week)")
        } footer: {
            if selectedDays.count < 3 {
                Text("Pick at least 3 running days.").foregroundStyle(.red)
            }
        }
    }

    private var coldStartSection: some View {
        Section {
            HStack {
                Text("Comfortable pace")
                Spacer()
                Picker("Min", selection: $comfortablePaceMinutes) {
                    ForEach(3..<10, id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                Text(":")
                Picker("Sec", selection: $comfortablePaceSeconds) {
                    ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu)
                Text("/km")
            }
            Stepper(
                "Weekly volume: \(Int(manualWeeklyKm)) km",
                value: $manualWeeklyKm,
                in: 10...80,
                step: 5
            )
        } header: {
            Text("Current Fitness")
        } footer: {
            Text("Not enough recent running history to estimate fitness — tell us how you run today.")
        }
    }

    private var feasibilitySection: some View {
        Section("Feasibility") {
            if let assessment {
                HStack {
                    Image(systemName: assessment.verdict.symbolName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(assessment.verdict.title).font(.subheadline.weight(.semibold))
                        Text("Goal fitness \(Int(assessment.goalVDOT.rounded())) vs projected \(Int(assessment.projectedVDOT.rounded())) VDOT")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(assessment.verdict.color)
            } else {
                Text("Enter goal details to see feasibility.")
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
        distance = existing.distance
        targetHours = Int(existing.targetTimeSeconds) / 3600
        targetMinutes = (Int(existing.targetTimeSeconds) % 3600) / 60
        raceDate = max(existing.raceDate, calendar.date(byAdding: .day, value: 1, to: .now)!)
        selectedDays = existing.availableDays
        longRunDay = existing.longRunDay
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
            dismiss()
        } catch {
            saveError = "Could not save goal: \(error.localizedDescription)"
        }
    }
}

extension FeasibilityVerdict {
    var title: String {
        switch self {
        case .ok: "Realistic goal"
        case .stretch: "Stretch goal"
        case .unrealistic: "Very ambitious goal"
        }
    }

    var symbolName: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .stretch: "exclamationmark.triangle.fill"
        case .unrealistic: "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .stretch: .orange
        case .unrealistic: .red
        }
    }
}
