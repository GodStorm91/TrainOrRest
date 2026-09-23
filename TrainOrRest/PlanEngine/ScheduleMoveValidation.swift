import Foundation

enum ScheduleMoveValidationResult: String, Codable, Equatable {
    case safeAutomatic
    case sameDayTimeOnly
    case targetDayConflict
    case crossWeekReview
    case crossPhaseReview
    case outsidePlan
    case invalidDate
}

enum ScheduleMoveSuggestedAction: String, Codable, Equatable {
    case apply
    case swapWorkouts
    case chooseAnotherDay
    case reviewWithCoach
    case restoreOriginalDate
    case reviewPlan
}

struct ScheduleMoveValidation: Equatable {
    var result: ScheduleMoveValidationResult
    var reasons: [String]
    var conflictWorkoutIDs: [UUID]
    var crossesTrainingWeek: Bool
    var crossesTrainingPhase: Bool
    var suggestedActions: [ScheduleMoveSuggestedAction]

    static func sameDayTimeOnly() -> ScheduleMoveValidation {
        ScheduleMoveValidation(
            result: .sameDayTimeOnly,
            reasons: ["Only the workout start time changed."],
            conflictWorkoutIDs: [],
            crossesTrainingWeek: false,
            crossesTrainingPhase: false,
            suggestedActions: [.apply]
        )
    }
}

struct ScheduleMoveValidationService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func validate(
        workout: PlannedWorkout,
        targetDate: Date,
        allWorkouts: [PlannedWorkout],
        plan: TrainingPlan,
        goal: GoalSpec
    ) -> ScheduleMoveValidation {
        let originalDay = calendar.startOfDay(for: workout.date)
        let targetDay = calendar.startOfDay(for: targetDate)
        if calendar.isDate(originalDay, inSameDayAs: targetDay) {
            return ScheduleMoveValidation.sameDayTimeOnly()
        }

        guard let targetWeek = plan.weekIndex(containing: targetDate, calendar: calendar) else {
            return ScheduleMoveValidation(
                result: .outsidePlan,
                reasons: ["The requested date falls outside the current training plan."],
                conflictWorkoutIDs: [],
                crossesTrainingWeek: true,
                crossesTrainingPhase: true,
                suggestedActions: [.reviewPlan, .restoreOriginalDate]
            )
        }

        let conflicts = allWorkouts.filter {
            $0.uuid != workout.uuid && calendar.isDate($0.date, inSameDayAs: targetDate)
        }
        if !conflicts.isEmpty {
            return ScheduleMoveValidation(
                result: .targetDayConflict,
                reasons: ["The target day already contains a workout."],
                conflictWorkoutIDs: conflicts.map(\.uuid),
                crossesTrainingWeek: targetWeek != workout.weekIndex,
                crossesTrainingPhase: phase(at: targetWeek, plan: plan) != workout.phaseRaw,
                suggestedActions: [.swapWorkouts, .chooseAnotherDay, .restoreOriginalDate]
            )
        }

        let crossesWeek = targetWeek != workout.weekIndex
        let crossesPhase = phase(at: targetWeek, plan: plan) != workout.phaseRaw
        if crossesPhase {
            return ScheduleMoveValidation(
                result: .crossPhaseReview,
                reasons: ["The requested date crosses training phases."],
                conflictWorkoutIDs: [],
                crossesTrainingWeek: crossesWeek,
                crossesTrainingPhase: true,
                suggestedActions: [.reviewWithCoach, .restoreOriginalDate]
            )
        }
        if crossesWeek {
            return ScheduleMoveValidation(
                result: .crossWeekReview,
                reasons: ["The requested date is outside the workout's planned week."],
                conflictWorkoutIDs: [],
                crossesTrainingWeek: true,
                crossesTrainingPhase: false,
                suggestedActions: [.reviewWithCoach, .restoreOriginalDate]
            )
        }

        let issues = validationIssuesAfterMoving(
            workout: workout,
            to: targetDate,
            workouts: allWorkouts,
            plan: plan,
            goal: goal
        )
        guard issues.isEmpty else {
            return ScheduleMoveValidation(
                result: .invalidDate,
                reasons: issues.map(\.message),
                conflictWorkoutIDs: [],
                crossesTrainingWeek: false,
                crossesTrainingPhase: false,
                suggestedActions: [.chooseAnotherDay, .reviewWithCoach, .restoreOriginalDate]
            )
        }

        return ScheduleMoveValidation(
            result: .safeAutomatic,
            reasons: ["The move stays inside the planned week and passed training validation."],
            conflictWorkoutIDs: [],
            crossesTrainingWeek: false,
            crossesTrainingPhase: false,
            suggestedActions: [.apply]
        )
    }

    private func phase(at weekIndex: Int, plan: TrainingPlan) -> String? {
        guard plan.weekPhasesRaw.indices.contains(weekIndex) else { return nil }
        return plan.weekPhasesRaw[weekIndex]
    }

    private func validationIssuesAfterMoving(
        workout: PlannedWorkout,
        to target: Date,
        workouts: [PlannedWorkout],
        plan: TrainingPlan,
        goal: GoalSpec
    ) -> [PlanValidator.Issue] {
        let baselineIssues = validationIssues(
            workout: workout,
            to: workout.date,
            workouts: workouts,
            plan: plan,
            goal: goal
        )
        let movedIssues = validationIssues(
            workout: workout,
            to: target,
            workouts: workouts,
            plan: plan,
            goal: goal
        )
        return movedIssues.filter { issue in
            !baselineIssues.contains(issue)
        }
    }

    private func validationIssues(
        workout: PlannedWorkout,
        to target: Date,
        workouts: [PlannedWorkout],
        plan: TrainingPlan,
        goal: GoalSpec
    ) -> [PlanValidator.Issue] {
        let weeks = plan.weekPhasesRaw.indices.map { index in
            let phase = TrainingPhase(rawValue: plan.weekPhasesRaw[index]) ?? .base
            let start = calendar.date(
                byAdding: .day,
                value: index * 7,
                to: PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
            ) ?? plan.anchorDate
            let specs = workouts
                .filter { $0.weekIndex == index }
                .compactMap { row -> PlannedWorkoutSpec? in
                    guard let kind = row.kind else { return nil }
                    return PlannedWorkoutSpec(
                        date: row.uuid == workout.uuid ? target : row.date,
                        kind: kind,
                        distanceKm: row.distanceKm,
                        paceBand: row.paceBand,
                        details: row.details,
                        structure: row.structure
                    )
                }
            return WeekPlan(
                startDate: start,
                index: index,
                phase: phase,
                isDownWeek: plan.weekIsDown[index],
                isPartial: index == 0 && !calendar.isDate(plan.anchorDate, inSameDayAs: start),
                targetVolumeKm: plan.weekTargetVolumesKm[index],
                workouts: specs
            )
        }
        let spec = TrainingPlanSpec(goal: goal, anchorDate: plan.anchorDate, weeks: weeks)
        return PlanValidator.validate(spec, calendar: calendar)
    }
}
