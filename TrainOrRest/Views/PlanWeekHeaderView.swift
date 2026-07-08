import SwiftUI

struct PlanWeekHeaderView: View {
    let weekStart: Date
    let phase: TrainingPhase?
    let volumeKm: Double?
    let isRecovery: Bool

    private var tint: Color {
        if isRecovery { return Theme.good }
        switch phase {
        case .base: return Theme.accent
        case .build: return Theme.warn
        case .peak: return Theme.accent2
        case .taper: return Theme.good
        case nil: return Theme.dim
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 6) { content }
        }
        .font(.torLabel(11, .semibold))
        .tracking(1.2)
        .foregroundStyle(Theme.faint)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var content: some View {
        Label("Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "calendar")
        if let phase {
            Text(phase.displayName.uppercased())
                .tracking(0.8)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.soft(tint), in: Capsule())
        }
        if let volumeKm {
            Text("\(Int(volumeKm.rounded())) km")
                .foregroundStyle(Theme.dim)
        }
        if isRecovery {
            Label("Recovery", systemImage: "leaf.fill")
                .foregroundStyle(Theme.good)
        }
    }
}
