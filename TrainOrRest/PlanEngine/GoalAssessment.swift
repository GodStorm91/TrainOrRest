import Foundation

enum GoalAssessmentMetric: Equatable {
    case calibratedProbability(value: Int, range: ClosedRange<Int>?, modelVersion: String, calculatedAt: Date)
    case goalAlignmentScore(value: Int, calculatedAt: Date)

    var value: Int {
        switch self {
        case .calibratedProbability(let value, _, _, _), .goalAlignmentScore(let value, _):
            return value
        }
    }

    var calculatedAt: Date {
        switch self {
        case .calibratedProbability(_, _, _, let calculatedAt), .goalAlignmentScore(_, let calculatedAt):
            return calculatedAt
        }
    }
}

enum GoalAssessmentSummaryStatus: String, Equatable {
    case onTrack = "on_track"
    case closeToTarget = "close_to_target"
    case adjustmentRecommended = "adjustment_recommended"
    case atRisk = "at_risk"
    case insufficientData = "insufficient_data"
}

enum GoalAssessmentFactorType: String, Equatable {
    case planAdherence = "plan_adherence"
    case keyWorkoutPerformance = "key_workout_performance"
    case longRunProgression = "long_run_progression"
    case trainingLoad = "training_load"
    case recovery
    case injuryRisk = "injury_risk"
    case trainingConsistency = "training_consistency"
    case timeRemaining = "time_remaining"
    case dataQuality = "data_quality"
}

enum GoalAssessmentFactorStatus: String, Equatable {
    case positive
    case neutral
    case negative
    case unknown
}

struct GoalAssessmentFactor: Identifiable, Equatable {
    var id: String
    var type: GoalAssessmentFactorType
    var labelKey: GoalAssessmentLabelKey
    var status: GoalAssessmentFactorStatus
    var displayValue: String
    var explanationKey: GoalAssessmentLabelKey?
    var impactScore: Int?
}

enum GoalAttentionSeverity: String, Equatable {
    case info
    case adjustment
    case highRisk = "high_risk"
}

struct GoalAttentionAction: Equatable {
    var id: String
    var labelKey: GoalAssessmentLabelKey
    var coachPrompt: String
}

enum GoalAttentionEvidenceKind: String, Equatable {
    case missingQualifyingRuns
    case completedPlannedDistance
    case missedKeyWorkouts
    case completedPlannedSessions
    case longestRunBehind
}

struct GoalAttentionEvidence: Identifiable, Equatable {
    var id: String
    var kind: GoalAttentionEvidenceKind
    var primaryValue: String
    var secondaryValue: String?
}

struct GoalAttentionItem: Identifiable, Equatable {
    var id: String
    var type: GoalAssessmentFactorType
    var severity: GoalAttentionSeverity
    var titleKey: GoalAssessmentLabelKey
    var evidence: [GoalAttentionEvidence]
    var impactExplanationKey: GoalAssessmentLabelKey
    var estimatedImpactPoints: Int?
    var recommendedAction: GoalAttentionAction?
}

struct GoalAssessment: Equatable {
    var goalId: String
    var raceName: String
    var raceDate: Date
    var targetLabel: String
    var targetFinishTimeSeconds: Double?
    var raceTimePrediction: RaceTimePrediction?
    var readiness: GoalReadinessAssessment
    var metric: GoalAssessmentMetric?
    var predictedFinishTime: PredictedFinishTime?
    var trend: GoalAssessmentTrend?
    var summaryStatus: GoalAssessmentSummaryStatus
    var summaryKey: GoalAssessmentLabelKey
    var summaryDetailKey: GoalAssessmentLabelKey
    var factors: [GoalAssessmentFactor]
    var attentionItems: [GoalAttentionItem]
    var dataSources: [GoalAssessmentDataSource]
}

struct RaceTimePrediction: Equatable {
    var targetTimeSeconds: Double
    var predictedTimeSeconds: Double
    var predictedRange: ClosedRange<Double>?
    var calculatedAt: Date
    var modelVersion: String?
}

struct GoalReadinessAssessment: Equatable {
    var score: Int?
    var status: GoalAssessmentSummaryStatus
    var components: [GoalReadinessComponent]
    var calculatedAt: Date
}

struct GoalReadinessComponent: Identifiable, Equatable {
    var id: String
    var type: GoalAssessmentFactorType
    var weight: Double
    var value: Double?
    var explanation: String
}

struct PredictedFinishTime: Equatable {
    var lowerSeconds: Double
    var upperSeconds: Double
    var calculatedAt: Date
}

struct GoalAssessmentTrend: Equatable {
    var delta: Int
    var comparisonDate: Date
}

struct GoalAssessmentDataSource: Identifiable, Equatable {
    var id: String
    var labelKey: GoalAssessmentLabelKey
    var value: String
}

enum GoalAssessmentLabelKey: String, Equatable {
    case raceGoal
    case goalConfidence
    case goalAlignment
    case targetTime
    case currentPrediction
    case targetGap
    case goalStatus
    case planAndActual
    case planned
    case actual
    case currentWeek
    case completedVolume
    case latestLongRun
    case adjustPlan
    case assessmentMethod
    case planAdjustmentProposal
    case applyChanges
    case keepCurrentPlan
    case insufficientPrediction
    case onTrack
    case adjustmentRecommended
    case atRisk
    case insufficientData
    case onTrackSummary
    case adjustmentSummary
    case atRiskSummary
    case insufficientDataSummary
    case planAdherence
    case keyWorkout
    case longRunProgression
    case trainingLoad
    case recovery
    case trainingConsistency
    case timeRemaining
    case dataQuality
    case good
    case stable
    case needsAdjustment
    case highRisk
    case unknown
    case mostImportantAdjustment
    case evidence
    case impact
    case action
    case why
    case whyMetric
    case metricMeaning
    case metricDataUsed
    case metricCalculatedAt
    case metricFactors
    case metricEstimateCaveat
    case metricAlignmentExplanation
    case metricProbabilityExplanation
    case viewRecommendation
    case viewMoreItems
    case weeklyVolumeBehindTitle
    case missedKeyWorkoutTitle
    case missedSessionsTitle
    case longRunBehindTitle
    case dataMissingTitle
    case volumeBehindImpact
    case missedKeyImpact
    case missedSessionsImpact
    case longRunBehindImpact
    case dataMissingImpact
    case qualitativeLargestImpact
    case completedRunsSource
    case plannedWorkoutsSource
    case fitnessEstimateSource
    case noAttention
}

enum GoalAssessmentBuilder {
    enum Tuning {
        static let minimumCompletedRunsForPrediction = FitnessEstimator.minQualifyingRuns
        static let onTrackScore = 80
        static let closeScore = 60
        static let adjustmentScore = 40
        static let longRunPenaltyPerKm = 2.0
        static let maximumLongRunPenalty = 14
        static let longRunTargetMarathonShare = 0.66
        static let longRunTargetOtherShare = 0.72
        static let performanceWeight = 0.35
        static let adherenceWeight = 0.20
        static let keyWorkoutWeight = 0.15
        static let longRunWeight = 0.15
        static let consistencyWeight = 0.10
        static let recoveryWeight = 0.05
    }

    static func build(
        goal: Goal,
        plan: TrainingPlan,
        activities: [CompletedActivity],
        today: Date = .now,
        calendar inputCalendar: Calendar = .current
    ) -> GoalAssessment? {
        guard let goalSpec = goal.spec,
              let summary = ActivePlanSummaryBuilder.build(goal: goal, plan: plan, activities: activities, today: today, calendar: inputCalendar)
        else { return nil }

        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let todayStart = calendar.startOfDay(for: today)
        let runSamples = activities.compactMap(Self.runSample)
        let fitness = FitnessEstimator.estimate(samples: runSamples, today: todayStart, calendar: calendar)
        let dataQualityFactor = dataQualityFactor(runSamples: runSamples)
        let longRunFactor = longRunFactor(goal: goalSpec, fitness: fitness)
        let adherenceFactor = adherenceFactor(summary.health)
        let keyFactor = keyWorkoutFactor(summary.health)
        let volumeFactor = volumeFactor(summary.health)
        let timeFactor = timeFactor(summary: summary)
        let factors = [adherenceFactor, keyFactor, longRunFactor, volumeFactor, timeFactor, dataQualityFactor]

        let prediction = raceTimePrediction(
            goal: goalSpec,
            fitness: fitness,
            calculatedAt: todayStart
        )
        let readiness = readinessAssessment(
            summary: summary,
            goal: goalSpec,
            prediction: prediction,
            fitness: fitness,
            runSamples: runSamples,
            calculatedAt: todayStart
        )
        let metric = readiness.score.map { GoalAssessmentMetric.goalAlignmentScore(value: $0, calculatedAt: todayStart) }
        let status = readiness.status
        let attentionItems = attentionItems(
            summary: summary,
            factors: factors,
            goal: goalSpec,
            metric: metric,
            runSamples: runSamples,
            today: todayStart,
            calendar: calendar
        )
        let finishRange = prediction.map {
            PredictedFinishTime(
                lowerSeconds: $0.predictedRange?.lowerBound ?? $0.predictedTimeSeconds,
                upperSeconds: $0.predictedRange?.upperBound ?? $0.predictedTimeSeconds,
                calculatedAt: $0.calculatedAt
            )
        }

        return GoalAssessment(
            goalId: "\(goal.distanceRaw)-\(Int(goal.targetTimeSeconds.rounded()))-\(Int(goal.raceDate.timeIntervalSince1970))",
            raceName: summary.title,
            raceDate: summary.raceDate,
            targetLabel: summary.title,
            targetFinishTimeSeconds: summary.targetTimeSeconds,
            raceTimePrediction: prediction,
            readiness: readiness,
            metric: metric,
            predictedFinishTime: finishRange,
            trend: nil,
            summaryStatus: status,
            summaryKey: summaryTitleKey(for: status),
            summaryDetailKey: summaryDetailKey(for: status),
            factors: factors,
            attentionItems: prioritized(attentionItems),
            dataSources: dataSources(summary: summary, activities: activities, fitness: fitness)
        )
    }

    static func primaryAttentionItem(for assessment: GoalAssessment) -> GoalAttentionItem? {
        guard assessment.summaryStatus != .onTrack else { return nil }
        return prioritized(assessment.attentionItems).first {
            $0.severity == .highRisk || $0.severity == .adjustment
        }
    }

    private static func runSample(_ activity: CompletedActivity) -> RunSample? {
        guard let meters = activity.distanceMeters, meters > 0 else { return nil }
        return RunSample(
            date: activity.date,
            distanceKm: meters / 1000,
            durationSeconds: activity.durationSeconds
        )
    }

    private static func readinessAssessment(
        summary: ActivePlanSummary,
        goal: GoalSpec,
        prediction: RaceTimePrediction?,
        fitness: FitnessProfile?,
        runSamples: [RunSample],
        calculatedAt: Date
    ) -> GoalReadinessAssessment {
        let components = readinessComponents(summary: summary, goal: goal, prediction: prediction, fitness: fitness)
        let available = components.filter { $0.value != nil && $0.weight > 0 }
        let score: Int?
        if runSamples.count < Tuning.minimumCompletedRunsForPrediction || available.isEmpty {
            score = nil
        } else {
            let totalWeight = available.reduce(0) { $0 + $1.weight }
            let weighted = available.reduce(0) { partial, component in
                partial + min(max(component.value ?? 0, 0), 100) * (component.weight / totalWeight)
            }
            score = Int(weighted.rounded())
        }
        let status = status(for: score)
        return GoalReadinessAssessment(score: score, status: status, components: components, calculatedAt: calculatedAt)
    }

    private static func raceTimePrediction(
        goal: GoalSpec,
        fitness: FitnessProfile?,
        calculatedAt: Date
    ) -> RaceTimePrediction? {
        guard let fitness else { return nil }
        let seconds = VDOTTable.predictedTimeSeconds(distanceMeters: goal.distance.meters, vdot: fitness.vdot)
        return RaceTimePrediction(
            targetTimeSeconds: goal.targetTimeSeconds,
            predictedTimeSeconds: seconds,
            predictedRange: nil,
            calculatedAt: calculatedAt,
            modelVersion: "vdot-v1"
        )
    }

    private static func readinessComponents(
        summary: ActivePlanSummary,
        goal: GoalSpec,
        prediction: RaceTimePrediction?,
        fitness: FitnessProfile?
    ) -> [GoalReadinessComponent] {
        let performance = prediction.map { prediction in
            let gap = prediction.predictedTimeSeconds - prediction.targetTimeSeconds
            if gap <= 0 { return 100.0 }
            let allowedSlowdown = max(prediction.targetTimeSeconds * 0.15, 60)
            return 100 - min(gap / allowedSlowdown, 1) * 100
        }
        let dueKeyCount = summary.health.missedWorkoutAudit.entries.filter {
            ($0.reason == .missed || $0.reason == .completed) && $0.isKeyWorkout
        }.count
        let keyCompleted = dueKeyCount - summary.health.missedKeySessions
        let keyScore = dueKeyCount > 0 ? Double(keyCompleted) / Double(dueKeyCount) * 100 : nil
        let longRunTarget = longRunTargetKm(goal)
        let longRunScore = fitness.map { min($0.longestRecentRunKm / max(longRunTarget, 0.1), 1) * 100 }
        let adherenceScore = summary.health.adherenceRate.map { min(max($0, 0), 1) * 100 }
        let volumeScore = summary.health.volumeCompliance.map { min(max($0, 0), 1) * 100 }

        return [
            GoalReadinessComponent(id: "predicted_performance", type: .keyWorkoutPerformance, weight: Tuning.performanceWeight, value: performance, explanation: "Prediction gap versus target finish time."),
            GoalReadinessComponent(id: "plan_adherence", type: .planAdherence, weight: Tuning.adherenceWeight, value: adherenceScore, explanation: "Completed due planned workouts divided by expected due workouts."),
            GoalReadinessComponent(id: "key_workout_completion", type: .keyWorkoutPerformance, weight: Tuning.keyWorkoutWeight, value: keyScore, explanation: "Completed due key workouts divided by due key workouts after audit exclusions."),
            GoalReadinessComponent(id: "long_run_progression", type: .longRunProgression, weight: Tuning.longRunWeight, value: longRunScore, explanation: "Longest recent run compared with the race-specific long-run target."),
            GoalReadinessComponent(id: "training_load", type: .trainingLoad, weight: Tuning.consistencyWeight, value: volumeScore, explanation: "Completed due distance divided by planned due distance."),
            GoalReadinessComponent(id: "recovery", type: .recovery, weight: Tuning.recoveryWeight, value: nil, explanation: "Recovery signal is omitted until enough wellness data is available.")
        ]
    }

    private static func status(for score: Int?) -> GoalAssessmentSummaryStatus {
        guard let score else { return .insufficientData }
        if score >= Tuning.onTrackScore { return .onTrack }
        if score >= Tuning.closeScore { return .closeToTarget }
        if score >= Tuning.adjustmentScore { return .adjustmentRecommended }
        return .atRisk
    }

    private static func summaryTitleKey(for status: GoalAssessmentSummaryStatus) -> GoalAssessmentLabelKey {
        switch status {
        case .onTrack: .onTrack
        case .closeToTarget: .adjustmentRecommended
        case .adjustmentRecommended: .adjustmentRecommended
        case .atRisk: .atRisk
        case .insufficientData: .insufficientData
        }
    }

    private static func summaryDetailKey(for status: GoalAssessmentSummaryStatus) -> GoalAssessmentLabelKey {
        switch status {
        case .onTrack: .onTrackSummary
        case .closeToTarget: .adjustmentSummary
        case .adjustmentRecommended: .adjustmentSummary
        case .atRisk: .atRiskSummary
        case .insufficientData: .insufficientDataSummary
        }
    }

    private static func adherenceFactor(_ health: PlanHealth) -> GoalAssessmentFactor {
        let value = health.adherenceRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        let status: GoalAssessmentFactorStatus = if let rate = health.adherenceRate {
            rate >= ActivePlanSummaryBuilder.Tuning.onTrackSessionRate ? .positive : rate < ActivePlanSummaryBuilder.Tuning.needsAttentionSessionRate ? .negative : .neutral
        } else {
            .unknown
        }
        return GoalAssessmentFactor(
            id: "plan_adherence",
            type: .planAdherence,
            labelKey: .planAdherence,
            status: status,
            displayValue: value,
            explanationKey: nil,
            impactScore: health.adherenceRate.map { -Int(max(0, 1 - $0) * 20) }
        )
    }

    private static func keyWorkoutFactor(_ health: PlanHealth) -> GoalAssessmentFactor {
        let missed = health.missedKeySessions
        return GoalAssessmentFactor(
            id: "key_workout_performance",
            type: .keyWorkoutPerformance,
            labelKey: .keyWorkout,
            status: missed == 0 ? .positive : missed >= ActivePlanSummaryBuilder.Tuning.missedKeySessionLimit ? .negative : .neutral,
            displayValue: missed == 0 ? "0 missed" : "\(missed) missed",
            explanationKey: nil,
            impactScore: missed > 0 ? -min(15, missed * 5) : 4
        )
    }

    private static func longRunFactor(goal: GoalSpec, fitness: FitnessProfile?) -> GoalAssessmentFactor {
        guard let fitness else {
            return GoalAssessmentFactor(
                id: "long_run_progression",
                type: .longRunProgression,
                labelKey: .longRunProgression,
                status: .unknown,
                displayValue: "—",
                explanationKey: nil,
                impactScore: nil
            )
        }
        let target = longRunTargetKm(goal)
        let gap = max(0, target - fitness.longestRecentRunKm)
        let status: GoalAssessmentFactorStatus = if gap <= 1 {
            .positive
        } else if gap >= 4 {
            .negative
        } else {
            .neutral
        }
        return GoalAssessmentFactor(
            id: "long_run_progression",
            type: .longRunProgression,
            labelKey: .longRunProgression,
            status: status,
            displayValue: gap <= 1 ? "\(Int(fitness.longestRecentRunKm.rounded())) km" : "Short \(Int(gap.rounded())) km",
            explanationKey: nil,
            impactScore: gap <= 1 ? 5 : -min(Int((gap * Tuning.longRunPenaltyPerKm).rounded()), Tuning.maximumLongRunPenalty)
        )
    }

    private static func volumeFactor(_ health: PlanHealth) -> GoalAssessmentFactor {
        let value = health.volumeCompliance.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        let status: GoalAssessmentFactorStatus = if let compliance = health.volumeCompliance {
            compliance >= ActivePlanSummaryBuilder.Tuning.onTrackVolumeRate ? .positive : compliance < ActivePlanSummaryBuilder.Tuning.needsAttentionVolumeRate ? .negative : .neutral
        } else {
            .unknown
        }
        return GoalAssessmentFactor(
            id: "training_load",
            type: .trainingLoad,
            labelKey: .trainingLoad,
            status: status,
            displayValue: value,
            explanationKey: nil,
            impactScore: health.volumeCompliance.map { -Int(max(0, 1 - min($0, 1)) * 18) }
        )
    }

    private static func timeFactor(summary: ActivePlanSummary) -> GoalAssessmentFactor {
        let weeks = (summary.daysRemaining ?? 0) / 7
        return GoalAssessmentFactor(
            id: "time_remaining",
            type: .timeRemaining,
            labelKey: .timeRemaining,
            status: weeks >= 4 ? .positive : .neutral,
            displayValue: "\(weeks) wk",
            explanationKey: nil,
            impactScore: weeks >= 4 ? 3 : 0
        )
    }

    private static func dataQualityFactor(runSamples: [RunSample]) -> GoalAssessmentFactor {
        let missing = max(0, Tuning.minimumCompletedRunsForPrediction - runSamples.count)
        return GoalAssessmentFactor(
            id: "data_quality",
            type: .dataQuality,
            labelKey: .dataQuality,
            status: missing == 0 ? .positive : .unknown,
            displayValue: missing == 0 ? "\(runSamples.count) runs" : "Need \(missing) more",
            explanationKey: nil,
            impactScore: missing == 0 ? 2 : nil
        )
    }

    private static func longRunTargetKm(_ goal: GoalSpec) -> Double {
        let share = goal.distance == .marathon ? Tuning.longRunTargetMarathonShare : Tuning.longRunTargetOtherShare
        return min(goal.distance.kilometers * share, goal.distance == .marathon ? 30 : goal.distance.kilometers)
    }

    private static func attentionItems(
        summary: ActivePlanSummary,
        factors: [GoalAssessmentFactor],
        goal: GoalSpec,
        metric: GoalAssessmentMetric?,
        runSamples: [RunSample],
        today: Date,
        calendar: Calendar
    ) -> [GoalAttentionItem] {
        var items: [GoalAttentionItem] = []
        if runSamples.count < Tuning.minimumCompletedRunsForPrediction {
            let missing = Tuning.minimumCompletedRunsForPrediction - runSamples.count
            items.append(item(
                id: "data_quality",
                type: .dataQuality,
                severity: .info,
                title: .dataMissingTitle,
                evidence: [
                    GoalAttentionEvidence(
                        id: "missing_qualifying_runs",
                        kind: .missingQualifyingRuns,
                        primaryValue: "\(missing)",
                        secondaryValue: "\(Tuning.minimumCompletedRunsForPrediction)"
                    )
                ],
                impact: .dataMissingImpact,
                points: nil
            ))
            return items
        }
        if let volume = summary.health.volumeCompliance,
           volume < ActivePlanSummaryBuilder.Tuning.needsAttentionVolumeRate {
            items.append(item(
                id: "training_load",
                type: .trainingLoad,
                severity: .adjustment,
                title: .weeklyVolumeBehindTitle,
                evidence: [
                    GoalAttentionEvidence(
                        id: "completed_planned_distance",
                        kind: .completedPlannedDistance,
                        primaryValue: "\(Int((volume * 100).rounded()))",
                        secondaryValue: nil
                    )
                ],
                impact: .volumeBehindImpact,
                points: estimatedImpact(factors, id: "training_load")
            ))
        }
        if summary.health.missedKeySessions > 0 {
            items.append(item(
                id: "key_workout_performance",
                type: .keyWorkoutPerformance,
                severity: summary.health.missedKeySessions >= ActivePlanSummaryBuilder.Tuning.missedKeySessionLimit ? .highRisk : .adjustment,
                title: .missedKeyWorkoutTitle,
                evidence: [
                    GoalAttentionEvidence(
                        id: "missed_key_workouts",
                        kind: .missedKeyWorkouts,
                        primaryValue: "\(summary.health.missedKeySessions)",
                        secondaryValue: nil
                    )
                ],
                impact: .missedKeyImpact,
                points: estimatedImpact(factors, id: "key_workout_performance")
            ))
        }
        if let adherence = summary.health.adherenceRate,
           adherence < ActivePlanSummaryBuilder.Tuning.needsAttentionSessionRate {
            items.append(item(
                id: "plan_adherence",
                type: .planAdherence,
                severity: .adjustment,
                title: .missedSessionsTitle,
                evidence: [
                    GoalAttentionEvidence(
                        id: "completed_planned_sessions",
                        kind: .completedPlannedSessions,
                        primaryValue: "\(Int((adherence * 100).rounded()))",
                        secondaryValue: nil
                    )
                ],
                impact: .missedSessionsImpact,
                points: estimatedImpact(factors, id: "plan_adherence")
            ))
        }
        if let longRun = factors.first(where: { $0.id == "long_run_progression" }),
           longRun.status == .negative {
            items.append(item(
                id: "long_run_progression",
                type: .longRunProgression,
                severity: .adjustment,
                title: .longRunBehindTitle,
                evidence: [
                    GoalAttentionEvidence(
                        id: "long_run_behind",
                        kind: .longestRunBehind,
                        primaryValue: longRun.displayValue,
                        secondaryValue: nil
                    )
                ],
                impact: .longRunBehindImpact,
                points: longRun.impactScore.map(abs)
            ))
        }
        return items
    }

    private static func item(
        id: String,
        type: GoalAssessmentFactorType,
        severity: GoalAttentionSeverity,
        title: GoalAssessmentLabelKey,
        evidence: [GoalAttentionEvidence],
        impact: GoalAssessmentLabelKey,
        points: Int?
    ) -> GoalAttentionItem {
        GoalAttentionItem(
            id: id,
            type: type,
            severity: severity,
            titleKey: title,
            evidence: evidence,
            impactExplanationKey: impact,
            estimatedImpactPoints: points,
            recommendedAction: GoalAttentionAction(
                id: "coach_recommendation_\(id)",
                labelKey: .viewRecommendation,
                coachPrompt: ""
            )
        )
    }

    private static func estimatedImpact(_ factors: [GoalAssessmentFactor], id: String) -> Int? {
        factors.first(where: { $0.id == id })?.impactScore.map(abs)
    }

    private static func prioritized(_ items: [GoalAttentionItem]) -> [GoalAttentionItem] {
        items.sorted { lhs, rhs in
            let left = priority(lhs)
            let right = priority(rhs)
            if left != right { return left > right }
            return lhs.id < rhs.id
        }
    }

    private static func priority(_ item: GoalAttentionItem) -> Int {
        let severity = switch item.severity {
        case .highRisk: 300
        case .adjustment: 200
        case .info: 100
        }
        let impact = item.estimatedImpactPoints ?? 0
        let actionable = item.recommendedAction == nil ? 0 : 20
        return severity + impact + actionable
    }

    private static func dataSources(
        summary: ActivePlanSummary,
        activities: [CompletedActivity],
        fitness: FitnessProfile?
    ) -> [GoalAssessmentDataSource] {
        [
            GoalAssessmentDataSource(id: "planned_workouts", labelKey: .plannedWorkoutsSource, value: "\(summary.weeklyProgress.reduce(0) { $0 + $1.plannedSessions })"),
            GoalAssessmentDataSource(id: "completed_runs", labelKey: .completedRunsSource, value: "\(activities.filter { ($0.distanceMeters ?? 0) > 0 }.count)"),
            GoalAssessmentDataSource(id: "fitness_estimate", labelKey: .fitnessEstimateSource, value: fitness.map { String(format: "VDOT %.1f", $0.vdot) } ?? "—")
        ]
    }
}
