import SwiftData
import XCTest
@testable import TrainOrRest

/// Coach-created workouts: canonical construction, the rejection matrix, and
/// atomic persistence that never touches an existing row.
@MainActor
final class CoachCreateWorkoutTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)      // Monday
    private let freeDay = PlanEngineTestSupport.date(2026, 1, 9, hour: 0)  // Friday, no workout
    private let occupiedDay = PlanEngineTestSupport.date(2026, 1, 7, hour: 0) // Wednesday tempo
    private let raceDay = PlanEngineTestSupport.date(2026, 1, 25, hour: 0)

    // MARK: - Success

    func testCreatesTempoWithAppDerivedPaceAndCanonicalStructure() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let paces = try XCTUnwrap(fitnessPaces(in: context))
        let targetBefore = try weekTarget(0, in: context)

        let result = try create(.tempo(workKm: 3), on: freeDay, in: context)

        let workout = try XCTUnwrap(workout(on: freeDay, in: context))
        XCTAssertEqual(result.summary, "Created tempo on 2026-01-09")
        XCTAssertEqual(workout.kind, .tempo)
        XCTAssertEqual(workout.distanceKm, 7, accuracy: 0.001) // 2 + 3 + 2
        XCTAssertEqual(workout.paceBand, paces.threshold, "pace comes from app fitness, never the payload")
        XCTAssertEqual(workout.details, "2 km warm-up · 3 km at T pace · 2 km cool-down")
        XCTAssertEqual(workout.structure.flatMap(\.steps).map(\.role), [.warmUp, .work, .coolDown])
        XCTAssertEqual(workout.structure.flatMap(\.steps)[1].paceBand, paces.threshold)
        XCTAssertTrue(workout.manuallyOverridden)
        XCTAssertEqual(workout.status, .planned)
        XCTAssertNotNil(workout.plan)
        XCTAssertEqual(try weekTarget(0, in: context), targetBefore + 7, accuracy: 0.001)
    }

    func testCreatesThresholdWithAppDerivedPaceAndCanonicalStructure() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let paces = try XCTUnwrap(fitnessPaces(in: context))

        let result = try create(.threshold(workKm: 4), on: freeDay, in: context)

        let workout = try XCTUnwrap(workout(on: freeDay, in: context))
        XCTAssertEqual(result.summary, "Created threshold on 2026-01-09")
        XCTAssertEqual(workout.kind, .threshold)
        XCTAssertEqual(workout.distanceKm, 8, accuracy: 0.001)
        XCTAssertEqual(workout.paceBand, paces.threshold)
        XCTAssertEqual(workout.details, "2 km warm-up · 4 km at T pace · 2 km cool-down")
        XCTAssertEqual(workout.structure.flatMap(\.steps).map(\.role), [.warmUp, .work, .coolDown])
    }


    func testCreatesIntervalsWithRepeatedWorkAndDurationRecovery() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let paces = try XCTUnwrap(fitnessPaces(in: context))

        _ = try create(.intervals(reps: 3), on: freeDay, in: context)

        let workout = try XCTUnwrap(workout(on: freeDay, in: context))
        let repeatGroup = try XCTUnwrap(workout.structure.first { $0.repeatCount > 1 })
        XCTAssertEqual(workout.kind, .intervals)
        XCTAssertEqual(workout.distanceKm, 7, accuracy: 0.001) // 2 + 3×1 + 2; the jog adds time, not distance
        XCTAssertEqual(repeatGroup.repeatCount, 3)
        XCTAssertEqual(repeatGroup.steps[0].paceBand, paces.interval)
        XCTAssertEqual(repeatGroup.steps[1].durationSeconds, 150)
        XCTAssertEqual(repeatGroup.steps[1].paceBand, paces.easy, "recovery resolves through the app's easy pace")
        XCTAssertEqual(workout.details, "2 km warm-up · 3 × 1 km at I pace (2–3 min jog) · 2 km cool-down")
    }

    func testCreatesEasyAndLongWithEasyPace() throws {
        for payload in [CreatePayload.easy(km: 5), .long(km: 10)] {
            let container = try seededContainer()
            let context = container.mainContext
            let paces = try XCTUnwrap(fitnessPaces(in: context))

            _ = try create(payload, on: freeDay, in: context)

            let workout = try XCTUnwrap(workout(on: freeDay, in: context))
            XCTAssertEqual(workout.paceBand, paces.easy)
            XCTAssertEqual(workout.structure.flatMap(\.steps).map(\.role), [.work])
        }
    }

    func testMultipleValidCreatesCommitTogether() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        let targetBefore = try weekTarget(0, in: context)

        // Both creates must fit under the week's volume cap, or the batch is
        // (correctly) rejected as a whole.
        let result = try CoachTools.apply(
            proposal: .init(changes: [
                change(.tempo(workKm: 3), on: freeDay),
                change(.easy(km: 3), on: saturday)
            ]),
            in: context, today: today, calendar: calendar
        )

        XCTAssertEqual(result.summary, "Created tempo on 2026-01-09; Created easy on 2026-01-10")
        XCTAssertNotNil(try workout(on: freeDay, in: context))
        XCTAssertNotNil(try workout(on: saturday, in: context))
        XCTAssertEqual(try weekTarget(0, in: context), targetBefore + 10, accuracy: 0.001)
    }

    func testCreateIgnoresUnrelatedExistingFutureVolumeViolation() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let plan = try XCTUnwrap(PlanStore.activePlan(in: context))
        var targets = plan.weekTargetVolumesKm
        targets[2] = 100
        plan.weekTargetVolumesKm = targets
        try context.save()

        let result = try create(.easy(km: 5), on: freeDay, in: context)

        XCTAssertEqual(result.summary, "Created easy on 2026-01-09")
        XCTAssertNotNil(try workout(on: freeDay, in: context))
        XCTAssertEqual(try weekTarget(2, in: context), 100, accuracy: 0.001)
    }

    func testMoveCannotWorsenExistingDuplicateDay() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let plan = try XCTUnwrap(PlanStore.activePlan(in: context))
        let occupied = try XCTUnwrap(try workout(on: occupiedDay, in: context))
        let kind = try XCTUnwrap(occupied.kind)
        let phase = try XCTUnwrap(TrainingPhase(rawValue: occupied.phaseRaw))
        let duplicate = PlannedWorkout(
            spec: .init(
                date: occupied.date, kind: kind, distanceKm: occupied.distanceKm,
                paceBand: occupied.paceBand, details: occupied.details, structure: occupied.structure
            ),
            weekIndex: occupied.weekIndex,
            phase: phase
        )
        duplicate.plan = plan
        context.insert(duplicate)
        try context.save()

        let source = try XCTUnwrap(try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            $0.weekIndex == occupied.weekIndex
                && $0.kind != .race
                && !calendar.isDate($0.date, inSameDayAs: occupiedDay)
        })
        XCTAssertThrowsError(try CoachTools.apply(
            proposal: .init(changes: [.init(
                date: CoachContextBuilder.day(source.date, calendar: calendar),
                action: .move,
                detail: CoachContextBuilder.day(occupiedDay, calendar: calendar)
            )]),
            in: context,
            today: today,
            calendar: calendar
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("Target date already has a workout"))
        }
    }

    // MARK: - Rejection matrix (nothing is ever written)

    func testRejectionsWriteNothing() throws {
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        let cases: [(String, [PlanAdjustmentProposal.Change])] = [
            ("past date", [change(.easy(km: 5), on: PlanEngineTestSupport.date(2026, 1, 4, hour: 0))]),
            ("race day", [change(.easy(km: 5), on: raceDay)]),
            ("after race", [change(.easy(km: 5), on: PlanEngineTestSupport.date(2026, 1, 26, hour: 0))]),
            ("occupied day", [change(.easy(km: 5), on: occupiedDay)]),
            ("outside plan", [change(.easy(km: 5), on: PlanEngineTestSupport.date(2026, 3, 6, hour: 0))]),
            ("hard sessions too close", [change(.tempo(workKm: 3), on: saturday)]),
            ("duplicate date in batch", [change(.easy(km: 5), on: freeDay), change(.easy(km: 4), on: freeDay)]),
            ("race kind", [change(.raw(kind: "race"), on: freeDay)]),
            ("both targets on one step", [change(.malformedStep, on: freeDay)]),
            ("unknown pace zone", [change(.raw(kind: "easy", zone: "sprint"), on: freeDay)]),
            ("create carries a detail date", [.init(date: "2026-01-09", action: .create, detail: "2026-01-10", workout: CreatePayload.easy(km: 5).workout)]),
            ("create without a workout", [.init(date: "2026-01-09", action: .create, detail: nil, workout: nil)]),
            ("excessive distance", [change(.easy(km: 500), on: freeDay)]),
            ("weekly volume over cap", [change(.easy(km: 12), on: freeDay)])
        ]

        for (name, changes) in cases {
            let container = try seededContainer()
            let context = container.mainContext
            let before = try snapshot(in: context)
            let targetsBefore = try targets(in: context)

            XCTAssertThrowsError(
                try CoachTools.apply(proposal: .init(changes: changes), in: context, today: today, calendar: calendar),
                "\(name) must be rejected"
            )
            XCTAssertEqual(try snapshot(in: context), before, "\(name) must not change any workout")
            XCTAssertEqual(try targets(in: context), targetsBefore, "\(name) must not change week targets")
        }
    }

    func testOverridableLoadRisksStageWarningsThenRequireAcknowledgement() throws {
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        let cases: [(name: String, changes: [PlanAdjustmentProposal.Change], kind: PlanValidator.Issue.Kind)] = [
            ("weekly volume", [change(.easy(km: 12), on: freeDay)], .weeklyVolumeTooHigh),
            ("quality spacing", [change(.tempo(workKm: 3), on: saturday)], .qualityTooClose)
        ]

        for (name, changes, kind) in cases {
            let container = try seededContainer()
            let context = container.mainContext
            let proposal = PlanAdjustmentProposal(changes: changes)
            let before = try snapshot(in: context)
            let targetsBefore = try targets(in: context)

            let preflight = try CoachTools.validateForConfirmation(
                proposal: proposal,
                in: context,
                today: today,
                calendar: calendar
            )
            XCTAssertEqual(preflight.warnings.map(\.kind), [kind], name)
            XCTAssertFalse(preflight.summary.isEmpty, name)
            // The warning is shown to the user verbatim; dates must read as a
            // local calendar day, never a raw Date description with a UTC offset.
            for warning in preflight.warnings {
                XCTAssertFalse(warning.message.contains("+0000"), "\(name): \(warning.message)")
                XCTAssertNil(warning.message.range(of: #"\d{2}:\d{2}:\d{2}"#, options: .regularExpression), "\(name): \(warning.message)")
            }

            XCTAssertThrowsError(
                try CoachTools.apply(
                    proposal: proposal,
                    in: context,
                    today: today,
                    calendar: calendar
                ),
                "\(name) must require acknowledgement"
            )
            XCTAssertEqual(try snapshot(in: context), before, "\(name) must not write without acknowledgement")
            XCTAssertEqual(try targets(in: context), targetsBefore, "\(name) must not alter targets without acknowledgement")

            let applied = try CoachTools.apply(
                proposal: proposal,
                in: context,
                today: today,
                calendar: calendar,
                acknowledging: preflight.warnings
            )
            XCTAssertFalse(applied.summary.isEmpty, name)
            XCTAssertNotEqual(try snapshot(in: context), before, "\(name) must persist after acknowledgement")
        }
    }

    func testStructuralCreateViolationsRejectPreflightAndApply() throws {
        let cases: [(name: String, changes: [PlanAdjustmentProposal.Change])] = [
            ("past", [change(.easy(km: 5), on: PlanEngineTestSupport.date(2026, 1, 4, hour: 0))]),
            ("race", [change(.easy(km: 5), on: raceDay)]),
            ("occupied", [change(.easy(km: 5), on: occupiedDay)])
        ]

        for (name, changes) in cases {
            let container = try seededContainer()
            let context = container.mainContext
            let proposal = PlanAdjustmentProposal(changes: changes)
            let before = try snapshot(in: context)
            let targetsBefore = try targets(in: context)

            XCTAssertThrowsError(
                try CoachTools.validateForConfirmation(
                    proposal: proposal,
                    in: context,
                    today: today,
                    calendar: calendar
                ),
                "\(name) must not stage"
            )
            XCTAssertEqual(try snapshot(in: context), before, "\(name) preflight must not write")
            XCTAssertEqual(try targets(in: context), targetsBefore, "\(name) preflight must not alter targets")

            XCTAssertThrowsError(
                try CoachTools.apply(
                    proposal: proposal,
                    in: context,
                    today: today,
                    calendar: calendar
                ),
                "\(name) must not apply"
            )
            XCTAssertEqual(try snapshot(in: context), before, "\(name) apply must not write")
            XCTAssertEqual(try targets(in: context), targetsBefore, "\(name) apply must not alter targets")
        }
    }

    func testExplicitCreateCanTargetNormalRestDay() throws {
        let container = try seededContainer(availableDays: [.monday, .tuesday, .wednesday, .thursday, .friday, .sunday])
        let context = container.mainContext
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        let result = try create(.easy(km: 5), on: saturday, in: context)
        XCTAssertEqual(result.summary, "Created easy on 2026-01-10")
        let workout = try XCTUnwrap(try workout(on: saturday, in: context))
        XCTAssertEqual(workout.kind, .easy)
        XCTAssertTrue(workout.manuallyOverridden)
    }

    /// Quality work without fitness is created unpaced and the runner is told,
    /// never refused. The note is informational, so nothing needs acknowledging.
    func testQualityCreateWithoutFitnessBuildsUnpacedWithNote() throws {
        let container = try seededContainer(withHistory: false)
        let context = container.mainContext

        let candidate = try CoachPlanCandidateEngine.prepare(
            proposal: .init(changes: [change(.tempo(workKm: 3), on: freeDay)]),
            in: context, today: today, calendar: calendar, language: .en
        )
        XCTAssertEqual(candidate.notes.map(\.kind), [.paceUnavailable])
        XCTAssertTrue(candidate.loadRisks.isEmpty, "a missing pace band is a fact, not a load risk")
        XCTAssertEqual(
            candidate.notes.first?.message,
            "Not enough recent runs to set a tempo pace. Run this by effort; TrainOrRest fills paces in once it has 6 runs in 28 days."
        )

        try create(.tempo(workKm: 3), on: freeDay, in: context)
        let workout = try XCTUnwrap(workout(on: freeDay, in: context))
        XCTAssertEqual(workout.kind, .tempo)
        XCTAssertNil(workout.paceBand)
        XCTAssertNil(workout.structure.flatMap(\.steps).first { $0.role == .work }?.paceBand)
        XCTAssertEqual(workout.details, "2 km warm-up · 3 km by effort · 2 km cool-down")
    }

    /// One bad create in a batch rolls the whole batch back, including targets.
    func testInvalidCreateInBatchRollsBackEverything() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        let before = try snapshot(in: context)
        let targetsBefore = try targets(in: context)

        XCTAssertThrowsError(try CoachTools.apply(
            proposal: .init(changes: [
                change(.tempo(workKm: 3), on: freeDay),      // valid on its own
                change(.tempo(workKm: 3), on: saturday)      // too close to Sunday's long run
            ]),
            in: context, today: today, calendar: calendar
        ))

        XCTAssertNil(try workout(on: freeDay, in: context), "the valid create must not survive alone")
        XCTAssertEqual(try snapshot(in: context), before)
        XCTAssertEqual(try targets(in: context), targetsBefore)
    }

    func testExistingWorkoutsKeepIdentityAndStateAfterSuccessfulCreate() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let before = try snapshot(in: context)

        _ = try create(.easy(km: 5), on: freeDay, in: context)

        let after = try snapshot(in: context).filter { row in before.contains { $0.uuid == row.uuid } }
        XCTAssertEqual(after, before, "creating a workout must not rewrite any existing row")
    }

    // MARK: - Payloads

    private enum CreatePayload {
        case easy(km: Double), long(km: Double), tempo(workKm: Double), threshold(workKm: Double), intervals(reps: Int)
        case malformedStep
        case raw(kind: String, zone: String = "easy")

        var workout: PlanAdjustmentProposal.CreateWorkout {
            typealias Step = PlanAdjustmentProposal.CreateWorkout.Step
            func distance(_ role: String, _ km: Double, _ zone: String) -> Step {
                Step(role: role, targetType: "distance_km", targetValue: km, paceZone: zone)
            }
            switch self {
            case .easy(let km):
                return .init(kind: "easy", blocks: [.init(repeatCount: 1, steps: [distance("work", km, "easy")])])
            case .long(let km):
                return .init(kind: "long", blocks: [.init(repeatCount: 1, steps: [distance("work", km, "easy")])])
            case .tempo(let workKm):
                return .init(kind: "tempo", blocks: [.init(repeatCount: 1, steps: [
                    distance("warm_up", 2, "easy"),
                    distance("work", workKm, "threshold"),
                    distance("cool_down", 2, "easy")
                ])])
            case .threshold(let workKm):
                return .init(kind: "threshold", blocks: [.init(repeatCount: 1, steps: [
                    distance("warm_up", 2, "easy"),
                    distance("work", workKm, "threshold"),
                    distance("cool_down", 2, "easy")
                ])])
            case .intervals(let reps):
                return .init(kind: "intervals", blocks: [
                    .init(repeatCount: 1, steps: [distance("warm_up", 2, "easy")]),
                    .init(repeatCount: reps, steps: [
                        distance("work", 1, "interval"),
                        Step(role: "recovery", targetType: "duration_seconds", targetValue: 150, paceZone: "easy")
                    ]),
                    .init(repeatCount: 1, steps: [distance("cool_down", 2, "easy")])
                ])
            case .malformedStep:
                return .init(kind: "easy", blocks: [.init(repeatCount: 1, steps: [
                    Step(role: "work", targetType: "elevation_m", targetValue: 5, paceZone: "easy")
                ])])
            case .raw(let kind, let zone):
                return .init(kind: kind, blocks: [.init(repeatCount: 1, steps: [distance("work", 5, zone)])])
            }
        }
    }

    private func change(_ payload: CreatePayload, on date: Date) -> PlanAdjustmentProposal.Change {
        .init(
            date: CoachContextBuilder.day(date, calendar: calendar),
            action: .create,
            detail: nil,
            workout: payload.workout
        )
    }

    @discardableResult
    private func create(_ payload: CreatePayload, on date: Date, in context: ModelContext) throws -> AppliedAdjustment {
        try CoachTools.apply(
            proposal: .init(changes: [change(payload, on: date)]),
            in: context, today: today, calendar: calendar
        )
    }

    // MARK: - Fixtures

    private struct RowSnapshot: Equatable {
        var uuid: UUID
        var date: Date
        var kind: String
        var distanceKm: Double
        var status: String
        var manuallyOverridden: Bool
        var matched: UUID?
    }

    private func snapshot(in context: ModelContext) throws -> [RowSnapshot] {
        try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)])).map {
            RowSnapshot(
                uuid: $0.uuid, date: $0.date, kind: $0.kindRaw, distanceKm: $0.distanceKm,
                status: $0.statusRaw, manuallyOverridden: $0.manuallyOverridden,
                matched: $0.matchedActivityUUID
            )
        }
    }

    private func targets(in context: ModelContext) throws -> [Double] {
        try XCTUnwrap(PlanStore.activePlan(in: context)).weekTargetVolumesKm
    }

    private func weekTarget(_ index: Int, in context: ModelContext) throws -> Double {
        try targets(in: context)[index]
    }

    private func workout(on date: Date, in context: ModelContext) throws -> PlannedWorkout? {
        try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    private func fitnessPaces(in context: ModelContext) throws -> TrainingPaces? {
        try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
            .map { VDOTTable.trainingPaces(vdot: $0.vdot) }
    }

    /// Returns the container: the caller must retain it, or SwiftData traps on
    /// a context whose container has been deallocated.
    private func seededContainer(
        availableDays: Set<Weekday> = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
        withHistory: Bool = true
    ) throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self, CoachRequestSnapshot.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        if withHistory {
            // 11 runs of 12 km spanning 30 days: enough qualifying runs and span
            // for a real FitnessProfile (~30 km/week).
            for step in 0..<11 {
                let offset = -(1 + step * 3)
                context.insert(CompletedActivity(
                    hkUUID: UUID(),
                    date: calendar.date(byAdding: .day, value: offset, to: today)!,
                    distanceMeters: 12_000,
                    durationSeconds: 3_960,
                    avgHeartRate: 145,
                    maxHeartRate: 168,
                    avgPaceSecondsPerKm: 330,
                    sourceName: "Garmin"
                ))
            }
            try context.save()
        }

        let goal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: raceDay,
            availableDays: availableDays,
            longRunDay: .sunday
        )
        // Generate the plan from the same fitness the coach path will recompute,
        // so cap and ramp checks agree with the stored plan.
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
            ?? FitnessProfile(vdot: 44, weeklyVolumeKm: 30, volumeTrend: 0, longestRecentRunKm: 12)
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)
        return container
    }
}
