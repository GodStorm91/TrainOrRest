import SwiftData
import XCTest
@testable import TrainOrRest

final class SmartSchedulingTests: XCTestCase {
    func testSmartSchedulingScopesAreSeparateAndPrivacyScoped() {
        let trainingScopes = Set(GoogleCalendarSyncSettings.scope.split(separator: " ").map(String.init))
        let smartScopes = Set(GoogleCalendarSyncSettings.smartSchedulingScope.split(separator: " ").map(String.init))

        XCTAssertTrue(trainingScopes.contains("https://www.googleapis.com/auth/calendar.app.created"))
        XCTAssertTrue(smartScopes.contains("https://www.googleapis.com/auth/calendar.freebusy"))
        XCTAssertTrue(smartScopes.contains("https://www.googleapis.com/auth/calendar.calendarlist.readonly"))
        XCTAssertFalse(smartScopes.contains("https://www.googleapis.com/auth/calendar.readonly"))
        XCTAssertFalse(smartScopes.contains("https://www.googleapis.com/auth/calendar.events.readonly"))
    }

    func testSmartSchedulingDefaultsOffForExistingConnection() throws {
        let connection = GoogleCalendarConnection()

        XCTAssertEqual(connection.smartSchedulingStatus, .off)
        XCTAssertFalse(connection.smartSchedulingEnabled)
        XCTAssertEqual(connection.preferredTrainingTime, .none)
    }

    @MainActor
    func testFreeBusyNormalizationExcludesRestOrTrainCalendarAndStoresNoTitles() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.smartSchedulingEnabled = true
        connection.googleCalendarID = "rot-training"
        context.insert(connection)
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }

        let api = FakeSmartSchedulingAPI()
        api.calendarList = [
            GoogleCalendarListEntry(id: "work", summary: "Work", description: "meetings", timeZone: "Asia/Tokyo", accessRole: "reader", primary: true, selected: true, backgroundColor: nil),
            GoogleCalendarListEntry(id: "rot-training", summary: "RestOrTrain Training", description: nil, timeZone: "Asia/Tokyo", accessRole: "owner", primary: false, selected: true, backgroundColor: nil),
            GoogleCalendarListEntry(id: "holidays", summary: "Holidays", description: nil, timeZone: "Asia/Tokyo", accessRole: "reader", primary: false, selected: true, backgroundColor: nil)
        ]
        api.freeBusyResponse = GoogleFreeBusyResponse(calendars: [
            "work": GoogleFreeBusyCalendar(errors: nil, busy: [
                GoogleFreeBusyBlock(start: "2026-08-20T09:00:00.000Z", end: "2026-08-20T10:00:00.000Z")
            ])
        ])
        let service = GoogleCalendarSyncService(
            modelContext: context,
            api: api,
            oauth: nil,
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: { self.date(2026, 8, 20, hour: 1, calendar: calendar) }
        )

        await service.refreshAvailability(reason: "test")

        let calendars = try context.fetch(FetchDescriptor<GoogleAvailabilityCalendar>())
        XCTAssertEqual(calendars.first(where: { $0.googleCalendarID == "work" })?.selectedForAvailability, true)
        XCTAssertEqual(calendars.first(where: { $0.googleCalendarID == "rot-training" })?.selectedForAvailability, false)
        XCTAssertEqual(calendars.first(where: { $0.googleCalendarID == "holidays" })?.selectedForAvailability, false)
        let days = try context.fetch(FetchDescriptor<DayAvailability>())
        XCTAssertFalse(days.isEmpty)
        XCTAssertEqual(days.flatMap(\.busyWindows).first?.state, .busy)
    }

    func testCandidateEngineRejectsBusyOverlapAndRanksPreferredEvening() throws {
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let goal = try XCTUnwrap(makeGoal(anchor: date(2026, 8, 17, calendar: calendar)).spec)
        let workout = makeWorkout(on: date(2026, 8, 20, calendar: calendar), plan: plan)
        let availability = DayAvailability(
            connectionID: UUID(),
            date: date(2026, 8, 20, calendar: calendar),
            timezoneIdentifier: "Asia/Tokyo",
            busyWindows: [
                AvailabilityWindow(start: date(2026, 8, 20, hour: 9, calendar: calendar), end: date(2026, 8, 20, hour: 17, calendar: calendar), state: .busy)
            ],
            availableWindows: [
                AvailabilityWindow(start: date(2026, 8, 20, hour: 6, calendar: calendar), end: date(2026, 8, 20, hour: 8, calendar: calendar), state: .available),
                AvailabilityWindow(start: date(2026, 8, 20, hour: 18, calendar: calendar), end: date(2026, 8, 20, hour: 21, calendar: calendar), state: .available)
            ],
            lastRefreshedAt: date(2026, 8, 20, calendar: calendar)
        )
        let request = SchedulingRequest(
            workout: workout,
            candidateDates: [date(2026, 8, 20, calendar: calendar)],
            currentTrainingWeek: 0,
            surroundingWorkouts: [workout],
            userPreferences: SmartSchedulingPreferences(preferredTime: .evening, earliestStartMinutes: 5 * 60, latestFinishMinutes: 21 * 60, bufferBeforeMinutes: 10, bufferAfterMinutes: 10),
            availability: [availability],
            timezone: TimeZone(identifier: "Asia/Tokyo")!,
            plan: plan,
            goal: goal
        )

        let candidates = SmartSchedulingEngine(calendar: calendar).candidates(for: request, limit: 2)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(calendar.component(.hour, from: candidates[0].startTime), 18)
        XCTAssertTrue(candidates[0].reasons.contains { $0.contains("preferred evening") })
    }

    func testLockedWorkoutHasNoSmartSchedulingCandidates() throws {
        let calendar = fixedCalendar
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 20, calendar: calendar), plan: plan)
        workout.isScheduleLocked = true
        let request = SchedulingRequest(
            workout: workout,
            candidateDates: [workout.date],
            currentTrainingWeek: 0,
            surroundingWorkouts: [workout],
            userPreferences: SmartSchedulingPreferences(preferredTime: .none, earliestStartMinutes: 0, latestFinishMinutes: 24 * 60, bufferBeforeMinutes: 0, bufferAfterMinutes: 0),
            availability: [],
            timezone: .current,
            plan: plan,
            goal: try XCTUnwrap(makeGoal(anchor: date(2026, 8, 17, calendar: calendar)).spec)
        )

        XCTAssertTrue(SmartSchedulingEngine(calendar: calendar).candidates(for: request).isEmpty)
    }

    @MainActor
    func testWorkoutDetailCandidateSearchRefreshesAvailabilityBeforeFindingSlot() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = fixedCalendar
        let connection = GoogleCalendarConnection()
        connection.connectionStatus = .connected
        connection.smartSchedulingEnabled = true
        context.insert(connection)
        let plan = makePlan(anchor: date(2026, 8, 17, calendar: calendar))
        let goal = makeGoal(anchor: date(2026, 8, 17, calendar: calendar))
        let workout = makeWorkout(on: date(2026, 8, 23, calendar: calendar), plan: plan)
        workout.status = .done
        context.insert(plan)
        context.insert(goal)
        context.insert(workout)
        try context.save()
        try GoogleCalendarTokenStore.save(validTokens, connectionID: connection.uuid)
        defer { try? GoogleCalendarTokenStore.delete(connectionID: connection.uuid) }

        let api = FakeSmartSchedulingAPI()
        api.calendarList = [
            GoogleCalendarListEntry(id: "primary", summary: "Primary", description: nil, timeZone: "Asia/Tokyo", accessRole: "owner", primary: true, selected: true, backgroundColor: nil)
        ]
        let service = GoogleCalendarSyncService(
            modelContext: context,
            api: api,
            oauth: nil,
            calendar: calendar,
            timeZone: TimeZone(identifier: "Asia/Tokyo")!,
            now: { self.date(2026, 8, 22, hour: 15, calendar: calendar) }
        )

        XCTAssertTrue(service.smartSchedulingCandidates(for: workout).isEmpty)

        let candidates = await service.refreshedSmartSchedulingCandidates(for: workout)

        XCTAssertEqual(api.freeBusyRequestCount, 1)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { calendar.isDate($0.date, inSameDayAs: workout.date) })
    }

    private var validTokens: GoogleCalendarTokenSet {
        GoogleCalendarTokenSet(accessToken: "access", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), tokenType: "Bearer")
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Goal.self, CompletedActivity.self, TrainingPlan.self, PlannedWorkout.self,
            GoogleCalendarConnection.self, GoogleCalendarEventLink.self,
            GoogleCalendarInboundChange.self, ScheduleChangeOperation.self,
            GoogleAvailabilityCalendar.self, DayAvailability.self,
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

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

private final class FakeSmartSchedulingAPI: GoogleCalendarAPIServicing {
    var calendarList: [GoogleCalendarListEntry] = []
    var freeBusyResponse = GoogleFreeBusyResponse(calendars: [:])
    var freeBusyRequestCount = 0

    func exchangeCode(_ code: String, verifier: String) async throws -> GoogleCalendarTokenSet { GoogleCalendarTokenSet(accessToken: "access", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), tokenType: "Bearer") }
    func refresh(_ refreshToken: String) async throws -> GoogleCalendarTokenSet { GoogleCalendarTokenSet(accessToken: "access", refreshToken: refreshToken, expiresAt: Date().addingTimeInterval(3600), tokenType: "Bearer") }
    func userInfo(accessToken: String) async throws -> GoogleCalendarUserInfo { GoogleCalendarUserInfo(sub: "user", email: "runner@example.com") }
    func calendar(id: String, accessToken: String) async throws -> GoogleCalendarListEntry { GoogleCalendarListEntry(id: id, summary: "RestOrTrain Training", description: nil, timeZone: nil, accessRole: nil, primary: nil, selected: nil, backgroundColor: nil) }
    func createCalendar(name: String, description: String, timeZone: String, accessToken: String) async throws -> GoogleCalendarListEntry { GoogleCalendarListEntry(id: "rot-training", summary: name, description: description, timeZone: timeZone, accessRole: "owner", primary: false, selected: true, backgroundColor: nil) }
    func deleteCalendar(id: String, accessToken: String) async throws {}
    func revokeToken(_ token: String) async throws {}
    func insertEvent(calendarID: String, event: GoogleCalendarEventPayload, accessToken: String) async throws -> GoogleCalendarEventResponse { GoogleCalendarEventResponse(id: event.id ?? UUID().uuidString) }
    func patchEvent(calendarID: String, eventID: String, event: GoogleCalendarEventPayload, accessToken: String) async throws -> GoogleCalendarEventResponse { GoogleCalendarEventResponse(id: eventID) }
    func deleteEvent(calendarID: String, eventID: String, accessToken: String) async throws {}
    func eventsByPrivateProperty(calendarID: String, key: String, value: String, accessToken: String) async throws -> [GoogleCalendarEventResponse] { [] }
    func listEvents(calendarID: String, syncToken: String?, accessToken: String) async throws -> GoogleCalendarEventPage { GoogleCalendarEventPage(items: [], nextSyncToken: nil) }
    func listCalendarList(accessToken: String) async throws -> [GoogleCalendarListEntry] { calendarList }
    func freeBusy(request: GoogleFreeBusyRequest, accessToken: String) async throws -> GoogleFreeBusyResponse {
        freeBusyRequestCount += 1
        return freeBusyResponse
    }
}
