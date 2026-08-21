import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class WorkoutPushServiceTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 9)
    private let easyPace = PaceBand(fastSecondsPerKm: 360, slowSecondsPerKm: 390)

    func testDisabledPushIsSilentNoOp() async throws {
        let container = try makeContainer()
        let defaults = try makeDefaults()
        let client = MockIntervalsICUService()
        let service = WorkoutPushService(
            modelContext: container.mainContext,
            client: client,
            calendar: calendar,
            userDefaults: defaults,
            keychainLoad: { _ in "key" }
        )

        await service.reconcile(today: today)

        XCTAssertEqual(client.eventsCalls.count, 0)
        XCTAssertNil(service.lastPushAt)
        XCTAssertNil(service.lastPushError)
    }

    func testMissingKeyIsSilentNoOp() async throws {
        let container = try makeContainer()
        let defaults = try makeDefaults()
        defaults.set(true, forKey: WorkoutPushSettings.enabledKey)
        defaults.set("i636286", forKey: WorkoutPushSettings.athleteIDKey)
        let client = MockIntervalsICUService()
        let service = WorkoutPushService(
            modelContext: container.mainContext,
            client: client,
            calendar: calendar,
            userDefaults: defaults,
            keychainLoad: { _ in nil }
        )

        await service.reconcile(today: today)

        XCTAssertEqual(client.eventsCalls.count, 0)
        XCTAssertNil(service.lastPushAt)
        XCTAssertNil(service.lastPushError)
    }

    func testReconcileListsUpsertsDeletesAndRecordsSuccess() async throws {
        let container = try makeContainer()
        let defaults = try makeDefaults()
        defaults.set(true, forKey: WorkoutPushSettings.enabledKey)
        defaults.set("i636286", forKey: WorkoutPushSettings.athleteIDKey)
        let workout = plannedWorkout(uuid: uuid(1))
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let client = MockIntervalsICUService(remoteEvents: [
            RemoteWorkoutEvent(id: 10, externalID: WorkoutDSL.externalID(for: uuid(1))),
            RemoteWorkoutEvent(id: 11, externalID: "trainorrest-orphan"),
            RemoteWorkoutEvent(id: 12, externalID: "manual"),
        ])
        let service = WorkoutPushService(
            modelContext: container.mainContext,
            client: client,
            calendar: calendar,
            userDefaults: defaults,
            keychainLoad: { _ in "test-key" }
        )

        await service.reconcile(today: today)

        XCTAssertEqual(client.eventsCalls, [
            .init(athleteID: "i636286", oldest: "2026-07-09", newest: "2026-07-16")
        ])
        XCTAssertEqual(client.upsertedEvents.map(\.externalID), [WorkoutDSL.externalID(for: uuid(1))])
        XCTAssertEqual(client.deletedEventIDs, [11])
        XCTAssertNotNil(service.lastPushAt)
        XCTAssertNil(service.lastPushError)
        XCTAssertNotNil(defaults.object(forKey: WorkoutPushSettings.lastPushAtKey))
        XCTAssertNil(defaults.string(forKey: WorkoutPushSettings.lastPushErrorKey))
    }

    func testClientFailureRecordsErrorWithoutThrowing() async throws {
        let container = try makeContainer()
        let defaults = try makeDefaults()
        defaults.set(true, forKey: WorkoutPushSettings.enabledKey)
        defaults.set("i636286", forKey: WorkoutPushSettings.athleteIDKey)
        let client = MockIntervalsICUService(eventsError: IntervalsICUError.unauthorized)
        let service = WorkoutPushService(
            modelContext: container.mainContext,
            client: client,
            calendar: calendar,
            userDefaults: defaults,
            keychainLoad: { _ in "bad-key" }
        )

        await service.reconcile(today: today)

        XCTAssertEqual(service.lastPushError, IntervalsICUError.unauthorized.errorDescription)
        XCTAssertEqual(defaults.string(forKey: WorkoutPushSettings.lastPushErrorKey), service.lastPushError)
    }

    func testInFlightReconcileQueuesOneFollowUpPass() async throws {
        let container = try makeContainer()
        let defaults = try makeDefaults()
        defaults.set(true, forKey: WorkoutPushSettings.enabledKey)
        defaults.set("i636286", forKey: WorkoutPushSettings.athleteIDKey)
        container.mainContext.insert(plannedWorkout(uuid: uuid(1)))
        try container.mainContext.save()

        let firstEventsStarted = expectation(description: "first events request started")
        let client = MockIntervalsICUService()
        client.suspendNextEventsCall = true
        client.onEventsCall = { count in
            if count == 1 {
                firstEventsStarted.fulfill()
            }
        }
        let service = WorkoutPushService(
            modelContext: container.mainContext,
            client: client,
            calendar: calendar,
            userDefaults: defaults,
            keychainLoad: { _ in "test-key" }
        )

        let task = Task { await service.reconcile(today: today) }
        await fulfillment(of: [firstEventsStarted], timeout: 1)

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        container.mainContext.insert(plannedWorkout(date: tomorrow, uuid: uuid(2)))
        try container.mainContext.save()

        await service.reconcile(today: tomorrow)
        XCTAssertEqual(client.eventsCalls.count, 1)

        client.resumeSuspendedEvents()
        await task.value

        XCTAssertEqual(client.eventsCalls.map(\.oldest), ["2026-07-09", "2026-07-10"])
        XCTAssertEqual(client.upsertedEvents.map(\.externalID), [
            WorkoutDSL.externalID(for: uuid(1)),
            WorkoutDSL.externalID(for: uuid(2)),
        ])
    }

    func testPlanChangeNotificationDoesNotCancelInFlightPush() async throws {
        let container = try makeContainer()
        let defaults = try makeDefaults()
        defaults.set(true, forKey: WorkoutPushSettings.enabledKey)
        defaults.set("i636286", forKey: WorkoutPushSettings.athleteIDKey)
        container.mainContext.insert(plannedWorkout(uuid: uuid(1)))
        try container.mainContext.save()

        let firstEventsStarted = expectation(description: "first notification reconcile started")
        let secondBulkUpsertFinished = expectation(description: "follow-up reconcile completed")
        let client = MockIntervalsICUService()
        client.suspendNextEventsCall = true
        client.onEventsCall = { count in
            if count == 1 {
                firstEventsStarted.fulfill()
            }
        }
        client.onBulkUpsert = { count in
            if count == 2 {
                secondBulkUpsertFinished.fulfill()
            }
        }
        let service = WorkoutPushService(
            modelContext: container.mainContext,
            client: client,
            calendar: calendar,
            userDefaults: defaults,
            debounceNanoseconds: 0,
            now: { self.today },
            keychainLoad: { _ in "test-key" }
        )

        NotificationCenter.default.post(name: .planDidChange, object: nil)
        await fulfillment(of: [firstEventsStarted], timeout: 1)

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        container.mainContext.insert(plannedWorkout(date: tomorrow, uuid: uuid(2)))
        try container.mainContext.save()

        NotificationCenter.default.post(name: .planDidChange, object: nil)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(client.eventsCalls.count, 1)
        XCTAssertFalse(client.suspendedEventsWasCancelled)
        XCTAssertNil(service.lastPushError)

        client.resumeSuspendedEvents()
        await fulfillment(of: [secondBulkUpsertFinished], timeout: 1)

        XCTAssertFalse(client.suspendedEventsWasCancelled)
        XCTAssertNil(service.lastPushError)
        XCTAssertEqual(client.eventsCalls.map(\.oldest), ["2026-07-09", "2026-07-09"])
        XCTAssertEqual(client.upsertedEvents.map(\.externalID), [
            WorkoutDSL.externalID(for: uuid(1)),
            WorkoutDSL.externalID(for: uuid(1)),
            WorkoutDSL.externalID(for: uuid(2)),
        ])

        _ = service
    }

    private func plannedWorkout(date: Date? = nil, uuid: UUID) -> PlannedWorkout {
        let structure = [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .work, distanceKm: 10, paceBand: easyPace)
            ])
        ]
        let spec = PlannedWorkoutSpec(
            date: date ?? today,
            kind: .easy,
            distanceKm: 10,
            paceBand: easyPace,
            details: "Easy run",
            structure: structure
        )
        let workout = PlannedWorkout(spec: spec, weekIndex: 0, phase: .base)
        workout.uuid = uuid
        return workout
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self, CoachRequestSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WorkoutPushServiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private final class MockIntervalsICUService: IntervalsICUServicing {
    struct EventsCall: Equatable {
        var athleteID: String
        var oldest: String
        var newest: String
    }

    var remoteEvents: [RemoteWorkoutEvent]
    var eventsError: Error?
    var eventsCalls: [EventsCall] = []
    var upsertedEvents: [IntervalsWorkoutEvent] = []
    var deletedEventIDs: [Int] = []
    var suspendNextEventsCall = false
    var onEventsCall: ((Int) -> Void)?
    var onBulkUpsert: ((Int) -> Void)?
    var suspendedEventsWasCancelled = false
    private var bulkUpsertCalls = 0
    private var suspendedEvents: CheckedContinuation<[RemoteWorkoutEvent], Error>?

    init(remoteEvents: [RemoteWorkoutEvent] = [], eventsError: Error? = nil) {
        self.remoteEvents = remoteEvents
        self.eventsError = eventsError
    }

    func bulkUpsert(
        _ events: [IntervalsWorkoutEvent],
        credentials: IntervalsICUCredentials
    ) async throws -> [RemoteWorkoutEvent] {
        bulkUpsertCalls += 1
        upsertedEvents.append(contentsOf: events)
        onBulkUpsert?(bulkUpsertCalls)
        return []
    }

    func events(
        credentials: IntervalsICUCredentials,
        oldest: String,
        newest: String
    ) async throws -> [RemoteWorkoutEvent] {
        eventsCalls.append(.init(athleteID: credentials.athleteID, oldest: oldest, newest: newest))
        onEventsCall?(eventsCalls.count)
        if suspendNextEventsCall {
            suspendNextEventsCall = false
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    suspendedEvents = continuation
                }
            } onCancel: {
                suspendedEventsWasCancelled = true
            }
        }
        if let eventsError {
            throw eventsError
        }
        return remoteEvents
    }

    func deleteEvent(id: Int, credentials: IntervalsICUCredentials) async throws {
        deletedEventIDs.append(id)
    }

    func resumeSuspendedEvents() {
        suspendedEvents?.resume(returning: remoteEvents)
        suspendedEvents = nil
    }
}
