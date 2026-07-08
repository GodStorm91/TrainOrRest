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
                Section {
                    Label("Changes are limited to the upcoming plan window and reviewed by local training rules.", systemImage: "checkmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(change.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ChangePill(title: "Before", value: summary(change.before), symbol: "clock")
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ChangePill(title: "Now", value: summary(change.after), symbol: "checkmark.circle")
            }

            VStack(alignment: .leading, spacing: 3) {
                Label(reasonText, systemImage: reasonSymbol)
                Label(impactText, systemImage: "chart.line.uptrend.xyaxis")
                Label("Reviewed by local plan rules before it reached your calendar.", systemImage: "checkmark.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func summary(_ entry: PlanDiff.Entry?) -> String {
        guard let entry else { return "Rest" }
        return "\(entry.kind.displayName) \(Formatters.kilometers(entry.distanceKm * 1000))"
    }

    private var reasonText: String {
        switch change.reason {
        case .readiness(let verdict):
            "Triggered by today's \(verdict.cardTitle.lowercased()) readiness verdict"
        case .volumeRefit:
            "Adjusted after recent completed training changed the volume fit"
        }
    }

    private var reasonSymbol: String {
        switch change.reason {
        case .readiness:
            "heart.text.square"
        case .volumeRefit:
            "arrow.triangle.2.circlepath"
        }
    }

    private var impactText: String {
        switch (change.before, change.after) {
        case let (before?, after?):
            let delta = after.distanceKm - before.distanceKm
            if before.kind != after.kind {
                return "Changed intensity from \(before.kind.displayName.lowercased()) to \(after.kind.displayName.lowercased())."
            }
            if abs(delta) >= 0.05 {
                return String(format: "Distance changed by %.1f km.", delta)
            }
            return "Workout kept in place with updated training details."
        case (_?, nil):
            return "Workout removed so the day becomes recovery."
        case (nil, let after?):
            return "Added \(after.kind.displayName.lowercased()) to keep the plan balanced."
        case (nil, nil):
            return "No workout impact."
        }
    }
}

private struct ChangePill: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }
}
