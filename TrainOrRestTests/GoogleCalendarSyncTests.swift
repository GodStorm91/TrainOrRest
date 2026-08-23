import SwiftData
import XCTest
@testable import TrainOrRest

final class GoogleCalendarSyncTests: XCTestCase {
    func testGoogleCalendarOAuthScopeIncludesIdentityAndCalendarAccess() {
        let scopes = Set(GoogleCalendarSyncSettings.scope.split(separator: " ").map(String.init))

        XCTAssertTrue(scopes.contains("openid"))
        XCTAssertTrue(scopes.contains("email"))
        XCTAssertTrue(scopes.contains("profile"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/calendar.app.created"))
    }

    func testAllDayPlannedWorkoutUsesExclusiveEndAndPrivateMetadata() throws {
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, calendar: calendar), plan: plan)
        let connection = GoogleCalendarConnection()

        let event = GoogleCalendarEventBuilder(calendar: calendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
            .desiredEvents(plan: plan, workouts: [workout], activities: [], connection: connection, today: date(2026, 8, 19, calendar: calendar))
            .first

        let payload = try XCTUnwrap(event?.payload)
        XCTAssertEqual(payload.start.date, "2026-08-25")
        XCTAssertEqual(payload.end.date, "2026-08-26")
        XCTAssertEqual(payload.transparency, "transparent")
        XCTAssertEqual(payload.visibility, "private")
        XCTAssertEqual(payload.extendedProperties.private["rotEntityId"], workout.uuid.uuidString)
        XCTAssertEqual(payload.extendedProperties.private["rotEntityType"], "plannedWorkout")
    }

    func testTimedWorkoutUsesDateTimeAndOpaqueTransparency() throws {
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, hour: 7, minute: 30, calendar: calendar), plan: plan)
        let connection = GoogleCalendarConnection()

        let payload = try XCTUnwrap(GoogleCalendarEventBuilder(calendar: calendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
            .desiredEvents(plan: plan, workouts: [workout], activities: [], connection: connection, today: date(2026, 8, 19, calendar: calendar))
            .first?.payload)

        XCTAssertNil(payload.start.date)
        XCTAssertEqual(payload.start.dateTime, "2026-08-25T07:30:00+09:00")
        XCTAssertEqual(payload.end.dateTime, "2026-08-25T08:12:40+09:00")
        XCTAssertNil(payload.start.timeZone)
        XCTAssertNil(payload.end.timeZone)
        XCTAssertEqual(payload.transparency, "opaque")
    }

    func testPlannedOnlyCompletionUpdatesExistingPlannedEventWithoutStandaloneActivity() throws {
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        let activity = makeActivity(on: workout.date)
        workout.status = .done
        workout.matchedActivityUUID = activity.hkUUID
        let connection = GoogleCalendarConnection()
        connection.completedActivityMode = .plannedOnly

        let desired = GoogleCalendarEventBuilder(calendar: calendar, timeZone: .current)
            .desiredEvents(plan: plan, workouts: [workout], activities: [activity], connection: connection, today: date(2026, 8, 19, calendar: calendar))

        XCTAssertEqual(desired.count, 1)
        XCTAssertEqual(desired[0].entityType, .plannedWorkout)
        XCTAssertTrue(desired[0].payload.summary.hasPrefix("✓ "))
        XCTAssertTrue(desired[0].payload.description?.contains("Completed") == true)
    }

    func testAllActivitiesAddsSpontaneousCompletedActivityOnce() throws {
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let connection = GoogleCalendarConnection()
        connection.completedActivityMode = .allActivities
        let activity = makeActivity(on: date(2026, 8, 20, hour: 6, calendar: calendar))

        let desired = GoogleCalendarEventBuilder(calendar: calendar, timeZone: .current)
            .desiredEvents(plan: plan, workouts: [], activities: [activity], connection: connection, today: date(2026, 8, 19, calendar: calendar))

        XCTAssertEqual(desired.count, 1)
        let event = try XCTUnwrap(desired.first)
        XCTAssertEqual(event.entityType, .completedActivity)
        XCTAssertTrue(event.payload.summary.hasPrefix("✓ Run"))
    }

    @MainActor
    func testInitialSyncCreatesCalendarOnceAndSkipsUnchangedEvents() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, calendar: calendar), plan: plan)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        context.insert(connection)
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.reconcile(reason: "test")
        await service.reconcile(reason: "test")

        XCTAssertEqual(api.createCalendarCount, 1)
        XCTAssertEqual(api.insertedEvents.count, 1)
        XCTAssertEqual(api.patchedEvents.count, 0)
        XCTAssertEqual(connection.connectionStatus, .connected)
        XCTAssertTrue(service.lastDebugReport?.contains("Google Calendar sync complete") == true)
        XCTAssertTrue(service.lastDebugReport?.contains("Desired events: 1") == true)
        XCTAssertTrue(service.lastDebugReport?.contains("Created: 0") == true)
        XCTAssertTrue(service.lastDebugReport?.contains("Skipped unchanged: 1") == true)
    }

    @MainActor
    func testLostInsertResponseIsRepairedThroughPrivateMetadata() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, calendar: calendar), plan: plan)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventsByEntity[workout.uuid.uuidString] = "existing-event"
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.reconcile(reason: "test")

        XCTAssertTrue(api.insertedEvents.isEmpty)
        XCTAssertEqual(api.patchedEvents, ["existing-event"])
        let links = try context.fetch(FetchDescriptor<GoogleCalendarEventLink>())
        XCTAssertEqual(links.first?.googleEventID, "existing-event")
    }

    @MainActor
    func testMissingLinkedEventIsRecreatedAndClearsPartialFailure() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, calendar: calendar), plan: plan)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .partialFailure
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: "missing-event"
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.patchErrorsByEventID["missing-event"] = .notFound
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.reconcile(reason: "test")

        XCTAssertEqual(connection.connectionStatus, .connected)
        XCTAssertEqual(api.patchedEvents, ["missing-event"])
        XCTAssertEqual(api.insertedEvents.count, 1)
        let link = try XCTUnwrap(try context.fetch(FetchDescriptor<GoogleCalendarEventLink>()).first)
        XCTAssertNotEqual(link.googleEventID, "missing-event")
        XCTAssertEqual(link.syncState, .synced)
    }

    @MainActor
    func testInvalidStartTimePatchRecreatesLinkedEvent() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, hour: 7, minute: 30, calendar: calendar), plan: plan)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .partialFailure
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: "bad-start-event"
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.patchErrorsByEventID["bad-start-event"] = .permanent(400, "invalid: Invalid start time.")
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.reconcile(reason: "test")

        XCTAssertEqual(connection.connectionStatus, .connected)
        XCTAssertEqual(api.patchedEvents, ["bad-start-event"])
        XCTAssertEqual(api.deletedEvents, ["bad-start-event"])
        XCTAssertEqual(api.insertedEvents.count, 1)
        XCTAssertEqual(api.insertedEvents.first?.start.dateTime, "2026-08-25T07:30:00+09:00")
        XCTAssertNil(api.insertedEvents.first?.start.timeZone)
        let link = try XCTUnwrap(try context.fetch(FetchDescriptor<GoogleCalendarEventLink>()).first)
        XCTAssertNotEqual(link.googleEventID, "bad-start-event")
        XCTAssertEqual(link.syncState, .synced)
    }

    @MainActor
    func testDuplicateIdentifierAfterInvalidStartTimeRepairsExistingEvent() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 23, hour: 6, calendar: calendar), plan: plan)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .partialFailure
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: "bad-start-event"
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let duplicateID = GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        let api = FakeGoogleCalendarAPI()
        api.patchErrorsByEventID["bad-start-event"] = .permanent(400, "invalid: Invalid start time.")
        api.insertErrorsByEventID[duplicateID] = .permanent(409, "duplicate: The requested identifier already exists.")
        api.remoteEventsByEntity[workout.uuid.uuidString] = duplicateID
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.reconcile(reason: "test")

        XCTAssertEqual(connection.connectionStatus, .connected)
        XCTAssertEqual(api.patchedEvents, ["bad-start-event", duplicateID])
        XCTAssertEqual(api.deletedEvents, ["bad-start-event"])
        XCTAssertEqual(api.insertedEvents.count, 1)
        let link = try XCTUnwrap(try context.fetch(FetchDescriptor<GoogleCalendarEventLink>()).first)
        XCTAssertEqual(link.googleEventID, duplicateID)
        XCTAssertEqual(link.syncState, .synced)
    }

    @MainActor
    func testAddBackCreatesGeneratedEventWhenDeletedDeterministicIDIsTombstoned() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, calendar: calendar), plan: plan)
        let eventID = GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: eventID
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [
            GoogleCalendarRemoteEvent(
                id: eventID,
                status: "cancelled",
                summary: nil,
                description: nil,
                start: nil,
                end: nil,
                updated: "2026-08-21T00:00:00Z",
                extendedProperties: nil
            )
        ], nextSyncToken: "token-1")]
        api.insertErrorsByEventID[eventID] = .permanent(409, "duplicate: The requested identifier already exists.")
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()
        service.addBackToGoogleCalendar(workoutID: workout.uuid)
        await service.reconcile(reason: "testAddBack")

        XCTAssertEqual(connection.connectionStatus, .connected)
        XCTAssertEqual(api.insertedEvents.count, 2)
        XCTAssertEqual(api.insertedEvents.first?.id, eventID)
        XCTAssertNil(api.insertedEvents.last?.id)
        XCTAssertEqual(api.patchedEvents, [])
        let link = try XCTUnwrap(try context.fetch(FetchDescriptor<GoogleCalendarEventLink>()).first)
        XCTAssertNotEqual(link.googleEventID, eventID)
        XCTAssertEqual(link.syncState, .synced)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>()).first?.status, .restored)
    }

    @MainActor
    func testInvalidStartTimeInsertFallsBackToAllDayEvent() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 23, hour: 6, calendar: calendar), plan: plan)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .partialFailure
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let eventID = GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        let api = FakeGoogleCalendarAPI()
        api.insertErrorsByEventID[eventID] = .permanent(400, "invalid: Invalid start time.")
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!, now: { self.date(2026, 8, 23, hour: 19, calendar: calendar) })

        await service.reconcile(reason: "test")

        XCTAssertEqual(connection.connectionStatus, .connected)
        XCTAssertEqual(api.insertedEvents.count, 2)
        XCTAssertEqual(api.insertedEvents.first?.start.dateTime, "2026-08-23T06:00:00+09:00")
        XCTAssertEqual(api.insertedEvents.last?.start.date, "2026-08-23")
        XCTAssertEqual(api.insertedEvents.last?.end.date, "2026-08-24")
        XCTAssertEqual(api.insertedEvents.last?.transparency, "transparent")
        let link = try XCTUnwrap(try context.fetch(FetchDescriptor<GoogleCalendarEventLink>()).first)
        XCTAssertEqual(link.googleEventID, eventID)
        XCTAssertEqual(link.lastGoogleScheduleSignature, "2026-08-23")
        XCTAssertEqual(link.syncState, .synced)
    }

    @MainActor
    func testEventPayloadFailureKeepsLastSuccessfulSyncAndSurfacesRetrySummary() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, calendar: calendar), plan: plan)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.lastSuccessfulSyncAt = date(2026, 8, 20, calendar: calendar)
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: "bad-event"
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.patchErrorsByEventID["bad-event"] = .permanent(400, "Bad Request")
        let now = date(2026, 8, 23, calendar: calendar)
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { now })

        await service.reconcile(reason: "test")

        XCTAssertEqual(connection.connectionStatus, .partialFailure)
        XCTAssertEqual(connection.lastSyncErrorCategory, .partialEventFailure)
        XCTAssertEqual(connection.lastSuccessfulSyncAt, date(2026, 8, 20, calendar: calendar))
        XCTAssertTrue(connection.lastSyncSummary?.contains("1 will retry") == true)
        XCTAssertTrue(connection.lastSyncSummary?.contains("First retry") == true)
        XCTAssertTrue(connection.lastSyncSummary?.contains("HTTP 400") == true)
        XCTAssertTrue(service.lastDebugReport?.contains("Failed: 1") == true)
        XCTAssertTrue(service.lastDebugReport?.contains("First retry:") == true)
        XCTAssertTrue(service.lastDebugReport?.contains("Bad Request") == true)
        XCTAssertTrue(service.lastDebugReport?.contains("start 2026-08-25") == true)
    }

    @MainActor
    func testEventAuthorizationFailureRequiresReconnectInsteadOfPartialRetry() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, calendar: calendar), plan: plan)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: "forbidden-event"
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.patchErrorsByEventID["forbidden-event"] = .unauthorized
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current)

        await service.reconcile(reason: "test")

        XCTAssertEqual(connection.connectionStatus, .needsReconnect)
        XCTAssertEqual(connection.lastSyncErrorCategory, .permissionRevoked)
        XCTAssertEqual(connection.lastSyncSummary, "Reconnect Google Calendar.")
        XCTAssertTrue(service.lastDebugReport?.contains("Google Calendar sync failed") == true)
        XCTAssertTrue(service.lastDebugReport?.contains("Error category: permissionRevoked") == true)
    }

    @MainActor
    func testRemovedFutureWorkoutDeletesManagedEvent() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        let removedWorkoutID = UUID()
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: removedWorkoutID,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: "google-event-1"
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: fixedCalendar, timeZone: .current)

        await service.reconcile(reason: "test")

        XCTAssertEqual(api.deletedEvents, ["google-event-1"])
    }

    @MainActor
    func testAlreadyMissingRemovedEventDoesNotKeepSyncIncomplete() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .partialFailure
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        let removedWorkoutID = UUID()
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: removedWorkoutID,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: "already-missing-event"
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.deleteErrorsByEventID["already-missing-event"] = .notFound
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: fixedCalendar, timeZone: .current)

        await service.reconcile(reason: "test")

        XCTAssertEqual(connection.connectionStatus, .connected)
        let link = try XCTUnwrap(try context.fetch(FetchDescriptor<GoogleCalendarEventLink>()).first)
        XCTAssertEqual(link.syncState, .deleted)
    }

    @MainActor
    func testSchedulingFromGoogleDefaultsOffAndUsesNarrowCalendarScope() throws {
        let connection = GoogleCalendarConnection()
        let scopes = Set(GoogleCalendarSyncSettings.scope.split(separator: " ").map(String.init))

        XCTAssertFalse(connection.allowsSchedulingFromGoogle)
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/calendar.app.created"))
        XCTAssertFalse(scopes.contains("https://www.googleapis.com/auth/calendar.readonly"))
        XCTAssertFalse(scopes.contains("https://www.googleapis.com/auth/calendar.events.readonly"))
        XCTAssertFalse(scopes.contains("https://www.googleapis.com/auth/calendar"))
    }

    @MainActor
    func testEnableAndDisableTwoWaySchedulingPersistsPreference() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        context.insert(connection)
        try context.save()
        let service = GoogleCalendarSyncService(modelContext: context, api: FakeGoogleCalendarAPI(), oauth: nil, calendar: fixedCalendar, timeZone: .current)

        service.updateSchedulingFromGoogle(enabled: true)
        XCTAssertTrue(connection.allowsSchedulingFromGoogle)

        service.updateSchedulingFromGoogle(enabled: false)
        XCTAssertFalse(connection.allowsSchedulingFromGoogle)
        XCTAssertNil(connection.googleCalendarIncrementalSyncToken)
    }

    @MainActor
    func testGoogleSameDayTimeChangeUpdatesWorkoutWhenOptedIn() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [
            remoteEvent(for: workout, start: GoogleCalendarEventDate(date: nil, dateTime: "2026-08-18T07:30:00+09:00", timeZone: "Asia/Tokyo"))
        ], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        XCTAssertTrue(calendar.isDate(workout.date, inSameDayAs: date(2026, 8, 18, calendar: calendar)))
        XCTAssertEqual(calendar.component(.hour, from: workout.date), 7)
        XCTAssertEqual(calendar.component(.minute, from: workout.date), 30)
        XCTAssertTrue(workout.manuallyOverridden)
        XCTAssertEqual(connection.googleCalendarIncrementalSyncToken, "token-1")
        let changes = try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>())
        XCTAssertEqual(changes.first?.status, .applied)
        XCTAssertEqual(changes.first?.reason, .sameDayTimeChanged)
    }

    @MainActor
    func testGoogleTimedWorkoutChangedBackToAllDayClearsExplicitStartTime() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, hour: 6, minute: 30, calendar: calendar), plan: plan)
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [
            remoteEvent(for: workout, start: GoogleCalendarEventDate(date: "2026-08-18", dateTime: nil, timeZone: nil))
        ], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        XCTAssertTrue(calendar.isDate(workout.date, inSameDayAs: date(2026, 8, 18, calendar: calendar)))
        XCTAssertEqual(calendar.component(.hour, from: workout.date), 0)
        XCTAssertEqual(calendar.component(.minute, from: workout.date), 0)
    }

    @MainActor
    func testGoogleSafeSameWeekDateMoveAppliesAutomatically() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [
            remoteEvent(for: workout, start: GoogleCalendarEventDate(date: "2026-08-20", dateTime: nil, timeZone: nil))
        ], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        XCTAssertTrue(calendar.isDate(workout.date, inSameDayAs: date(2026, 8, 20, calendar: calendar)))
        XCTAssertEqual(workout.scheduleUpdatedFrom, "googleCalendar")
        XCTAssertNotNil(workout.scheduleUpdatedAt)
        let changes = try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>())
        XCTAssertEqual(changes.first?.status, .applied)
        XCTAssertEqual(changes.first?.reason, .sameWeekDateChanged)
    }

    @MainActor
    func testGoogleCrossWeekDateMoveRequiresReview() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [
            remoteEvent(for: workout, start: GoogleCalendarEventDate(date: "2026-08-26", dateTime: nil, timeZone: nil))
        ], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        XCTAssertTrue(calendar.isDate(workout.date, inSameDayAs: date(2026, 8, 18, calendar: calendar)))
        let changes = try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>())
        XCTAssertEqual(changes.first?.status, .pendingReview)
        XCTAssertEqual(changes.first?.reason, .outsidePlannedWeek)
    }

    @MainActor
    func testGoogleMoveToOccupiedDayRequiresReviewAndDoesNotMoveWorkout() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let source = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        let occupied = makeWorkout(on: date(2026, 8, 21, calendar: calendar), plan: plan)
        context.insert(goal)
        context.insert(plan)
        context.insert(source)
        context.insert(occupied)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: source.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: source.uuid)
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [
            remoteEvent(for: source, start: GoogleCalendarEventDate(date: "2026-08-21", dateTime: nil, timeZone: nil))
        ], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        XCTAssertTrue(calendar.isDate(source.date, inSameDayAs: date(2026, 8, 18, calendar: calendar)))
        let changes = try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>())
        XCTAssertEqual(changes.first?.status, .pendingReview)
        XCTAssertEqual(changes.first?.reason, .targetDayConflict)
    }

    @MainActor
    func testGoogleContentEditIsNormalizedWithoutChangingWorkout() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        var event = remoteEvent(for: workout, start: GoogleCalendarEventDate(date: "2026-08-18", dateTime: nil, timeZone: nil))
        event.summary = "Gym"
        event.description = "Lift"
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [event], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        XCTAssertEqual(workout.kind, .tempo)
        XCTAssertEqual(workout.distanceKm, 8)
        XCTAssertEqual(api.patchedEvents.count, 1)
        let changes = try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>())
        XCTAssertEqual(changes.first?.status, .restored)
        XCTAssertEqual(changes.first?.reason, .contentRestored)
    }

    @MainActor
    func testDuplicateInboundReviewItemIsNotDuplicated() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let source = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        let occupied = makeWorkout(on: date(2026, 8, 21, calendar: calendar), plan: plan)
        context.insert(goal)
        context.insert(plan)
        context.insert(source)
        context.insert(occupied)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: source.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: source.uuid)
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let moved = remoteEvent(for: source, start: GoogleCalendarEventDate(date: "2026-08-21", dateTime: nil, timeZone: nil))
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [moved, moved], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        let changes = try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>())
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.reason, .targetDayConflict)
    }

    @MainActor
    func testEchoedOutboundScheduleChangeIsIgnored() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        let event = remoteEvent(for: workout, start: GoogleCalendarEventDate(date: "2026-08-18", dateTime: nil, timeZone: nil))
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        let link = GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: event.id
        )
        link.lastGoogleScheduleSignature = GoogleCalendarInboundReconciler(calendar: calendar).scheduleSignature(for: event)
        context.insert(link)
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [event], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        let changes = try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>())
        XCTAssertTrue(changes.isEmpty)
    }

    @MainActor
    func testDeletedGoogleEventKeepsWorkoutAndSuppressesCalendarEventUntilAddBack() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        let eventID = GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: eventID
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.remoteEventPages = [GoogleCalendarEventPage(items: [
            GoogleCalendarRemoteEvent(
                id: eventID,
                status: "cancelled",
                summary: nil,
                description: nil,
                start: nil,
                end: nil,
                updated: "2026-08-21T00:00:00Z",
                extendedProperties: nil
            )
        ], nextSyncToken: "token-1")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannedWorkout>()).count, 1)
        XCTAssertEqual(api.insertedEvents.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GoogleCalendarEventLink>()).first?.syncState, .notVisibleInGoogleCalendar)
        let changes = try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>())
        XCTAssertEqual(changes.first?.status, .pendingReview)
        XCTAssertEqual(changes.first?.reason, .eventDeleted)

        service.addBackToGoogleCalendar(workoutID: workout.uuid)
        await service.reconcile(reason: "testAddBack")

        XCTAssertEqual(api.insertedEvents.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GoogleCalendarInboundChange>()).first?.status, .restored)
    }

    @MainActor
    func testOutboundPatchOmitsRemindersToPreserveGoogleCustomization() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 25, calendar: calendar), plan: plan)
        let eventID = GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: eventID
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.reconcile(reason: "test")

        XCTAssertEqual(api.patchedEvents, [eventID])
        XCTAssertNil(api.patchedEventPayloads.first?.reminders)
    }

    @MainActor
    func testExpiredInboundSyncTokenRetriesOnceWithBoundedFullRefresh() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 18, calendar: calendar), plan: plan)
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.googleCalendarID = "calendar-1"
        connection.allowsSchedulingFromGoogle = true
        connection.googleCalendarIncrementalSyncToken = "old-token"
        context.insert(connection)
        context.insert(GoogleCalendarEventLink(
            connectionID: connection.uuid,
            localEntityType: .plannedWorkout,
            localEntityID: workout.uuid,
            trainingPlanID: nil,
            googleCalendarID: "calendar-1",
            googleEventID: GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        ))
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }
        let api = FakeGoogleCalendarAPI()
        api.listEventsErrors = [.syncTokenExpired]
        api.remoteEventPages = [GoogleCalendarEventPage(items: [], nextSyncToken: "fresh-token")]
        let service = GoogleCalendarSyncService(modelContext: context, api: api, oauth: nil, calendar: calendar, timeZone: .current, now: { self.date(2026, 8, 19, calendar: calendar) })

        await service.checkForCalendarChanges()

        XCTAssertEqual(api.listEventsSyncTokens, ["old-token", nil])
        XCTAssertEqual(connection.googleCalendarIncrementalSyncToken, "fresh-token")
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var validTokens: GoogleCalendarTokenSet {
        GoogleCalendarTokenSet(accessToken: "access", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), tokenType: "Bearer")
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Goal.self, CompletedActivity.self, TrainingPlan.self, PlannedWorkout.self,
            GoogleCalendarConnection.self, GoogleCalendarEventLink.self,
            GoogleCalendarInboundChange.self,
            ScheduleChangeOperation.self,
            GoogleAvailabilityCalendar.self,
            DayAvailability.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makePlan(anchor: Date) -> TrainingPlan {
        TrainingPlan(spec: TrainingPlanSpec(
            goal: GoalSpec(distance: .marathon, targetTimeSeconds: 14_400, raceDate: anchor.addingTimeInterval(60 * 60 * 24 * 70), availableDays: [.tuesday, .thursday, .saturday, .sunday], longRunDay: .sunday),
            anchorDate: anchor,
            weeks: [WeekPlan(startDate: anchor, index: 0, phase: .base, isDownWeek: false, isPartial: false, targetVolumeKm: 42, workouts: [])]
        ), generatedAt: anchor)
    }

    private func makeGoal(anchor: Date) -> Goal {
        Goal(spec: GoalSpec(
            distance: .marathon,
            targetTimeSeconds: 14_400,
            raceDate: anchor.addingTimeInterval(60 * 60 * 24 * 70),
            availableDays: [.tuesday, .thursday, .saturday, .sunday],
            longRunDay: .sunday
        ), createdAt: anchor)
    }

    private func makeWorkout(on date: Date, plan: TrainingPlan) -> PlannedWorkout {
        let workout = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: date,
                kind: .tempo,
                distanceKm: 8,
                paceBand: PaceBand(fastSecondsPerKm: 315, slowSecondsPerKm: 325),
                details: "4 × 8 min tempo"
            ),
            weekIndex: 0,
            phase: .base
        )
        workout.plan = plan
        return workout
    }

    private func makeActivity(on date: Date) -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: date,
            distanceMeters: 8_140,
            durationSeconds: 3_092,
            avgHeartRate: nil,
            maxHeartRate: nil,
            avgPaceSecondsPerKm: 380,
            sourceName: "Unit Test"
        )
    }

    private func remoteEvent(for workout: PlannedWorkout, start: GoogleCalendarEventDate) -> GoogleCalendarRemoteEvent {
        let eventID = GoogleCalendarEventBuilder.deterministicEventID(type: .plannedWorkout, id: workout.uuid)
        return GoogleCalendarRemoteEvent(
            id: eventID,
            status: "confirmed",
            summary: "Tempo Run · 8 km",
            description: GoogleCalendarEventBuilder(calendar: fixedCalendar, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
                .plannedWorkoutEvent(workout, plan: workout.plan!, completion: nil)
                .payload
                .description,
            start: start,
            end: start,
            updated: "2026-08-21T00:00:00Z",
            extendedProperties: GoogleCalendarExtendedProperties(private: [
                "rotEntityId": workout.uuid.uuidString,
                "rotEntityType": "plannedWorkout"
            ])
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

private final class FakeGoogleCalendarAPI: GoogleCalendarAPIServicing {
    var createCalendarCount = 0
    var insertedEvents: [GoogleCalendarEventPayload] = []
    var patchedEvents: [String] = []
    var deletedEvents: [String] = []
    var insertErrorsByEventID: [String: GoogleCalendarAPIError] = [:]
    var patchErrorsByEventID: [String: GoogleCalendarAPIError] = [:]
    var deleteErrorsByEventID: [String: GoogleCalendarAPIError] = [:]
    var remoteEventsByEntity: [String: String] = [:]
    var remoteEventPages: [GoogleCalendarEventPage] = []
    var listEventsErrors: [GoogleCalendarAPIError] = []
    var listEventsSyncTokens: [String?] = []
    var patchedEventPayloads: [GoogleCalendarEventPayload] = []
    var calendarList: [GoogleCalendarListEntry] = []
    var freeBusyResponse = GoogleFreeBusyResponse(calendars: [:])

    func exchangeCode(_ code: String, verifier: String) async throws -> GoogleCalendarTokenSet {
        GoogleCalendarTokenSet(accessToken: "access", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), tokenType: "Bearer")
    }

    func refresh(_ refreshToken: String) async throws -> GoogleCalendarTokenSet {
        GoogleCalendarTokenSet(accessToken: "refreshed", refreshToken: refreshToken, expiresAt: Date().addingTimeInterval(3600), tokenType: "Bearer")
    }

    func userInfo(accessToken: String) async throws -> GoogleCalendarUserInfo {
        GoogleCalendarUserInfo(sub: "google-user", email: "runner@example.com")
    }

    func calendar(id: String, accessToken: String) async throws -> GoogleCalendarListEntry {
        GoogleCalendarListEntry(id: id, summary: "RestOrTrain Training", description: nil, timeZone: "Asia/Tokyo")
    }

    func createCalendar(name: String, description: String, timeZone: String, accessToken: String) async throws -> GoogleCalendarListEntry {
        createCalendarCount += 1
        return GoogleCalendarListEntry(id: "calendar-1", summary: name, description: description, timeZone: timeZone)
    }

    func deleteCalendar(id: String, accessToken: String) async throws {}

    func revokeToken(_ token: String) async throws {}

    func insertEvent(calendarID: String, event: GoogleCalendarEventPayload, accessToken: String) async throws -> GoogleCalendarEventResponse {
        insertedEvents.append(event)
        if let error = event.id.flatMap({ insertErrorsByEventID.removeValue(forKey: $0) }) {
            throw error
        }
        return GoogleCalendarEventResponse(id: event.id ?? UUID().uuidString)
    }

    func patchEvent(calendarID: String, eventID: String, event: GoogleCalendarEventPayload, accessToken: String) async throws -> GoogleCalendarEventResponse {
        patchedEvents.append(eventID)
        patchedEventPayloads.append(event)
        if let error = patchErrorsByEventID[eventID] {
            throw error
        }
        return GoogleCalendarEventResponse(id: eventID)
    }

    func deleteEvent(calendarID: String, eventID: String, accessToken: String) async throws {
        deletedEvents.append(eventID)
        if let error = deleteErrorsByEventID[eventID] {
            throw error
        }
    }

    func eventsByPrivateProperty(calendarID: String, key: String, value: String, accessToken: String) async throws -> [GoogleCalendarEventResponse] {
        remoteEventsByEntity[value].map { [GoogleCalendarEventResponse(id: $0)] } ?? []
    }

    func listEvents(calendarID: String, syncToken: String?, accessToken: String) async throws -> GoogleCalendarEventPage {
        listEventsSyncTokens.append(syncToken)
        if !listEventsErrors.isEmpty {
            throw listEventsErrors.removeFirst()
        }
        return remoteEventPages.isEmpty ? GoogleCalendarEventPage(items: [], nextSyncToken: "empty-token") : remoteEventPages.removeFirst()
    }

    func listCalendarList(accessToken: String) async throws -> [GoogleCalendarListEntry] {
        calendarList
    }

    func freeBusy(request: GoogleFreeBusyRequest, accessToken: String) async throws -> GoogleFreeBusyResponse {
        freeBusyResponse
    }
}
