import SwiftUI
import UIKit
import XCTest
@testable import TrainOrRest

@MainActor
final class GoalAssessmentSnapshotTests: XCTestCase {
    func testRenderGoalAssessmentScreenshots() throws {
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "design/goal-assessment-screenshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        try render(
            RaceGoalStatusCard(
                assessment: assessment(status: .onTrack, metric: 84, attentionItems: []),
                language: .vi,
                onShowMetricDetail: {},
                onShowAssessmentDetail: {}
            ),
            name: "on-track-state",
            output: output
        )

        let weeklySummary = planSummary(adjusted: false)
        let predictionAssessment = assessment(status: .adjustmentRecommended, metric: 52, attentionItems: [])
        try render(
            RaceGoalStatusCard(
                assessment: predictionAssessment,
                summary: weeklySummary,
                language: .vi,
                onShowMetricDetail: {},
                onShowAssessmentDetail: {}
            ),
            name: "predicted-time-state",
            output: output,
            height: 980
        )
        try render(
            RaceGoalStatusCard(
                assessment: predictionAssessment,
                summary: weeklySummary,
                language: .vi,
                onShowMetricDetail: {},
                onShowAssessmentDetail: {}
            ),
            name: "plan-vs-actual-chart",
            output: output,
            height: 980
        )
        try render(
            RaceGoalStatusCard(
                assessment: predictionAssessment,
                summary: weeklySummary,
                language: .vi,
                initialSelectedWeekID: 4,
                onShowMetricDetail: {},
                onShowAssessmentDetail: {}
            ),
            name: "week-detail-interaction",
            output: output,
            height: 1080
        )
        try render(
            RaceGoalStatusCard(
                assessment: predictionAssessment,
                summary: planSummary(adjusted: true),
                language: .vi,
                onShowMetricDetail: {},
                onShowAssessmentDetail: {}
            ),
            name: "applied-plan-state",
            output: output,
            height: 980
        )

        let adjustment = attention(
            id: "long_run_progression",
            type: .longRunProgression,
            severity: .adjustment,
            title: .longRunBehindTitle,
            evidence: GoalAttentionEvidence(
                id: "long_run_behind",
                kind: .longestRunBehind,
                primaryValue: "Short 4 km"
            ),
            points: 9
        )
        let adjustmentAssessment = assessment(
            status: .adjustmentRecommended,
            metric: 68,
            attentionItems: [adjustment]
        )
        try render(
            VStack(spacing: 16) {
                RaceGoalStatusCard(
                    assessment: adjustmentAssessment,
                    language: .vi,
                    onShowMetricDetail: {},
                    onShowAssessmentDetail: {}
                )
                PrimaryAttentionCard(
                    assessment: adjustmentAssessment,
                    item: adjustment,
                    language: .vi,
                    onShowDetails: {},
                    coachRequest: CalendarReviewChatRequest(prompt: "Goal ID: snapshot\nAttention item ID: long_run_progression")
                )
            },
            name: "adjustment-needed-state",
            output: output,
            height: 1040
        )

        let highRisk = attention(
            id: "key_workout_performance",
            type: .keyWorkoutPerformance,
            severity: .highRisk,
            title: .missedKeyWorkoutTitle,
            evidence: GoalAttentionEvidence(
                id: "missed_key_workouts",
                kind: .missedKeyWorkouts,
                primaryValue: "2"
            ),
            points: 20
        )
        let highRiskAssessment = assessment(
            status: .atRisk,
            metric: 41,
            attentionItems: [highRisk]
        )
        try render(
            VStack(spacing: 16) {
                RaceGoalStatusCard(
                    assessment: highRiskAssessment,
                    language: .vi,
                    onShowMetricDetail: {},
                    onShowAssessmentDetail: {}
                )
                PrimaryAttentionCard(
                    assessment: highRiskAssessment,
                    item: highRisk,
                    language: .vi,
                    onShowDetails: {},
                    coachRequest: CalendarReviewChatRequest(prompt: "Goal ID: snapshot\nAttention item ID: key_workout_performance")
                )
            },
            name: "high-risk-state",
            output: output,
            height: 1040
        )

        try render(
            RaceGoalStatusCard(
                assessment: assessment(status: .insufficientData, metric: nil, attentionItems: [
                    attention(
                        id: "data_quality",
                        type: .dataQuality,
                        severity: .info,
                        title: .dataMissingTitle,
                        evidence: GoalAttentionEvidence(
                            id: "missing_qualifying_runs",
                            kind: .missingQualifyingRuns,
                            primaryValue: "2",
                            secondaryValue: "4"
                        ),
                        points: nil
                    )
                ]),
                language: .vi,
                onShowMetricDetail: {},
                onShowAssessmentDetail: {}
            ),
            name: "insufficient-data-state",
            output: output
        )

        try render(
            GoalAssessmentDetailContent(assessment: adjustmentAssessment, language: .vi),
            name: "goal-details-sheet",
            output: output,
            height: 760
        )

        try render(
            PlanAdjustmentPreviewSheet(
                proposal: previewProposal(),
                language: .vi,
                onApply: { _ in }
            ),
            name: "plan-adjustment-preview",
            output: output,
            height: 760
        )
    }

    private func render<Content: View>(
        _ content: Content,
        name: String,
        output: URL,
        width: CGFloat = 390,
        height: CGFloat = 844
    ) throws {
        let renderer = ImageRenderer(
            content: content
                .padding(16)
                .frame(width: width, height: height, alignment: .top)
                .background(Theme.bg)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: output.appending(path: "\(name).png"))
    }

    private func assessment(
        status: GoalAssessmentSummaryStatus,
        metric: Int?,
        attentionItems: [GoalAttentionItem]
    ) -> GoalAssessment {
        GoalAssessment(
            goalId: "snapshot-goal",
            raceName: "Mito Marathon · Sub 4",
            raceDate: date(2026, 10, 25),
            targetLabel: "Sub 4",
            targetFinishTimeSeconds: 14_399,
            raceTimePrediction: metric == nil ? nil : RaceTimePrediction(
                targetTimeSeconds: 14_399,
                predictedTimeSeconds: 14_760,
                predictedRange: 14_580...14_940,
                calculatedAt: date(2026, 8, 29),
                modelVersion: "snapshot"
            ),
            readiness: GoalReadinessAssessment(
                score: metric,
                status: status,
                components: [],
                calculatedAt: date(2026, 8, 29)
            ),
            metric: metric.map { .goalAlignmentScore(value: $0, calculatedAt: date(2026, 8, 29)) },
            predictedFinishTime: metric == nil ? nil : PredictedFinishTime(
                lowerSeconds: 14_580,
                upperSeconds: 14_940,
                calculatedAt: date(2026, 8, 29)
            ),
            trend: metric.map { GoalAssessmentTrend(delta: $0 >= 76 ? 4 : -6, comparisonDate: date(2026, 8, 22)) },
            summaryStatus: status,
            summaryKey: summaryKey(status),
            summaryDetailKey: summaryDetailKey(status),
            factors: [
                GoalAssessmentFactor(id: "plan_adherence", type: .planAdherence, labelKey: .planAdherence, status: metric == nil ? .unknown : .positive, displayValue: metric == nil ? "—" : "82%", impactScore: 4),
                GoalAssessmentFactor(id: "long_run_progression", type: .longRunProgression, labelKey: .longRunProgression, status: status == .adjustmentRecommended ? .negative : .neutral, displayValue: status == .adjustmentRecommended ? "Short 4 km" : "24 km", impactScore: status == .adjustmentRecommended ? -9 : 2),
                GoalAssessmentFactor(id: "recovery", type: .recovery, labelKey: .recovery, status: .neutral, displayValue: "Ổn định", impactScore: 0),
                GoalAssessmentFactor(id: "data_quality", type: .dataQuality, labelKey: .dataQuality, status: metric == nil ? .unknown : .positive, displayValue: metric == nil ? "Need 2 more" : "12 runs", impactScore: nil)
            ],
            attentionItems: attentionItems,
            dataSources: [
                GoalAssessmentDataSource(id: "planned_workouts", labelKey: .plannedWorkoutsSource, value: "48"),
                GoalAssessmentDataSource(id: "completed_runs", labelKey: .completedRunsSource, value: "12"),
                GoalAssessmentDataSource(id: "fitness_estimate", labelKey: .fitnessEstimateSource, value: metric == nil ? "—" : "VDOT 45.2")
            ]
        )
    }

    private func attention(
        id: String,
        type: GoalAssessmentFactorType,
        severity: GoalAttentionSeverity,
        title: GoalAssessmentLabelKey,
        evidence: GoalAttentionEvidence,
        points: Int?
    ) -> GoalAttentionItem {
        GoalAttentionItem(
            id: id,
            type: type,
            severity: severity,
            titleKey: title,
            evidence: [evidence],
            impactExplanationKey: .qualitativeLargestImpact,
            estimatedImpactPoints: points,
            recommendedAction: GoalAttentionAction(id: "coach_recommendation_\(id)", labelKey: .viewRecommendation, coachPrompt: "")
        )
    }

    private func summaryKey(_ status: GoalAssessmentSummaryStatus) -> GoalAssessmentLabelKey {
        switch status {
        case .onTrack: .onTrack
        case .closeToTarget: .adjustmentRecommended
        case .adjustmentRecommended: .adjustmentRecommended
        case .atRisk: .atRisk
        case .insufficientData: .insufficientData
        }
    }

    private func summaryDetailKey(_ status: GoalAssessmentSummaryStatus) -> GoalAssessmentLabelKey {
        switch status {
        case .onTrack: .onTrackSummary
        case .closeToTarget: .adjustmentSummary
        case .adjustmentRecommended: .adjustmentSummary
        case .atRisk: .atRiskSummary
        case .insufficientData: .insufficientDataSummary
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 8
        return components.date!
    }

    private func planSummary(adjusted: Bool) -> ActivePlanSummary {
        let weeks = [
            week(0, "2026-07-20", planned: 35, actual: 32, key: (2, 2), longRun: (18, 18), current: false, future: false),
            week(1, "2026-07-27", planned: 38, actual: 34, key: (2, 1), longRun: (21, 19), current: false, future: false),
            week(2, "2026-08-03", planned: 40, actual: 31, key: (2, 1), longRun: (24, 20), current: false, future: false),
            week(3, "2026-08-10", planned: 42, actual: 36, key: (2, 1), longRun: (26, 23), current: false, future: false),
            week(4, "2026-08-17", planned: adjusted ? 39 : 44, actual: 31, key: (2, 1), longRun: (28, 23), current: true, future: false),
            week(5, "2026-08-24", planned: adjusted ? 42 : 46, actual: nil, key: (2, 0), longRun: (adjusted ? 26 : 30, nil), current: false, future: true),
            week(6, "2026-08-31", planned: adjusted ? 45 : 50, actual: nil, key: (2, 0), longRun: (adjusted ? 28 : 32, nil), current: false, future: true),
            week(7, "2026-09-07", planned: adjusted ? 48 : 52, actual: nil, key: (2, 0), longRun: (adjusted ? 30 : 34, nil), current: false, future: true)
        ]
        return ActivePlanSummary(
            title: "Mito Marathon · Sub 4",
            raceDate: date(2026, 10, 25),
            targetTimeSeconds: 14_399,
            runningDaysPerWeek: 5,
            startDate: date(2026, 7, 20),
            endDate: date(2026, 10, 25),
            currentWeek: 5,
            totalWeeks: 14,
            timelineProgress: 0.42,
            daysRemaining: 57,
            isRaceDay: false,
            health: PlanHealth(
                status: .needsAttention,
                reasons: [.missedKeySessions(3), .weeklyVolumeBehind],
                adherenceRate: 0.47,
                volumeCompliance: 0.47,
                missedKeySessions: 3,
                missedWorkoutAudit: MissedWorkoutAudit(),
                evaluatedAt: date(2026, 8, 29)
            ),
            currentPhase: nil,
            thisWeek: weeks[4],
            nextWorkout: nil,
            upcomingWorkouts: [],
            weeklyProgress: weeks,
            phases: []
        )
    }

    private func week(
        _ index: Int,
        _ start: String,
        planned: Double,
        actual: Double?,
        key: (Int, Int),
        longRun: (Double?, Double?),
        current: Bool,
        future: Bool
    ) -> ActivePlanWeekSummary {
        let startDate = isoDate(start)
        return ActivePlanWeekSummary(
            weekIndex: index,
            startDate: startDate,
            endDate: Calendar(identifier: .gregorian).date(byAdding: .day, value: 6, to: startDate)!,
            plannedSessions: 5,
            completedSessions: actual == nil ? 0 : 4,
            plannedDistanceKm: planned,
            completedDistanceKm: actual ?? 0,
            plannedKeySessions: key.0,
            completedKeySessions: key.1,
            plannedLongRunKm: longRun.0,
            completedLongRunKm: longRun.1,
            isCurrentWeek: current,
            isFutureWeek: future
        )
    }

    private func previewProposal() -> GoalPlanAdjustmentProposal {
        GoalPlanAdjustmentProposal(
            id: "snapshot-proposal",
            goalId: "snapshot-goal",
            basedOnAssessmentId: "snapshot-assessment",
            explanation: "Coach đề xuất 4 thay đổi cho 8 tuần còn lại. Các buổi đã lỡ sẽ không được dồn toàn bộ vào lịch mới.",
            changes: [
                previewChange("long-run", type: .distanceChange, before: ("2026-09-06", "Long run", 24), after: ("2026-09-06", "Long run", 26), reason: "Tăng dần sức bền, không bù toàn bộ 7 km còn thiếu."),
                previewChange("tempo", type: .intensityChange, before: ("2026-09-09", "Tempo", 8), after: ("2026-09-09", "Tempo", 7), reason: "Giảm tải để cân bằng với long run."),
                previewChange("recovery", type: .recoveryChange, before: ("2026-09-10", "Easy", 6), after: nil, reason: "Tạo khoảng hồi phục sau hai buổi chất lượng.")
            ],
            warnings: ["Một số buổi đã khóa lịch được giữ nguyên."],
            createdAt: date(2026, 8, 29)
        )
    }

    private func previewChange(
        _ id: String,
        type: GoalPlanAdjustmentChange.ChangeType,
        before: (String, String, Double),
        after: (String, String, Double)?,
        reason: String
    ) -> GoalPlanAdjustmentChange {
        GoalPlanAdjustmentChange(
            id: id,
            type: type,
            workoutId: UUID(),
            reason: reason,
            before: PlanWorkoutSnapshot(date: isoDate(before.0), kindRaw: before.1, distanceKm: before.2, details: before.1),
            after: after.map { PlanWorkoutSnapshot(date: isoDate($0.0), kindRaw: $0.1, distanceKm: $0.2, details: $0.1) }
        )
    }

    private func isoDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }
}
