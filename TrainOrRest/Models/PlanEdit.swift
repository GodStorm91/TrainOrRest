import Foundation
import SwiftData

struct PlanWorkoutReceiptSnapshot: Codable, Equatable {
    var uuid: UUID
    var date: Date
    var weekIndex: Int
    var phaseRaw: String
    var kindRaw: String
    var distanceKm: Double
    var paceFastSecondsPerKm: Double?
    var paceSlowSecondsPerKm: Double?
    var details: String
    var structure: [WorkoutStepGroup]
    var statusRaw: String
    var manuallyOverridden: Bool
    var matchedActivityUUID: UUID?
    var shoeID: UUID?
    var shoeAssignmentSourceRaw: String?
    var scheduleUpdatedFromRaw: String?
    var scheduleUpdatedAt: Date?
    var scheduleLock: Bool?

    init(
        uuid: UUID,
        date: Date,
        weekIndex: Int,
        phaseRaw: String,
        kindRaw: String,
        distanceKm: Double,
        paceFastSecondsPerKm: Double?,
        paceSlowSecondsPerKm: Double?,
        details: String,
        structure: [WorkoutStepGroup],
        statusRaw: String,
        manuallyOverridden: Bool,
        matchedActivityUUID: UUID?,
        shoeID: UUID?,
        shoeAssignmentSourceRaw: String?,
        scheduleUpdatedFromRaw: String?,
        scheduleUpdatedAt: Date?,
        scheduleLock: Bool?
    ) {
        self.uuid = uuid
        self.date = date
        self.weekIndex = weekIndex
        self.phaseRaw = phaseRaw
        self.kindRaw = kindRaw
        self.distanceKm = distanceKm
        self.paceFastSecondsPerKm = paceFastSecondsPerKm
        self.paceSlowSecondsPerKm = paceSlowSecondsPerKm
        self.details = details
        self.structure = structure
        self.statusRaw = statusRaw
        self.manuallyOverridden = manuallyOverridden
        self.matchedActivityUUID = matchedActivityUUID
        self.shoeID = shoeID
        self.shoeAssignmentSourceRaw = shoeAssignmentSourceRaw
        self.scheduleUpdatedFromRaw = scheduleUpdatedFromRaw
        self.scheduleUpdatedAt = scheduleUpdatedAt
        self.scheduleLock = scheduleLock
    }
    init(workout: PlannedWorkout) {
        uuid = workout.uuid
        date = workout.date
        weekIndex = workout.weekIndex
        phaseRaw = workout.phaseRaw
        kindRaw = workout.kindRaw
        distanceKm = workout.distanceKm
        paceFastSecondsPerKm = workout.paceFastSecondsPerKm
        paceSlowSecondsPerKm = workout.paceSlowSecondsPerKm
        details = workout.details
        structure = workout.structure
        statusRaw = workout.statusRaw
        manuallyOverridden = workout.manuallyOverridden
        matchedActivityUUID = workout.matchedActivityUUID
        shoeID = workout.shoeID
        shoeAssignmentSourceRaw = workout.shoeAssignmentSourceRaw
        scheduleUpdatedFromRaw = workout.scheduleUpdatedFromRaw
        scheduleUpdatedAt = workout.scheduleUpdatedAt
        scheduleLock = workout.scheduleLock
    }

    func apply(to workout: PlannedWorkout) {
        workout.uuid = uuid
        workout.date = date
        workout.weekIndex = weekIndex
        workout.phaseRaw = phaseRaw
        workout.kindRaw = kindRaw
        workout.distanceKm = distanceKm
        workout.paceFastSecondsPerKm = paceFastSecondsPerKm
        workout.paceSlowSecondsPerKm = paceSlowSecondsPerKm
        workout.details = details
        workout.structure = structure
        workout.statusRaw = statusRaw
        workout.manuallyOverridden = manuallyOverridden
        workout.matchedActivityUUID = matchedActivityUUID
        workout.shoeID = shoeID
        workout.shoeAssignmentSourceRaw = shoeAssignmentSourceRaw
        workout.scheduleUpdatedFromRaw = scheduleUpdatedFromRaw
        workout.scheduleUpdatedAt = scheduleUpdatedAt
        workout.scheduleLock = scheduleLock
    }

    func makeWorkout(plan: TrainingPlan) -> PlannedWorkout {
        let kind = WorkoutKind(rawValue: kindRaw) ?? .easy
        let phase = TrainingPhase(rawValue: phaseRaw) ?? .base
        let row = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: date,
                kind: kind,
                distanceKm: distanceKm,
                paceBand: paceFastSecondsPerKm.flatMap { fast in
                    paceSlowSecondsPerKm.map { PaceBand(fastSecondsPerKm: fast, slowSecondsPerKm: $0) }
                },
                details: details,
                structure: structure
            ),
            weekIndex: weekIndex,
            phase: phase
        )
        apply(to: row)
        row.plan = plan
        return row
    }
}

struct PlanEditOperation: Codable, Equatable {
    var before: PlanWorkoutReceiptSnapshot?
    var after: PlanWorkoutReceiptSnapshot?
}

struct PlanEditWeekTarget: Codable, Equatable {
    var weekIndex: Int
    var before: Double
    var after: Double
}

struct PlanEditTransaction: Codable, Equatable {
    var operations: [PlanEditOperation]
    var weekTargets: [PlanEditWeekTarget]
}

enum PlanEditReceiptCodec {
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    static func encode(_ transaction: PlanEditTransaction) throws -> Data {
        try encoder().encode(transaction)
    }

    static func decode(_ data: Data) throws -> PlanEditTransaction {
        try decoder().decode(PlanEditTransaction.self, from: data)
    }

    static func canonicalized(_ transaction: PlanEditTransaction) throws -> PlanEditTransaction {
        try decode(encode(transaction))
    }

    static func snapshotsMatch(
        _ current: PlanWorkoutReceiptSnapshot,
        _ expected: PlanWorkoutReceiptSnapshot
    ) -> Bool {
        guard let currentData = try? encoder().encode(current),
              let expectedData = try? encoder().encode(expected) else {
            return false
        }
        return currentData == expectedData
    }
}

/// Journal entry for an applied coach plan transaction. New rows store an exact,
/// reversible receipt; legacy replacement rows keep their original fields.
@Model
final class PlanEdit {
    @Attribute(.unique) var id: UUID
    var appliedAt: Date
    var workoutUUID: UUID
    var workoutDate: Date
    var weekIndex: Int

    var kindRaw: String
    var distanceKm: Double
    var paceFastSecondsPerKm: Double?
    var paceSlowSecondsPerKm: Double?
    var details: String
    var structure: [WorkoutStepGroup] = []
    var statusRaw: String
    var manuallyOverridden: Bool
    var matchedActivityUUID: UUID?
    var weekTargetVolumeKmBefore: Double

    var afterKindRaw: String
    var afterDistanceKm: Double
    var afterPaceFastSecondsPerKm: Double?
    var afterPaceSlowSecondsPerKm: Double?
    var afterDetails: String
    var afterStructure: [WorkoutStepGroup] = []
    var afterStatusRaw: String
    var afterManuallyOverridden: Bool
    var afterMatchedActivityUUID: UUID?
    var weekTargetVolumeKmAfter: Double

    var revertedAt: Date?
    var source: String
    /// Optional transaction payload for multi-workout Chat proposals. Existing
    /// rows keep using the legacy single-workout fields above.
    var operationData: Data?
    var summaryText: String?
    var basePlanRevision: String?
    var appliedPlanRevision: String?

    init(
        appliedAt: Date,
        workout: PlannedWorkout,
        weekTargetVolumeKmBefore: Double,
        afterKindRaw: String,
        afterDistanceKm: Double,
        afterPaceFastSecondsPerKm: Double?,
        afterPaceSlowSecondsPerKm: Double?,
        afterDetails: String,
        afterStructure: [WorkoutStepGroup],
        afterStatusRaw: String,
        afterManuallyOverridden: Bool,
        afterMatchedActivityUUID: UUID?,
        weekTargetVolumeKmAfter: Double,
        source: String = "coach"
    ) {
        self.id = UUID()
        self.appliedAt = appliedAt
        self.workoutUUID = workout.uuid
        self.workoutDate = workout.date
        self.weekIndex = workout.weekIndex
        self.kindRaw = workout.kindRaw
        self.distanceKm = workout.distanceKm
        self.paceFastSecondsPerKm = workout.paceFastSecondsPerKm
        self.paceSlowSecondsPerKm = workout.paceSlowSecondsPerKm
        self.details = workout.details
        self.structure = workout.structure
        self.statusRaw = workout.statusRaw
        self.manuallyOverridden = workout.manuallyOverridden
        self.matchedActivityUUID = workout.matchedActivityUUID
        self.weekTargetVolumeKmBefore = weekTargetVolumeKmBefore
        self.afterKindRaw = afterKindRaw
        self.afterDistanceKm = afterDistanceKm
        self.afterPaceFastSecondsPerKm = afterPaceFastSecondsPerKm
        self.afterPaceSlowSecondsPerKm = afterPaceSlowSecondsPerKm
        self.afterDetails = afterDetails
        self.afterStructure = afterStructure
        self.afterStatusRaw = afterStatusRaw
        self.afterManuallyOverridden = afterManuallyOverridden
        self.afterMatchedActivityUUID = afterMatchedActivityUUID
        self.weekTargetVolumeKmAfter = weekTargetVolumeKmAfter
        self.revertedAt = nil
        self.source = source
        self.operationData = nil
        self.summaryText = nil
        self.basePlanRevision = nil
        self.appliedPlanRevision = nil
    }

    init(
        appliedAt: Date,
        transaction: PlanEditTransaction,
        operationData: Data,
        summary: String,
        basePlanRevision: String,
        source: String = "coach"
    ) {
        let seedBefore = transaction.operations.lazy.compactMap(\.before).first
        let seedAfter = transaction.operations.lazy.compactMap(\.after).first
        let before = seedBefore ?? seedAfter
        let after = seedAfter ?? seedBefore
        let target = transaction.weekTargets.first

        id = UUID()
        self.appliedAt = appliedAt
        workoutUUID = before?.uuid ?? UUID()
        workoutDate = before?.date ?? appliedAt
        weekIndex = before?.weekIndex ?? target?.weekIndex ?? 0
        kindRaw = before?.kindRaw ?? WorkoutKind.easy.rawValue
        distanceKm = before?.distanceKm ?? 0
        paceFastSecondsPerKm = before?.paceFastSecondsPerKm
        paceSlowSecondsPerKm = before?.paceSlowSecondsPerKm
        details = before?.details ?? summary
        structure = before?.structure ?? []
        statusRaw = before?.statusRaw ?? WorkoutStatus.planned.rawValue
        manuallyOverridden = before?.manuallyOverridden ?? true
        matchedActivityUUID = before?.matchedActivityUUID
        weekTargetVolumeKmBefore = target?.before ?? 0
        afterKindRaw = after?.kindRaw ?? before?.kindRaw ?? WorkoutKind.easy.rawValue
        afterDistanceKm = after?.distanceKm ?? before?.distanceKm ?? 0
        afterPaceFastSecondsPerKm = after?.paceFastSecondsPerKm
        afterPaceSlowSecondsPerKm = after?.paceSlowSecondsPerKm
        afterDetails = after?.details ?? before?.details ?? summary
        afterStructure = after?.structure ?? before?.structure ?? []
        afterStatusRaw = after?.statusRaw ?? before?.statusRaw ?? WorkoutStatus.planned.rawValue
        afterManuallyOverridden = after?.manuallyOverridden ?? before?.manuallyOverridden ?? true
        afterMatchedActivityUUID = after?.matchedActivityUUID
        weekTargetVolumeKmAfter = target?.after ?? target?.before ?? 0
        revertedAt = nil
        self.source = source
        self.operationData = operationData
        summaryText = summary
        self.basePlanRevision = basePlanRevision
        appliedPlanRevision = nil
    }

    var beforeKind: WorkoutKind? { WorkoutKind(rawValue: kindRaw) }
    var afterKind: WorkoutKind? { WorkoutKind(rawValue: afterKindRaw) }
}

@MainActor
enum PlanEditStore {
    static let revertWindowDays = 7
    static let changedAfterEditMessage = "This session changed after the coach edit; revert manually."
    private static let distanceTolerance = 0.001

    static func revert(
        _ editId: UUID,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws {
        let descriptor = FetchDescriptor<PlanEdit>(
            predicate: #Predicate { $0.id == editId }
        )
        guard let edit = try context.fetch(descriptor).first else {
            throw CoachTools.ValidationError("Coach edit was not found.")
        }
        try revert(edit, in: context, today: today, calendar: calendar)
    }

    static func revert(
        _ edit: PlanEdit,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws {
        guard edit.revertedAt == nil else {
            throw CoachTools.ValidationError("That coach edit was already reverted.")
        }
        let cutoff = calendar.date(byAdding: .day, value: -revertWindowDays, to: today) ?? today
        guard edit.appliedAt >= cutoff else {
            throw CoachTools.ValidationError("Coach edits can only be reverted for 7 days.")
        }
        if let operationData = edit.operationData {
            let transaction: PlanEditTransaction
            do {
                transaction = try PlanEditReceiptCodec.decode(operationData)
            } catch {
                throw CoachTools.ValidationError("That coach edit receipt could not be read.")
            }
            try revert(
                transaction,
                edit: edit,
                in: context,
                today: today
            )
            return
        }
        guard let plan = try PlanStore.activePlan(in: context),
              plan.weekTargetVolumesKm.indices.contains(edit.weekIndex) else {
            throw CoachTools.ValidationError(changedAfterEditMessage)
        }
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        guard let workout = workouts.first(where: { $0.uuid == edit.workoutUUID }),
              calendar.isDate(workout.date, inSameDayAs: edit.workoutDate),
              workout.weekIndex == edit.weekIndex,
              workout.kindRaw == edit.afterKindRaw,
              isClose(workout.distanceKm, edit.afterDistanceKm),
              workout.paceFastSecondsPerKm == edit.afterPaceFastSecondsPerKm,
              workout.paceSlowSecondsPerKm == edit.afterPaceSlowSecondsPerKm,
              workout.details == edit.afterDetails,
              workout.structure == edit.afterStructure,
              workout.statusRaw == edit.afterStatusRaw,
              workout.manuallyOverridden == edit.afterManuallyOverridden,
              workout.matchedActivityUUID == edit.afterMatchedActivityUUID,
              isClose(plan.weekTargetVolumesKm[edit.weekIndex], edit.weekTargetVolumeKmAfter) else {
            throw CoachTools.ValidationError(changedAfterEditMessage)
        }

        do {
            workout.kindRaw = edit.kindRaw
            workout.distanceKm = edit.distanceKm
            workout.paceFastSecondsPerKm = edit.paceFastSecondsPerKm
            workout.paceSlowSecondsPerKm = edit.paceSlowSecondsPerKm
            workout.details = edit.details
            workout.structure = edit.structure
            workout.statusRaw = edit.statusRaw
            workout.manuallyOverridden = edit.manuallyOverridden
            workout.matchedActivityUUID = edit.matchedActivityUUID

            var targets = plan.weekTargetVolumesKm
            targets[edit.weekIndex] = edit.weekTargetVolumeKmBefore
            plan.weekTargetVolumesKm = targets
            edit.revertedAt = today

            try context.save()
            NotificationCenter.default.post(name: .planDidChange, object: nil)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func revert(
        _ transaction: PlanEditTransaction,
        edit: PlanEdit,
        in context: ModelContext,
        today: Date
    ) throws {
        guard let plan = try PlanStore.activePlan(in: context) else {
            throw CoachTools.ValidationError(changedAfterEditMessage)
        }
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        let byID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.uuid, $0) })

        for operation in transaction.operations {
            switch operation.after {
            case .none:
                if let before = operation.before, byID[before.uuid] != nil {
                    throw CoachTools.ValidationError(changedAfterEditMessage)
                }
            case .some(let expected):
                guard let current = byID[expected.uuid],
                      PlanEditReceiptCodec.snapshotsMatch(
                        PlanWorkoutReceiptSnapshot(workout: current),
                        expected
                      ) else {
                    throw CoachTools.ValidationError(changedAfterEditMessage)
                }
            }
        }
        for target in transaction.weekTargets {
            guard plan.weekTargetVolumesKm.indices.contains(target.weekIndex),
                  isClose(plan.weekTargetVolumesKm[target.weekIndex], target.after) else {
                throw CoachTools.ValidationError(changedAfterEditMessage)
            }
        }

        do {
            for operation in transaction.operations {
                switch (operation.before, operation.after) {
                case (nil, .some(let created)):
                    guard let row = byID[created.uuid] else {
                        throw CoachTools.ValidationError(changedAfterEditMessage)
                    }
                    context.delete(row)
                case (.some(let deleted), nil):
                    context.insert(deleted.makeWorkout(plan: plan))
                case (.some(let before), .some(let after)):
                    guard let row = byID[after.uuid] else {
                        throw CoachTools.ValidationError(changedAfterEditMessage)
                    }
                    before.apply(to: row)
                    row.plan = plan
                case (nil, nil):
                    break
                }
            }
            var targets = plan.weekTargetVolumesKm
            for target in transaction.weekTargets {
                targets[target.weekIndex] = target.before
            }
            plan.weekTargetVolumesKm = targets
            plan.generatedAt = today
            edit.revertedAt = today
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        NotificationCenter.default.post(name: .planDidChange, object: nil)
    }

    private static func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= distanceTolerance
    }
}
