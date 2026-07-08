import SwiftUI

struct ActivityRow: View {
    let activity: CompletedActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(activity.effortColor)
                .frame(width: 34, height: 34)
                .background(TrainingVisualStyle.tint(activity.effortColor, opacity: 0.16), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { stats }
                    VStack(alignment: .leading, spacing: 6) { stats }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stats: some View {
        ActivityStatPill(Formatters.kilometers(activity.distanceMeters), symbol: "map")
        ActivityStatPill(Formatters.pace(activity.avgPaceSecondsPerKm), symbol: "speedometer")
        ActivityStatPill(Formatters.duration(activity.durationSeconds), symbol: "clock")
    }
}

struct ActivityStatPill: View {
    let value: String
    let symbol: String

    init(_ value: String, symbol: String) {
        self.value = value
        self.symbol = symbol
    }

    var body: some View {
        Label(value, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.chip, in: Capsule())
    }
}
