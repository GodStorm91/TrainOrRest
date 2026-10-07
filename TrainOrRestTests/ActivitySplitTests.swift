import XCTest
@testable import TrainOrRest

final class ActivitySplitTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    /// Builds a run as evenly spaced distance samples. `paces` holds one pace
    /// in seconds per kilometer for each kilometer, so the expected split
    /// durations are the input, not a derivation of the implementation.
    private func run(
        paces: [Double],
        samplesPerKilometer: Int,
        source: String = "Garmin Connect",
        startingAt offset: TimeInterval = 0
    ) -> [DistanceSample] {
        var samples: [DistanceSample] = []
        var cursor = start.addingTimeInterval(offset)
        let meters = 1000 / Double(samplesPerKilometer)
        for pace in paces {
            let span = pace / Double(samplesPerKilometer)
            for _ in 0..<samplesPerKilometer {
                let end = cursor.addingTimeInterval(span)
                samples.append(DistanceSample(start: cursor, end: end, meters: meters, sourceName: source))
                cursor = end
            }
        }
        return samples
    }

    private func heartRates(_ values: [(TimeInterval, Double)], source: String = "Garmin Connect") -> [HeartRateSample] {
        values.map {
            let at = start.addingTimeInterval($0.0)
            return HeartRateSample(start: at, end: at, bpm: $0.1, sourceName: source)
        }
    }

    // MARK: - Reconstruction

    func testSplitDurationsMatchEachKilometersPace() {
        let result = SplitBuilder.reconstruct(
            distanceSamples: run(paces: [300, 330, 285], samplesPerKilometer: 10),
            heartRateSamples: []
        )

        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.splits.map(\.kilometer), [1, 2, 3])
        XCTAssertEqual(result.splits.map(\.durationSeconds), [300, 330, 285], accuracy: 0.01)
    }

    func testKilometerBoundaryInterpolatesInsideASample() {
        // 150 m samples never land on a kilometer boundary, so every split
        // after the first depends on interpolating within a sample.
        var samples: [DistanceSample] = []
        var cursor = start
        for _ in 0..<20 {
            let end = cursor.addingTimeInterval(45)
            samples.append(DistanceSample(start: cursor, end: end, meters: 150, sourceName: "Garmin Connect"))
            cursor = end
        }

        let result = SplitBuilder.reconstruct(distanceSamples: samples, heartRateSamples: [])

        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.splits.count, 3)
        // Constant 150 m per 45 s is 300 s/km throughout.
        for split in result.splits.prefix(3) where !split.isPartial {
            XCTAssertEqual(split.durationSeconds, 300, accuracy: 0.01)
        }
    }

    func testTrailingFragmentIsReportedAsPartialWithNormalizedPace() {
        var samples = run(paces: [300], samplesPerKilometer: 10)
        let last = samples[samples.count - 1].end
        samples.append(DistanceSample(
            start: last,
            end: last.addingTimeInterval(150),
            meters: 500,
            sourceName: "Garmin Connect"
        ))

        let result = SplitBuilder.reconstruct(distanceSamples: samples, heartRateSamples: [])

        XCTAssertEqual(result.splits.count, 2)
        let partial = result.splits[1]
        XCTAssertTrue(partial.isPartial)
        XCTAssertEqual(partial.distanceMeters, 500, accuracy: 0.01)
        XCTAssertEqual(partial.durationSeconds, 150, accuracy: 0.01)
        XCTAssertEqual(partial.paceSecondsPerKm ?? 0, 300, accuracy: 0.01)
    }

    func testFragmentBelowTheFloorIsDropped() {
        var samples = run(paces: [300], samplesPerKilometer: 10)
        let last = samples[samples.count - 1].end
        samples.append(DistanceSample(
            start: last,
            end: last.addingTimeInterval(15),
            meters: 50,
            sourceName: "Garmin Connect"
        ))

        let result = SplitBuilder.reconstruct(distanceSamples: samples, heartRateSamples: [])

        XCTAssertEqual(result.splits.count, 1)
    }

    // MARK: - Pauses

    func testLongGapBetweenSamplesIsExcludedFromSplitDuration() {
        let first = run(paces: [300], samplesPerKilometer: 10)
        let stopEnd = first[first.count - 1].end.addingTimeInterval(180)
        let second = run(paces: [300], samplesPerKilometer: 10, startingAt: stopEnd.timeIntervalSince(start))

        let result = SplitBuilder.reconstruct(distanceSamples: first + second, heartRateSamples: [])

        XCTAssertEqual(result.splits.count, 2)
        // Wall clock puts 480 s between the boundaries; moving time is 300 s.
        XCTAssertEqual(result.splits[1].durationSeconds, 300, accuracy: 0.01)
    }

    func testShortGapCountsAsRunningTime() {
        let first = run(paces: [300], samplesPerKilometer: 10)
        let resumeAt = first[first.count - 1].end.addingTimeInterval(10)
        let second = run(paces: [300], samplesPerKilometer: 10, startingAt: resumeAt.timeIntervalSince(start))

        let result = SplitBuilder.reconstruct(distanceSamples: first + second, heartRateSamples: [])

        XCTAssertEqual(result.splits[1].durationSeconds, 310, accuracy: 0.01)
    }

    // MARK: - Heart rate

    func testHeartRateIsAveragedWithinEachKilometer() {
        let result = SplitBuilder.reconstruct(
            distanceSamples: run(paces: [300, 300], samplesPerKilometer: 10),
            heartRateSamples: heartRates([
                (60, 140), (120, 150),
                (360, 170), (420, 180),
            ])
        )

        XCTAssertEqual(result.splits[0].averageHeartRate ?? 0, 145, accuracy: 0.01)
        XCTAssertEqual(result.splits[1].averageHeartRate ?? 0, 175, accuracy: 0.01)
    }

    func testHeartRateIsNilForAKilometerWithNoReadings() {
        let result = SplitBuilder.reconstruct(
            distanceSamples: run(paces: [300, 300], samplesPerKilometer: 10),
            heartRateSamples: heartRates([(60, 140)])
        )

        XCTAssertNotNil(result.splits[0].averageHeartRate)
        XCTAssertNil(result.splits[1].averageHeartRate)
    }

    // MARK: - Refusals

    func testCoarseSamplesAreRefusedRatherThanInterpolated() {
        // One sample per kilometer: every split would be a straight copy of
        // the run average dressed up as a measurement.
        let result = SplitBuilder.reconstruct(
            distanceSamples: run(paces: [300, 300, 300], samplesPerKilometer: 1),
            heartRateSamples: []
        )

        XCTAssertEqual(result.rejection, .tooCoarse)
        XCTAssertTrue(result.splits.isEmpty)
        XCTAssertEqual(result.samplesPerKilometer, 1, accuracy: 0.01)
        XCTAssertFalse(result.isRetryable)
    }

    func testMissingSeriesIsRetryableRatherThanTerminal() {
        let result = SplitBuilder.reconstruct(distanceSamples: [], heartRateSamples: [])

        XCTAssertEqual(result.rejection, .noSamples)
        XCTAssertTrue(result.isRetryable)
    }

    func testRunUnderOneKilometerIsRefused() {
        var samples: [DistanceSample] = []
        var cursor = start
        for _ in 0..<8 {
            let end = cursor.addingTimeInterval(30)
            samples.append(DistanceSample(start: cursor, end: end, meters: 100, sourceName: "Garmin Connect"))
            cursor = end
        }

        let result = SplitBuilder.reconstruct(distanceSamples: samples, heartRateSamples: [])

        XCTAssertEqual(result.rejection, .tooShort)
        XCTAssertFalse(result.isRetryable)
    }

    // MARK: - Source selection

    func testIPhoneSamplesAreIgnoredWhenGarminWroteTheRun() {
        // A phone in a pocket writes its own distance for the same window;
        // mixing the two would double count and wreck every boundary.
        let garmin = run(paces: [300, 300], samplesPerKilometer: 10)
        let phone = run(paces: [300, 300], samplesPerKilometer: 10, source: "iPhone")

        let result = SplitBuilder.reconstruct(distanceSamples: garmin + phone, heartRateSamples: [])

        XCTAssertEqual(result.splits.count, 2)
        XCTAssertEqual(result.distanceSampleCount, garmin.count)
    }

    func testPhoneSamplesAreUsedWhenGarminWroteNothing() {
        let result = SplitBuilder.reconstruct(
            distanceSamples: run(paces: [300, 300], samplesPerKilometer: 10, source: "iPhone"),
            heartRateSamples: []
        )

        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.splits.count, 2)
    }

    // MARK: - Diagnostics

    func testMedianSampleDurationIsReported() {
        let result = SplitBuilder.reconstruct(
            distanceSamples: run(paces: [300], samplesPerKilometer: 10),
            heartRateSamples: []
        )

        XCTAssertEqual(result.medianSampleSeconds ?? 0, 30, accuracy: 0.01)
    }

    // MARK: - Mixed sample granularity

    /// Garmin can write one long sample among short ones. That sample alone
    /// spans more than a kilometer, so the builder must emit several splits
    /// from it rather than one.
    func testSingleSampleSpanningSeveralKilometersYieldsSeveralSplits() {
        let lead = run(paces: [300], samplesPerKilometer: 10)
        let coarseStart = lead[lead.count - 1].end
        let coarse = DistanceSample(
            start: coarseStart,
            end: coarseStart.addingTimeInterval(750),
            meters: 2500,
            sourceName: "Garmin Connect"
        )
        let tailStart = coarse.end
        let tail = run(paces: [300], samplesPerKilometer: 10, startingAt: tailStart.timeIntervalSince(start))

        let result = SplitBuilder.reconstruct(distanceSamples: lead + [coarse] + tail, heartRateSamples: [])

        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.splits.count, 5)
        XCTAssertEqual(result.splits.map(\.kilometer), [1, 2, 3, 4, 5])
        XCTAssertEqual(result.splits.map(\.durationSeconds), [300, 300, 300, 300, 150], accuracy: 0.01)
        XCTAssertEqual(result.splits.prefix(4).map(\.isPartial), [false, false, false, false])
        XCTAssertTrue(result.splits[4].isPartial)
        XCTAssertEqual(result.splits[4].paceSecondsPerKm ?? 0, 300, accuracy: 0.01)
    }

    // MARK: - Persistence

    func testSplitsAreNilUntilReconstructionRuns() {
        let activity = makeActivity()

        XCTAssertNil(activity.splitsData)
        XCTAssertNil(activity.splits)
    }

    /// A refusal must persist as an encoded empty array, not as nil. Nil means
    /// "try again next sync", so collapsing the two would re-query HealthKit
    /// for every coarse run on every sync forever.
    func testRefusalPersistsAsEmptyRatherThanNil() {
        let activity = makeActivity()

        activity.splits = []

        XCTAssertNotNil(activity.splitsData)
        XCTAssertEqual(activity.splits, [])
    }

    func testSplitsSurviveEncodingRoundTrip() {
        let activity = makeActivity()
        let reconstructed = SplitBuilder.reconstruct(
            distanceSamples: run(paces: [300, 330], samplesPerKilometer: 10),
            heartRateSamples: heartRates([(60, 140), (400, 160)])
        )

        activity.splits = reconstructed.splits

        XCTAssertEqual(activity.splits, reconstructed.splits)
    }

    private func makeActivity() -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: start,
            distanceMeters: 2000,
            durationSeconds: 630,
            avgHeartRate: 150,
            maxHeartRate: 170,
            avgPaceSecondsPerKm: 315,
            sourceName: "Garmin Connect"
        )
    }
}

private func XCTAssertEqual(
    _ actual: [Double],
    _ expected: [Double],
    accuracy: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (lhs, rhs) in zip(actual, expected) {
        XCTAssertEqual(lhs, rhs, accuracy: accuracy, file: file, line: line)
    }
}
