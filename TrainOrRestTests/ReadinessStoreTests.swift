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
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatMessage.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
