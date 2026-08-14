import Foundation
import HealthKit
import OSLog
import SwiftData

/// Orchestrates HealthKit → SwiftData sync.
///
/// Workouts sync incrementally via a persisted HKQueryAnchor; `hkUUID`
/// uniqueness makes re-imports idempotent. Daily wellness is recomputed
/// wholesale over a rolling window each sync — sleep overlap-merging and
/// per-day reduction need each day's full sample set, which incremental
/// deltas can't provide reliably.
@MainActor
final class SyncEngine: ObservableObject {
    static let wellnessWindowDays = 60

    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    /// Set from the scene phase; suppresses the morning notification while
    /// the user is looking at the app.
    var isForeground = false

    /// Shared with views for authorization calls — Apple recommends a single
    /// HKHealthStore per app.
    let health: HealthKitService
    private let modelContext: ModelContext
    private var resyncRequested = false
    private let calendar: Calendar
    private let logger = Logger(subsystem: "com.khanhnguyen.TrainOrRest", category: "sync")

    init(health: HealthKitService, modelContext: ModelContext, calendar: Calendar = .current) {
        self.health = health
        self.modelContext = modelContext
        self.calendar = calendar
    }

    /// Registers observer queries so Garmin Connect writes trigger a sync
    /// even when the app is backgrounded.
    func startObserving() {
        health.startObserving { [weak self] in
            await self?.syncAll()
        }
    }

    /// Runs a full sync; a trigger arriving mid-sync queues one follow-up
    /// pass so late-landing samples are not dropped.
    func syncAll() async {
        guard !isSyncing else {
            resyncRequested = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            resyncRequested = false
            await performSync()
        } while resyncRequested
    }

    private func performSync() async {
        lastError = nil
        do {
            try await syncWorkouts()
            try await syncWellness()
            try modelContext.save()
            // Matching and readiness failures must not read as sync failures —
            // the synced data is already saved at this point.
            do {
                try PlanStore.autoMatch(in: modelContext, calendar: calendar)
            } catch {
                logger.error("Workout auto-match failed: \(error, privacy: .public)")
            }
            do {
                let readiness = try ReadinessStore.runDailyPipeline(
                    in: modelContext, today: .now, calendar: calendar
                )
                if let readiness, !isForeground {
                    await VerdictNotifier.notifyIfNeeded(for: readiness, in: modelContext)
                }
            } catch {
                logger.error("Readiness pipeline failed: \(error, privacy: .public)")
            }
            logger.info("Sync completed at \(Date.now, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            logger.error("Sync failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Workouts

    private func syncWorkouts() async throws {
        let state = try fetchOrCreateSyncState(domain: SyncState.workoutsDomain)
        let delta = try await health.runningWorkoutDelta(anchorData: state.anchorData)

        for summary in delta.added {
            let pace = ActivityMapper.averagePaceSecondsPerKm(
                distanceMeters: summary.distanceMeters,
                durationSeconds: summary.durationSeconds
            )
            if let existing = try fetchActivity(hkUUID: summary.uuid) {
                existing.date = summary.start
                existing.distanceMeters = summary.distanceMeters
                existing.durationSeconds = summary.durationSeconds
                existing.avgHeartRate = summary.avgHeartRate
                existing.maxHeartRate = summary.maxHeartRate
                existing.avgPaceSecondsPerKm = pace
                existing.sourceName = summary.sourceName
            } else {
                modelContext.insert(CompletedActivity(
                    hkUUID: summary.uuid,
                    date: summary.start,
                    distanceMeters: summary.distanceMeters,
                    durationSeconds: summary.durationSeconds,
                    avgHeartRate: summary.avgHeartRate,
                    maxHeartRate: summary.maxHeartRate,
                    avgPaceSecondsPerKm: pace,
                    sourceName: summary.sourceName
                ))
            }
        }

        for uuid in delta.deletedUUIDs {
            if let activity = try fetchActivity(hkUUID: uuid) {
                modelContext.delete(activity)
            }
        }

        if let newAnchor = delta.newAnchorData {
            state.anchorData = newAnchor
        }
        state.lastSyncAt = .now
        logger.info("Workouts sync: +\(delta.added.count) −\(delta.deletedUUIDs.count)")

        try await backfillMissingHeartRates()
    }

    /// Garmin can write a workout before its heart-rate series, and the
    /// anchored query never revisits delivered workouts — so re-resolve
    /// heart rate for recent activities that still lack it.
    private func backfillMissingHeartRates() async throws {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        let descriptor = FetchDescriptor<CompletedActivity>(
            predicate: #Predicate { $0.avgHeartRate == nil && $0.date >= cutoff }
        )
        let missing = try modelContext.fetch(descriptor)
        guard !missing.isEmpty else { return }

        let summaries = try await health.recentRunningWorkouts(since: cutoff)
        let byUUID = Dictionary(summaries.map { ($0.uuid, $0) }) { first, _ in first }
        var filled = 0
        for activity in missing {
            guard let summary = byUUID[activity.hkUUID], summary.avgHeartRate != nil else { continue }
            activity.avgHeartRate = summary.avgHeartRate
            activity.maxHeartRate = summary.maxHeartRate
            filled += 1
        }
        if filled > 0 {
            logger.info("Backfilled heart rate for \(filled) activities")
        }
    }

    // MARK: - Wellness

    private func syncWellness() async throws {
        let windowStart = calendar.date(
            byAdding: .day,
            value: -Self.wellnessWindowDays,
            to: calendar.startOfDay(for: .now)
        ) ?? .distantPast

        let milliseconds = HKUnit.secondUnit(with: .milli)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let vo2Unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        async let hrvSamples = health.quantitySamples(.heartRateVariabilitySDNN, unit: milliseconds, since: windowStart)
        async let rhrSamples = health.quantitySamples(.restingHeartRate, unit: bpm, since: windowStart)
        async let vo2Samples = health.quantitySamples(.vo2Max, unit: vo2Unit, since: windowStart)
        async let sleepIntervals = health.asleepIntervals(since: windowStart)

        let resolvedHRVSamples = try await hrvSamples
        let hrvByDay = WellnessReducer.firstValuePerDay(resolvedHRVSamples, calendar: calendar)
        let hrvSamplesByDay = Dictionary(grouping: resolvedHRVSamples) {
            calendar.startOfDay(for: $0.start)
        }
        let hrvResolutionsByDay = hrvSamplesByDay.compactMapValues { samples -> SourceResolution? in
            guard let sample = samples.first else { return nil }
            let day = calendar.startOfDay(for: sample.start)
            return WellnessReducer.hrvSourceResolution(
                samples: samples,
                divergenceThreshold: hrvDivergenceThreshold(for: day, hrvByDay: hrvByDay)
            )
        }
        let rhrByDay = WellnessReducer.latestValuePerDay(try await rhrSamples, calendar: calendar)
        let vo2ByDay = WellnessReducer.latestValuePerDay(try await vo2Samples, calendar: calendar)
        let resolvedSleep = try await sleepIntervals
        let sleepByDay = SleepAggregator.nightlySleepHours(intervals: resolvedSleep, calendar: calendar)
        let stagesByDay = SleepStageAggregator.nightlyStageHours(intervals: resolvedSleep, calendar: calendar)

        // Include existing rows in the window so days whose samples were
        // deleted from Health get cleared rather than keeping stale values.
        let existingRows = try modelContext.fetch(FetchDescriptor<DailyWellness>(
            predicate: #Predicate { $0.date >= windowStart }
        ))
        let allDays = Set(hrvByDay.keys)
            .union(rhrByDay.keys)
            .union(vo2ByDay.keys)
            .union(sleepByDay.keys)
            .union(existingRows.map(\.date))

        for day in allDays {
            let row = try fetchOrCreateWellness(date: day)
            let hrvResolution = hrvResolutionsByDay[day]
            row.hrvSDNN = hrvResolution?.primaryValue ?? hrvByDay[day]
            row.hrvPrimarySource = hrvResolution?.primarySource
            row.hrvAltValue = hrvResolution?.altValue
            row.hrvAltSource = hrvResolution?.altSource
            row.hrvDisputed = hrvResolution?.diverged ?? false
            row.restingHeartRate = rhrByDay[day]
            row.sleepHours = sleepByDay[day]
            row.vo2Max = vo2ByDay[day]
            let stages = stagesByDay[day]
            row.deepSleepHours = stages?.deep
            row.remSleepHours = stages?.rem
            row.lightSleepHours = stages?.light
        }

        let state = try fetchOrCreateSyncState(domain: SyncState.wellnessDomain)
        state.lastSyncAt = .now
        logger.info("Wellness sync: \(allDays.count) days recomputed")
    }

    private func hrvDivergenceThreshold(for day: Date, hrvByDay: [Date: Double]) -> Double {
        let dayStart = calendar.startOfDay(for: day)
        let start = calendar.date(
            byAdding: .day,
            value: -(ReadinessEngine.Tuning.baselineWindowDays - 1),
            to: dayStart
        ) ?? .distantPast
        let values = hrvByDay
            .filter { $0.key >= start && $0.key <= dayStart }
            .map(\.value)
        guard values.count >= 2 else { return 5.0 }
        let average = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
        let standardDeviation = sqrt(variance)
        return standardDeviation > 0 ? standardDeviation : 5.0
    }

    // MARK: - Fetch helpers

    private func fetchActivity(hkUUID: UUID) throws -> CompletedActivity? {
        var descriptor = FetchDescriptor<CompletedActivity>(
            predicate: #Predicate { $0.hkUUID == hkUUID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchOrCreateWellness(date: Date) throws -> DailyWellness {
        var descriptor = FetchDescriptor<DailyWellness>(
            predicate: #Predicate { $0.date == date }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let row = DailyWellness(date: date)
        modelContext.insert(row)
        return row
    }

    private func fetchOrCreateSyncState(domain: String) throws -> SyncState {
        var descriptor = FetchDescriptor<SyncState>(
            predicate: #Predicate { $0.domain == domain }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let state = SyncState(domain: domain)
        modelContext.insert(state)
        return state
    }
}
