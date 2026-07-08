import SwiftData
import SwiftUI

/// The full training plan, week by week.
struct PlanCalendarView: View {
    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @Query private var plans: [TrainingPlan]
    @State private var isEditingGoal = false
    @State private var visibleWeekStarts: Set<Date> = []

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Plan Yet",
                        systemImage: "calendar.badge.plus",
                        description: Text("Set a race goal to generate your training plan.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(weekStarts, id: \.self) { weekStart in
                        Section {
                            ForEach(workoutsByWeekStart[weekStart] ?? []) { workout in
                                NavigationLink {
                                    WorkoutDetailView(workout: workout)
                                } label: {
                                    PlannedWorkoutRow(workout: workout)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Theme.line)
                            }
                        } header: {
                            weekHeader(weekStart)
                        }
                        .id(weekStart)
                        .onAppear { visibleWeekStarts.insert(weekStart) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Training Plan")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Today", systemImage: "calendar") {
                        proxy.scrollTo(todayWeekStart, anchor: .top)
                    }
                    .disabled(!weekStarts.contains(todayWeekStart))
                    Button("Edit Goal", systemImage: "target") { isEditingGoal = true }
                }
            }
            .sheet(isPresented: $isEditingGoal) { GoalEntryView() }
        }
    }

    // Weeks are grouped by date, not stored week index: regeneration keeps
    // past rows from older generations whose indices no longer align.
    private var workoutsByWeekStart: [Date: [PlannedWorkout]] {
        Dictionary(grouping: workouts) {
            PlanGenerator.mondayOfWeek(containing: $0.date, calendar: calendar)
        }
    }

    private var weekStarts: [Date] {
        workoutsByWeekStart.keys.sorted()
    }

    private var todayWeekStart: Date {
        PlanGenerator.mondayOfWeek(containing: .now, calendar: calendar)
    }

    /// Index into the current plan's week metadata, valid only for weeks at
    /// or after the plan anchor.
    private func planWeekIndex(for weekStart: Date) -> Int? {
        guard let plan = plans.first else { return nil }
        let anchorWeek = PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
        let offset = (calendar.dateComponents([.day], from: anchorWeek, to: weekStart).day ?? 0) / 7
        guard offset >= 0, plan.weekPhasesRaw.indices.contains(offset) else { return nil }
        return offset
    }

    @ViewBuilder
    private func weekHeader(_ weekStart: Date) -> some View {
        PlanWeekHeaderView(
            weekStart: weekStart,
            phase: phase(for: weekStart),
            volumeKm: volume(for: weekStart),
            isRecovery: isRecoveryWeek(weekStart)
        )
        .opacity(visibleWeekStarts.contains(weekStart) ? 1 : 0.85)
        .animation(.easeOut(duration: 0.18), value: visibleWeekStarts.contains(weekStart))
    }

    private func phase(for weekStart: Date) -> TrainingPhase? {
        guard let index = planWeekIndex(for: weekStart), let plan = plans.first else { return nil }
        return plan.phase(forWeek: index)
    }

    private func volume(for weekStart: Date) -> Double? {
        guard let index = planWeekIndex(for: weekStart), let plan = plans.first else { return nil }
        return plan.weekTargetVolumesKm[index]
    }

    private func isRecoveryWeek(_ weekStart: Date) -> Bool {
        guard let index = planWeekIndex(for: weekStart), let plan = plans.first else { return false }
        return plan.weekIsDown[index]
    }
}

extension WorkoutKind {
    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .long: "Long run"
        case .tempo: "Tempo"
        case .intervals: "Intervals"
        case .race: "Race"
        }
    }

    var symbolName: String {
        switch self {
        case .easy: "figure.run"
        case .long: "arrow.up.right.circle"
        case .tempo: "gauge.with.needle"
        case .intervals: "timer"
        case .race: "flag.checkered"
        }
    }
}

extension WorkoutStatus {
    var symbolName: String {
        switch self {
        case .planned: "circle"
        case .done: "checkmark.circle.fill"
        case .skipped: "slash.circle"
        }
    }

    var color: Color {
        switch self {
        case .planned: Theme.dim
        case .done: Theme.good
        case .skipped: Theme.warn
        }
    }
}

extension Formatters {
    static func paceBand(_ band: PaceBand) -> String {
        let fast = pace(band.fastSecondsPerKm).replacingOccurrences(of: " /km", with: "")
        return "\(fast)–\(pace(band.slowSecondsPerKm))"
    }
}
