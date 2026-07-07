import SwiftData
import SwiftUI

/// "What changed & why": today's plan vs this morning's snapshot.
struct PlanDiffView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var changes: [PlanDiff.DayChange] = []

    var body: some View {
        List {
            if changes.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("Today's plan matches yesterday's schedule.")
                )
            } else {
                ForEach(changes.indices, id: \.self) { index in
                    DiffRow(change: changes[index])
                }
            }
        }
        .navigationTitle("Plan Changes")
        .task {
            changes = (try? ReadinessStore.todaysChanges(
                in: modelContext, today: .now, calendar: .current
            )) ?? []
        }
    }
}

private struct DiffRow: View {
    let change: PlanDiff.DayChange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                Text(summary(change.before))
                Image(systemName: "arrow.right")
                    .font(.caption)
                Text(summary(change.after))
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            Text(reasonText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func summary(_ entry: PlanDiff.Entry?) -> String {
        guard let entry else { return "Rest" }
        return "\(entry.kind.displayName) \(Formatters.kilometers(entry.distanceKm * 1000))"
    }

    private var reasonText: String {
        switch change.reason {
        case .readiness(let verdict):
            "Readiness: \(verdict.cardTitle.lowercased())"
        case .volumeRefit:
            "Volume re-fit from completed training"
        }
    }
}
