import SwiftUI

/// Garmin/HealthKit run summary used by the calendar after a planned workout is completed.
struct CalendarRunSummaryCard: View {
    let activity: CompletedActivity
    let plannedWorkout: PlannedWorkout?
    var compact: Bool = false
    var onReview: (() -> Void)? = nil

    private var load: Int {
        Int(TrainingLoad.sessionLoad(durationSeconds: activity.durationSeconds, avgPaceSecondsPerKm: activity.avgPaceSecondsPerKm, paces: nil).rounded())
    }

    private var filledSegments: Int {
        guard let plannedKm = plannedWorkout?.distanceKm, plannedKm > 0,
              let actualKm = activity.distanceMeters.map({ $0 / 1000 }) else {
            return min(5, max(1, Int((activity.durationSeconds / 1800).rounded())))
        }
        return min(5, max(1, Int((actualKm / plannedKm * 5).rounded())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Running")
                        .font(.torHeading(16, .bold))
                        .foregroundStyle(Theme.text)
                    Text(sourceLine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.faint)
                }

                Spacer(minLength: 8)

                if activity.postRunReviewDismissedAt != nil {
                    Text("REVIEWED")
                        .font(.torLabel(9, .bold))
                        .foregroundStyle(Theme.good)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.good.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(index < filledSegments ? Theme.accent : Theme.line)
                        .frame(height: compact ? 40 : 54)
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                metric("Duration", Formatters.duration(activity.durationSeconds).replacingOccurrences(of: " ", with: ""))
                metric("Distance", Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: ""))
                metric("Pace", Formatters.pace(activity.avgPaceSecondsPerKm).replacingOccurrences(of: " /km", with: "/km"))
                metric("Load", "\(load)")
                Spacer(minLength: 4)
                if let onReview {
                    Button(action: onReview) {
                        Label("Review", systemImage: "message.badge")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
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

    private var sourceLine: String {
        let clean = activity.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Apple Health" }
        if clean.localizedCaseInsensitiveContains("garmin") { return "\(clean) via Garmin" }
        return clean
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: 48, alignment: .leading)
    }
}
