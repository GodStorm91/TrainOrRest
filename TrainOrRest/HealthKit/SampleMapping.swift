import Foundation

// Plain-value summaries decoupled from HealthKit types so mapping rules stay
// pure and unit-testable without an HKHealthStore.

/// Everything needed from an HKWorkout to build a CompletedActivity.
struct WorkoutSummary {
    let uuid: UUID
    let start: Date
    let durationSeconds: Double
    let distanceMeters: Double?
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let sourceName: String
}

/// A quantity sample reduced to the fields the daily reducers need.
struct QuantitySampleSummary {
    let start: Date
    let value: Double
    let sourceName: String
}

enum SleepStage: String, Codable {
    case deep, rem, light, unspecified
}

/// An asleep-stage interval from sleep analysis.
struct SleepInterval {
    let start: Date
    let end: Date
    let sourceName: String
    /// Defaults to `.unspecified` so total-sleep callers/tests that don't care
    /// about staging keep working.
    var stage: SleepStage = .unspecified
}

enum GarminSource {
    /// Garmin Connect writes to Apple Health under this source-name prefix
    /// (verified empirically on device; kept as a prefix match to tolerate
    /// naming variants like "Garmin Connect™").
    static let namePrefix = "Garmin"

    /// When Garmin and other sources both contribute samples of a type
    /// (e.g. iPhone sleep estimates alongside watch data), keep only
    /// Garmin's to avoid double counting. Falls back to all items when
    /// Garmin wrote nothing.
    static func preferGarmin<T>(_ items: [T], sourceName: (T) -> String) -> [T] {
        let garmin = items.filter { sourceName($0).hasPrefix(namePrefix) }
        return garmin.isEmpty ? items : garmin
    }
}

enum ActivityMapper {
    static func averagePaceSecondsPerKm(distanceMeters: Double?, durationSeconds: Double) -> Double? {
        guard let meters = distanceMeters, meters > 0, durationSeconds > 0 else { return nil }
        return durationSeconds / (meters / 1000)
    }
}

enum SleepAggregator {
    /// Total asleep hours keyed by the date each sleep span ends — nights
    /// attribute to the wake date, naps to the same day. Overlapping intervals
    /// are merged first so multi-record nights and re-imports never double count.
    static func nightlySleepHours(intervals: [SleepInterval], calendar: Calendar) -> [Date: Double] {
        let preferred = GarminSource.preferGarmin(intervals, sourceName: \.sourceName)
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        var merged: [(start: Date, end: Date)] = []
        for interval in preferred {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append((interval.start, interval.end))
            }
        }

        var hoursByWakeDate: [Date: Double] = [:]
        for span in merged {
            let wakeDate = calendar.startOfDay(for: span.end)
            hoursByWakeDate[wakeDate, default: 0] += span.end.timeIntervalSince(span.start) / 3600
        }
        return hoursByWakeDate
    }
}

enum SleepStageAggregator {
    struct StageHours: Equatable {
        var deep = 0.0
        var rem = 0.0
        var light = 0.0
    }

    /// Per-stage hours keyed by wake date. Stages within a source are disjoint,
    /// so durations are summed directly (no overlap merge); `unspecified`
    /// counts toward light. Source preference matches the total aggregator.
    static func nightlyStageHours(intervals: [SleepInterval], calendar: Calendar) -> [Date: StageHours] {
        let preferred = GarminSource.preferGarmin(intervals, sourceName: \.sourceName)
            .filter { $0.end > $0.start }

        var byDay: [Date: StageHours] = [:]
        for interval in preferred {
            let day = calendar.startOfDay(for: interval.end)
            let hours = interval.end.timeIntervalSince(interval.start) / 3600
            var stages = byDay[day] ?? StageHours()
            switch interval.stage {
            case .deep: stages.deep += hours
            case .rem: stages.rem += hours
            case .light, .unspecified: stages.light += hours
            }
            byDay[day] = stages
        }
        return byDay
    }
}

enum WellnessReducer {
    /// Earliest sample value per day. Used for HRV (SDNN), where Garmin's
    /// overnight measurement is the first sample of the wake day.
    static func firstValuePerDay(_ samples: [QuantitySampleSummary], calendar: Calendar) -> [Date: Double] {
        reducePerDay(samples, calendar: calendar) { $0.start < $1.start }
    }

    /// Latest sample value per day. Used for resting HR and VO2max, where the
    /// most recent write for the day is authoritative.
    static func latestValuePerDay(_ samples: [QuantitySampleSummary], calendar: Calendar) -> [Date: Double] {
        reducePerDay(samples, calendar: calendar) { $0.start > $1.start }
    }

    private static func reducePerDay(
        _ samples: [QuantitySampleSummary],
        calendar: Calendar,
        winner: (QuantitySampleSummary, QuantitySampleSummary) -> Bool
    ) -> [Date: Double] {
        let preferred = GarminSource.preferGarmin(samples, sourceName: \.sourceName)
        var pickByDay: [Date: QuantitySampleSummary] = [:]
        for sample in preferred {
            let day = calendar.startOfDay(for: sample.start)
            if let current = pickByDay[day] {
                if winner(sample, current) { pickByDay[day] = sample }
            } else {
                pickByDay[day] = sample
            }
        }
        return pickByDay.mapValues(\.value)
    }
}
