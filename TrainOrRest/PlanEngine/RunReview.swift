import Foundation

/// Post-run review for a completed activity. Pure value logic so UI can stay thin
/// and HealthKit/SwiftData quirks don't leak into the coaching copy.
struct RunReview: Equatable {
    enum Verdict: Equatable {
        case onPlan
        case overcooked
        case undercooked
        case unmatched

        var title: String {
            switch self {
            case .onPlan: "Nice execution"
            case .overcooked: "You went hotter than planned"
            case .undercooked: "You kept it lighter than planned"
            case .unmatched: "Run logged"
            }
        }

        var symbolName: String {
            switch self {
            case .onPlan: "checkmark.seal.fill"
            case .overcooked: "flame.fill"
            case .undercooked: "leaf.fill"
            case .unmatched: "figure.run"
            }
        }
    }

    var verdict: Verdict
    var distanceDeltaKm: Double?
    var paceDeltaSecondsPerKm: Double?
    var durationDeltaSeconds: Double?
    var bullets: [String]
    var recoveryNote: String

    static func make(
        activityDistanceMeters: Double?,
        activityDurationSeconds: Double,
        activityPaceSecondsPerKm: Double?,
        avgHeartRate: Double?,
        plannedDistanceKm: Double?,
        plannedPaceBand: PaceBand?,
        plannedDurationSeconds: Double?
    ) -> RunReview {
        let activityDistanceKm = activityDistanceMeters.map { $0 / 1000 }
        let distanceDelta = zip(activityDistanceKm, plannedDistanceKm).map(-)
        let plannedPace = plannedPaceBand.map { ($0.fastSecondsPerKm + $0.slowSecondsPerKm) / 2 }
        let paceDelta = zip(activityPaceSecondsPerKm, plannedPace).map(-)
        let durationDelta = plannedDurationSeconds.map { activityDurationSeconds - $0 }

        let hasPlan = plannedDistanceKm != nil || plannedPaceBand != nil || plannedDurationSeconds != nil
        let verdict = classify(
            hasPlan: hasPlan,
            distanceDeltaKm: distanceDelta,
            paceDeltaSecondsPerKm: paceDelta,
            avgHeartRate: avgHeartRate
        )

        var bullets: [String] = []
        if let distanceDelta {
            bullets.append(distanceDeltaText(distanceDelta))
        }
        if let paceDelta {
            bullets.append(paceDeltaText(paceDelta))
        }
        if let durationDelta {
            bullets.append(durationDeltaText(durationDelta))
        }
        if let avgHeartRate {
            bullets.append("Average HR: \(Int(avgHeartRate.rounded())) bpm")
        }
        if bullets.isEmpty {
            bullets.append("Synced successfully. Add distance/pace data for a sharper review.")
        }

        return RunReview(
            verdict: verdict,
            distanceDeltaKm: distanceDelta,
            paceDeltaSecondsPerKm: paceDelta,
            durationDeltaSeconds: durationDelta,
            bullets: bullets,
            recoveryNote: recoveryNote(for: verdict, avgHeartRate: avgHeartRate)
        )
    }

    private static func classify(
        hasPlan: Bool,
        distanceDeltaKm: Double?,
        paceDeltaSecondsPerKm: Double?,
        avgHeartRate: Double?
    ) -> Verdict {
        guard hasPlan else { return .unmatched }
        let wentLong = (distanceDeltaKm ?? 0) > 1.0
        let wentShort = (distanceDeltaKm ?? 0) < -1.0
        let muchFaster = (paceDeltaSecondsPerKm ?? 0) < -20
        let muchSlower = (paceDeltaSecondsPerKm ?? 0) > 30
        let highHR = (avgHeartRate ?? 0) >= 165

        if wentLong || muchFaster || highHR { return .overcooked }
        if wentShort || muchSlower { return .undercooked }
        return .onPlan
    }

    private static func distanceDeltaText(_ delta: Double) -> String {
        if abs(delta) < 0.15 { return "Distance landed on plan" }
        let direction = delta > 0 ? "over" : "under"
        return String(format: "%.1f km %@ planned", abs(delta), direction)
    }

    private static func paceDeltaText(_ delta: Double) -> String {
        if abs(delta) < 10 { return "Pace was right in range" }
        let direction = delta < 0 ? "faster" : "slower"
        return "\(formatPaceDelta(abs(delta))) /km \(direction) than planned"
    }

    private static func durationDeltaText(_ delta: Double) -> String {
        if abs(delta) < 60 { return "Duration matched the plan" }
        let direction = delta > 0 ? "longer" : "shorter"
        return "\(formatDurationDelta(abs(delta))) \(direction) than planned"
    }

    private static func formatPaceDelta(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func formatDurationDelta(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    private static func recoveryNote(for verdict: Verdict, avgHeartRate: Double?) -> String {
        switch verdict {
        case .onPlan:
            return "Good match. Keep the next session as planned unless tomorrow's readiness says otherwise."
        case .overcooked:
            return "Treat this as extra load. If tomorrow feels heavy, downgrade the next quality session."
        case .undercooked:
            return "No drama. Bank the aerobic work and avoid cramming the missed load into tomorrow."
        case .unmatched:
            if let avgHeartRate, avgHeartRate >= 165 {
                return "This looks like a hard effort. Give recovery priority before stacking intensity."
            }
            return "Synced from Garmin. Match it to a plan day for a tighter review."
        }
    }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
