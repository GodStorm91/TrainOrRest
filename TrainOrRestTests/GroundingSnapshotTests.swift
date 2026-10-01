import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class GroundingSnapshotTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5, hour: 6)
    private let readinessComputedAt = PlanEngineTestSupport.date(2026, 1, 5, hour: 6)
        .addingTimeInterval(12 * 60)
    private let planGeneratedAt = PlanEngineTestSupport.date(2026, 1, 5, hour: 6)

    override func setUp() {
        super.setUp()
        NSTimeZone.default = calendar.timeZone
    }

    func testSummaryIncludesSelectedEvidenceAndContentRevision() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = try seedFixedData(in: context)
        let evidence = EvidenceSelection(workout: .planned(workout.uuid), hasPhoto: true)

        let snapshot = try CoachGrounding.snapshot(
            evidence: evidence,
            in: context,
            today: readinessComputedAt,
            calendar: calendar
        )

        XCTAssertTrue(snapshot.summary.contains("Readiness: rest"))
        XCTAssertTrue(snapshot.summary.contains("Plan: 2026-01-05...2026-01-11"))
        XCTAssertTrue(snapshot.summary.contains("Workout: Tue planned Tempo, 8.0 km"))
        XCTAssertTrue(snapshot.summary.contains("Photo: attached"))
        XCTAssertTrue(snapshot.summary.contains("plan \(snapshot.planVersion)"))
        XCTAssertEqual(snapshot.planVersion.count, 64)
    }

    func testPlanVersionChangesWithStoredPlanContent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = try seedFixedData(in: context)

        let before = try CoachGrounding.snapshot(
            evidence: EvidenceSelection(),
            in: context,
            today: readinessComputedAt,
            calendar: calendar
        )
        workout.distanceKm += 1
        try context.save()
        let after = try CoachGrounding.snapshot(
            evidence: EvidenceSelection(),
            in: context,
            today: readinessComputedAt,
            calendar: calendar
        )

        XCTAssertEqual(before.readinessVersion, "2026-01-04T21:12:00Z")
        XCTAssertEqual(before.planVersion.count, 64)
        XCTAssertNotEqual(after.planVersion, before.planVersion)
    }

    func testVersionsAreNoneWhenReadinessAndPlanAreAbsent() throws {
        let container = try makeContainer()

        let snapshot = try CoachGrounding.snapshot(
            evidence: EvidenceSelection(),
            in: container.mainContext,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.readinessVersion, "none")
        XCTAssertEqual(snapshot.planVersion, "none")
        XCTAssertTrue(snapshot.summary.contains("Readiness: not computed."))
        XCTAssertTrue(snapshot.summary.contains("Versions: readiness none; plan none."))
    }

    func testFootnoteLineReflectsEvidenceSet() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = try seedFixedData(in: context)
        let evidence = EvidenceSelection(
            readinessSnapshot: false,
            weekPlan: true,
            workout: .planned(workout.uuid),
            hasPhoto: true
        )

        let snapshot = try CoachGrounding.snapshot(
            evidence: evidence,
            in: context,
            today: readinessComputedAt,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.footnoteLine, "Based on 6:12 AM · This week · Tue workout · Photo")
    }

    func testMessageFootnoteAndSummaryMirrorReviewedSnapshot() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = try seedFixedData(in: context)
        let evidence = EvidenceSelection(workout: .planned(workout.uuid), hasPhoto: true)
        let snapshot = try CoachGrounding.snapshot(
            evidence: evidence,
            in: context,
            today: readinessComputedAt,
            calendar: calendar
        )
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("Grounded reply.")], stopReason: "end_turn")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.readinessComputedAt })

        await store.submitTestTurn(text: "Should I train?",
        model: "claude-test",
        attachments: [.health, .plannedWorkout(workout.uuid), .image(CoachImageAttachment(
            data: Data([1, 2, 3]),
            mediaType: "image/jpeg",
            filename: "test.jpg"
        ))],
        evidence: evidence,
        groundingSnapshot: snapshot,
        apiKey: "test-key",
        in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        let assistant = try XCTUnwrap(messages.first { $0.role == .assistant })
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.groundingSummary, snapshot.summary)
        XCTAssertEqual(assistant.groundingFootnote, snapshot.footnoteLine)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self, CoachRequestSnapshot.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func seedFixedData(in context: ModelContext) throws -> PlannedWorkout {
        let readiness = DailyReadiness(
            date: calendar.startOfDay(for: readinessComputedAt),
            assessment: ReadinessAssessment(
                verdict: .rest,
                score: 42,
                reasons: ["Sleep below recent norm", "Load ramp high"],
                ruleIDs: [.shortSleep, .loadRamp],
                baselineDayCount: 28,
                snapshot: .init(
                    hrvMean7: 45,
                    hrvMean28: 52,
                    rhrMean7: 54,
                    rhrMean28: 49,
                    sleepLastNight: 5.5,
                    sleepMean14: 7.2,
                    acuteChronicRatio: 1.4
                )
            ),
            computedAt: readinessComputedAt
        )
        context.insert(readiness)

        let monday = calendar.startOfDay(for: today)
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let spec = TrainingPlanSpec(
            goal: GoalSpec(
                distance: .halfMarathon,
                targetTimeSeconds: 105 * 60,
                raceDate: PlanEngineTestSupport.date(2026, 4, 19),
                availableDays: [.monday, .tuesday],
                longRunDay: .tuesday
            ),
            anchorDate: monday,
            weeks: [
                WeekPlan(
                    startDate: monday,
                    index: 0,
                    phase: .base,
                    isDownWeek: false,
                    isPartial: false,
                    targetVolumeKm: 14,
                    workouts: [
                        PlannedWorkoutSpec(
                            date: monday,
                            kind: .easy,
                            distanceKm: 6,
                            paceBand: nil,
                            details: "Easy"
                        ),
                        PlannedWorkoutSpec(
                            date: tuesday,
                            kind: .tempo,
                            distanceKm: 8,
                            paceBand: nil,
                            details: "Tempo"
                        )
                    ]
                )
            ]
        )
        let plan = TrainingPlan(spec: spec, generatedAt: planGeneratedAt)
        context.insert(plan)
        var tuesdayWorkout: PlannedWorkout?
        for workoutSpec in spec.weeks.flatMap(\.workouts) {
            let workout = PlannedWorkout(spec: workoutSpec, weekIndex: 0, phase: .base)
            workout.plan = plan
            context.insert(workout)
            if calendar.isDate(workout.date, inSameDayAs: tuesday) {
                tuesdayWorkout = workout
            }
        }
        try context.save()
        return try XCTUnwrap(tuesdayWorkout)
    }
}

@MainActor
private final class MockClaudeClient: ClaudeServicing {
    private var responses: [ClaudeResponse]

    init(responses: [ClaudeResponse]) {
        self.responses = responses
    }

    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        responses.removeFirst()
    }
}
