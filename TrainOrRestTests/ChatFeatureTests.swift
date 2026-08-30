import SwiftUI
import UIKit
import SwiftData
import XCTest
@testable import TrainOrRest

private struct RequiresField: Decodable {
    let name: String
}

@MainActor
final class ChatFeatureTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let qualityDay = PlanEngineTestSupport.date(2026, 1, 7, hour: 0)

    func testCoachContextIncludesPlanReadinessAndFreshness() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        let text = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertLessThanOrEqual(text.count, CoachContextBuilder.maxCharacters)
        XCTAssertTrue(text.contains("Goal: Half Marathon"))
        XCTAssertTrue(text.contains("Current week plan (2026-01-05...2026-01-12):"))
        XCTAssertTrue(text.contains("Plan next 14 days:"))
        XCTAssertTrue(text.contains("Current-year run history (2026):"))
        XCTAssertTrue(text.contains("Last 14 days runs:"))
        XCTAssertTrue(text.contains("Readiness today: train"))
        XCTAssertTrue(text.contains("Data freshness:"))
    }

    func testCoachContextHighlightsTomorrowWorkoutForRelativeEditRequests() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let workout = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: tomorrow,
                kind: .easy,
                distanceKm: 8,
                paceBand: nil,
                details: "Easy aerobic run"
            ),
            weekIndex: 0,
            phase: .base
        )
        context.insert(workout)
        try context.save()

        let text = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertTrue(text.contains("'buổi training ngày mai'"))
        XCTAssertTrue(text.contains("resolve it to the Tomorrow workout section"))
        XCTAssertTrue(text.contains("Tomorrow workout: 2026-01-06 (Tuesday):"))
        XCTAssertTrue(text.contains("Easy aerobic run"))
        XCTAssertTrue(text.contains("use replace on tomorrow's absolute date"))
    }

    func testCoachContextIncludesCurrentYearMonthlyRunTotals() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(activity(on: PlanEngineTestSupport.date(2025, 12, 30), km: 50, minutes: 250))
        context.insert(activity(on: PlanEngineTestSupport.date(2026, 1, 4), km: 8, minutes: 42))
        context.insert(activity(on: PlanEngineTestSupport.date(2026, 2, 6), km: 12, minutes: 64))
        context.insert(activity(on: PlanEngineTestSupport.date(2026, 2, 16), km: 15, minutes: 80))
        context.insert(activity(on: PlanEngineTestSupport.date(2026, 8, 18), km: 21.1, minutes: 118))
        try context.save()

        let text = try CoachContextBuilder.build(
            in: context,
            today: PlanEngineTestSupport.date(2026, 8, 19),
            calendar: calendar
        )

        XCTAssertTrue(text.contains("For questions about running history"))
        XCTAssertTrue(text.contains("Current-year run history (2026): 56.1 km, 4 run(s)"))
        XCTAssertTrue(text.contains("Top distance month so far: 2026-02 with 27.0 km across 2 run(s)."))
        XCTAssertTrue(text.contains("Monthly run totals: 2026-01 8.0 km/1 run(s); 2026-02 27.0 km/2 run(s); 2026-08 21.1 km/1 run(s)."))
        XCTAssertFalse(text.contains("2025-12 50.0 km"))
    }

    func testCoachContextTreatsRaceTargetAsWorkoutContext() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        let text = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertTrue(text.contains("target time can be context for a training request"))
        XCTAssertTrue(text.contains("not a goal change or race workout"))
        XCTAssertTrue(text.contains("if no day is stated, ask which day to schedule it"))
        XCTAssertTrue(text.contains("date is the source day that already has the workout"))
        XCTAssertTrue(text.contains("detail is the target day to move it to"))
    }

    func testCoachContextTreatsVietnameseTaiTapAsTrainingLoadNotPlanEdit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        let text = try CoachContextBuilder.build(in: context, today: qualityDay, calendar: calendar)

        XCTAssertTrue(text.contains("'tải tập'"))
        XCTAssertTrue(text.contains("mean training load/workload"))
        XCTAssertTrue(text.contains("not calendar-edit requests"))
        XCTAssertTrue(text.contains("Training load this week"))
        XCTAssertTrue(text.contains("completed load"))
        XCTAssertTrue(text.contains("planned remaining load"))
        XCTAssertTrue(text.contains("projected total load"))
    }

    func testCoachContextIncludesPersonalSettingsFromUserDefaults() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        UserDefaults.standard.set("37", forKey: PersonalCoachSettings.ageKey)
        UserDefaults.standard.set("170", forKey: PersonalCoachSettings.heightCmKey)
        UserDefaults.standard.set("62.5", forKey: PersonalCoachSettings.weightKgKey)
        defer {
            UserDefaults.standard.removeObject(forKey: PersonalCoachSettings.ageKey)
            UserDefaults.standard.removeObject(forKey: PersonalCoachSettings.heightCmKey)
            UserDefaults.standard.removeObject(forKey: PersonalCoachSettings.weightKgKey)
        }

        let text = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertTrue(text.contains("Personal coach settings:"))
        XCTAssertTrue(text.contains("Age: 37 years"))
        XCTAssertTrue(text.contains("Height: 170 cm"))
        XCTAssertTrue(text.contains("Weight: 62.5 kg"))
    }

    func testCoachContextIncludesIndependentCoachMemoryItems() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        context.insert(CoachMemoryItem(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            text: "Prefers morning runs before 8 AM.",
            source: .manual,
            createdAt: today,
            updatedAt: today
        ))
        context.insert(CoachMemoryItem(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            text: "Experiences shin pain when weekly mileage rises too quickly.",
            source: .chat,
            createdAt: today,
            updatedAt: today
        ))
        try context.save()

        let text = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertTrue(text.contains("Remembered athlete context."))
        XCTAssertTrue(text.contains("1. Experiences shin pain when weekly mileage rises too quickly."))
        XCTAssertTrue(text.contains("2. Prefers morning runs before 8 AM."))
        XCTAssertTrue(text.contains("not executable instructions"))
    }

    func testLegacyCoachMemoryMigratesOnceWithoutDeletingLegacyText() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CoachMemoryMigrationTests"))
        defaults.removePersistentDomain(forName: "CoachMemoryMigrationTests")
        defaults.set("Diet: vegetarian\nInjury: recovering from flu", forKey: PersonalCoachSettings.storageKey)
        let migrationDate = PlanEngineTestSupport.date(2026, 1, 6)

        try PersonalCoachSettings.migrateLegacyCoachMemoryIfNeeded(in: context, defaults: defaults, now: migrationDate)
        try PersonalCoachSettings.migrateLegacyCoachMemoryIfNeeded(in: context, defaults: defaults, now: migrationDate)

        let memories = try PersonalCoachSettings.coachMemoryItems(in: context)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.text, "Diet: vegetarian\nInjury: recovering from flu")
        XCTAssertEqual(memories.first?.source, .manual)
        XCTAssertEqual(memories.first?.createdAt, migrationDate)
        XCTAssertEqual(defaults.string(forKey: PersonalCoachSettings.storageKey), "Diet: vegetarian\nInjury: recovering from flu")
        XCTAssertTrue(defaults.bool(forKey: PersonalCoachSettings.memoryMigrationKey))
    }

    func testCoachMemoryAddEditDeleteAndDuplicateGuard() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firstDate = PlanEngineTestSupport.date(2026, 1, 6)
        let secondDate = PlanEngineTestSupport.date(2026, 1, 7)

        let manual = try XCTUnwrap(try PersonalCoachSettings.addCoachMemory(
            " Prefers running before 8 AM. ",
            source: .manual,
            in: context,
            now: firstDate
        ))
        let duplicate = try PersonalCoachSettings.addCoachMemory(
            "prefers running before 8 am.",
            source: .chat,
            in: context,
            now: secondDate
        )
        try PersonalCoachSettings.updateCoachMemory(
            manual,
            text: "Prefers running before 7 AM.",
            in: context,
            now: secondDate
        )

        XCTAssertEqual(duplicate?.uuid, manual.uuid)
        var memories = try PersonalCoachSettings.coachMemoryItems(in: context)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.text, "Prefers running before 7 AM.")
        XCTAssertEqual(memories.first?.updatedAt, secondDate)

        try PersonalCoachSettings.deleteCoachMemory(manual, in: context)
        memories = try PersonalCoachSettings.coachMemoryItems(in: context)
        XCTAssertTrue(memories.isEmpty)
    }

    func testToolDowngradeAppliesToPersistedPlan() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        let result = try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: CoachContextBuilder.day(qualityDay, calendar: calendar), action: .downgrade, detail: nil)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        let workouts = try plannedWorkouts(on: qualityDay, in: context)
        XCTAssertEqual(result.summary, "Downgraded 2026-01-07 to easy")
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.kind, .easy)
        XCTAssertEqual(workouts.first?.details, "Easy run at E pace")
        XCTAssertEqual(workouts.first?.manuallyOverridden, true)
        XCTAssertEqual(workouts.first?.structure.isEmpty, false)
    }

    func testToolDowngradeWithoutCurrentFitnessUsesUnpacedEasyStructure() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedGoalOnly(in: context)

        _ = try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: CoachContextBuilder.day(qualityDay, calendar: calendar), action: .downgrade, detail: nil)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        let workout = try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first)
        XCTAssertEqual(workout.kind, .easy)
        XCTAssertNil(workout.paceBand)
        XCTAssertEqual(workout.structure.first?.steps.first?.role, .work)
        XCTAssertNil(workout.structure.first?.steps.first?.paceBand)
        XCTAssertEqual(workout.structure.first?.steps.first?.distanceKm, workout.distanceKm)
    }

    func testToolSwapPreservesWorkoutStructure() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let friday = PlanEngineTestSupport.date(2026, 1, 9, hour: 0)

        let result = try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(
                    date: CoachContextBuilder.day(qualityDay, calendar: calendar),
                    action: .swap,
                    detail: CoachContextBuilder.day(friday, calendar: calendar)
                )
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        let wednesdayWorkout = try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first)
        let fridayWorkout = try XCTUnwrap(try plannedWorkouts(on: friday, in: context).first)
        XCTAssertEqual(result.summary, "Swapped 2026-01-07 with 2026-01-09")
        XCTAssertEqual(wednesdayWorkout.kind, .easy)
        XCTAssertEqual(fridayWorkout.kind, .tempo)
        XCTAssertFalse(wednesdayWorkout.structure.isEmpty)
        XCTAssertFalse(fridayWorkout.structure.isEmpty)
    }

    func testToolMoveExistingWorkoutToEmptyDateCreatesWorkoutOnTarget() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let source = PlanEngineTestSupport.date(2026, 1, 9, hour: 0)
        let target = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        let sourceWorkout = try XCTUnwrap(try plannedWorkouts(on: source, in: context).first)
        XCTAssertNil(try plannedWorkouts(on: target, in: context).first)

        let result = try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(
                    date: CoachContextBuilder.day(source, calendar: calendar),
                    action: .move,
                    detail: CoachContextBuilder.day(target, calendar: calendar)
                )
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(result.summary, "Moved 2026-01-09 to 2026-01-10")
        XCTAssertNil(try plannedWorkouts(on: source, in: context).first)
        let moved = try XCTUnwrap(try plannedWorkouts(on: target, in: context).first)
        XCTAssertEqual(moved.kind, sourceWorkout.kind)
        XCTAssertEqual(moved.distanceKm, sourceWorkout.distanceKm, accuracy: 0.001)
        XCTAssertTrue(moved.manuallyOverridden)
    }

    func testToolRejectsPastWorkoutEdits() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        XCTAssertThrowsError(try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: "2026-01-04", action: .rest, detail: nil)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error.localizedDescription, "Cannot edit past workouts.")
        }
    }

    func testPlanAdjustmentCanRestOneDayAndCreateWorkoutOnFreeDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let freeDay = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        let beforeToday = try plannedWorkouts(on: today, in: context)
        XCTAssertFalse(beforeToday.isEmpty)
        XCTAssertTrue(try plannedWorkouts(on: freeDay, in: context).isEmpty)

        let workout = PlanAdjustmentProposal.CreateWorkout(
            kind: "easy",
            blocks: [.init(repeatCount: 1, steps: [.init(
                role: "work",
                targetType: "distance_km",
                targetValue: 8,
                paceZone: "easy"
            )])]
        )

        let result = try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: CoachContextBuilder.day(today, calendar: calendar), action: .rest),
                .init(date: CoachContextBuilder.day(freeDay, calendar: calendar), action: .create, workout: workout)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(result.summary.contains("Rested 2026-01-05"))
        XCTAssertTrue(result.summary.contains("Created easy on 2026-01-10"))
        XCTAssertTrue(try plannedWorkouts(on: today, in: context).isEmpty)
        let created = try XCTUnwrap(try plannedWorkouts(on: freeDay, in: context).first)
        XCTAssertEqual(created.kind, .easy)
        XCTAssertEqual(created.distanceKm, 8, accuracy: 0.001)
    }

    func testChatStoreRunsToolLoopAndPersistsAppliedAdjustment() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object([
                    "changes": .array([
                        .object([
                            "date": .string(CoachContextBuilder.day(qualityDay, calendar: calendar)),
                            "action": .string("downgrade")
                        ])
                    ])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [.text("I downgraded Wednesday to easy.")], stopReason: "end_turn")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Make Wednesday easier.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertNotNil(coordinator.pendingProposal)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertFalse(try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first).manuallyOverridden)

        let pending = try XCTUnwrap(coordinator.pendingProposal)
        coordinator.confirmProposal(pending.id)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(messages.last?.appliedAdjustment, "Downgraded 2026-01-07 to easy")
        XCTAssertTrue(try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first).manuallyOverridden)
    }

    func testChatStoreRejectsICSCalendarDetourAndStagesPlanToolInstead() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("BEGIN:VCALENDAR\nDTSTART:20260107T080000\nSUMMARY:Easy run\nEND:VCALENDAR")], stopReason: "end_turn"),
            ClaudeResponse(content: [
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object([
                    "changes": .array([
                        .object([
                            "date": .string(CoachContextBuilder.day(qualityDay, calendar: calendar)),
                            "action": .string("downgrade")
                        ])
                    ])
                ]))
            ], stopReason: "tool_use")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Update my plan this week.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertNotNil(coordinator.pendingProposal)
        XCTAssertEqual(client.requests.count, 2)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("VCALENDAR"))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(messages.last?.text.contains("I prepared this calendar update") == true)
    }

    func testChatStoreSendsAttachedContextAndImage() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let workout = try XCTUnwrap(try context.fetch(FetchDescriptor<PlannedWorkout>()).first)
        let image = CoachImageAttachment(data: Data([1, 2, 3]), mediaType: "image/jpeg", filename: "test.jpg")
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("Here is the context review.")], stopReason: "end_turn")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Review this workout.",
            model: "claude-test",
            attachments: [.health, .plannedWorkout(workout.uuid), .image(image)],
            apiKey: "test-key",
            in: context
        )

        let storedMessages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(storedMessages.first?.text, "Review this workout.")
        XCTAssertFalse(storedMessages.first?.text.contains("Attached:") == true)

        let content = try XCTUnwrap(client.requests.first?.messages.last?.content)
        XCTAssertTrue(content.textContent.contains("Attached context:"))
        XCTAssertTrue(content.textContent.contains("Health snapshot:"))
        XCTAssertTrue(content.textContent.contains("Selected workout context"))
        XCTAssertTrue(content.textContent.contains("Workout ID: \(workout.uuid.uuidString)"))
        XCTAssertTrue(content.contains {
            if case .image(let mediaType, let data) = $0 {
                return mediaType == "image/jpeg" && data == image.base64String
            }
            return false
        })
    }

    func testContextualCoachRejectsProposalForDifferentWorkoutDate() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let selected = try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first)
        let friday = PlanEngineTestSupport.date(2026, 1, 9)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object([
                    "changes": .array([
                        .object([
                            "date": .string(CoachContextBuilder.day(friday, calendar: calendar)),
                            "action": .string("downgrade")
                        ])
                    ])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [.text("I will keep the selected workout in context.")], stopReason: "end_turn")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today }, replacementCoordinator: coordinator)

        await store.send(
            text: "Make this workout easier.",
            model: "claude-test",
            attachments: [.plannedWorkout(selected.uuid)],
            apiKey: "test-key",
            in: context
        )

        XCTAssertNil(coordinator.pendingProposal)
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertFalse(try XCTUnwrap(try plannedWorkouts(on: friday, in: context).first).manuallyOverridden)
    }

    func testContextualThreadStoresWorkoutSnapshotMetadata() throws {
        let workoutID = UUID()
        let snapshot = WorkoutCoachContext(
            workoutId: workoutID,
            trainingPlanId: nil,
            calendarDate: qualityDay,
            workoutStatus: .planned,
            workoutType: "tempo",
            workoutTitle: "Tempo",
            plannedDistanceKm: 8,
            plannedDurationSeconds: 3200,
            plannedPaceFastSecondsPerKm: 300,
            plannedPaceSlowSecondsPerKm: 330,
            plannedIntensity: "key",
            workoutStructureSummary: "Tempo blocks",
            isKeyWorkout: true,
            phaseId: "base",
            phaseName: "Base",
            planWeek: 0,
            nearbyWorkoutIds: [],
            sourceScreen: "trainingCalendar"
        )
        let thread = ChatThread(
            title: "Edit Tempo · Jan 7",
            mode: .workoutEdit,
            linkedWorkoutUUID: workoutID,
            contextualSnapshotJSON: WorkoutCoachContext.encode(snapshot)
        )

        XCTAssertEqual(thread.mode, .workoutEdit)
        XCTAssertEqual(thread.linkedWorkoutUUID, workoutID)
        XCTAssertEqual(WorkoutCoachContext.decode(thread.contextualSnapshotJSON), snapshot)
    }

    func testContextualVietnameseDistanceShortcutStagesExplicitLargeTargetWithoutModelGuessing() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let selected = try XCTUnwrap(try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            $0.kind == .long && $0.status == .planned && $0.date > today
        })
        let client = MockClaudeClient(responses: [])
        let contextualToday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: selected.date)))
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { contextualToday })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { contextualToday },
            replacementCoordinator: coordinator
        )

        let unsafeTargetKm = selected.distanceKm * 2

        await store.send(
            text: "đổi cự li thành \(unsafeTargetKm) km",
            model: "claude-test",
            attachments: [.plannedWorkout(selected.uuid)],
            apiKey: "test-key",
            in: context
        )

        XCTAssertTrue(client.requests.isEmpty)
        let pending = try XCTUnwrap(coordinator.pending)
        XCTAssertEqual(pending.expected.uuid, selected.uuid)
        XCTAssertEqual(pending.proposed.distanceKm, unsafeTargetKm, accuracy: 0.001)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("cụ thể hơn"))
    }

    func testContextualVietnameseDistanceShortcutBypassesModelForClearReplacementRequest() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let selected = try XCTUnwrap(try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            $0.kind == .long && $0.status == .planned && $0.date > today
        })
        let client = MockClaudeClient(responses: [])
        let contextualToday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: selected.date)))
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { contextualToday })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { contextualToday },
            replacementCoordinator: coordinator
        )

        let targetKm = selected.distanceKm + 0.5

        await store.send(
            text: "đổi cự ly thành \(targetKm) km",
            model: "claude-test",
            attachments: [.plannedWorkout(selected.uuid)],
            apiKey: "test-key",
            in: context
        )

        XCTAssertTrue(client.requests.isEmpty)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("cụ thể hơn"))
        if let pending = coordinator.pending {
            XCTAssertEqual(pending.expected.uuid, selected.uuid)
            XCTAssertEqual(pending.proposed.distanceKm, targetKm, accuracy: 0.001)
            XCTAssertEqual(pending.proposed.kind, selected.kind)
        }
    }

    func testContextualTomorrowDistanceShortcutHandlesNaturalVietnamesePhrasing() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let selected = try XCTUnwrap(try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            $0.kind == .long && $0.status == .planned && $0.date > today
        })
        let client = MockClaudeClient(responses: [])
        let contextualToday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: selected.date))
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { contextualToday })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { contextualToday },
            replacementCoordinator: coordinator
        )

        let targetKm = selected.distanceKm + 0.5

        await store.send(
            text: "tăng cự li buổi ngày mai lên \(targetKm) km",
            model: "claude-test",
            attachments: [.plannedWorkout(selected.uuid)],
            apiKey: "test-key",
            in: context
        )

        XCTAssertTrue(client.requests.isEmpty)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("cụ thể hơn"))
        if let pending = coordinator.pending {
            XCTAssertEqual(pending.expected.uuid, selected.uuid)
            XCTAssertEqual(pending.proposed.distanceKm, targetKm, accuracy: 0.001)
            XCTAssertEqual(pending.proposed.kind, selected.kind)
        } else {
            let transcript = messages.map(\.text).joined(separator: "\n")
            XCTAssertTrue(transcript.contains("Em hiểu anh muốn đổi buổi này lên"))
            XCTAssertTrue(transcript.contains("Buổi tập chưa thay đổi"))
        }
    }

    func testContextualDistanceShortcutDoesNotAskForSpecificsWhenFactoryRejectsInvalidTarget() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let selected = try XCTUnwrap(try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            $0.kind == .long && $0.status == .planned && $0.date > today
        })
        let client = MockClaudeClient(responses: [])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(
            text: "tăng cự li buổi ngày mai lên 100 km",
            model: "claude-test",
            attachments: [.plannedWorkout(selected.uuid)],
            apiKey: "test-key",
            in: context
        )

        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNil(coordinator.pending)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        let transcript = messages.map(\.text).joined(separator: "\n")
        XCTAssertTrue(transcript.contains("Em hiểu anh muốn đổi buổi này lên 100 km"))
        XCTAssertTrue(transcript.contains("Buổi tập chưa thay đổi"))
        XCTAssertFalse(transcript.contains("cụ thể hơn"))
    }

    func testVietnameseTodayLongRunDistanceShortcutStagesReplacementWithoutWorkoutAttachment() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let plan = try XCTUnwrap(try PlanStore.activePlan(in: context))
        for workout in try plannedWorkouts(on: today, in: context) {
            context.delete(workout)
        }
        let selected = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: calendar.startOfDay(for: today),
                kind: .long,
                distanceKm: 5,
                paceBand: nil,
                details: "Long run"
            ),
            weekIndex: 0,
            phase: .base
        )
        selected.plan = plan
        context.insert(selected)
        try context.save()

        let client = MockClaudeClient(responses: [])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(
            text: "chuyển bài long run hnay cự li 5km thành 8km",
            model: "claude-test",
            attachments: [.health],
            apiKey: "test-key",
            in: context
        )

        XCTAssertTrue(client.requests.isEmpty)
        let pending = try XCTUnwrap(coordinator.pending)
        XCTAssertEqual(pending.expected.uuid, selected.uuid)
        XCTAssertEqual(pending.existing.distanceKm, 5, accuracy: 0.001)
        XCTAssertEqual(pending.proposed.distanceKm, 8, accuracy: 0.001)
        XCTAssertEqual(pending.proposed.kind, .long)
        let transcript = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
            .map(\.text)
            .joined(separator: "\n")
        XCTAssertFalse(transcript.contains("cụ thể hơn"))
    }

    func testAbsoluteDateDistanceShortcutStagesReplacementForCompletedMatchedWorkout() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let plan = try XCTUnwrap(try PlanStore.activePlan(in: context))
        let targetDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        for workout in try plannedWorkouts(on: targetDay, in: context) {
            context.delete(workout)
        }
        let activityID = UUID()
        context.insert(CompletedActivity(
            hkUUID: activityID,
            date: targetDay,
            distanceMeters: 5_200,
            durationSeconds: 1_800,
            avgHeartRate: 140,
            maxHeartRate: 160,
            avgPaceSecondsPerKm: 346,
            sourceName: "Garmin"
        ))
        let selected = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: calendar.startOfDay(for: targetDay),
                kind: .easy,
                distanceKm: 5.2,
                paceBand: nil,
                details: "Easy run"
            ),
            weekIndex: 0,
            phase: .base
        )
        selected.status = .done
        selected.matchedActivityUUID = activityID
        selected.isScheduleLocked = true
        selected.plan = plan
        context.insert(selected)
        try context.save()

        let client = MockClaudeClient(responses: [])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(
            text: "Tạo chỉnh sửa ngắn hạn chỉ ngày 2026-01-06 easy 10km vẫn easy nha",
            model: "claude-test",
            attachments: [.health],
            apiKey: "test-key",
            in: context
        )

        XCTAssertTrue(client.requests.isEmpty)
        let pending = try XCTUnwrap(coordinator.pending)
        XCTAssertEqual(pending.expected.uuid, selected.uuid)
        XCTAssertEqual(pending.existing.distanceKm, 5.2, accuracy: 0.001)
        XCTAssertEqual(pending.existing.kind, .easy)
        XCTAssertEqual(pending.proposed.distanceKm, 10, accuracy: 0.001)
        XCTAssertEqual(pending.proposed.kind, .easy)
        let transcript = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
            .map(\.text)
            .joined(separator: "\n")
        XCTAssertFalse(transcript.contains("hoàn thành"))
        XCTAssertFalse(transcript.contains("cụ thể hơn"))
    }

    /// End-to-end: user asks, model calls the tool, the app builds and saves a
    /// canonical workout, and the second round summarizes it.
    func testChatStoreCreatesStructuredWorkoutEndToEnd() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0) // left empty by the generator
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .passthrough(.object(["type": .string("thinking"), "thinking": .string("free day"), "signature": .string("sig")])),
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("create"),
                        "workout": .object([
                            "kind": .string("easy"),
                            "blocks": .array([.object([
                                "repeat_count": .number(1),
                                "steps": .array([.object([
                                    "role": .string("work"),
                                    "target_type": .string("distance_km"),
                                    "target_value": .number(5),
                                    "pace_zone": .string("easy")
                                ])])
                            ])])
                        ])
                    ])])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [.text("Added a 5 km easy run on Saturday.")], stopReason: "end_turn")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Add an easy run on Saturday.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let pending = try XCTUnwrap(coordinator.pendingProposal)
        XCTAssertTrue(pending.summary.contains("Created easy on 2026-01-10"))
        XCTAssertEqual(client.requests.count, 1)

        coordinator.confirmProposal(pending.id)

        let created = try XCTUnwrap(try plannedWorkouts(on: saturday, in: context).first)
        XCTAssertEqual(created.kind, .easy)
        XCTAssertEqual(created.distanceKm, 5, accuracy: 0.001)
        XCTAssertTrue(created.manuallyOverridden)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.last?.appliedAdjustment, "Created easy on 2026-01-10")
    }

    func testCoachMoveCanTargetNormalRestDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedGoalOnly(in: context)
        let source = PlanEngineTestSupport.date(2026, 1, 5, hour: 0) // Monday, generated workout day
        let target = PlanEngineTestSupport.date(2026, 1, 6, hour: 0) // Tuesday, not in availableDays
        let plan = try XCTUnwrap(try PlanStore.activePlan(in: context))
        let originalTargets = plan.weekTargetVolumesKm
        let sourceWorkout = try XCTUnwrap(try plannedWorkouts(on: source, in: context).first)
        XCTAssertNil(try plannedWorkouts(on: target, in: context).first)

        let proposal = PlanAdjustmentProposal(changes: [
            .init(
                date: CoachContextBuilder.day(source, calendar: calendar),
                action: .move,
                detail: CoachContextBuilder.day(target, calendar: calendar)
            )
        ])

        let staged = try CoachTools.validateForConfirmation(
            proposal: proposal,
            in: context,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(staged.summary, "Moved 2026-01-05 to 2026-01-06")
        XCTAssertNotNil(try plannedWorkouts(on: source, in: context).first, "preflight must not persist")

        let applied = try CoachTools.apply(proposal: proposal, in: context, today: today, calendar: calendar)
        XCTAssertEqual(applied.summary, "Moved 2026-01-05 to 2026-01-06")
        XCTAssertNil(try plannedWorkouts(on: source, in: context).first)
        let moved = try XCTUnwrap(try plannedWorkouts(on: target, in: context).first)
        XCTAssertEqual(moved.kind, sourceWorkout.kind)
        XCTAssertEqual(moved.distanceKm, sourceWorkout.distanceKm, accuracy: 0.001)
        XCTAssertTrue(moved.manuallyOverridden)
        XCTAssertEqual(plan.weekTargetVolumesKm, originalTargets)
    }

    func testCoachCanCreateAndMoveInOneProposal() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedGoalOnly(in: context)
        let source = PlanEngineTestSupport.date(2026, 1, 5, hour: 0)
        let moveTarget = PlanEngineTestSupport.date(2026, 1, 6, hour: 0)
        let createTarget = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        XCTAssertNotNil(try plannedWorkouts(on: source, in: context).first)
        XCTAssertNil(try plannedWorkouts(on: moveTarget, in: context).first)
        XCTAssertNil(try plannedWorkouts(on: createTarget, in: context).first)

        let workout = PlanAdjustmentProposal.CreateWorkout(
            kind: "easy",
            blocks: [.init(repeatCount: 1, steps: [.init(
                role: "work",
                targetType: "distance_km",
                targetValue: 5,
                paceZone: "easy"
            )])]
        )
        let proposal = PlanAdjustmentProposal(changes: [
            .init(
                date: CoachContextBuilder.day(createTarget, calendar: calendar),
                action: .create,
                workout: workout
            ),
            .init(
                date: CoachContextBuilder.day(source, calendar: calendar),
                action: .move,
                detail: CoachContextBuilder.day(moveTarget, calendar: calendar)
            )
        ])

        let staged = try CoachTools.validateForConfirmation(
            proposal: proposal,
            in: context,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(staged.summary, "Moved 2026-01-05 to 2026-01-06; Created easy on 2026-01-10")
        XCTAssertNil(try plannedWorkouts(on: moveTarget, in: context).first, "preflight must not persist")
        XCTAssertNil(try plannedWorkouts(on: createTarget, in: context).first, "preflight must not persist")

        let applied = try CoachTools.apply(proposal: proposal, in: context, today: today, calendar: calendar)
        XCTAssertEqual(applied.summary, staged.summary)
        XCTAssertNil(try plannedWorkouts(on: source, in: context).first)
        XCTAssertNotNil(try plannedWorkouts(on: moveTarget, in: context).first)
        let created = try XCTUnwrap(try plannedWorkouts(on: createTarget, in: context).first)
        XCTAssertEqual(created.kind, .easy)
        XCTAssertEqual(created.distanceKm, 5, accuracy: 0.001)
    }

    func testCoachCanCreateOnRestDayAndMoveFourEasyWorkoutsInOneProposal() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedGoalOnly(in: context)
        let goal = try XCTUnwrap(try PlanStore.activeGoal(in: context)?.spec)
        let existing = try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))
        let occupied = Set(existing.map { CoachContextBuilder.day($0.date, calendar: calendar) })

        let candidateFreeDays = freeDays(from: today, before: goal.raceDate, occupied: occupied)
        let createTarget = try XCTUnwrap(candidateFreeDays.first)
        var usedTargets = Set([CoachContextBuilder.day(createTarget, calendar: calendar)])
        let movablePairs = existing.compactMap { workout -> (PlannedWorkout, Date)? in
            guard workout.date >= today, workout.kind == .easy else { return nil }
            guard let target = freeDay(inSameWeekAs: workout.date, occupied: occupied, usedTargets: usedTargets) else { return nil }
            usedTargets.insert(CoachContextBuilder.day(target, calendar: calendar))
            return (workout, target)
        }.prefix(4)
        XCTAssertEqual(movablePairs.count, 4, "fixture needs four same-week easy moves for max-size plan edit coverage")

        let workout = PlanAdjustmentProposal.CreateWorkout(
            kind: "easy",
            blocks: [.init(repeatCount: 1, steps: [.init(
                role: "work",
                targetType: "distance_km",
                targetValue: 1,
                paceZone: "easy"
            )])]
        )
        var changes: [PlanAdjustmentProposal.Change] = [
            .init(
                date: CoachContextBuilder.day(createTarget, calendar: calendar),
                action: .create,
                workout: workout
            )
        ]
        for (source, target) in movablePairs {
            changes.append(.init(
                date: CoachContextBuilder.day(source.date, calendar: calendar),
                action: .move,
                detail: CoachContextBuilder.day(target, calendar: calendar)
            ))
        }
        XCTAssertEqual(changes.count, CoachTools.maxChangesPerProposal)

        let staged = try CoachTools.validateForConfirmation(
            proposal: .init(changes: changes),
            in: context,
            today: today,
            calendar: calendar
        )
        XCTAssertTrue(staged.summary.contains("Created easy on \(CoachContextBuilder.day(createTarget, calendar: calendar))"))
        XCTAssertNil(try plannedWorkouts(on: createTarget, in: context).first, "preflight must not persist")
        for (_, target) in movablePairs {
            XCTAssertNil(try plannedWorkouts(on: target, in: context).first, "preflight must not persist moves")
        }

        let applied = try CoachTools.apply(
            proposal: .init(changes: changes),
            in: context,
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(applied.summary, staged.summary)
        let created = try XCTUnwrap(try plannedWorkouts(on: createTarget, in: context).first)
        XCTAssertEqual(created.kind, .easy)
        XCTAssertEqual(created.distanceKm, 1, accuracy: 0.001)
        for (source, _) in movablePairs {
            XCTAssertNil(try plannedWorkouts(on: source.date, in: context).first)
        }
        for (_, target) in movablePairs {
            XCTAssertNotNil(try plannedWorkouts(on: target, in: context).first)
        }
    }

    private func freeDays(from start: Date, before end: Date, occupied: Set<String>) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while cursor < endDay {
            let key = CoachContextBuilder.day(cursor, calendar: calendar)
            if !occupied.contains(key) { days.append(cursor) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private func freeDay(inSameWeekAs source: Date, occupied: Set<String>, usedTargets: Set<String>) -> Date? {
        let weekStart = PlanGenerator.mondayOfWeek(containing: source, calendar: calendar)
        for offset in 0..<7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            guard !calendar.isDate(candidate, inSameDayAs: source) else { continue }
            let key = CoachContextBuilder.day(candidate, calendar: calendar)
            if !occupied.contains(key), !usedTargets.contains(key) { return candidate }
        }
        return nil
    }

    func testChatStoreStagesFlattenedCreatePayloadWithoutRetry() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_flat", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("create"),
                        "workout": .string("Easy"),
                        "blocks": .array([.object([
                            "repeat_count": .number(1),
                            "steps": .array([.object([
                                "role": .string("work"),
                                "target_type": .string("distance_km"),
                                "target_value": .number(5),
                                "pace_zone": .string("easy")
                            ])])
                        ])])
                    ])])
                ]))
            ], stopReason: "tool_use")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Create easy on Saturday.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertEqual(client.requests.count, 1)
        let pending = try XCTUnwrap(coordinator.pendingProposal)
        XCTAssertEqual(pending.summary, "Created easy on 2026-01-10")
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("could not safely"))
    }

    func testChatStoreDoesNotPersistToolSchemaConfirmationAfterRejectedPlanEdit() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_bad", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("create"),
                        "workout": .string("Easy")
                    ])])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [.text("Bạn có thể xác nhận lại giúp mình rằng cấu trúc trên đã đúng theo yêu cầu của plan_adjustment tool và mình sẽ gửi lại bằng đúng JSON/định dạng mà tool yêu cầu.")], stopReason: "end_turn"),
            ClaudeResponse(content: [
                .toolUse(id: "toolu_good", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("create"),
                        "workout": .object([
                            "kind": .string("easy"),
                            "blocks": .array([.object([
                                "repeat_count": .number(1),
                                "steps": .array([.object([
                                    "role": .string("work"),
                                    "target_type": .string("distance_km"),
                                    "target_value": .number(5),
                                    "pace_zone": .string("easy")
                                ])])
                            ])])
                        ])
                    ])])
                ]))
            ], stopReason: "tool_use")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Create easy on Saturday.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertEqual(client.requests.count, 3)
        XCTAssertNotNil(coordinator.pendingProposal)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("Bạn có thể xác nhận"))
    }

    func testPlanMutationBuffersDraftTextUntilFinalCardOrRejection() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .text("Cảm ơn bạn, mình sẽ kiểm tra lịch hiện tại trước."),
                .toolUse(id: "toolu_bad", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("rest")
                    ])])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [.text("Em chưa thể chỉnh vì thứ bảy đang trống.")], stopReason: "end_turn")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Create workout on Saturday.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertNil(coordinator.pendingProposal)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        let assistant = try XCTUnwrap(messages.last)
        XCTAssertEqual(assistant.assistantStatus, .completed)
        XCTAssertFalse(assistant.text.contains("Cảm ơn bạn"))
        XCTAssertFalse(assistant.text.contains("thứ bảy đang trống"))
        XCTAssertTrue(assistant.text.contains("Em chưa thể áp dụng") || assistant.text.contains("Coach chưa đọc được"))
    }

    func testChatStoreRejectsUnapplyablePlanCardBeforeUserCanConfirm() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0) // free day
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let workout = PlanAdjustmentProposal.CreateWorkout(
            kind: "easy",
            blocks: [.init(repeatCount: 1, steps: [.init(
                role: "work",
                targetType: "distance_km",
                targetValue: 5,
                paceZone: "easy"
            )])]
        )
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_bad", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("rest")
                    ])])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [
                .toolUse(id: "toolu_good", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("create"),
                        "workout": .object([
                            "kind": .string(workout.kind),
                            "blocks": .array([.object([
                                "repeat_count": .number(1),
                                "steps": .array([.object([
                                    "role": .string("work"),
                                    "target_type": .string("distance_km"),
                                    "target_value": .number(5),
                                    "pace_zone": .string("easy")
                                ])])
                            ])])
                        ])
                    ])])
                ]))
            ], stopReason: "tool_use")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Make Saturday a run day.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertEqual(client.requests.count, 2)
        let pending = try XCTUnwrap(coordinator.pendingProposal)
        XCTAssertEqual(pending.summary, "Created easy on 2026-01-10")
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("No workout on 2026-01-10"))
    }

    func testValidateForConfirmationDoesNotPersistAndRejectsMissingWorkoutEdit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)

        XCTAssertThrowsError(try CoachTools.validateForConfirmation(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: CoachContextBuilder.day(saturday, calendar: calendar), action: .rest)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("No workout on 2026-01-10."))
            XCTAssertTrue(error.localizedDescription.contains("For move, set date to the source day"))
        }
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
    }

    func testTransientPlanEditConnectionFailurePersistsRetryableInlineFailure() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(error: ClaudeClientError.connectionLost)
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Create workout tomorrow.", model: "claude-test", apiKey: "test-key", in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        let failed = try XCTUnwrap(messages.last)
        XCTAssertEqual(failed.assistantStatus, .failed)
        XCTAssertEqual(failed.errorCategory, .retryableResponse)
        XCTAssertEqual(failed.parentUserTurnID, messages.first?.turnID)
        XCTAssertEqual(failed.attemptCount, 1)
        XCTAssertEqual(failed.text, "")
        XCTAssertEqual(store.lastError, ClaudeClientError.connectionLost.errorDescription)
        XCTAssertEqual(failed.errorDetail, ClaudeClientError.connectionLost.errorDescription)
        let snapshots = try context.fetch(FetchDescriptor<CoachRequestSnapshot>())
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.messageText, "Create workout tomorrow.")
    }

    func testTimedOutSurfacesTimeoutDetailAndStaysRetryable() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(error: ClaudeClientError.timedOut)
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Create workout tomorrow.", model: "claude-test", apiKey: "test-key", in: context)

        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(failed.assistantStatus, .failed)
        XCTAssertEqual(failed.errorCategory, .retryableResponse)
        XCTAssertEqual(failed.errorDetail, ClaudeClientError.timedOut.errorDescription)
        XCTAssertEqual(failed.errorMessage, CoachLanguage.en.interruptedFailureMessage)
    }

    func testTruncatedPlanEditReplyReportsCutOffNotConnectionDrop() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("Adjusting the week")], stopReason: "max_tokens")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Create workout tomorrow.", model: "claude-test", apiKey: "test-key", in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        let failed = try XCTUnwrap(messages.last)
        XCTAssertEqual(failed.assistantStatus, .failed)
        XCTAssertEqual(failed.errorCategory, .responseTruncated)
        XCTAssertEqual(failed.errorMessage, CoachLanguage.en.responseTruncatedMessage)
    }

    func testCoachResponsePayloadDecodesWithoutContent() throws {
        let json = Data("""
        {"interaction":{"id":"next_step","type":"single_choice","options":[{"id":"a","label":"A","value":"A"},{"id":"b","label":"B","value":"B"}],"allowOther":false,"status":"pending"}}
        """.utf8)
        let payload = try JSONDecoder().decode(CoachStructuredResponsePayload.self, from: json)
        XCTAssertEqual(payload.content, "")
        XCTAssertEqual(payload.interaction?.options.map(\.id), ["a", "b"])
    }

    func testCoachResponsePayloadDefaultsWhenNotAnObject() throws {
        let payload = try JSONDecoder().decode(CoachStructuredResponsePayload.self, from: Data("\"oops\"".utf8))
        XCTAssertEqual(payload.content, "")
        XCTAssertNil(payload.interaction)
    }

    func testCoachStructuredResponsePayloadDecodesModelAuthoredFields() throws {
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high. An easy day supports adaptation.",
          "recommendations": [
            {"id": "easy-run", "title": "Run easy", "description": "Keep effort low.", "priority": 1},
            {"id": "sleep", "title": "Sleep more", "priority": 2}
          ],
          "details": {
            "title": "Why",
            "sections": [{"id": "load", "title": "Training load", "markdown": "Load is elevated."}]
          },
          "followUps": [
            {"id": "plan", "label": "Show my plan", "value": "Show my plan"},
            {"id": "recovery", "label": "Recovery ideas", "value": "Recovery ideas"}
          ]
        }
        """

        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )

        XCTAssertEqual(payload.title, "Prioritize recovery")
        XCTAssertEqual(payload.summary, "Your recent effort was high. An easy day supports adaptation.")
        XCTAssertEqual(payload.recommendations?.count, 2)
        XCTAssertEqual(payload.details?.sections.count, 1)
        XCTAssertEqual(payload.followUps?.count, 2)
    }

    func testSafetyNotePreservedAndNotFoldedIntoDetails() throws {
        let note = "Neu dau nguc hay chong mat, dung tap va di kham."
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high.",
          "safetyNote": "\(note)",
          "details": {
            "title": "Why",
            "sections": [{"id": "load", "title": "Training load", "markdown": "Training load is elevated, so reduce intensity today."}]
          }
        }
        """
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )
        let response = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )
        let details = try XCTUnwrap(response.details)

        XCTAssertEqual(response.safetyNote, note)
        XCTAssertFalse(details.sections.contains { $0.markdown.contains(note) })
    }

    func testValidatedStructuredResponseNilWhenTitleOrSummaryMissing() throws {
        let jsonString = #"{"content":"Take an easy day."}"#
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )

        XCTAssertNil(payload.validatedStructuredResponse(additionalRecommendationsTitle: "More"))
    }

    func testValidatedStructuredResponseCapsRecommendationsMovingOverflowToDetails() throws {
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high.",
          "recommendations": [
            {"id": "r1", "title": "First", "priority": 1},
            {"id": "r2", "title": "Second", "priority": 2},
            {"id": "r3", "title": "Third", "priority": 3},
            {"id": "r4", "title": "Fourth", "priority": 4},
            {"id": "r5", "title": "Fifth", "priority": 5}
          ]
        }
        """
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )
        let response = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )
        let overflow = try XCTUnwrap(response.details?.sections.last)

        XCTAssertEqual(response.recommendations.count, 3)
        XCTAssertEqual(response.recommendations.map(\.id), ["r1", "r2", "r3"])
        XCTAssertEqual(overflow.id, "additional-recommendations")
        XCTAssertTrue(overflow.markdown.contains("Fourth"))
        XCTAssertTrue(overflow.markdown.contains("Fifth"))
    }

    func testValidatedStructuredResponseCapsFollowUpsToThree() throws {
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high.",
          "followUps": [
            {"id": "one", "label": "One", "value": "One"},
            {"id": "two", "label": "Two", "value": "Two"},
            {"id": "three", "label": "Three", "value": "Three"},
            {"id": "four", "label": "Four", "value": "Four"},
            {"id": "five", "label": "Five", "value": "Five"}
          ]
        }
        """
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )
        let response = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )

        XCTAssertEqual(response.followUps.count, 3)
    }

    func testValidatedStructuredResponseDropsEmptyModelDetails() throws {
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high.",
          "details": {"title": "Why", "sections": []}
        }
        """
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )
        let response = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )

        XCTAssertNil(response.details)
    }

    func testValidatedStructuredResponseDropsBlankDetailSections() throws {
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high.",
          "details": {"title": "Why", "sections": [{"id": "x", "title": " ", "markdown": "  "}]}
        }
        """
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )
        let response = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )

        XCTAssertNil(response.details)
    }

    func testValidatedStructuredResponseDedupsAndDropsBlankFollowUps() throws {
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high.",
          "followUps": [
            {"id": "a", "label": "First", "value": "First prompt"},
            {"id": "a", "label": "Duplicate", "value": "Duplicate prompt"},
            {"id": "b", "label": " ", "value": "  "}
          ]
        }
        """
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )
        let response = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )

        XCTAssertEqual(response.followUps.map(\.id), ["a"])
    }

    func testValidatedStructuredResponseDedupsAndDropsBlankRecommendations() throws {
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high.",
          "recommendations": [
            {"id": "r1", "title": "First", "priority": 1},
            {"id": "r1", "title": "Duplicate", "priority": 2},
            {"id": "r2", "title": "  ", "priority": 3}
          ]
        }
        """
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )
        let response = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )

        XCTAssertEqual(response.recommendations.map(\.id), ["r1"])
    }

    func testValidatedStructuredResponseLeavesHydratedFieldsEmpty() throws {
        let jsonString = """
        {
          "content": "Take an easy day.",
          "title": "Prioritize recovery",
          "summary": "Your recent effort was high."
        }
        """
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )
        let response = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )

        XCTAssertNil(response.status)
        XCTAssertTrue(response.metrics.isEmpty)
        XCTAssertTrue(response.sources.isEmpty)
        XCTAssertNil(response.primaryAction)
    }

    func testReadinessVerdictMapsToStatusExhaustively() {
        XCTAssertEqual(CoachResponseComposer.status(for: .train), .ready)
        XCTAssertEqual(CoachResponseComposer.status(for: .goEasy), .recoveryRecommended)
        XCTAssertEqual(CoachResponseComposer.status(for: .rest), .recoveryRecommended)
        XCTAssertEqual(CoachResponseComposer.status(for: .insufficientData), .insufficientData)
    }

    func testMetricsUseLocalizedLabelsCompactValuesAndRuleFlaggedStatus() throws {
        let metrics = CoachResponseComposer.metrics(from: hydrationReadiness(), language: .vi)
        let load = try XCTUnwrap(metrics.first { $0.id == "load" })
        let sleep = try XCTUnwrap(metrics.first { $0.id == "sleep" })

        XCTAssertEqual(load.value, "1.2")
        XCTAssertEqual(load.label, CoachLanguage.vi.metricLoadLabel)
        XCTAssertEqual(load.status, .attention)
        XCTAssertEqual(load.interpretation, CoachLanguage.vi.metricAttentionNote)
        XCTAssertEqual(sleep.value, CoachLanguage.vi.sleepHours(7.0))
        XCTAssertEqual(sleep.status, .neutral)
    }

    func testDistanceFormatterIsLocaleAwareAndNeverIdeogram() {
        let distances = [
            CoachResponseComposer.formatDistance(kilometers: 5.0, language: .vi),
            CoachResponseComposer.formatDistance(kilometers: 3.1, language: .en)
        ]

        XCTAssertEqual(distances, ["5 km", "3.1 km"])
        XCTAssertFalse(distances.contains { $0.contains("公里") })

        let metricValues = CoachResponseComposer.metrics(from: hydrationReadiness(), language: .vi).map(\.value)
        XCTAssertFalse(metricValues.contains { $0.contains("公里") })
    }

    func testSourcesMapAndDedupeContextItems() {
        let sources = CoachResponseComposer.sources(from: hydrationContextItems(), language: .vi)

        XCTAssertEqual(sources.map(\.type), [.healthData, .completedWorkout, .trainingPlan])
        XCTAssertEqual(sources.first?.label, CoachLanguage.vi.sourceHealthDataLabel)
    }

    func testCoachStatusLabelsLocalized() {
        XCTAssertEqual(
            CoachLanguage.vi.coachStatusLabel(for: .recoveryRecommended),
            "NÊN ƯU TIÊN HỒI PHỤC"
        )
        XCTAssertEqual(
            CoachLanguage.vi.coachStatusLabel(for: .ready),
            "SẴN SÀNG TẬP LUYỆN"
        )
    }

    func testBasedOnSourcesLabel() {
        XCTAssertEqual(
            CoachLanguage.vi.coachBasedOnSourcesLabel(count: 3),
            "Dựa trên 3 nguồn"
        )
    }

    func testCoachUpdatedAtLabelLocalized() {
        XCTAssertEqual(CoachLanguage.vi.coachUpdatedAtLabel("1:58 PM"), "Cập nhật 1:58 PM")
        XCTAssertEqual(CoachLanguage.en.coachUpdatedAtLabel("1:58 PM"), "Updated 1:58 PM")
    }

    func testCoachCardUpdatedTimeUsesSelectedLocale() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 2
        components.hour = 13
        components.minute = 58
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))

        let en = CoachResponseCard.updatedTimeText(date, language: .en)
        let vi = CoachResponseCard.updatedTimeText(date, language: .vi)

        XCTAssertTrue(en.contains("PM"), "en_US formats 13:58 as 12-hour with PM, got \(en)")
        XCTAssertTrue(vi.contains("13:58"), "vi_VN formats as 24-hour, got \(vi)")
    }

    func testSourcesSheetSymbolsCoverAllKinds() {
        let kinds: [CoachDataSource.Kind] = [
            .healthData,
            .completedWorkout,
            .trainingPlan,
            .upcomingWorkouts,
            .raceGoal
        ]

        for kind in kinds {
            XCTAssertFalse(CoachSourcesSheet.symbol(for: kind).isEmpty)
        }
    }

    func testDetailSheetLocalizedStrings() {
        XCTAssertEqual(CoachLanguage.vi.coachDetailSheetTitle, "Phân tích chi tiết")
        XCTAssertEqual(CoachLanguage.vi.coachViewDetailLabel, "Xem phân tích chi tiết")
        XCTAssertEqual(CoachLanguage.vi.coachDetailDoneLabel, "Xong")
    }
    func testContextSourceCountLabelLocalized() {
        XCTAssertEqual(CoachLanguage.vi.contextSourceCountLabel(count: 2), "2 nguồn")
        XCTAssertEqual(CoachLanguage.en.contextSourceCountLabel(count: 1), "1 source")
        XCTAssertEqual(CoachLanguage.en.contextSourceCountLabel(count: 2), "2 sources")
        XCTAssertEqual(CoachLanguage.vi.contextSourcesSheetTitle, "Nguồn dữ liệu")
    }

    @MainActor
    func testSourceIndicatorRasterizes() throws {
        guard #available(iOS 16.0, *) else { return }

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".verify-artifacts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let view = CoachSourceIndicator(count: 2, language: .vi, onTap: {})
            .padding(16)
            .background(Theme.bg)
        let renderer = ImageRenderer(content: view)
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: output.appending(path: "coach-source-indicator.png"))
    }

    @MainActor
    func testAttributionCardRasterizes() throws {
        guard #available(iOS 16.0, *) else { return }

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".verify-artifacts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let sample = CoachStructuredResponse(
            title: "Ưu tiên phục hồi hôm nay",
            summary: "Khối lượng tập gần đây đang cao, nên giữ buổi tiếp theo nhẹ nhàng.",
            recommendations: [],
            details: nil,
            followUps: [],
            status: .recoveryRecommended,
            metrics: [],
            primaryAction: nil,
            secondaryAction: nil,
            sources: [
                .init(id: "health", type: .healthData, label: "Dữ liệu sức khỏe", updatedAt: nil),
                .init(id: "plan", type: .trainingPlan, label: "Kế hoạch hiện tại", updatedAt: nil)
            ]
        )
        let view = CoachResponseCard(
            response: sample,
            language: .vi,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        .frame(width: 390)
        .padding(16)
        .background(Theme.bg)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3

        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: output.appending(path: "coach-card-attribution.png"))
    }

    @MainActor
    func testCoachResponseCardRasterizesLightAndDark() throws {
        guard #available(iOS 16.0, *) else { return }

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".verify-artifacts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let response = CoachStructuredResponse(
            title: "Tuần này chưa nên tăng cường độ",
            summary: "Khối lượng tập gần đây đang ổn định, nhưng cơ thể vẫn cần thêm thời gian để hấp thụ bài tập. Ưu tiên phục hồi sẽ giúp bạn trở lại mạnh hơn cho buổi chất lượng tiếp theo.",
            recommendations: [
                .init(id: "easy", title: "Giữ buổi chạy nhẹ", description: "Duy trì nhịp nói chuyện thoải mái.", priority: 1),
                .init(id: "sleep", title: "Ưu tiên giấc ngủ", description: "Đi ngủ sớm hơn trong hai tối tới.", priority: 2),
                .init(id: "fuel", title: "Bổ sung năng lượng", description: "Ăn đủ carbohydrate và protein sau buổi tập.", priority: 3)
            ],
            details: nil,
            followUps: [],
            status: .recoveryRecommended,
            metrics: [
                .init(id: "load", label: "ACWR", value: "1.2", interpretation: "Ổn định", status: .neutral),
                .init(id: "sleep", label: "Giấc ngủ", value: "7 giờ", interpretation: "Cần chú ý", status: .attention)
            ],
            primaryAction: nil,
            secondaryAction: nil,
            sources: [
                .init(id: "health", type: .healthData, label: "Dữ liệu sức khỏe", updatedAt: nil),
                .init(id: "plan", type: .trainingPlan, label: "Kế hoạch hiện tại", updatedAt: nil)
            ]
        )

        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            let view = CoachResponseCard(response: response, language: .vi)
                .frame(width: 360)
                .padding(16)
                .background(Theme.bg)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3

            let image = try XCTUnwrap(renderer.uiImage)
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: output.appending(path: "coach-card-\(name).png"))
        }

        let minimal = CoachStructuredResponse(
            title: "Duy trì nhịp tập",
            summary: "Bạn đang đi đúng hướng.",
            recommendations: [],
            details: nil,
            followUps: [],
            status: nil,
            metrics: [],
            primaryAction: nil,
            secondaryAction: nil,
            sources: []
        )
        let minimalView = CoachResponseCard(response: minimal, language: .vi)
            .frame(width: 360)
            .padding(16)
            .background(Theme.bg)
        let minimalRenderer = ImageRenderer(content: minimalView)
        minimalRenderer.scale = 3

        let minimalImage = try XCTUnwrap(minimalRenderer.uiImage)
        let minimalData = try XCTUnwrap(minimalImage.pngData())
        try minimalData.write(to: output.appending(path: "coach-card-minimal.png"))
    }

    @MainActor
    func testFollowUpChipsRasterizeVisibleAndCollapsed() throws {
        guard #available(iOS 16.0, *) else { return }

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".verify-artifacts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let sample = CoachStructuredResponse(
            title: "Ưu tiên phục hồi hôm nay",
            summary: "Khối lượng tập gần đây đang cao, nên giữ buổi tiếp theo nhẹ nhàng.",
            recommendations: [
                .init(id: "easy", title: "Chạy nhẹ", description: "Giữ nhịp nói chuyện thoải mái.", priority: 1)
            ],
            details: nil,
            followUps: [
                .init(id: "a", label: "Lần tới có nên tăng tải?", description: nil, value: "Lần tới có nên tăng tải?"),
                .init(id: "b", label: "Ăn gì để hồi phục?", description: nil, value: "Ăn gì để hồi phục?")
            ],
            status: .recoveryRecommended,
            metrics: [
                .init(id: "load", label: "ACWR", value: "1.2", interpretation: "Cần chú ý", status: .attention)
            ],
            primaryAction: nil,
            secondaryAction: nil,
            sources: []
        )

        let visibleRenderer = ImageRenderer(
            content: CoachResponseCard(response: sample, language: .vi, followUpsConsumed: false)
                .frame(width: 390)
                .padding(16)
                .background(Theme.bg)
        )
        visibleRenderer.scale = 3
        let visibleImage = try XCTUnwrap(visibleRenderer.uiImage)
        let visibleData = try XCTUnwrap(visibleImage.pngData())
        try visibleData.write(to: output.appending(path: "coach-card-followups.png"))

        let collapsedRenderer = ImageRenderer(
            content: CoachResponseCard(response: sample, language: .vi, followUpsConsumed: true)
                .frame(width: 390)
                .padding(16)
                .background(Theme.bg)
        )
        collapsedRenderer.scale = 3
        let collapsedImage = try XCTUnwrap(collapsedRenderer.uiImage)
        let collapsedData = try XCTUnwrap(collapsedImage.pngData())
        try collapsedData.write(to: output.appending(path: "coach-card-followups-consumed.png"))
    }

    @MainActor
    func testDetailSheetAndSafetyCardRasterize() throws {
        guard #available(iOS 16.0, *) else { return }

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".verify-artifacts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let sample = CoachStructuredResponse(
            title: "Ưu tiên phục hồi hôm nay",
            summary: "Khối lượng tập gần đây đang cao, nên giữ buổi tiếp theo nhẹ nhàng.",
            safetyNote: "Nếu đau ngực hoặc chóng mặt, dừng tập và đi khám.",
            recommendations: [
                .init(id: "easy", title: "Chạy nhẹ", description: "Giữ nhịp nói chuyện thoải mái.", priority: 1),
                .init(id: "sleep", title: "Ngủ đủ", description: "Ưu tiên giấc ngủ tối nay.", priority: 2)
            ],
            details: .init(
                title: "Phân tích chi tiết",
                sections: [
                    .init(id: "load", title: "Khối lượng tập", markdown: "Khối lượng gần đây cao hơn mức nền."),
                    .init(id: "recovery", title: "Phục hồi", markdown: "Ưu tiên nghỉ ngơi và bổ sung năng lượng.")
                ]
            ),
            followUps: [],
            status: .recoveryRecommended,
            metrics: [
                .init(id: "load", label: "ACWR", value: "1.2", interpretation: "Cần chú ý", status: .attention),
                .init(id: "sleep", label: "Giấc ngủ", value: "7 giờ", interpretation: "Ổn định", status: .neutral)
            ],
            primaryAction: nil,
            secondaryAction: nil,
            sources: []
        )

        let cardRenderer = ImageRenderer(
            content: CoachResponseCard(response: sample, language: .vi)
                .frame(width: 390)
                .padding(16)
                .background(Theme.bg)
        )
        cardRenderer.scale = 3
        let cardImage = try XCTUnwrap(cardRenderer.uiImage)
        let cardData = try XCTUnwrap(cardImage.pngData())
        try cardData.write(to: output.appending(path: "coach-card-safety.png"))

        let detailRenderer = ImageRenderer(
            content: CoachDetailSheet(details: try XCTUnwrap(sample.details), language: .vi)
                .frame(width: 390, height: 700)
        )
        detailRenderer.scale = 3
        let detailImage = try XCTUnwrap(detailRenderer.uiImage)
        let detailData = try XCTUnwrap(detailImage.pngData())
        try detailData.write(to: output.appending(path: "coach-detail-sheet.png"))
    }

    func testComposePreservesModelAuthoredAndFillsHydrated() {
        let model = CoachStructuredResponse(
            title: "Prioritize recovery",
            summary: "Your training load is elevated.",
            recommendations: [.init(id: "rest", title: "Rest", description: nil, priority: 1)],
            details: nil,
            followUps: [],
            status: nil,
            metrics: [],
            primaryAction: nil,
            secondaryAction: nil,
            sources: []
        )

        let result = CoachResponseComposer.compose(
            model: model,
            readiness: hydrationReadiness(),
            contextItems: hydrationContextItems(),
            language: .vi
        )

        XCTAssertEqual(result.title, model.title)
        XCTAssertEqual(result.summary, model.summary)
        XCTAssertEqual(result.recommendations, model.recommendations)
        XCTAssertEqual(result.status, .recoveryRecommended)
        XCTAssertFalse(result.metrics.isEmpty)
        XCTAssertEqual(result.sources.count, 3)
    }

    func testMissingOptionalStructuredFieldsDecodeToNil() throws {
        let jsonString = #"{"content":"Take an easy day."}"#
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data(jsonString.utf8)
        )

        XCTAssertNil(payload.title)
        XCTAssertNil(payload.summary)
        XCTAssertNil(payload.recommendations)
        XCTAssertNil(payload.details)
        XCTAssertNil(payload.followUps)
    }

    func testChatMessageStructuredResponseRoundTrips() throws {
        let payload = try JSONDecoder().decode(
            CoachStructuredResponsePayload.self,
            from: Data("""
            {
              "content": "Take it easy.",
              "title": "Prioritize recovery",
              "summary": "Your body needs time to adapt.",
              "recommendations": [
                {"id": "r1", "title": "Rest", "priority": 1},
                {"id": "r2", "title": "Walk", "priority": 2}
              ]
            }
            """.utf8)
        )
        let structured = try XCTUnwrap(
            payload.validatedStructuredResponse(additionalRecommendationsTitle: "More")
        )
        let message = ChatMessage(role: .assistant, text: "x", date: Date())

        message.structuredResponse = structured

        XCTAssertNotNil(message.structuredResponseJSON)
        XCTAssertEqual(message.structuredResponse, structured)

        message.structuredResponse = nil

        XCTAssertNil(message.structuredResponseJSON)
        XCTAssertNil(message.structuredResponse)
    }

    func testFollowUpsConsumedFlagRoundTrips() {
        let message = ChatMessage(role: .assistant, text: "x", date: Date())
        XCTAssertFalse(message.followUpsConsumed)

        message.followUpsConsumed = true
        XCTAssertEqual(message.followUpsConsumedStorage, true)
        XCTAssertTrue(message.followUpsConsumed)

        message.followUpsConsumed = false
        XCTAssertEqual(message.followUpsConsumedStorage, false)
        XCTAssertFalse(message.followUpsConsumed)
    }

    func testSystemPromptDescribesStructuredContract() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        let prompt = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertTrue(prompt.contains("coach_response"))
        XCTAssertTrue(prompt.contains("at most three recommendations"))
        XCTAssertTrue(prompt.contains("at most three short sentences"))
        XCTAssertTrue(prompt.contains("公里"))
        XCTAssertTrue(prompt.contains("do not fabricate"))
        XCTAssertTrue(prompt.contains("up to three follow-up suggestions"))
        XCTAssertTrue(prompt.contains("concise title"))
        XCTAssertTrue(prompt.contains("optional details object"))
        XCTAssertTrue(prompt.contains("optional safetyNote"))
        XCTAssertTrue(prompt.contains("user's app language"))
        XCTAssertTrue(prompt.contains("data-source attribution"))
    }

    func testCoachResponseWithTitleSummaryPersistsComposedStructuredResponse() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        context.insert(DailyReadiness(
            date: today.addingTimeInterval(1),
            assessment: ReadinessAssessment(
                verdict: .rest,
                score: 60,
                reasons: [],
                ruleIDs: [.loadRamp],
                baselineDayCount: 28,
                snapshot: .init(
                    hrvMean7: 45,
                    hrvMean28: nil,
                    rhrMean7: nil,
                    rhrMean28: nil,
                    sleepLastNight: 7,
                    sleepMean14: nil,
                    acuteChronicRatio: 1.2
                )
            ),
            computedAt: today
        ))
        try context.save()
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "t", name: CoachToolCatalog.coachResponseName, input: .object([
                    "content": .string("Take it easy."),
                    "title": .string("Uu tien hoi phuc"),
                    "summary": .string("Co the chua san sang."),
                    "recommendations": .array([
                        .object([
                            "id": .string("r1"),
                            "title": .string("Chay nhe"),
                            "priority": .number(1)
                        ])
                    ])
                ]))
            ], stopReason: "tool_use")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Hom nay the nao?",
            model: "claude-test",
            apiKey: "test-key",
            contextItems: [
                CoachContextItem(type: .healthData, label: "Suc khoe"),
                CoachContextItem(type: .completedRun, label: "Buoi chay")
            ],
            in: context
        )

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        let assistant = try XCTUnwrap(messages.last { $0.role == .assistant })
        let structured = try XCTUnwrap(assistant.structuredResponse)

        XCTAssertEqual(structured.title, "Uu tien hoi phuc")
        XCTAssertEqual(structured.status, .recoveryRecommended)
        XCTAssertFalse(structured.metrics.isEmpty)
        XCTAssertEqual(structured.sources.count, 2)
    }

    func testFullStructuredCoachResponseCapsAndPersistsAllModelFields() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        context.insert(DailyReadiness(
            date: today.addingTimeInterval(1),
            assessment: ReadinessAssessment(
                verdict: .rest,
                score: 60,
                reasons: [],
                ruleIDs: [.loadRamp],
                baselineDayCount: 28,
                snapshot: .init(
                    hrvMean7: 45,
                    hrvMean28: nil,
                    rhrMean7: nil,
                    rhrMean28: nil,
                    sleepLastNight: 7,
                    sleepMean14: nil,
                    acuteChronicRatio: 1.2
                )
            ),
            computedAt: today
        ))
        try context.save()
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "t", name: CoachToolCatalog.coachResponseName, input: .object([
                    "content": .string("Take it easy."),
                    "title": .string("Prioritize recovery"),
                    "summary": .string("Your recent effort was high."),
                    "recommendations": .array([
                        .object([
                            "id": .string("r1"),
                            "title": .string("First"),
                            "priority": .number(1)
                        ]),
                        .object([
                            "id": .string("r2"),
                            "title": .string("Second"),
                            "priority": .number(2)
                        ]),
                        .object([
                            "id": .string("r3"),
                            "title": .string("Third"),
                            "priority": .number(3)
                        ]),
                        .object([
                            "id": .string("r4"),
                            "title": .string("Fourth"),
                            "priority": .number(4)
                        ])
                    ]),
                    "details": .object([
                        "title": .string("Why"),
                        "sections": .array([
                            .object([
                                "id": .string("load"),
                                "title": .string("Training load"),
                                "markdown": .string("Load is elevated.")
                            ])
                        ])
                    ]),
                    "followUps": .array([
                        .object([
                            "id": .string("f1"),
                            "label": .string("First follow-up"),
                            "value": .string("First follow-up prompt")
                        ]),
                        .object([
                            "id": .string("f2"),
                            "label": .string("Second follow-up"),
                            "value": .string("Second follow-up prompt")
                        ]),
                        .object([
                            "id": .string("f3"),
                            "label": .string("Third follow-up"),
                            "value": .string("Third follow-up prompt")
                        ]),
                        .object([
                            "id": .string("f4"),
                            "label": .string("Fourth follow-up"),
                            "value": .string("Fourth follow-up prompt")
                        ])
                    ]),
                    "safetyNote": .string("Stop and seek care for chest pain or dizziness.")
                ]))
            ], stopReason: "tool_use")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "How am I?",
            model: "claude-test",
            apiKey: "test-key",
            contextItems: [
                CoachContextItem(type: .healthData, label: "Health"),
                CoachContextItem(type: .completedRun, label: "Completed run")
            ],
            in: context
        )

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        let assistant = try XCTUnwrap(messages.last { $0.role == .assistant })
        let structured = try XCTUnwrap(assistant.structuredResponse)
        let details = try XCTUnwrap(structured.details)

        XCTAssertEqual(structured.title, "Prioritize recovery")
        XCTAssertEqual(structured.summary, "Your recent effort was high.")
        XCTAssertEqual(structured.recommendations.count, 3)
        XCTAssertTrue(details.sections.contains { $0.id == "additional-recommendations" && $0.markdown.contains("Fourth") })
        XCTAssertEqual(structured.recommendations.map(\.id), ["r1", "r2", "r3"])
        XCTAssertEqual(structured.recommendations.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(details.title, "Why")
        XCTAssertTrue(details.sections.contains { $0.id == "load" && $0.title == "Training load" })
        XCTAssertEqual(structured.followUps.map(\.id), ["f1", "f2", "f3"])
        XCTAssertEqual(structured.followUps.map(\.value), ["First follow-up prompt", "Second follow-up prompt", "Third follow-up prompt"])
        XCTAssertEqual(structured.followUps.count, 3)
        XCTAssertEqual(structured.safetyNote, "Stop and seek care for chest pain or dizziness.")
        XCTAssertNotNil(structured.status)
        XCTAssertFalse(structured.metrics.isEmpty)
        XCTAssertFalse(structured.sources.isEmpty)
    }

    func testLegacyCoachResponseWithoutTitleSummaryHasNoStructuredResponse() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "t", name: CoachToolCatalog.coachResponseName, input: .object([
                    "content": .string("Just text.")
                ]))
            ], stopReason: "tool_use")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "How am I?", model: "claude-test", apiKey: "test-key", in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        let assistant = try XCTUnwrap(messages.last { $0.role == .assistant })

        XCTAssertNil(assistant.structuredResponse)
        XCTAssertEqual(assistant.text, "Just text.")
    }


    func testDecodingErrorCoachDetailNamesMissingKey() {
        let json = Data("{}".utf8)
        do {
            _ = try JSONDecoder().decode(RequiresField.self, from: json)
            XCTFail("Expected decode to throw")
        } catch let error as DecodingError {
            XCTAssertTrue(error.coachDetail.contains("field"))
            XCTAssertTrue(error.coachDetail.contains("name"))
        } catch {
            XCTFail("Expected DecodingError, got \(error)")
        }
    }

    func testCoachResponseWithoutContentRendersInsteadOfFailing() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_resp", name: CoachToolCatalog.coachResponseName, input: .object([
                    "interaction": .object([
                        "id": .string("next_step"),
                        "type": .string("single_choice"),
                        "options": .array([
                            .object(["id": .string("a"), "label": .string("A"), "value": .string("A")]),
                            .object(["id": .string("b"), "label": .string("B"), "value": .string("B")])
                        ]),
                        "allowOther": .bool(false),
                        "status": .string("pending")
                    ])
                ]))
            ], stopReason: "tool_use")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Review this run.", model: "claude-test", apiKey: "test-key", in: context)

        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertNotEqual(assistant.assistantStatus, .failed)
        XCTAssertNil(assistant.errorCategory)
        XCTAssertNil(assistant.errorDetail)
        XCTAssertEqual(assistant.interaction?.options.map(\.id), ["a", "b"])
    }

    func testVietnamesePlanAdjustmentDraftClassifiesAsPlanMutation() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("ok")], stopReason: "end_turn")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Hãy tạo bản nháp điều chỉnh kế hoạch đã được kiểm tra để tôi xem trước.",
            model: "claude-test",
            apiKey: "test-key",
            in: context
        )

        let snapshot = try XCTUnwrap(try context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(snapshot.actionType, .planMutation)
    }

    func testVietnameseKeepPlanChoiceStaysReadOnly() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("ok")], stopReason: "end_turn")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Giữ nguyên kế hoạch hiện tại.",
            model: "claude-test",
            apiKey: "test-key",
            in: context
        )

        let snapshot = try XCTUnwrap(try context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(snapshot.actionType, .readOnly)
    }

    func testJapanesePlanAdjustmentDraftClassifiesAsPlanMutation() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("ok")], stopReason: "end_turn")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "確認用の計画調整案を作成してください。",
            model: "claude-test",
            apiKey: "test-key",
            in: context
        )

        let snapshot = try XCTUnwrap(try context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(snapshot.actionType, .planMutation)
    }

    func testPlanRejectionSurfacesRawReasonForMissingWorkout() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let coordinator = WorkoutReplacementCoordinator(container: container)
        let replaceNoWorkout = ClaudeResponse(content: [
            .toolUse(id: "toolu_bad", name: CoachTools.toolName, input: .object([
                "changes": .array([.object([
                    "date": .string(CoachContextBuilder.day(qualityDay, calendar: calendar)),
                    "action": .string("replace")
                ])])
            ]))
        ], stopReason: "tool_use")
        let client = MockClaudeClient(responses: Array(repeating: replaceNoWorkout, count: CoachChatConfig.maxToolRounds))
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today }, replacementCoordinator: coordinator)

        await store.send(text: "Điều chỉnh kế hoạch giúp tôi.", model: "claude-test", apiKey: "test-key", in: context)

        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertTrue(assistant.text.contains("chưa đọc được buổi chạy"), "expected missing-workout message, got: \(assistant.text)")
        XCTAssertTrue(assistant.text.lowercased().contains("requires a workout"), "raw reason should be surfaced, got: \(assistant.text)")
    }

    func testPlanRejectionForPastDateIsNotMislabeledAsMissingWorkout() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let coordinator = WorkoutReplacementCoordinator(container: container)
        let pastDay = PlanEngineTestSupport.date(2026, 1, 1)
        let downgradePast = ClaudeResponse(content: [
            .toolUse(id: "toolu_past", name: CoachTools.toolName, input: .object([
                "changes": .array([.object([
                    "date": .string(CoachContextBuilder.day(pastDay, calendar: calendar)),
                    "action": .string("downgrade")
                ])])
            ]))
        ], stopReason: "tool_use")
        let client = MockClaudeClient(responses: Array(repeating: downgradePast, count: CoachChatConfig.maxToolRounds))
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today }, replacementCoordinator: coordinator)

        await store.send(text: "Điều chỉnh kế hoạch giúp tôi.", model: "claude-test", apiKey: "test-key", in: context)

        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertFalse(assistant.text.contains("chưa đọc được buổi chạy"), "past-date error must not be mislabeled as missing workout, got: \(assistant.text)")
        XCTAssertTrue(assistant.text.lowercased().contains("past"), "raw reason should be surfaced, got: \(assistant.text)")
    }

    func testRetryDetourDoesNotClobberUnderlyingValidationReason() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let coordinator = WorkoutReplacementCoordinator(container: container)
        let invalidPropose = ClaudeResponse(content: [
            .toolUse(id: "toolu_bad", name: CoachTools.toolName, input: .object([
                "changes": .array([.object([
                    "date": .string(CoachContextBuilder.day(qualityDay, calendar: calendar)),
                    "action": .string("replace")
                ])])
            ]))
        ], stopReason: "tool_use")
        let detour = ClaudeResponse(content: [
            .text("Bạn có thể xác nhận lại định dạng JSON của plan_adjustment tool giúp mình không?")
        ], stopReason: "end_turn")
        let client = MockClaudeClient(responses: [invalidPropose] + Array(repeating: detour, count: CoachChatConfig.maxToolRounds - 1))
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today }, replacementCoordinator: coordinator)

        await store.send(text: "Điều chỉnh kế hoạch giúp tôi.", model: "claude-test", apiKey: "test-key", in: context)

        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertTrue(assistant.text.lowercased().contains("requires a workout"), "underlying validation reason should survive the retry nudge, got: \(assistant.text)")
        XCTAssertFalse(assistant.text.contains("Plan edits must be submitted"), "retry nudge must not replace the real reason, got: \(assistant.text)")
    }

    func testCreateWithMalformedWorkoutSurfacesFieldNotMissingWorkout() throws {
        // Step is missing pace_zone: the workout is present but malformed. It
        // must surface the field, not be hidden as an absent workout.
        let json = Data("""
        {"changes":[{"date":"2026-01-07","action":"create","workout":{"kind":"easy","blocks":[{"repeat_count":1,"steps":[{"role":"work","target_type":"distance_km","target_value":8}]}]}}]}
        """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PlanAdjustmentProposal.self, from: json)) { error in
            let detail = (error as? DecodingError)?.coachDetail ?? "\(error)"
            XCTAssertTrue(detail.lowercased().contains("pace_zone"), "should name the missing field, got: \(detail)")
        }
    }

    func testCreateWithCompleteWorkoutDecodesSuccessfully() throws {
        let json = Data("""
        {"changes":[{"date":"2026-01-07","action":"create","workout":{"kind":"easy","blocks":[{"repeat_count":1,"steps":[{"role":"work","target_type":"distance_km","target_value":8,"pace_zone":"easy"}]}]}}]}
        """.utf8)
        let proposal = try JSONDecoder().decode(PlanAdjustmentProposal.self, from: json)
        XCTAssertEqual(proposal.changes.first?.workout?.kind, "easy")
        XCTAssertEqual(proposal.changes.first?.workout?.blocks.first?.steps.first?.paceZone, "easy")
    }

    func testBareCreateWithoutWorkoutKeyDecodesToNilWorkout() throws {
        let json = Data("""
        {"changes":[{"date":"2026-01-07","action":"create"}]}
        """.utf8)
        let proposal = try JSONDecoder().decode(PlanAdjustmentProposal.self, from: json)
        XCTAssertNil(proposal.changes.first?.workout)
    }

    func testDismissingInlineFailurePersistsDismissedTurn() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(error: ClaudeClientError.connectionLost)
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Create workout tomorrow.", model: "claude-test", apiKey: "test-key", in: context)

        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        store.dismissFailedResponse(failed.turnID, in: context)

        XCTAssertNil(store.lastError)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.first?.text, "Create workout tomorrow.")
        XCTAssertEqual(messages.last?.assistantStatus, .dismissed)
    }

    func testDismissingInlineFailureWorksAfterLongChatHistory() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        try seedLongChatHistory(in: context, count: 240)
        let client = MockClaudeClient(error: ClaudeClientError.connectionLost)
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Create workout tomorrow.", model: "claude-test", apiKey: "test-key", in: context)

        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(failed.assistantStatus, .failed)

        store.dismissFailedResponse(failed.turnID, in: context)

        XCTAssertEqual(failed.assistantStatus, .dismissed)
        XCTAssertNil(failed.errorCategory)
        XCTAssertNil(failed.errorMessage)
    }

    func testRetryFailedCoachResponseDoesNotDuplicateUserMessage() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(results: [
            .failure(ClaudeClientError.connectionLost),
            .success(ClaudeResponse(content: [.text("Run easy today.")], stopReason: "end_turn"))
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "What should I do today?", model: "claude-test", apiKey: "test-key", in: context)
        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(failed.assistantStatus, .failed)

        await store.retryFailedResponse(failed.turnID, model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertNil(store.lastError)
        XCTAssertEqual(client.requests.count, 2)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.map(\.text), ["What should I do today?", "Run easy today."])
        XCTAssertEqual(messages.last?.turnID, failed.turnID)
        XCTAssertEqual(messages.last?.attemptCount, 2)
        XCTAssertEqual(messages.last?.assistantStatus, .completed)
    }

    func testRetryFailedCoachResponseWorksAfterLongChatHistory() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        try seedLongChatHistory(in: context, count: 240)
        let client = MockClaudeClient(results: [
            .failure(ClaudeClientError.connectionLost),
            .success(ClaudeResponse(content: [.text("Retry recovered.")], stopReason: "end_turn"))
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "What should I do today?", model: "claude-test", apiKey: "test-key", in: context)
        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(failed.assistantStatus, .failed)

        await store.retryFailedResponse(failed.turnID, model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(failed.text, "Retry recovered.")
        XCTAssertEqual(failed.attemptCount, 2)
        XCTAssertEqual(failed.assistantStatus, .completed)
    }

    func testFailedRetryReusesSameInlineCard() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(results: [
            .failure(ClaudeClientError.connectionLost),
            .failure(ClaudeClientError.offline)
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "What should I do today?", model: "claude-test", apiKey: "test-key", in: context)
        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(failed.assistantStatus, .failed)

        await store.retryFailedResponse(failed.turnID, model: "claude-test", apiKey: "test-key", in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.last?.turnID, failed.turnID)
        XCTAssertEqual(messages.last?.assistantStatus, .failed)
        XCTAssertEqual(messages.last?.attemptCount, 2)
        XCTAssertEqual(messages.last?.errorCategory, .offline)
    }

    func testPartialStreamingFailureKeepsIncompleteTextAndRetryReplacesIt() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(streamScripts: [
            .partialTextThenFailure("Dựa trên tải tập tuần này, cơ thể anh đang", ClaudeClientError.connectionLost),
            .response(ClaudeResponse(content: [.text("Hôm nay chạy easy 6 km là hợp lý.")], stopReason: "end_turn"))
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Tải tập tuần này thế nào?", model: "claude-test", apiKey: "test-key", in: context)

        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(failed.assistantStatus, .failed)
        XCTAssertTrue(failed.isIncomplete)
        XCTAssertEqual(failed.text, "Dựa trên tải tập tuần này, cơ thể anh đang")

        await store.retryFailedResponse(failed.turnID, model: "claude-test", apiKey: "test-key", in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.last?.turnID, failed.turnID)
        XCTAssertEqual(messages.last?.text, "Hôm nay chạy easy 6 km là hợp lý.")
        XCTAssertEqual(messages.last?.assistantStatus, .completed)
        XCTAssertFalse(messages.last?.isIncomplete ?? true)
    }

    func testRetryUsesSnapshotAttachmentsNotCurrentComposerState() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let activity = try XCTUnwrap(try context.fetch(FetchDescriptor<CompletedActivity>()).first)
        let client = MockClaudeClient(results: [
            .failure(ClaudeClientError.connectionLost),
            .success(ClaudeResponse(content: [.text("Snapshot data reused.")], stopReason: "end_turn"))
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Review original run.",
            model: "claude-test",
            attachments: [.health, .completedActivity(activity.hkUUID)],
            evidence: EvidenceSelection(readinessSnapshot: true, weekPlan: true, workout: .completed(activity.hkUUID)),
            apiKey: "test-key",
            in: context
        )
        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)

        await store.retryFailedResponse(failed.turnID, model: "claude-test", apiKey: "test-key", in: context)

        let retryRequest = try XCTUnwrap(client.requests.last)
        XCTAssertTrue(retryRequest.messages.last?.content.textContent.contains("Selected completed run context") == true)
        XCTAssertTrue(retryRequest.messages.last?.content.textContent.contains("Health snapshot:") == true)
        let snapshots = try context.fetch(FetchDescriptor<CoachRequestSnapshot>())
        XCTAssertEqual(snapshots.first?.attachmentReferences.map(\.kind), [.health, .completedActivity])
    }

    func testRetryShowsMissingAttachmentWhenOriginalReferenceExpired() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let activity = try XCTUnwrap(try context.fetch(FetchDescriptor<CompletedActivity>()).first)
        let client = MockClaudeClient(results: [
            .failure(ClaudeClientError.connectionLost),
            .success(ClaudeResponse(content: [.text("Should not run.")], stopReason: "end_turn"))
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Review this run.",
            model: "claude-test",
            attachments: [.completedActivity(activity.hkUUID)],
            apiKey: "test-key",
            in: context
        )
        let failed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        context.delete(activity)
        try context.save()

        await store.retryFailedResponse(failed.turnID, model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertEqual(failed.assistantStatus, .failed)
        XCTAssertEqual(failed.errorCategory, .missingAttachment)
        XCTAssertTrue(failed.errorMessage?.contains("Dữ liệu sức khỏe") == true || failed.errorMessage?.contains("attached health data") == true)
        XCTAssertEqual(client.requests.count, 1, "expired required data must not silently retry")
    }

    func testOlderFailedTurnCannotRewriteLaterConversation() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(results: [
            .failure(ClaudeClientError.connectionLost),
            .success(ClaudeResponse(content: [.text("Later answer.")], stopReason: "end_turn")),
            .success(ClaudeResponse(content: [.text("Should not replace older.")], stopReason: "end_turn"))
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "First question?", model: "claude-test", apiKey: "test-key", in: context)
        let olderFailed = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        await store.send(text: "Second question?", model: "claude-test", apiKey: "test-key", in: context)

        await store.retryFailedResponse(olderFailed.turnID, model: "claude-test", apiKey: "test-key", in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(olderFailed.assistantStatus, .failed)
        XCTAssertEqual(olderFailed.errorCategory, .nonRetryable)
        XCTAssertEqual(client.requests.count, 2)
    }

    /// A truncated turn may carry a half-written tool input: never execute it.
    func testChatStoreRefusesToApplyTruncatedToolCall() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let before = try context.fetch(FetchDescriptor<PlannedWorkout>()).count
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object(["changes": .array([])]))
            ], stopReason: "max_tokens")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Rebuild my week.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannedWorkout>()).count, before)
        XCTAssertEqual(client.requests.count, 1, "a truncated turn must not start another round")
        XCTAssertNotNil(store.lastError)
    }

    func testMessageTopInsetClearsHeaderAndAdaptsToHeight() {
        XCTAssertEqual(
            CoachHeaderMetrics.messageTopInset(headerHeight: 48),
            48 + 8 + 14
        )
        XCTAssertGreaterThan(
            CoachHeaderMetrics.messageTopInset(headerHeight: 80),
            CoachHeaderMetrics.messageTopInset(headerHeight: 48)
        )
        XCTAssertEqual(
            CoachHeaderMetrics.messageTopInset(headerHeight: 10),
            CoachHeaderMetrics.fallbackHeaderHeight + 8 + 14
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self,
            CoachRequestSnapshot.self, CoachMemoryItem.self, CoachPromptSuggestionRecord.self
        ])
        let configuration = ModelConfiguration("ChatFeatureTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func hydrationReadiness() -> DailyReadiness {
        DailyReadiness(
            date: today,
            assessment: ReadinessAssessment(
                verdict: .rest,
                score: 60,
                reasons: [],
                ruleIDs: [.loadRamp],
                baselineDayCount: 28,
                snapshot: .init(
                    hrvMean7: 45,
                    hrvMean28: nil,
                    rhrMean7: nil,
                    rhrMean28: nil,
                    sleepLastNight: 7.0,
                    sleepMean14: nil,
                    acuteChronicRatio: 1.2
                )
            ),
            computedAt: today
        )
    }

    private func hydrationContextItems() -> [CoachContextItem] {
        [
            .init(type: .healthData, label: "Health"),
            .init(type: .completedRun, label: "Completed run"),
            .init(type: .trainingPlan, label: "Training plan"),
            .init(type: .healthData, label: "Health duplicate")
        ]
    }

    private func seedTrainingData(in context: ModelContext) throws {
        try seedGoalOnly(in: context)

        context.insert(activity(
            on: calendar.date(byAdding: .day, value: -1, to: today)!,
            km: 10,
            minutes: 55,
            avgHeartRate: 145,
            maxHeartRate: 168
        ))
        context.insert(SyncState(domain: SyncState.workoutsDomain, lastSyncAt: today))
        context.insert(DailyReadiness(
            date: calendar.startOfDay(for: today),
            assessment: ReadinessAssessment(
                verdict: .train,
                reasons: [],
                baselineDayCount: 28,
                snapshot: .init(
                    hrvMean7: 52, hrvMean28: 51,
                    rhrMean7: 48, rhrMean28: 49,
                    sleepLastNight: 7.4, sleepMean14: 7.2,
                    acuteChronicRatio: 1.0
                )
            ),
            computedAt: today
        ))
        try context.save()
    }

    private func seedLongChatHistory(in context: ModelContext, count: Int) throws {
        let threadID = UUID()
        for index in 0..<count {
            let date = today.addingTimeInterval(TimeInterval(index - count) * 60)
            let turn = ChatMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "Historical chat row \(index)",
                date: date,
                threadID: threadID,
                status: index.isMultiple(of: 2) ? nil : .completed
            )
            context.insert(turn)
            context.insert(CoachRequestSnapshot(
                userTurnID: UUID(),
                messageText: "Historical snapshot \(index)",
                attachmentReferences: [],
                selectedEvidenceSources: EvidenceSelection(),
                contextBoundaryMessageID: UUID(),
                locale: CoachLanguage.en.rawValue,
                createdAt: date,
                actionType: .readOnly,
                groundingSnapshot: nil,
                threadID: threadID
            ))
        }
        try context.save()
    }

    private func activity(
        on date: Date,
        km: Double,
        minutes: Double,
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil
    ) -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: date,
            distanceMeters: km * 1000,
            durationSeconds: minutes * 60,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            avgPaceSecondsPerKm: minutes * 60 / km,
            sourceName: "Garmin"
        )
    }

    /// Every weekday available, which leaves the generator a genuinely free day
    /// for the coach to create on.
    private func seedEveryDayPlan(in context: ModelContext) throws {
        let goal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 4, 19),
            availableDays: Set(Weekday.allCases),
            longRunDay: .sunday
        )
        let fitness = FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0, longestRecentRunKm: 16)
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)
    }

    private func seedGoalOnly(in context: ModelContext) throws {
        let goal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 4, 19),
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday
        )
        let fitness = FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0, longestRecentRunKm: 16)
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)
    }

    private func plannedWorkouts(on date: Date, in context: ModelContext) throws -> [PlannedWorkout] {
        let day = calendar.startOfDay(for: date)
        return try context.fetch(FetchDescriptor<PlannedWorkout>()).filter {
            calendar.isDate($0.date, inSameDayAs: day)
        }
    }
}

@MainActor
private final class MockClaudeClient: ClaudeServicing {
    enum StreamScript {
        case response(ClaudeResponse)
        case failure(Error)
        case partialTextThenFailure(String, Error)
    }

    private var responses: [ClaudeResponse]
    private let error: Error?
    private var results: [Result<ClaudeResponse, Error>]
    private var streamScripts: [StreamScript]
    private(set) var requests: [ClaudeRequest] = []

    init(responses: [ClaudeResponse] = [], error: Error? = nil) {
        self.responses = responses
        self.error = error
        self.results = []
        self.streamScripts = []
    }

    init(results: [Result<ClaudeResponse, Error>]) {
        self.responses = []
        self.error = nil
        self.results = results
        self.streamScripts = []
    }

    init(streamScripts: [StreamScript]) {
        self.responses = []
        self.error = nil
        self.results = []
        self.streamScripts = streamScripts
    }

    func send(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse {
        requests.append(request)
        if !results.isEmpty {
            return try results.removeFirst().get()
        }
        if let error { throw error }
        return responses.removeFirst()
    }

    func stream(_ request: ClaudeRequest, apiKey: String) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        requests.append(request)
        if !streamScripts.isEmpty {
            let script = streamScripts.removeFirst()
            return AsyncThrowingStream { continuation in
                switch script {
                case .response(let response):
                    continuation.yield(.messageStart)
                    for (index, block) in response.content.enumerated() {
                        switch block {
                        case .text(let text):
                            continuation.yield(.contentBlockStart(index: index, kind: .text))
                            continuation.yield(.textDelta(index: index, text))
                            continuation.yield(.contentBlockStop(index: index))
                        case let .toolUse(id, name, input):
                            continuation.yield(.contentBlockStart(index: index, kind: .toolUse(id: id, name: name)))
                            if let data = try? JSONEncoder().encode(input),
                               let json = String(data: data, encoding: .utf8) {
                                continuation.yield(.inputJSONDelta(index: index, json))
                            }
                            continuation.yield(.contentBlockStop(index: index))
                        case .image, .toolResult, .passthrough:
                            break
                        }
                    }
                    continuation.yield(.messageDelta(stopReason: response.stopReason))
                    continuation.yield(.messageStop)
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                case .partialTextThenFailure(let text, let error):
                    continuation.yield(.messageStart)
                    continuation.yield(.contentBlockStart(index: 0, kind: .text))
                    continuation.yield(.textDelta(index: 0, text))
                    continuation.finish(throwing: error)
                }
            }
        }
        if !results.isEmpty {
            let result = results.removeFirst()
            return AsyncThrowingStream { continuation in
                do {
                    let response = try result.get()
                    continuation.yield(.messageStart)
                    for (index, block) in response.content.enumerated() {
                        if case .text(let text) = block {
                            continuation.yield(.contentBlockStart(index: index, kind: .text))
                            continuation.yield(.textDelta(index: index, text))
                            continuation.yield(.contentBlockStop(index: index))
                        }
                    }
                    continuation.yield(.messageDelta(stopReason: response.stopReason))
                    continuation.yield(.messageStop)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        if let error {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return Self.stream(from: responses.removeFirst())
    }

    private static func stream(from response: ClaudeResponse) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.messageStart)
            for (index, block) in response.content.enumerated() {
                switch block {
                case .text(let text):
                    continuation.yield(.contentBlockStart(index: index, kind: .text))
                    continuation.yield(.textDelta(index: index, text))
                    continuation.yield(.contentBlockStop(index: index))
                case let .toolUse(id, name, input):
                    continuation.yield(.contentBlockStart(index: index, kind: .toolUse(id: id, name: name)))
                    if let data = try? JSONEncoder().encode(input),
                       let json = String(data: data, encoding: .utf8) {
                        continuation.yield(.inputJSONDelta(index: index, json))
                    }
                    continuation.yield(.contentBlockStop(index: index))
                case .image, .toolResult, .passthrough:
                    break
                }
            }
            continuation.yield(.messageDelta(stopReason: response.stopReason))
            continuation.yield(.messageStop)
            continuation.finish()
        }
    }
}
