import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class ReadinessStoreTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)

    func testDailyPipelineBackfillsEmptyFutureWorkoutStructures() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let history = PlanEngineTestSupport.history(
            weeks: 8,
            runsPerWeek: 2,
            distanceKm: 8,
            paceSecondsPerKm: 330,
            endingAt: today
        )
        for sample in history {
            context.insert(CompletedActivity(
                hkUUID: UUID(),
                date: sample.date,
                distanceMeters: sample.distanceKm * 1000,
                durationSeconds: sample.durationSeconds,
                avgHeartRate: nil,
                maxHeartRate: nil,
                avgPaceSecondsPerKm: sample.durationSeconds / sample.distanceKm,
                sourceName: "Garmin"
            ))
        }
        let fitness = try XCTUnwrap(PlanStore.currentFitness(in: context, today: today, calendar: calendar))
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)

        let futureRows = try context.fetch(FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate { $0.date >= today }
        ))
        XCTAssertFalse(futureRows.isEmpty)
        for row in futureRows where row.kind != .race {
            row.structure = []
        }
        try context.save()

        try ReadinessStore.runDailyPipeline(in: context, today: today, calendar: calendar)

        let regeneratedRows = try context.fetch(FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate { $0.date >= today }
        ))
        let pushableRows = regeneratedRows.filter { $0.kind != .race }
        XCTAssertFalse(pushableRows.isEmpty)
        XCTAssertTrue(pushableRows.allSatisfy { !$0.structure.isEmpty })
    }

    func testDailyPipelineCollapsesSameDayDuplicatePlannedWorkouts() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let history = PlanEngineTestSupport.history(
            weeks: 8,
            runsPerWeek: 2,
            distanceKm: 8,
            paceSecondsPerKm: 330,
            endingAt: today
        )
        for sample in history {
            context.insert(CompletedActivity(
                hkUUID: UUID(),
                date: sample.date,
                distanceMeters: sample.distanceKm * 1000,
                durationSeconds: sample.durationSeconds,
                avgHeartRate: nil,
                maxHeartRate: nil,
                avgPaceSecondsPerKm: sample.durationSeconds / sample.distanceKm,
                sourceName: "Garmin"
            ))
        }
        let fitness = try XCTUnwrap(PlanStore.currentFitness(in: context, today: today, calendar: calendar))
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)

        let original = try XCTUnwrap(
            try context.fetch(FetchDescriptor<PlannedWorkout>()).first { $0.date >= today && $0.status == .planned }
        )
        let shoeID = UUID()
        original.shoeID = shoeID
        original.manuallyOverridden = true
        let plan = try XCTUnwrap(try PlanStore.activePlan(in: context))
        let kind = try XCTUnwrap(original.kind)
        let phase = try XCTUnwrap(TrainingPhase(rawValue: original.phaseRaw))
        for _ in 0..<3 {
            let clone = PlannedWorkout(
                spec: PlannedWorkoutSpec(
                    date: original.date,
                    kind: kind,
                    distanceKm: original.distanceKm,
                    paceBand: original.paceBand,
                    details: original.details,
                    structure: original.structure
                ),
                weekIndex: original.weekIndex,
                phase: phase
            )
            clone.manuallyOverridden = true
            clone.plan = plan
            context.insert(clone)
        }
        try context.save()
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PlannedWorkout>()).filter {
                calendar.isDate($0.date, inSameDayAs: original.date) && $0.status == .planned
            }.count,
            4
        )

        try ReadinessStore.runDailyPipeline(in: context, today: today, calendar: calendar)

        let remaining = try context.fetch(FetchDescriptor<PlannedWorkout>()).filter {
            calendar.isDate($0.date, inSameDayAs: original.date) && $0.status == .planned
        }
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.shoeID, shoeID)
        XCTAssertEqual(remaining.first?.uuid, original.uuid)
    }

    func testDailyPipelineRealignsStaleManualWorkoutWeekWhenScheduleIsUnchanged() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let history = PlanEngineTestSupport.history(
            weeks: 8,
            runsPerWeek: 2,
            distanceKm: 8,
            paceSecondsPerKm: 330,
            endingAt: today
        )
        for sample in history {
            context.insert(CompletedActivity(
                hkUUID: UUID(),
                date: sample.date,
                distanceMeters: sample.distanceKm * 1000,
                durationSeconds: sample.durationSeconds,
                avgHeartRate: nil,
                maxHeartRate: nil,
                avgPaceSecondsPerKm: sample.durationSeconds / sample.distanceKm,
                sourceName: "Garmin"
            ))
        }
        let fitness = try XCTUnwrap(PlanStore.currentFitness(in: context, today: today, calendar: calendar))
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)
        try ReadinessStore.runDailyPipeline(in: context, today: today, calendar: calendar)

        let plan = try XCTUnwrap(try PlanStore.activePlan(in: context))
        let edited = try XCTUnwrap(
            try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)])).last {
                $0.date >= today && $0.status == .planned && $0.kind == .easy
            }
        )
        let expectedWeek = edited.weekIndex
        let expectedPhase = edited.phaseRaw
        edited.manuallyOverridden = true
        edited.weekIndex = plan.weekPhasesRaw.count + 1
        edited.phaseRaw = expectedPhase == TrainingPhase.taper.rawValue
            ? TrainingPhase.base.rawValue
            : TrainingPhase.taper.rawValue
        try context.save()
        let autoRows = try Set(context.fetch(FetchDescriptor<PlannedWorkout>()).filter {
            $0.date >= today && $0.status == .planned && !$0.manuallyOverridden
        }.map(\.uuid))

        try ReadinessStore.runDailyPipeline(in: context, today: today, calendar: calendar)

        let autoRowsAfter = try Set(context.fetch(FetchDescriptor<PlannedWorkout>()).filter {
            $0.date >= today && $0.status == .planned && !$0.manuallyOverridden
        }.map(\.uuid))
        XCTAssertEqual(autoRowsAfter, autoRows)
        XCTAssertEqual(edited.weekIndex, expectedWeek)
        XCTAssertEqual(edited.phaseRaw, expectedPhase)
    }

    private var goal: GoalSpec {
        GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 4, 19),
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, RuleOverride.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self, CoachRequestSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
