import Foundation
import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class RaceMigrationTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    func testMigrationCreatesUpcomingMarathonRace() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let raceDate = date(2026, 10, 25)
        let goal = Goal(
            spec: GoalSpec(
                distance: .marathon,
                targetTimeSeconds: 14_400,
                raceDate: raceDate,
                availableDays: [.monday, .wednesday, .friday, .sunday],
                longRunDay: .sunday
            ),
            createdAt: date(2026, 4, 1)
        )
        context.insert(goal)
        try context.save()

        try RaceSeasonStore.migrateGoalIfNeeded(
            in: context,
            now: date(2026, 4, 1),
            calendar: calendar,
            defaults: makeDefaults()
        )

        let races = try RaceSeasonStore.races(in: context)
        XCTAssertEqual(races.count, 1)
        let spec = try XCTUnwrap(races.first?.spec)
        XCTAssertEqual(spec.name, "Marathon")
        XCTAssertEqual(spec.date, raceDate)
        XCTAssertEqual(spec.distanceMeters, 42_195.0)
        XCTAssertEqual(spec.targetTimeSeconds, 14_400.0)
        XCTAssertEqual(spec.priority, .a)
        XCTAssertEqual(spec.status, .upcoming)
    }

    func testMigrationLeavesGoalAndPlanUntouched() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let createdAt = date(2026, 4, 1)
        let raceDate = date(2026, 10, 25)
        let goalSpec = GoalSpec(
            distance: .marathon,
            targetTimeSeconds: 14_400,
            raceDate: raceDate,
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday
        )
        let goal = Goal(spec: goalSpec, createdAt: createdAt)
        let plan = TrainingPlan(spec: trainingPlanSpec(for: goalSpec, anchorDate: createdAt), generatedAt: createdAt)
        let workout = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: date(2026, 4, 2),
                kind: .easy,
                distanceKm: 5,
                paceBand: nil,
                details: "Easy run"
            ),
            weekIndex: 0,
            phase: .base
        )
        workout.plan = plan
        context.insert(goal)
        context.insert(plan)
        context.insert(workout)
        try context.save()

        let beforeWorkoutCount = try context.fetch(FetchDescriptor<PlannedWorkout>()).count
        XCTAssertEqual(beforeWorkoutCount, 1)

        try RaceSeasonStore.migrateGoalIfNeeded(in: context, now: createdAt, calendar: calendar, defaults: makeDefaults())

        let goals = try context.fetch(FetchDescriptor<Goal>())
        XCTAssertEqual(goals.count, 1)
        let storedGoal = try XCTUnwrap(goals.first)
        XCTAssertEqual(storedGoal.distanceRaw, "marathon")
        XCTAssertEqual(storedGoal.targetTimeSeconds, 14_400.0)
        XCTAssertEqual(storedGoal.raceDate, raceDate)
        XCTAssertEqual(storedGoal.availableDayNumbers, [1, 2, 4, 6])
        XCTAssertEqual(storedGoal.longRunDayNumber, 1)
        XCTAssertEqual(storedGoal.createdAt, createdAt)

        let plans = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.anchorDate, createdAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannedWorkout>()).count, 1)
    }

    func testMigrationRunsOnlyOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let goal = Goal(
            spec: GoalSpec(
                distance: .tenK,
                targetTimeSeconds: 3_600,
                raceDate: date(2026, 8, 2),
                availableDays: [.tuesday, .thursday, .sunday],
                longRunDay: .sunday
            ),
            createdAt: date(2026, 4, 1)
        )
        context.insert(goal)
        try context.save()

        let defaults = makeDefaults()
        try RaceSeasonStore.migrateGoalIfNeeded(in: context, now: date(2026, 4, 1), calendar: calendar, defaults: defaults)
        try RaceSeasonStore.migrateGoalIfNeeded(in: context, now: date(2026, 4, 2), calendar: calendar, defaults: defaults)

        XCTAssertEqual(try RaceSeasonStore.races(in: context).count, 1)
    }

    func testMigrationMarksPastGoalRaceCompleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let goal = Goal(
            spec: GoalSpec(
                distance: .fiveK,
                targetTimeSeconds: 1_800,
                raceDate: date(2026, 4, 5),
                availableDays: [.monday, .wednesday, .friday],
                longRunDay: .friday
            ),
            createdAt: date(2026, 4, 1)
        )
        context.insert(goal)
        try context.save()

        try RaceSeasonStore.migrateGoalIfNeeded(in: context, now: date(2026, 4, 6), calendar: calendar, defaults: makeDefaults())

        let race = try XCTUnwrap(try RaceSeasonStore.races(in: context).first)
        XCTAssertEqual(try XCTUnwrap(race.spec).status, .completed)
    }

    func testDeletedMigratedRaceStaysDeletedOnRelaunch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let defaults = makeDefaults()
        let goal = Goal(
            spec: GoalSpec(
                distance: .halfMarathon,
                targetTimeSeconds: 6_300,
                raceDate: date(2026, 9, 20),
                availableDays: [.tuesday, .thursday, .sunday],
                longRunDay: .sunday
            ),
            createdAt: date(2026, 4, 1)
        )
        context.insert(goal)
        try context.save()

        try RaceSeasonStore.migrateGoalIfNeeded(in: context, now: date(2026, 4, 1), calendar: calendar, defaults: defaults)
        let migrated = try XCTUnwrap(try RaceSeasonStore.races(in: context).first)
        try RaceSeasonStore.remove(id: migrated.id, in: context)
        XCTAssertTrue(try RaceSeasonStore.races(in: context).isEmpty)

        try RaceSeasonStore.migrateGoalIfNeeded(in: context, now: date(2026, 4, 2), calendar: calendar, defaults: defaults)

        XCTAssertTrue(try RaceSeasonStore.races(in: context).isEmpty)
    }

    func testInsertingSecondUpcomingARaceDemotesFirstToB() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firstID = UUID()
        let secondID = UUID()
        let now = date(2026, 4, 1)
        try RaceSeasonStore.insert(
            RaceSpec(
                id: firstID,
                name: "Spring 10K",
                date: date(2026, 5, 10),
                distanceMeters: 10_000,
                targetTimeSeconds: 3_600,
                priority: .a
            ),
            in: context,
            now: now
        )
        try RaceSeasonStore.insert(
            RaceSpec(
                id: secondID,
                name: "Fall Marathon",
                date: date(2026, 10, 25),
                distanceMeters: 42_195,
                targetTimeSeconds: 14_400,
                priority: .a
            ),
            in: context,
            now: now
        )

        let first = try XCTUnwrap(try RaceSeasonStore.race(id: firstID, in: context))
        let second = try XCTUnwrap(try RaceSeasonStore.race(id: secondID, in: context))
        XCTAssertEqual(try XCTUnwrap(first.spec).priority, .b)
        XCTAssertEqual(try XCTUnwrap(second.spec).priority, .a)
    }

    func testSyncGoalToARaceUpdatesGoalInputsOnly() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let goal = Goal(
            spec: GoalSpec(
                distance: .fiveK,
                targetTimeSeconds: 1_800,
                raceDate: date(2026, 7, 4),
                availableDays: [.monday, .wednesday, .saturday],
                longRunDay: .saturday
            ),
            createdAt: date(2026, 4, 1)
        )
        context.insert(goal)
        try context.save()

        try RaceSeasonStore.insert(
            RaceSpec(
                name: "Autumn Half",
                date: date(2026, 10, 18),
                distanceMeters: 21_097.5,
                targetTimeSeconds: 7_200,
                priority: .a
            ),
            in: context,
            now: date(2026, 4, 1)
        )
        try RaceSeasonStore.syncGoalToARace(in: context, calendar: calendar)

        let storedGoal = try XCTUnwrap(try PlanStore.activeGoal(in: context))
        XCTAssertEqual(storedGoal.distanceRaw, "halfMarathon")
        XCTAssertEqual(storedGoal.raceDate, date(2026, 10, 18))
        XCTAssertEqual(storedGoal.targetTimeSeconds, 7_200.0)
        XCTAssertEqual(storedGoal.availableDayNumbers, [2, 4, 7])
        XCTAssertEqual(storedGoal.longRunDayNumber, 7)
    }

    func testRemoveDeletesRaceFromSeason() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let id = UUID()
        try RaceSeasonStore.insert(
            RaceSpec(
                id: id,
                name: "City 5K",
                date: date(2026, 6, 7),
                distanceMeters: 5_000,
                targetTimeSeconds: 1_800,
                priority: .c
            ),
            in: context,
            now: date(2026, 4, 1)
        )

        try RaceSeasonStore.remove(id: id, in: context)

        XCTAssertNil(try RaceSeasonStore.race(id: id, in: context))
        XCTAssertEqual(try RaceSeasonStore.season(in: context).races, [])
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "RaceMigrationTests-\(UUID().uuidString)") ?? .standard
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Race.self, Goal.self, TrainingPlan.self, PlannedWorkout.self])
        let configuration = ModelConfiguration(
            "RaceMigrationTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func trainingPlanSpec(for goal: GoalSpec, anchorDate: Date) -> TrainingPlanSpec {
        TrainingPlanSpec(
            goal: goal,
            anchorDate: anchorDate,
            weeks: [
                WeekPlan(
                    startDate: anchorDate,
                    index: 0,
                    phase: .base,
                    isDownWeek: false,
                    isPartial: false,
                    targetVolumeKm: 5,
                    workouts: []
                )
            ]
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        PlanEngineTestSupport.date(year, month, day)
    }
}
