import Foundation

/// A distance sample reduced to the fields split reconstruction needs.
/// `meters` is the distance covered across `start...end`, not a running total.
struct DistanceSample: Equatable {
    let start: Date
    let end: Date
    let meters: Double
    let sourceName: String
}

/// A heart-rate reading reduced to a timestamp and a value. Garmin writes
/// these as instantaneous samples, so only the midpoint matters.
struct HeartRateSample: Equatable {
    let start: Date
    let end: Date
    let bpm: Double
    let sourceName: String

    var midpoint: Date {
        start.addingTimeInterval(end.timeIntervalSince(start) / 2)
    }
}

/// One kilometer of a run. The final entry may be shorter than a kilometer,
/// in which case `paceSecondsPerKm` is normalized but `distanceMeters` is not.
struct ActivitySplit: Codable, Equatable {
    let kilometer: Int
    let distanceMeters: Double
    let durationSeconds: Double
    let averageHeartRate: Double?

    var isPartial: Bool { distanceMeters < 999 }

    var paceSecondsPerKm: Double? {
        guard distanceMeters > 0, durationSeconds > 0 else { return nil }
        return durationSeconds / (distanceMeters / 1000)
    }
}

/// Why no splits could be produced. `noSamples` is retryable because Garmin
/// writes the workout before its sample series, so the series may still
/// arrive. The others are terminal for that activity.
enum SplitRejection: String, Equatable {
    case noSamples
    case tooShort
    case tooCoarse
}

/// Reconstruction outcome plus the measurements that explain it. The counts
/// are what tell us, on a real device, whether Garmin's HealthKit writes are
/// fine-grained enough for this approach at all.
struct SplitReconstruction: Equatable {
    let splits: [ActivitySplit]
    let distanceSampleCount: Int
    let samplesPerKilometer: Double
    let medianSampleSeconds: Double?
    let rejection: SplitRejection?

    var isRetryable: Bool { rejection == .noSamples }
}

enum SplitBuilder {
    /// A run shorter than this cannot produce a single full kilometer.
    static let minimumDistanceMeters: Double = 1000

    /// Below this, a kilometer boundary lands inside a sample covering more
    /// than a third of a kilometer and the resulting pace is interpolation,
    /// not measurement. Refusing beats reporting a number we invented.
    static let minimumSamplesPerKilometer: Double = 3

    /// A gap longer than this between consecutive distance samples is treated
    /// as a stop, not as slow running, and excluded from split duration.
    static let pauseThresholdSeconds: TimeInterval = 20

    /// A trailing fragment shorter than this is dropped rather than reported
    /// as its own split. A 40 m tail has no meaningful pace and reading one
    /// off a handful of samples invents precision.
    static let minimumPartialMeters: Double = 100

    static func reconstruct(
        distanceSamples: [DistanceSample],
        heartRateSamples: [HeartRateSample]
    ) -> SplitReconstruction {
        let distance = GarminSource.preferGarmin(distanceSamples, sourceName: \.sourceName)
            .filter { $0.meters > 0 }
            .sorted { $0.start < $1.start }

        guard !distance.isEmpty else {
            return SplitReconstruction(
                splits: [],
                distanceSampleCount: 0,
                samplesPerKilometer: 0,
                medianSampleSeconds: nil,
                rejection: .noSamples
            )
        }

        let totalMeters = distance.reduce(0) { $0 + $1.meters }
        let median = medianDuration(of: distance)
        let perKilometer = totalMeters > 0
            ? Double(distance.count) / (totalMeters / 1000)
            : 0

        func rejected(_ reason: SplitRejection) -> SplitReconstruction {
            SplitReconstruction(
                splits: [],
                distanceSampleCount: distance.count,
                samplesPerKilometer: perKilometer,
                medianSampleSeconds: median,
                rejection: reason
            )
        }

        guard totalMeters >= minimumDistanceMeters else { return rejected(.tooShort) }
        guard perKilometer >= minimumSamplesPerKilometer else { return rejected(.tooCoarse) }

        let heartRate = GarminSource.preferGarmin(heartRateSamples, sourceName: \.sourceName)
            .sorted { $0.midpoint < $1.midpoint }

        return SplitReconstruction(
            splits: splits(from: distance, heartRate: heartRate, totalMeters: totalMeters),
            distanceSampleCount: distance.count,
            samplesPerKilometer: perKilometer,
            medianSampleSeconds: median,
            rejection: nil
        )
    }

    /// Walks the samples once, advancing two clocks together: wall time, used
    /// to attribute heart rate, and moving time, which skips stops and is what
    /// a split duration should measure.
    private static func splits(
        from distance: [DistanceSample],
        heartRate: [HeartRateSample],
        totalMeters: Double
    ) -> [ActivitySplit] {
        var result: [ActivitySplit] = []
        var covered: Double = 0
        var movingElapsed: TimeInterval = 0
        var splitStartMoving: TimeInterval = 0
        var splitStartWall = distance[0].start
        var previousEnd: Date?

        for sample in distance {
            if let previousEnd {
                let gap = sample.start.timeIntervalSince(previousEnd)
                if gap > 0, gap <= pauseThresholdSeconds {
                    movingElapsed += gap
                }
            }
            previousEnd = sample.end

            let span = max(sample.end.timeIntervalSince(sample.start), 0)
            let sampleStartMoving = movingElapsed
            movingElapsed += span

            var target = Double(result.count + 1) * 1000
            while covered + sample.meters >= target {
                let fraction = (target - covered) / sample.meters
                let crossingWall = sample.start.addingTimeInterval(span * fraction)
                let crossingMoving = sampleStartMoving + span * fraction

                result.append(ActivitySplit(
                    kilometer: result.count + 1,
                    distanceMeters: 1000,
                    durationSeconds: crossingMoving - splitStartMoving,
                    averageHeartRate: averageHeartRate(heartRate, from: splitStartWall, to: crossingWall)
                ))

                splitStartMoving = crossingMoving
                splitStartWall = crossingWall
                target += 1000
            }
            covered += sample.meters
        }

        let remainder = totalMeters - Double(result.count) * 1000
        if remainder >= minimumPartialMeters, let lastEnd = previousEnd {
            result.append(ActivitySplit(
                kilometer: result.count + 1,
                distanceMeters: remainder,
                durationSeconds: movingElapsed - splitStartMoving,
                averageHeartRate: averageHeartRate(heartRate, from: splitStartWall, to: lastEnd)
            ))
        }

        return result
    }

    /// Plain mean of the readings whose midpoint falls in the window. Garmin
    /// samples heart rate at a near-constant cadence, so weighting by duration
    /// would add machinery without changing the answer.
    private static func averageHeartRate(
        _ samples: [HeartRateSample],
        from start: Date,
        to end: Date
    ) -> Double? {
        let window = samples.filter { $0.midpoint >= start && $0.midpoint < end }
        guard !window.isEmpty else { return nil }
        return window.reduce(0) { $0 + $1.bpm } / Double(window.count)
    }

    private static func medianDuration(of samples: [DistanceSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let durations = samples.map { $0.end.timeIntervalSince($0.start) }.sorted()
        let middle = durations.count / 2
        return durations.count.isMultiple(of: 2)
            ? (durations[middle - 1] + durations[middle]) / 2
            : durations[middle]
    }
}
