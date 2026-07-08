import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    @Bindable var workout: PlannedWorkout
    @Query private var activities: [CompletedActivity]

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

            if let matched = matchedActivity {
                Section("Completed Run") {
                    NavigationLink {
                        ActivityDetailView(activity: matched)
                    } label: {
                        ActivityRow(activity: matched)
                    }
                }
            }

            Section("Status") {
                statusButtons
            }
        }
        .navigationTitle(workout.date.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var matchedActivity: CompletedActivity? {
        guard let uuid = workout.matchedActivityUUID else { return nil }
        return activities.first { $0.hkUUID == uuid }
    }

    private var statusButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusButton("Done", status: .done, tint: .green)
                statusButton("Skipped", status: .skipped, tint: .orange)
                statusButton("Planned", status: .planned, tint: .blue)
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
        }
        .tint(tint)
        .disabled(workout.status == status)
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
