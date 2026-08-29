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
        case .adjustmentRecommended: .adjustmentRecommended
        case .atRisk: .atRisk
        case .insufficientData: .insufficientData
        }
    }

    private func summaryDetailKey(_ status: GoalAssessmentSummaryStatus) -> GoalAssessmentLabelKey {
        switch status {
        case .onTrack: .onTrackSummary
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
}
