import Foundation
import HealthKit
import OSLog

/// Thin async wrapper around HKHealthStore: authorization, typed queries,
/// observer registration. All HealthKit types are converted to plain value
/// types at this boundary so downstream logic stays testable.
final class HealthKitService {
    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.khanhnguyen.TrainOrRest", category: "healthkit")

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let readTypes: Set<HKObjectType> = [
        .workoutType(),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.vo2Max),
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKCategoryType(.sleepAnalysis),
    ]

    /// Sample types observed for background delivery of Garmin writes.
    static let observedTypes: [HKSampleType] = [
        .workoutType(),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.vo2Max),
        HKCategoryType(.sleepAnalysis),
    ]

    // MARK: - Authorization

    /// Whether the system would show the permission sheet if we asked.
    /// (HealthKit never reveals whether read access was actually granted.)
    func needsAuthorizationRequest() async throws -> Bool {
        let status = try await store.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        return status == .shouldRequest
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: - Workouts

    struct WorkoutDelta {
        let added: [WorkoutSummary]
        let deletedUUIDs: [UUID]
        let newAnchorData: Data?
    }

    /// Incremental fetch of running workouts via anchored query; returns plain
    /// summaries (with avg/max HR resolved) plus the serialized new anchor.
    func runningWorkoutDelta(anchorData: Data?) async throws -> WorkoutDelta {
        let anchor = try Self.decodeAnchor(anchorData)
        let predicate = HKQuery.predicateForWorkouts(with: .running)

        let (samples, deleted, newAnchor): ([HKSample], [HKDeletedObject], HKQueryAnchor?) =
            try await withCheckedThrowingContinuation { continuation in
                let query = HKAnchoredObjectQuery(
                    type: .workoutType(),
                    predicate: predicate,
                    anchor: anchor,
                    limit: HKObjectQueryNoLimit
                ) { _, samples, deleted, newAnchor, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (samples ?? [], deleted ?? [], newAnchor))
                    }
                }
                store.execute(query)
            }

        var added: [WorkoutSummary] = []
        for case let workout as HKWorkout in samples {
            added.append(await summary(for: workout))
        }

        return WorkoutDelta(
            added: added,
            deletedUUIDs: deleted.map(\.uuid),
            newAnchorData: try newAnchor.map(Self.encodeAnchor)
        )
    }

    /// Non-anchored re-read of recent running workouts. Used to backfill
    /// heart-rate stats for workouts that synced before Garmin wrote their
    /// heart-rate series (the anchored query never revisits them).
    func recentRunningWorkouts(since start: Date) async throws -> [WorkoutSummary] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: start, end: nil),
        ])
        let samples = try await sampleQuery(type: .workoutType(), predicate: predicate)
        var summaries: [WorkoutSummary] = []
        for case let workout as HKWorkout in samples {
            summaries.append(await summary(for: workout))
        }
        return summaries
    }

    private func summary(for workout: HKWorkout) async -> WorkoutSummary {
        let (avg, max) = await heartRateStats(start: workout.startDate, end: workout.endDate)
        let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
        return WorkoutSummary(
            uuid: workout.uuid,
            start: workout.startDate,
            durationSeconds: workout.duration,
            distanceMeters: distance,
            avgHeartRate: avg,
            maxHeartRate: max,
            sourceName: workout.sourceRevision.source.name
        )
    }

    /// Average and max heart rate over an interval. No data is not an error —
    /// Garmin occasionally writes runs without HR — so failures map to nil.
    private func heartRateStats(start: Date, end: Date) async -> (avg: Double?, max: Double?) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.heartRate),
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, stats, _ in
                continuation.resume(returning: (
                    stats?.averageQuantity()?.doubleValue(for: bpm),
                    stats?.maximumQuantity()?.doubleValue(for: bpm)
                ))
            }
            store.execute(query)
        }
    }

    // MARK: - Wellness samples

    func quantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        since start: Date
    ) async throws -> [QuantitySampleSummary] {
        let samples = try await sampleQuery(
            type: HKQuantityType(identifier),
            predicate: HKQuery.predicateForSamples(withStart: start, end: nil)
        )
        return samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            return QuantitySampleSummary(
                start: quantity.startDate,
                value: quantity.quantity.doubleValue(for: unit),
                sourceName: quantity.sourceRevision.source.name
            )
        }
    }

    func asleepIntervals(since start: Date) async throws -> [SleepInterval] {
        let asleepValues = HKCategoryValueSleepAnalysis.predicateForSamples(equalTo: HKCategoryValueSleepAnalysis.allAsleepValues)
        let dateRange = HKQuery.predicateForSamples(withStart: start, end: nil)
        let samples = try await sampleQuery(
            type: HKCategoryType(.sleepAnalysis),
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [dateRange, asleepValues])
        )
        return samples.compactMap { sample in
            guard let category = sample as? HKCategorySample else { return nil }
            let stage: SleepStage = switch HKCategoryValueSleepAnalysis(rawValue: category.value) {
            case .asleepDeep: .deep
            case .asleepREM: .rem
            case .asleepCore: .light
            default: .unspecified
            }
            return SleepInterval(
                start: category.startDate,
                end: category.endDate,
                sourceName: category.sourceRevision.source.name,
                stage: stage
            )
        }
    }

    private func sampleQuery(type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Background delivery

    /// Registers observer queries and enables background delivery so Garmin
    /// Connect writes wake the app. The completion handler is called only
    /// after `onChange` finishes, so iOS keeps the app alive while the
    /// triggered sync runs instead of suspending it mid-write.
    func startObserving(onChange: @escaping @Sendable () async -> Void) {
        for type in Self.observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [logger] _, completionHandler, error in
                if let error {
                    logger.error("Observer for \(type.identifier, privacy: .public) failed: \(error, privacy: .public)")
                    completionHandler()
                    return
                }
                logger.info("Background delivery received for \(type.identifier, privacy: .public)")
                Task {
                    await onChange()
                    completionHandler()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { [logger] success, error in
                if let error {
                    logger.error("enableBackgroundDelivery(\(type.identifier, privacy: .public)) failed: \(error, privacy: .public)")
                } else if success {
                    logger.info("Background delivery enabled for \(type.identifier, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Anchor serialization

    static func encodeAnchor(_ anchor: HKQueryAnchor) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    static func decodeAnchor(_ data: Data?) throws -> HKQueryAnchor? {
        guard let data else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}
