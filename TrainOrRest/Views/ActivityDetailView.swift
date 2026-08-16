import SwiftData
import SwiftUI

struct ActivityDetailView: View {
    let activity: CompletedActivity
    @Query(sort: \PlannedWorkout.date) private var plannedWorkouts: [PlannedWorkout]

    private let calendar = Calendar.current

    var body: some View {
        List {
            Section {
                RunDetailSummary(activity: activity)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
            }
            Section {
                RunReviewCard(activity: activity, plannedWorkout: matchedWorkout, compact: false)
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

    private var matchedWorkout: PlannedWorkout? {
        if let exact = plannedWorkouts.first(where: { $0.matchedActivityUUID == activity.hkUUID }) {
            return exact
        }
        return plannedWorkouts.first {
            calendar.isDate($0.date, inSameDayAs: activity.date)
        }
    }
}

struct RunReviewCard: View {
    let activity: CompletedActivity
    let plannedWorkout: PlannedWorkout?
    var compact = true

    private var review: RunReview {
        RunReview.make(
            activityDistanceMeters: activity.distanceMeters,
            activityDurationSeconds: activity.durationSeconds,
            activityPaceSecondsPerKm: activity.avgPaceSecondsPerKm,
            avgHeartRate: activity.avgHeartRate,
            plannedDistanceKm: plannedWorkout?.distanceKm,
            plannedPaceBand: plannedWorkout?.paceBand,
            plannedDurationSeconds: plannedWorkout?.expectedDurationSeconds
        )
    }

    private var accent: Color {
        switch review.verdict {
        case .onPlan: Theme.good
        case .overcooked: Theme.warn
        case .undercooked: Theme.data
        case .unmatched: Theme.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: review.verdict.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(TrainingVisualStyle.tint(accent, opacity: 0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    TorEyebrow("Post-run review").tracking(1.5)
                    Text(review.verdict.title)
                        .font(.torHeading(compact ? 16 : 18, .bold))
                        .foregroundStyle(Theme.text)
                }
                Spacer()
            }

            if let plannedWorkout {
                Text("Matched to \(plannedWorkout.kind?.displayName ?? plannedWorkout.kindRaw) · \(Formatters.kilometers(plannedWorkout.distanceKm * 1000))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            } else {
                Text("No planned workout matched yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(review.bullets.prefix(compact ? 3 : review.bullets.count)), id: \.self) { bullet in
                    Label(bullet, systemImage: "smallcircle.filled.circle")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
            }

            Text(review.recoveryNote)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TrainingVisualStyle.tint(accent, opacity: 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(TrainingVisualStyle.tint(accent, opacity: 0.35), lineWidth: 1))
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
