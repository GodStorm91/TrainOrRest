import SwiftUI

struct ActivityDetailView: View {
    let activity: CompletedActivity

    var body: some View {
        List {
            Section {
                RunDetailSummary(activity: activity)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
            }
            Section("Run") {
                LabeledContent("Date", value: activity.date.formatted(date: .long, time: .shortened))
                LabeledContent("Distance", value: Formatters.kilometers(activity.distanceMeters))
                LabeledContent("Duration", value: Formatters.duration(activity.durationSeconds))
                LabeledContent("Avg Pace", value: Formatters.pace(activity.avgPaceSecondsPerKm))
            }
            Section("Heart Rate") {
                LabeledContent("Average", value: Formatters.heartRate(activity.avgHeartRate))
                LabeledContent("Max", value: Formatters.heartRate(activity.maxHeartRate))
            }
            Section("Source") {
                LabeledContent("Recorded by", value: activity.sourceName)
            }
        }
        .navigationTitle(activity.date.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RunDetailSummary: View {
    let activity: CompletedActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Formatters.kilometers(activity.distanceMeters))
                        .font(.largeTitle.bold())
                        .contentTransition(.numericText())
                }
                Spacer()
                Image(systemName: "figure.run")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(activity.effortColor)
                    .frame(width: 42, height: 42)
                    .background(TrainingVisualStyle.tint(activity.effortColor, opacity: 0.18), in: Circle())
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { stats }
                VStack(alignment: .leading, spacing: 6) { stats }
            }
        }
        .padding(14)
        .background(TrainingVisualStyle.tint(activity.effortColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(TrainingVisualStyle.tint(activity.effortColor, opacity: 0.28), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.18), value: activity.distanceMeters)
    }

    @ViewBuilder
    private var stats: some View {
        ActivityStatPill(Formatters.pace(activity.avgPaceSecondsPerKm), symbol: "speedometer")
        ActivityStatPill(Formatters.duration(activity.durationSeconds), symbol: "clock")
        ActivityStatPill(Formatters.heartRate(activity.avgHeartRate), symbol: "heart")
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
