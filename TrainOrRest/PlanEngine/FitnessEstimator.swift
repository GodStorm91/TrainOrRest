import Foundation

/// Derives a FitnessProfile from recent run history. Pure: caller supplies
/// samples, `today`, and a calendar.
enum FitnessEstimator {
    static let historyWindowWeeks = 8
    /// Runs shorter than this are too noisy for a VDOT estimate.
    static let minEffortDistanceKm = 3.0
    static let minEffortDurationSeconds = 12.0 * 60
    /// Below this, history is a cold start — require manual input instead.
    static let minQualifyingRuns = 6
    static let minHistorySpanDays = 28

    /// Returns nil on cold start (<6 qualifying runs or <4 weeks of history);
    /// callers must then fall back to `profile(comfortablePaceSecondsPerKm:)`.
    static func estimate(samples: [RunSample], today: Date, calendar: Calendar) -> FitnessProfile? {
        let windowStart = calendar.date(
            byAdding: .day,
            value: -historyWindowWeeks * 7,
            to: calendar.startOfDay(for: today)
        ) ?? .distantPast

        let qualifying = samples.filter {
            $0.date >= windowStart && $0.date <= today
                && $0.distanceKm >= minEffortDistanceKm
                && $0.durationSeconds >= minEffortDurationSeconds
        }

        guard qualifying.count >= minQualifyingRuns,
              let oldest = qualifying.map(\.date).min(),
              let newest = qualifying.map(\.date).max(),
              newest.timeIntervalSince(oldest) >= Double(minHistorySpanDays) * 86_400
        else { return nil }

        // Best training effort as VDOT. Training runs undersell race fitness,
        // which errs conservative (slower training paces) — acceptable.
        let bestVDOT = qualifying
            .map { VDOTTable.vdot(distanceMeters: $0.distanceKm * 1000, timeSeconds: $0.durationSeconds) }
            .max() ?? 0

        func volume(weeksAgoRange range: Range<Int>) -> Double {
            let end = calendar.date(byAdding: .day, value: -range.lowerBound * 7, to: calendar.startOfDay(for: today))!
            let start = calendar.date(byAdding: .day, value: -range.upperBound * 7, to: calendar.startOfDay(for: today))!
            return weeklyAverage(samples: samples, start: start, end: end, weeks: range.count)
        }

        let recent = volume(weeksAgoRange: 0..<4)
        let prior = volume(weeksAgoRange: 4..<8)
        let trend = prior > 0 ? (recent - prior) / prior : 0

        return FitnessProfile(
            vdot: bestVDOT,
            weeklyVolumeKm: recent,
            volumeTrend: trend,
            longestRecentRunKm: qualifying.map(\.distanceKm).max() ?? 0
        )
    }

    /// Cold-start fallback: user states a comfortable (easy) pace. Easy pace
    /// sits around 70% VO2max in the Daniels model.
    static func profile(comfortablePaceSecondsPerKm pace: Double, weeklyVolumeKm: Double) -> FitnessProfile {
        let easyFraction = 0.70
        let velocity = 60_000 / pace
        let vdot = VDOTTable.oxygenCost(velocityMetersPerMinute: velocity) / easyFraction
        return FitnessProfile(
            vdot: vdot,
            weeklyVolumeKm: weeklyVolumeKm,
            volumeTrend: 0,
            longestRecentRunKm: 0
        )
    }

    /// All runs count toward volume (unlike the VDOT estimate, which only
    /// uses qualifying efforts). The window ends at start-of-today, so
    /// today's runs are excluded — a conservative undercount.
    private static func weeklyAverage(
        samples: [RunSample], start: Date, end: Date, weeks: Int
    ) -> Double {
        guard weeks > 0 else { return 0 }
        let total = samples
            .filter { $0.date >= start && $0.date < end }
            .reduce(0) { $0 + $1.distanceKm }
        return total / Double(weeks)
    }
}
