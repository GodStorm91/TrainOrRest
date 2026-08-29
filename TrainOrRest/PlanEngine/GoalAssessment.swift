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
        static let onTrackScore = 76
        static let highRiskScore = 45
        static let keyMissPenalty = 10
        static let sessionMissPenalty = 4
        static let volumePenaltyWeight = 35.0
        static let longRunPenaltyPerKm = 2.0
        static let maximumLongRunPenalty = 14
        static let longRunTargetMarathonShare = 0.66
        static let longRunTargetOtherShare = 0.72
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

        let metric = alignmentMetric(
            summary: summary,
            factors: factors,
            fitness: fitness,
            runSamples: runSamples,
            calculatedAt: todayStart
        )
        let status = summaryStatus(summary: summary, metric: metric, fitness: fitness, runSamples: runSamples)
        let attentionItems = attentionItems(
            summary: summary,
            factors: factors,
            goal: goalSpec,
            metric: metric,
            runSamples: runSamples,
            today: todayStart,
            calendar: calendar
        )
        let prediction = predictedFinishTime(
            goal: goalSpec,
            fitness: fitness,
            calculatedAt: todayStart
        )

        return GoalAssessment(
            goalId: "\(goal.distanceRaw)-\(Int(goal.targetTimeSeconds.rounded()))-\(Int(goal.raceDate.timeIntervalSince1970))",
            raceName: summary.title,
            raceDate: summary.raceDate,
            targetLabel: summary.title,
            targetFinishTimeSeconds: summary.targetTimeSeconds,
            metric: metric,
            predictedFinishTime: prediction,
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

    private static func alignmentMetric(
        summary: ActivePlanSummary,
        factors: [GoalAssessmentFactor],
        fitness: FitnessProfile?,
        runSamples: [RunSample],
        calculatedAt: Date
    ) -> GoalAssessmentMetric? {
        guard runSamples.count >= Tuning.minimumCompletedRunsForPrediction,
              summary.health.adherenceRate != nil || summary.health.volumeCompliance != nil
        else { return nil }

        var score = 100
        if let adherence = summary.health.adherenceRate {
            score -= Int(max(0, 1 - adherence) * 42)
        }
        if let volume = summary.health.volumeCompliance {
            score -= Int(max(0, 1 - min(volume, 1)) * Tuning.volumePenaltyWeight)
        }
        score -= summary.health.missedKeySessions * Tuning.keyMissPenalty
        score -= factors.compactMap(\.impactScore).filter { $0 < 0 }.map(abs).reduce(0, +) / 2
        if fitness == nil { score -= 12 }
        return .goalAlignmentScore(value: min(max(score, 0), 100), calculatedAt: calculatedAt)
    }

    private static func predictedFinishTime(
        goal: GoalSpec,
        fitness: FitnessProfile?,
        calculatedAt: Date
    ) -> PredictedFinishTime? {
        guard let fitness else { return nil }
        let seconds = VDOTTable.predictedTimeSeconds(distanceMeters: goal.distance.meters, vdot: fitness.vdot)
        return PredictedFinishTime(lowerSeconds: seconds, upperSeconds: seconds, calculatedAt: calculatedAt)
    }

    private static func summaryStatus(
        summary: ActivePlanSummary,
        metric: GoalAssessmentMetric?,
        fitness: FitnessProfile?,
        runSamples: [RunSample]
    ) -> GoalAssessmentSummaryStatus {
        if runSamples.count < Tuning.minimumCompletedRunsForPrediction || metric == nil {
            return .insufficientData
        }
        if summary.health.status == .needsAttention || (metric?.value ?? 100) < Tuning.onTrackScore {
            return (metric?.value ?? 100) < Tuning.highRiskScore ? .atRisk : .adjustmentRecommended
        }
        return .onTrack
    }

    private static func summaryTitleKey(for status: GoalAssessmentSummaryStatus) -> GoalAssessmentLabelKey {
        switch status {
        case .onTrack: .onTrack
        case .adjustmentRecommended: .adjustmentRecommended
        case .atRisk: .atRisk
        case .insufficientData: .insufficientData
        }
    }

    private static func summaryDetailKey(for status: GoalAssessmentSummaryStatus) -> GoalAssessmentLabelKey {
        switch status {
        case .onTrack: .onTrackSummary
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
            impactScore: missed > 0 ? -missed * Tuning.keyMissPenalty : 4
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
        let share = goal.distance == .marathon ? Tuning.longRunTargetMarathonShare : Tuning.longRunTargetOtherShare
        let target = min(goal.distance.kilometers * share, goal.distance == .marathon ? 30 : goal.distance.kilometers)
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
