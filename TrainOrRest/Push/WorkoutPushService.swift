import Foundation
import OSLog
import SwiftData

extension Notification.Name {
    static let planDidChange = Notification.Name("TrainOrRest.planDidChange")
}

enum WorkoutPushSettings {
    static let enabledKey = "workoutPushEnabled"
    static let athleteIDKey = "intervalsICUAthleteID"
    static let lastPushAtKey = "workoutPushLastPushAt"
    static let lastPushErrorKey = "workoutPushLastPushError"
}

@MainActor
final class WorkoutPushService: ObservableObject {
    @Published private(set) var isPushing = false
    @Published private(set) var lastPushAt: Date?
    @Published private(set) var lastPushError: String?
    @Published private(set) var lastPushSkipReason: String?

    private let modelContext: ModelContext
    private let client: IntervalsICUServicing
    private let calendar: Calendar
    private let userDefaults: UserDefaults
    private let keychainLoad: (String) throws -> String?
    private let debounceNanoseconds: UInt64
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.khanhnguyen.TrainOrRest", category: "workout-push")
    private var planChangeObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var pendingReconcileToday: Date?

    init(
        modelContext: ModelContext,
        client: IntervalsICUServicing = IntervalsICUClient(),
        calendar: Calendar = .current,
        userDefaults: UserDefaults = .standard,
        debounceNanoseconds: UInt64 = 1_000_000_000,
        now: @escaping () -> Date = Date.init,
        keychainLoad: @escaping (String) throws -> String? = { try KeychainStore.load(account: $0) }
    ) {
        self.modelContext = modelContext
        self.client = client
        self.calendar = calendar
        self.userDefaults = userDefaults
        self.debounceNanoseconds = debounceNanoseconds
        self.now = now
        self.keychainLoad = keychainLoad
        lastPushAt = userDefaults.object(forKey: WorkoutPushSettings.lastPushAtKey) as? Date
        lastPushError = userDefaults.string(forKey: WorkoutPushSettings.lastPushErrorKey)
        observePlanChanges()
    }

    deinit {
        if let planChangeObserver {
            NotificationCenter.default.removeObserver(planChangeObserver)
        }
        debounceTask?.cancel()
    }

    func reconcile(
        today: Date = .now,
        requireEnabled: Bool = true,
        forceRecreate: Bool = false
    ) async {
        guard !isPushing else {
            pendingReconcileToday = today
            return
        }

        isPushing = true
        defer { isPushing = false }

        var nextToday: Date? = today
        while let currentToday = nextToday {
            pendingReconcileToday = nil
            await reconcileOnce(
                today: currentToday,
                requireEnabled: requireEnabled,
                forceRecreate: forceRecreate
            )
            nextToday = pendingReconcileToday
        }
    }

    private func reconcileOnce(today: Date, requireEnabled: Bool, forceRecreate: Bool) async {
        guard !requireEnabled || userDefaults.bool(forKey: WorkoutPushSettings.enabledKey) else {
            recordSkip("Watch Push is off.")
            return
        }
        let athleteID = userDefaults.string(forKey: WorkoutPushSettings.athleteIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !athleteID.isEmpty else {
            recordSkip("Add intervals.icu Athlete ID in Profile first.")
            return
        }
        guard let apiKey = try? keychainLoad(KeychainStore.intervalsICUAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            recordSkip("Save intervals.icu API key in Profile first.")
            return
        }

        do {
            let localEvents = try desiredEvents(today: today)
            let start = calendar.startOfDay(for: today)
            let end = calendar.date(byAdding: .day, value: PushReconciler.windowDays, to: start) ?? start
            let credentials = IntervalsICUCredentials(athleteID: athleteID, apiKey: apiKey)
            let remoteEvents = try await client.events(
                credentials: credentials,
                oldest: dateQuery(start),
                newest: dateQuery(end)
            )
            let plan = PushReconciler.reconcile(
                desiredEvents: localEvents,
                remoteEvents: remoteEvents,
                forceRecreate: forceRecreate
            )
            for eventID in plan.toDelete {
                try await client.deleteEvent(id: eventID, credentials: credentials)
            }
            if !plan.toUpsert.isEmpty {
                _ = try await client.bulkUpsert(plan.toUpsert, credentials: credentials)
            }
            recordSuccess()
            logger.info("Workout push reconciled: upsert \(plan.toUpsert.count), delete \(plan.toDelete.count)")
        } catch {
            let message = recordFailure(error)
            logger.error("Workout push failed: \(message, privacy: .public)")
        }
    }

    private func desiredEvents(today: Date) throws -> [IntervalsWorkoutEvent] {
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: PushReconciler.windowDays, to: start) ?? start
        let descriptor = FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let workouts = try modelContext.fetch(descriptor)
        return PushReconciler.desiredEvents(from: workouts, today: today, calendar: calendar)
    }

    private func observePlanChanges() {
        planChangeObserver = NotificationCenter.default.addObserver(
            forName: .planDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDebouncedReconcile()
            }
        }
    }

    private func scheduleDebouncedReconcile() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            Task { @MainActor in
                await self.reconcile(today: self.now())
            }
        }
    }

    private func recordSuccess() {
        let date = Date()
        lastPushAt = date
        lastPushError = nil
        lastPushSkipReason = nil
        userDefaults.set(date, forKey: WorkoutPushSettings.lastPushAtKey)
        userDefaults.removeObject(forKey: WorkoutPushSettings.lastPushErrorKey)
    }

    private func recordFailure(_ error: Error) -> String {
        let message: String
        if let intervalsError = error as? IntervalsICUError {
            message = intervalsError.errorDescription ?? "Workout push failed. Try again later."
        } else {
            message = "Workout push failed. Try again later."
        }
        lastPushError = message
        lastPushSkipReason = nil
        userDefaults.set(message, forKey: WorkoutPushSettings.lastPushErrorKey)
        return message
    }

    private func recordSkip(_ reason: String) {
        lastPushSkipReason = reason
        lastPushError = nil
    }

    private func dateQuery(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }
}
