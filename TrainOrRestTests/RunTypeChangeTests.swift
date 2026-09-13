import Foundation
import SwiftData
import XCTest
@testable import TrainOrRest

/// Changing a planned run's type (easy -> tempo) is always a single replace on
/// that day. Fitness only decides whether paces are filled in or a note is
/// shown; it never blocks the change.
@MainActor
final class RunTypeChangeTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 9, 12, hour: 8)
    private let easyDay = PlanEngineTestSupport.date(2026, 9, 13, hour: 0)

    func testWarmStartTypeChangeIsOnePacedReplace() throws {
        let container = try seededContainer(withHistory: true)
        let candidate = try prepareTempoReplace(in: container.mainContext)

        let op = try XCTUnwrap(candidate.transaction.operations.first)
        XCTAssertEqual(candidate.transaction.operations.count, 1, candidate.summary)
        XCTAssertEqual(op.before?.kindRaw, WorkoutKind.easy.rawValue)
        XCTAssertEqual(op.after?.kindRaw, WorkoutKind.tempo.rawValue)
        XCTAssertNotNil(op.after?.paceFastSecondsPerKm, "warm start fills the tempo pace in")
        XCTAssertTrue(candidate.loadRisks.isEmpty, "\(candidate.loadRisks.map(\.message))")
        XCTAssertTrue(candidate.notes.isEmpty, "\(candidate.notes.map(\.message))")
    }

    func testColdStartTypeChangeIsOneUnpacedReplaceWithNote() throws {
        let container = try seededContainer(withHistory: false)
        let candidate = try prepareTempoReplace(in: container.mainContext)

        let op = try XCTUnwrap(candidate.transaction.operations.first)
        XCTAssertEqual(candidate.transaction.operations.count, 1, candidate.summary)
        XCTAssertEqual(op.before?.kindRaw, WorkoutKind.easy.rawValue)
        XCTAssertEqual(op.after?.kindRaw, WorkoutKind.tempo.rawValue)
        XCTAssertNil(op.after?.paceFastSecondsPerKm, "cold start leaves the tempo by effort")
        XCTAssertTrue(candidate.loadRisks.isEmpty, "a missing pace is a fact, not a load risk")
        XCTAssertEqual(candidate.notes.map(\.kind), [.paceUnavailable])
    }

    private func prepareTempoReplace(in context: ModelContext) throws -> CoachPlanCandidate {
        typealias Step = PlanAdjustmentProposal.CreateWorkout.Step
        let tempo = PlanAdjustmentProposal.CreateWorkout(kind: "tempo", blocks: [.init(repeatCount: 1, steps: [
            Step(role: "warm_up", targetType: "distance_km", targetValue: 2, paceZone: "easy"),
            Step(role: "work", targetType: "distance_km", targetValue: 4, paceZone: "threshold"),
            Step(role: "cool_down", targetType: "distance_km", targetValue: 2, paceZone: "easy")
        ])])
        return try CoachPlanCandidateEngine.prepare(
            proposal: PlanAdjustmentProposal(changes: [.init(
                date: CoachContextBuilder.day(easyDay, calendar: calendar),
                action: .replace,
                detail: nil,
                workout: tempo
            )]),
            in: context,
            today: today,
            calendar: calendar,
            language: .vi
        )
    }

    private func seededContainer(withHistory: Bool) throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, PlanEdit.self
        ])
        let configuration = ModelConfiguration("RunTypeChange-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        if withHistory {
            for offset in 0..<24 {
                let day = calendar.date(byAdding: .day, value: -(2 + offset * 2), to: today)!
                context.insert(CompletedActivity(
                    hkUUID: UUID(), date: day, distanceMeters: (8 + Double(offset % 3)) * 1000,
                    durationSeconds: 46 * 60, avgHeartRate: 145, maxHeartRate: 168,
                    avgPaceSecondsPerKm: 345, sourceName: "Garmin"
                ))
            }
        }
        let goal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 12, 6),
            availableDays: [.tuesday, .thursday, .saturday, .sunday],
            longRunDay: .sunday
        )
        let fitness = FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0, longestRecentRunKm: 16)
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)
        XCTAssertEqual(
            try PlanStore.currentFitness(in: context, today: today, calendar: calendar) != nil,
            withHistory,
            "fixture must be \(withHistory ? "warm" : "cold")"
        )

        // The plan puts Sunday's long run on 13/09; the bug report is about an
        // easy run there, so downgrade it in place.
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        let existing = try XCTUnwrap(workouts.first { calendar.isDate($0.date, inSameDayAs: easyDay) })
        existing.kindRaw = WorkoutKind.easy.rawValue
        existing.structure = WorkoutStructure.run(distanceKm: existing.distanceKm, paceBand: existing.paceBand)
        existing.details = "Easy run"
        try context.save()
        return container
    }
}
