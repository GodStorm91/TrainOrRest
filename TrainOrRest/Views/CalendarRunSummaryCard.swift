import SwiftUI

/// Garmin/HealthKit run summary used by the calendar after a planned workout is completed.
struct CalendarRunSummaryCard: View {
    let activity: CompletedActivity
    let plannedWorkout: PlannedWorkout?
    var compact: Bool = false
    var reviewDestination: ChatView? = nil
    var onReview: (() -> Void)? = nil
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    private var load: Int {
        Int(TrainingLoad.sessionLoad(durationSeconds: activity.durationSeconds, avgPaceSecondsPerKm: activity.avgPaceSecondsPerKm, paces: nil).rounded())
    }

    private var splits: [SplitDatum] {
        (activity.splits ?? []).compactMap(SplitDatum.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.history.running)
                        .font(.torHeading(16, .bold))
                        .foregroundStyle(Theme.text)
                    Text(sourceLine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.faint)
                }

                Spacer(minLength: 8)

                if activity.postRunReviewDismissedAt != nil {
                    Text(language.history.reviewed)
                        .font(.torLabel(9, .bold))
                        .foregroundStyle(Theme.good)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.good.opacity(0.12), in: Capsule())
                }
            }

            if !splits.isEmpty {
                SplitPaceColumns(
                    splits: splits,
                    band: plannedWorkout?.paceBand,
                    height: compact ? 40 : 54
                )
            } else if activity.splits != nil {
                Text(language.history.splitsUnavailable)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.faint)
            }

            metricSummary

            if let plannedWorkout {
                planTargetRow(plannedWorkout)
            }
        }
        .padding(compact ? 12 : 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var reviewAction: some View {
        if let reviewDestination {
            NavigationLink {
                reviewDestination
            } label: {
                reviewLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.history.reviewRunWithCoach)
        } else if let onReview {
            Button(action: onReview) {
                reviewLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.history.reviewRun)
        }
    }

    private var reviewLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "message.badge")
            Text(language.history.review)
        }
        .font(.footnote.weight(.bold))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: compact ? 78 : 92, minHeight: 42)
        .background(Color.black, in: Capsule())
    }

    private var metricSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                metric(language.history.duration, Formatters.duration(activity.durationSeconds).replacingOccurrences(of: " ", with: ""), fixedWidth: true)
                metric(language.history.distance, Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: ""), fixedWidth: true)
                metric(language.history.pace, Formatters.pace(activity.avgPaceSecondsPerKm).replacingOccurrences(of: " /km", with: "/km"), fixedWidth: true)
                metric(language.history.load, "\(load)", fixedWidth: true)
                Spacer(minLength: 4)
                reviewAction
            }
            VStack(alignment: .leading, spacing: 10) {
                metric(language.history.duration, Formatters.duration(activity.durationSeconds).replacingOccurrences(of: " ", with: ""))
                metric(language.history.distance, Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: ""))
                metric(language.history.pace, Formatters.pace(activity.avgPaceSecondsPerKm).replacingOccurrences(of: " /km", with: "/km"))
                metric(language.history.load, "\(load)")
                reviewAction
            }
        }
    }

    private func planTargetRow(_ workout: PlannedWorkout) -> some View {
        let workoutName = workout.kind.map(language.name) ?? language.genericRunLabel
        let metrics = plannedMetrics(workout)

        return HStack(spacing: 8) {
            Image(systemName: workout.kind?.symbolName ?? "figure.run")
                .font(.caption.weight(.semibold))
                .foregroundStyle(workout.kind?.styleColor ?? Theme.accent)
                .frame(width: 24, height: 24)
                .background(
                    Theme.soft(workout.kind?.styleColor ?? Theme.accent),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(language.history.planTarget)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                Text(workoutName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.text)
                Text(metrics)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(
            language.history.planTargetAccessibility(
                workout: workoutName,
                metrics: metrics
            )
        )
    }

    private func plannedMetrics(_ workout: PlannedWorkout) -> String {
        var metrics = [String(format: "%.2f km", workout.distanceKm)]
        if let paceBand = workout.paceBand {
            metrics.append(
                Formatters.paceBand(paceBand)
                    .replacingOccurrences(of: " /km", with: "/km")
            )
        }
        if let duration = workout.expectedDurationSeconds {
            metrics.append("~\(Int((duration / 60).rounded())) min")
        }
        return metrics.joined(separator: " · ")
    }

    private var sourceLine: String {
        let clean = activity.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Apple Health" }
        if clean.localizedCaseInsensitiveContains("garmin") { return language.history.viaGarmin(clean) }
        return clean
    }

    private func metric(_ label: String, _ value: String, fixedWidth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: fixedWidth, vertical: !fixedWidth)
        }
        .frame(minWidth: 48, alignment: .leading)
    }
}
