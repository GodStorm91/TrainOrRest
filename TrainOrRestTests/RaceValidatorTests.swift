import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class RaceValidatorTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let goalRaceDay = PlanEngineTestSupport.date(2026, 1, 11)
    private let extraRaceDay = PlanEngineTestSupport.date(2026, 1, 9)
    private let firstWorkoutDay = PlanEngineTestSupport.date(2026, 1, 6)
    private let secondWorkoutDay = PlanEngineTestSupport.date(2026, 1, 7)

    func testGoalRaceWorkoutNeedsNoSeasonDate() {
        let issues = raceIssues(in: planSpec())

        XCTAssertEqual(issues.count, 0)
    }

    func testOffSeasonRaceWorkoutIsReported() {
        let issues = raceIssues(in: planSpec(includesExtraRace: true))

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].kind, .raceOffSeasonDay)
        XCTAssertEqual(issues[0].message, "Race workout on a day with no scheduled race")
        XCTAssertEqual(issues[0].day, calendar.startOfDay(for: extraRaceDay))
    }

    func testSeasonRaceWorkoutIsAllowed() {
        let issues = raceIssues(
            in: planSpec(includesExtraRace: true),
            seasonRaceDates: [extraRaceDay]
        )

        XCTAssertEqual(issues.count, 0)
    }

    func testOffSeasonRaceWorkoutBlocksChanges() {
        switch PlanValidator.Issue.Kind.raceOffSeasonDay.severity {
        case .blocking:
            break
        case .acknowledge, .inform:
            XCTFail("Expected blocking severity")
        }
    }

    func testApplyWritesTwoDaysAndRevertRestoresBothRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (first, second) = try seedPlan(in: context)
        let firstBefore = PlanWorkoutReceiptSnapshot(workout: first)
        let secondBefore = PlanWorkoutReceiptSnapshot(workout: second)

        let editID = try XCTUnwrap(RacePlanApplier.apply(
            twoDayChange(),
            in: context,
            today: today,
            calendar: calendar,
            summary: "Applied race schedule"
        ))

        let firstAfter = try XCTUnwrap(try workout(on: firstWorkoutDay, in: context))
        let secondAfter = try XCTUnwrap(try workout(on: secondWorkoutDay, in: context))
        let plan = try XCTUnwrap(try PlanStore.activePlan(in: context))
        let edit = try XCTUnwrap(try planEdit(id: editID, in: context))
        XCTAssertEqual(firstAfter.kindRaw, WorkoutKind.easy.rawValue)
        XCTAssertEqual(firstAfter.distanceKm, 3.0)
        XCTAssertEqual(firstAfter.details, "Easy 3.0 km")
        XCTAssertTrue(firstAfter.manuallyOverridden)
        XCTAssertEqual(secondAfter.kindRaw, WorkoutKind.race.rawValue)
        XCTAssertEqual(secondAfter.distanceKm, 5.0)
        XCTAssertEqual(secondAfter.details, "Race: Tune-up 5.0 km")
        XCTAssertTrue(secondAfter.manuallyOverridden)
        XCTAssertEqual(plan.weekTargetVolumesKm, [8.0])
        XCTAssertEqual(edit.source, "race")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlanEdit>()).count, 1)

        try PlanEditStore.revert(editID, in: context, today: today, calendar: calendar)

        let restoredFirst = try XCTUnwrap(try workout(on: firstWorkoutDay, in: context))
        let restoredSecond = try XCTUnwrap(try workout(on: secondWorkoutDay, in: context))
        XCTAssertEqual(restoredFirst.kindRaw, WorkoutKind.easy.rawValue)
        XCTAssertEqual(restoredFirst.distanceKm, 5.0)
        XCTAssertEqual(restoredSecond.kindRaw, WorkoutKind.tempo.rawValue)
        XCTAssertEqual(restoredSecond.distanceKm, 8.0)
        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: restoredFirst), firstBefore)
        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: restoredSecond), secondBefore)
        XCTAssertEqual(plan.weekTargetVolumesKm, [13.0])
    }

    func testApplyEmptyChangeReturnsNilAndInsertsNoPlanEdit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try seedPlan(in: context)

        let editID = try RacePlanApplier.apply(
            .empty,
            in: context,
            today: today,
            calendar: calendar,
            summary: "Applied race schedule"
        )

        XCTAssertNil(editID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlanEdit>()).count, 0)
    }

    func testRecoveryRestDeletesWorkoutAndRevertRestoresIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (first, _) = try seedPlan(in: context)
        let before = PlanWorkoutReceiptSnapshot(workout: first)
        let change = RaceScheduleChange(dayChanges: [
            RaceDayChange(
                date: firstWorkoutDay,
                intent: .recovery,
                raceID: raceID,
                beforeSummary: "Easy 5.0 km",
                afterSummary: "Rest",
                afterKilometers: 0
            )
        ], warnings: [])

        let editID = try XCTUnwrap(RacePlanApplier.apply(
            change,
            in: context,
            today: today,
            calendar: calendar,
            summary: "Applied race recovery"
        ))

        let plan = try XCTUnwrap(try PlanStore.activePlan(in: context))
        XCTAssertNil(try workout(on: firstWorkoutDay, in: context))
        XCTAssertEqual(plan.weekTargetVolumesKm, [8.0])

        try PlanEditStore.revert(editID, in: context, today: today, calendar: calendar)

        let restored = try XCTUnwrap(try workout(on: firstWorkoutDay, in: context))
        XCTAssertEqual(restored.kindRaw, WorkoutKind.easy.rawValue)
        XCTAssertEqual(restored.distanceKm, 5.0)
        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: restored), before)
        XCTAssertEqual(plan.weekTargetVolumesKm, [13.0])
    }

    private func raceIssues(
        in plan: TrainingPlanSpec,
        seasonRaceDates: Set<Date> = []
    ) -> [PlanValidator.Issue] {
        PlanValidator.validate(
            plan,
            calendar: calendar,
            seasonRaceDates: seasonRaceDates
        ).filter { $0.kind == .raceMissing || $0.kind == .raceOffSeasonDay }
    }

    private func planSpec(includesExtraRace: Bool = false) -> TrainingPlanSpec {
        var workouts = [PlannedWorkoutSpec(
            date: goalRaceDay,
            kind: .race,
            distanceKm: 21.1,
            paceBand: nil,
            details: "Race 21.1 km"
        )]
        if includesExtraRace {
            workouts.append(PlannedWorkoutSpec(
                date: extraRaceDay,
                kind: .race,
                distanceKm: 5.0,
                paceBand: nil,
                details: "Race 5.0 km"
            ))
        }
        return TrainingPlanSpec(
            goal: goalSpec(),
            anchorDate: today,
            weeks: [WeekPlan(
                startDate: today,
                index: 0,
                phase: .taper,
                isDownWeek: false,
                isPartial: false,
                targetVolumeKm: 5,
                workouts: workouts
            )]
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TrainingPlan.self, PlannedWorkout.self, PlanEdit.self])
        let configuration = ModelConfiguration(
            "RaceValidatorTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func seedPlan(in context: ModelContext) throws -> (PlannedWorkout, PlannedWorkout) {
        let spec = TrainingPlanSpec(
            goal: goalSpec(),
            anchorDate: today,
            weeks: [WeekPlan(
                startDate: today,
                index: 0,
                phase: .base,
                isDownWeek: false,
                isPartial: false,
                targetVolumeKm: 13,
                workouts: []
            )]
        )
        let plan = TrainingPlan(spec: spec, generatedAt: today)
        let first = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: firstWorkoutDay,
                kind: .easy,
                distanceKm: 5,
                paceBand: nil,
                details: "Easy 5.0 km"
            ),
            weekIndex: 0,
            phase: .base
        )
        let second = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: secondWorkoutDay,
                kind: .tempo,
                distanceKm: 8,
                paceBand: nil,
                details: "Tempo 8.0 km"
            ),
            weekIndex: 0,
            phase: .base
        )
        first.plan = plan
        second.plan = plan
        context.insert(plan)
        context.insert(first)
        context.insert(second)
        try context.save()
        return (first, second)
    }

    private func twoDayChange() -> RaceScheduleChange {
        RaceScheduleChange(dayChanges: [
            RaceDayChange(
                date: firstWorkoutDay,
                intent: .taper,
                raceID: raceID,
                beforeSummary: "Easy 5.0 km",
                afterSummary: "Easy 3.0 km",
                afterKilometers: 3
            ),
            RaceDayChange(
                date: secondWorkoutDay,
                intent: .replacesQuality,
                raceID: raceID,
                beforeSummary: "Tempo 8.0 km",
                afterSummary: "Race: Tune-up 5.0 km",
                afterKilometers: 5
            )
        ], warnings: [])
    }

    private func goalSpec() -> GoalSpec {
        GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 6_300,
            raceDate: goalRaceDay,
            availableDays: Set(Weekday.allCases),
            longRunDay: .sunday
        )
    }

    private func workout(on date: Date, in context: ModelContext) throws -> PlannedWorkout? {
        try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    private func planEdit(id: UUID, in context: ModelContext) throws -> PlanEdit? {
        try context.fetch(FetchDescriptor<PlanEdit>()).first { $0.id == id }
    }

    private var raceID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }
}
