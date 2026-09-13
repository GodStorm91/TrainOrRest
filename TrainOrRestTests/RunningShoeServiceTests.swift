import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class RunningShoeServiceTests: XCTestCase {
    func testAutoAssignmentDisabledReturnsNone() {
        let shoe = makeShoe(types: [.easy])
        let preferences = RunningShoePreferences(shoeAutoAssignmentEnabled: false)

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .easy,
            activeShoes: [shoe],
            preferences: preferences,
            existingShoeID: nil,
            existingAssignmentSource: .none
        )

        XCTAssertNil(result.shoeID)
        XCTAssertEqual(result.source, .none)
    }

    func testNoActiveShoesReturnsNone() {
        let shoe = makeShoe(types: [.easy], status: .retired)

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .easy,
            activeShoes: [shoe],
            preferences: RunningShoePreferences(),
            existingShoeID: nil,
            existingAssignmentSource: .none
        )

        XCTAssertNil(result.shoeID)
    }

    func testSingleMatchingShoeIsSelected() {
        let shoe = makeShoe(types: [.easy])

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .easy,
            activeShoes: [shoe],
            preferences: RunningShoePreferences(),
            existingShoeID: nil,
            existingAssignmentSource: .none
        )

        XCTAssertEqual(result.shoeID, shoe.id)
        XCTAssertEqual(result.source, .auto)
    }

    func testBestMatchPrefersPrimaryUse() {
        let preferred = makeShoe(model: "Daily", types: [.easy, .longRun], primary: .easy)
        let primary = makeShoe(model: "Long", types: [.easy, .longRun], primary: .longRun)

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .longRun,
            activeShoes: [preferred, primary],
            preferences: RunningShoePreferences(),
            existingShoeID: nil,
            existingAssignmentSource: .none
        )

        XCTAssertEqual(result.shoeID, primary.id)
    }

    func testNewestMatchedStrategyPrefersNewestMatchingShoe() {
        let old = makeShoe(model: "Old", types: [.easy], createdAt: Date(timeIntervalSince1970: 1))
        let newest = makeShoe(model: "New", types: [.easy], createdAt: Date(timeIntervalSince1970: 2))
        let preferences = RunningShoePreferences(shoeAutoAssignmentStrategy: .newestMatched)

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .easy,
            activeShoes: [old, newest],
            preferences: preferences,
            existingShoeID: nil,
            existingAssignmentSource: .none
        )

        XCTAssertEqual(result.shoeID, newest.id)
    }

    func testRotateMatchedStrategyPrefersLeastRecentlyUsed() {
        let used = makeShoe(model: "Used", types: [.easy])
        let fresh = makeShoe(model: "Fresh", types: [.easy])
        let entries = [
            ShoeMileageEntry(
                shoeID: used.id,
                activityID: UUID(),
                distanceKm: 8,
                createdAt: Date(timeIntervalSince1970: 10)
            )
        ]
        let preferences = RunningShoePreferences(shoeAutoAssignmentStrategy: .rotateMatched)

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .easy,
            activeShoes: [used, fresh],
            preferences: preferences,
            existingShoeID: nil,
            existingAssignmentSource: .none,
            mileageEntries: entries
        )

        XCTAssertEqual(result.shoeID, fresh.id)
    }

    func testNearRetirementShoeIsExcludedWhenAnotherMatchExists() {
        let aging = makeShoe(model: "Aging", types: [.longRun], initialMileage: 570, expected: 600)
        let safe = makeShoe(model: "Safe", types: [.longRun], initialMileage: 120, expected: 600)

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .longRun,
            activeShoes: [aging, safe],
            preferences: RunningShoePreferences(avoidNearRetirementShoes: true, nearRetirementThresholdPercent: 90),
            existingShoeID: nil,
            existingAssignmentSource: .none
        )

        XCTAssertEqual(result.shoeID, safe.id)
        XCTAssertFalse(result.isNearMileageRange)
    }

    func testFallsBackWhenAllMatchingShoesAreNearRetirement() {
        let aging = makeShoe(model: "Aging", types: [.tempo], initialMileage: 570, expected: 600)

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .tempo,
            activeShoes: [aging],
            preferences: RunningShoePreferences(avoidNearRetirementShoes: true, nearRetirementThresholdPercent: 90),
            existingShoeID: nil,
            existingAssignmentSource: .none
        )

        XCTAssertEqual(result.shoeID, aging.id)
        XCTAssertTrue(result.isNearMileageRange)
    }

    func testManualAssignmentIsPreserved() {
        let manual = makeShoe(model: "Manual", types: [.race])
        let auto = makeShoe(model: "Auto", types: [.easy])

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .easy,
            activeShoes: [manual, auto],
            preferences: RunningShoePreferences(),
            existingShoeID: manual.id,
            existingAssignmentSource: .manual
        )

        XCTAssertEqual(result.shoeID, manual.id)
        XCTAssertEqual(result.source, .manual)
    }

    func testRetiredShoeIgnored() {
        let retired = makeShoe(model: "Retired", types: [.easy], status: .retired)
        let active = makeShoe(model: "Active", types: [.easy])

        let result = ShoeAssignmentService.selectShoeForWorkout(
            workoutType: .easy,
            activeShoes: [retired, active],
            preferences: RunningShoePreferences(),
            existingShoeID: nil,
            existingAssignmentSource: .none
        )

        XCTAssertEqual(result.shoeID, active.id)
    }


    func testUnassignedSyncedActivityGetsShoeAndMileageAutomatically() throws {
        let schema = Schema([
            RunningShoe.self,
            ShoeMileageEntry.self,
            RunningShoePreferences.self,
            CompletedActivity.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let shoe = makeShoe(types: [.easy], primary: .easy)
        let activity = CompletedActivity(
            hkUUID: UUID(),
            date: .now,
            distanceMeters: 8_200,
            durationSeconds: 2_700,
            avgHeartRate: 145,
            maxHeartRate: 168,
            avgPaceSecondsPerKm: 329,
            sourceName: "Garmin"
        )
        context.insert(shoe)
        context.insert(activity)

        try ShoeAssignmentService.assignAutomaticShoesToUnassignedActivities(in: context)
        try context.save()

        XCTAssertEqual(activity.shoeID, shoe.id)
        XCTAssertEqual(activity.shoeAssignmentSource, .auto)
        XCTAssertEqual(
            try ShoeMileageService.currentMileageKm(for: shoe, in: context),
            8.2,
            accuracy: 0.001
        )
    }
    func testActivityAddsMileage() {
        let shoe = makeShoe(initialMileage: 10)
        let activityID = UUID()

        let ledger = ShoeMileageService.applyingMileage(
            activityID: activityID,
            shoeID: shoe.id,
            distanceKm: 7,
            to: []
        )

        XCTAssertEqual(ShoeMileageService.currentMileageKm(for: shoe, ledger: ledger), 17, accuracy: 0.001)
    }

    func testDuplicateSyncDoesNotDoubleCount() {
        let shoe = makeShoe()
        let activityID = UUID()

        var ledger = ShoeMileageService.applyingMileage(activityID: activityID, shoeID: shoe.id, distanceKm: 7, to: [])
        ledger = ShoeMileageService.applyingMileage(activityID: activityID, shoeID: shoe.id, distanceKm: 7, to: ledger)

        XCTAssertEqual(ledger.count, 1)
        XCTAssertEqual(ShoeMileageService.currentMileageKm(for: shoe, ledger: ledger), 7, accuracy: 0.001)
    }

    func testActivityDeletionRemovesMileage() {
        let shoe = makeShoe()
        let activityID = UUID()
        let ledger = [
            ShoeMileageEntry(shoeID: shoe.id, activityID: activityID, distanceKm: 7)
        ]

        let updated = ShoeMileageService.applyingMileage(activityID: activityID, shoeID: nil, distanceKm: nil, to: ledger)

        XCTAssertEqual(ShoeMileageService.currentMileageKm(for: shoe, ledger: updated), 0, accuracy: 0.001)
    }

    func testActivityDistanceEditUpdatesMileage() {
        let shoe = makeShoe()
        let activityID = UUID()
        let ledger = [
            ShoeMileageEntry(shoeID: shoe.id, activityID: activityID, distanceKm: 7)
        ]

        let updated = ShoeMileageService.applyingMileage(activityID: activityID, shoeID: shoe.id, distanceKm: 9.5, to: ledger)

        XCTAssertEqual(ShoeMileageService.currentMileageKm(for: shoe, ledger: updated), 9.5, accuracy: 0.001)
    }

    func testShoeReassignmentMovesMileage() {
        let first = makeShoe(model: "First")
        let second = makeShoe(model: "Second")
        let activityID = UUID()
        let ledger = [
            ShoeMileageEntry(shoeID: first.id, activityID: activityID, distanceKm: 7)
        ]

        let updated = ShoeMileageService.applyingMileage(activityID: activityID, shoeID: second.id, distanceKm: 7, to: ledger)

        XCTAssertEqual(ShoeMileageService.currentMileageKm(for: first, ledger: updated), 0, accuracy: 0.001)
        XCTAssertEqual(ShoeMileageService.currentMileageKm(for: second, ledger: updated), 7, accuracy: 0.001)
    }

    func testWearStateBoundaries() {
        XCTAssertEqual(ShoeWearStatusService.wearStatus(currentMileageKm: 79, expectedLifespanKm: 100), .normal)
        XCTAssertEqual(ShoeWearStatusService.wearStatus(currentMileageKm: 80, expectedLifespanKm: 100), .approaching)
        XCTAssertEqual(ShoeWearStatusService.wearStatus(currentMileageKm: 89, expectedLifespanKm: 100), .approaching)
        XCTAssertEqual(ShoeWearStatusService.wearStatus(currentMileageKm: 90, expectedLifespanKm: 100), .inspect)
        XCTAssertEqual(ShoeWearStatusService.wearStatus(currentMileageKm: 99, expectedLifespanKm: 100), .inspect)
        XCTAssertEqual(ShoeWearStatusService.wearStatus(currentMileageKm: 100, expectedLifespanKm: 100), .pastRange)
        XCTAssertEqual(ShoeWearStatusService.wearStatus(currentMileageKm: 105, expectedLifespanKm: 100), .pastRange)
    }

    func testInheritPlannedShoeCopiesWhenActivityHasNone() {
        let shoeID = UUID()
        let planned = PlannedWorkout(
            spec: PlannedWorkoutSpec(date: Date(), kind: .easy, distanceKm: 8, paceBand: nil, details: ""),
            weekIndex: 0,
            phase: .base
        )
        planned.shoeID = shoeID
        planned.shoeAssignmentSource = .auto

        let activity = makeActivity()

        XCTAssertTrue(ShoeAssignmentService.inheritPlannedShoe(onto: activity, from: planned))
        XCTAssertEqual(activity.shoeID, shoeID)
        XCTAssertEqual(activity.shoeAssignmentSource, .auto)
    }

    func testInheritPlannedShoeDoesNotOverwriteExistingActivityShoe() {
        let planned = PlannedWorkout(
            spec: PlannedWorkoutSpec(date: Date(), kind: .easy, distanceKm: 8, paceBand: nil, details: ""),
            weekIndex: 0,
            phase: .base
        )
        planned.shoeID = UUID()
        planned.shoeAssignmentSource = .auto

        let existing = UUID()
        let activity = makeActivity()
        activity.shoeID = existing
        activity.shoeAssignmentSource = .manual

        XCTAssertFalse(ShoeAssignmentService.inheritPlannedShoe(onto: activity, from: planned))
        XCTAssertEqual(activity.shoeID, existing)
        XCTAssertEqual(activity.shoeAssignmentSource, .manual)
    }

    func testInheritPlannedShoeNoopsWithoutPlannedShoe() {
        let planned = PlannedWorkout(
            spec: PlannedWorkoutSpec(date: Date(), kind: .easy, distanceKm: 8, paceBand: nil, details: ""),
            weekIndex: 0,
            phase: .base
        )
        let activity = makeActivity()

        XCTAssertFalse(ShoeAssignmentService.inheritPlannedShoe(onto: activity, from: planned))
        XCTAssertFalse(ShoeAssignmentService.inheritPlannedShoe(onto: activity, from: nil))
        XCTAssertNil(activity.shoeID)
    }

    func testReminderStagesStartAtInspectionAndReplacementThresholds() {
        XCTAssertEqual(
            ShoeWearStatusService.reminderStage(currentMileageKm: 89, expectedLifespanKm: 100),
            .none
        )
        XCTAssertEqual(
            ShoeWearStatusService.reminderStage(currentMileageKm: 90, expectedLifespanKm: 100),
            .inspect
        )
        XCTAssertEqual(
            ShoeWearStatusService.reminderStage(currentMileageKm: 100, expectedLifespanKm: 100),
            .replace
        )
    }

    private func makeShoe(
        brand: String = "ASICS",
        model: String = "Superblast",
        types: [ShoeWorkoutType] = [.easy],
        primary: ShoeWorkoutType? = nil,
        status: RunningShoeStatus = .active,
        initialMileage: Double = 0,
        expected: Double = 600,
        createdAt: Date = .now
    ) -> RunningShoe {
        RunningShoe(
            brand: brand,
            model: model,
            initialMileageKm: initialMileage,
            status: status,
            preferredWorkoutTypes: types,
            primaryWorkoutType: primary ?? types.first,
            expectedLifespanKm: expected,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeActivity() -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: Date(),
            distanceMeters: 8000,
            durationSeconds: 2400,
            avgHeartRate: nil,
            maxHeartRate: nil,
            avgPaceSecondsPerKm: nil,
            sourceName: "test"
        )
    }

}
