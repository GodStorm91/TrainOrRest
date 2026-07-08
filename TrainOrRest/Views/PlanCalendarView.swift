import SwiftData
import SwiftUI

/// The full training plan, week by week.
struct PlanCalendarView: View {
    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @Query private var plans: [TrainingPlan]
    @State private var isEditingGoal = false

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
                } else {
                    ForEach(weekStarts, id: \.self) { weekStart in
                        Section {
                            ForEach(workoutsByWeekStart[weekStart] ?? []) { workout in
                                NavigationLink {
                                    WorkoutDetailView(workout: workout)
                                } label: {
                                    PlannedWorkoutRow(workout: workout)
                                }
                            }
                        } header: {
                            weekHeader(weekStart)
                        }
                        .id(weekStart)
                    }
                }
            }
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
        HStack {
            Text("Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))")
            if let index = planWeekIndex(for: weekStart), let plan = plans.first {
                if let phase = plan.phase(forWeek: index) {
                    Text("· \(phase.displayName)")
                }
                Text("· \(Int(plan.weekTargetVolumesKm[index].rounded())) km")
                if plan.weekIsDown[index] {
                    Text("· recovery").foregroundStyle(.teal)
                }
            }
        }
    }
}

struct PlannedWorkoutRow: View {
    let workout: PlannedWorkout

    private var isToday: Bool { Calendar.current.isDateInToday(workout.date) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind?.symbolName ?? "questionmark")
                .foregroundStyle(workout.kind == .race ? .orange : .accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(workout.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.subheadline.weight(isToday ? .bold : .medium))
                    if isToday {
                        Text("Today")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(workout.kind?.displayName ?? workout.kindRaw)
                    Text(Formatters.kilometers(workout.distanceKm * 1000))
                    if let band = workout.paceBand {
                        Text(Formatters.paceBand(band))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: workout.status.symbolName)
                .foregroundStyle(workout.status.color)
        }
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
        case .planned: .secondary
        case .done: .green
        case .skipped: .orange
        }
    }
}

extension Formatters {
    static func paceBand(_ band: PaceBand) -> String {
        let fast = pace(band.fastSecondsPerKm).replacingOccurrences(of: " /km", with: "")
        return "\(fast)–\(pace(band.slowSecondsPerKm))"
    }
}
