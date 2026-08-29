import XCTest
@testable import TrainOrRest

final class GoalAssessmentTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    func testHeuristicScoreRendersAsGoalAlignment() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 24), completedThrough: 14)
        guard case .goalAlignmentScore(let value, _) = assessment.metric else {
            return XCTFail("Expected deterministic goal-alignment score")
        }

        XCTAssertGreaterThan(value, 0)
        XCTAssertEqual(CoachLanguage.vi.goalAssessmentText(.goalAlignment), "Mức độ bám mục tiêu")
        XCTAssertEqual(CoachLanguage.en.goalAssessmentText(.goalAlignment), "Goal alignment")
    }

    func testMissingMetricDoesNotFabricatePercentage() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 5), completedThrough: 0, includeFitnessHistory: false)

        XCTAssertNil(assessment.metric)
        XCTAssertNil(assessment.predictedFinishTime)
        XCTAssertEqual(assessment.summaryStatus, .insufficientData)
        XCTAssertEqual(assessment.summaryKey, .insufficientData)
    }

    func testTargetAndPredictedTimesAreSeparateValues() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 24), completedThrough: 14)
        let predicted = try XCTUnwrap(assessment.predictedFinishTime)

        XCTAssertEqual(assessment.targetFinishTimeSeconds, 14_399)
        XCTAssertNotEqual(Int(predicted.lowerSeconds.rounded()), Int(assessment.targetFinishTimeSeconds ?? 0))
    }

    func testTrendIsAbsentWithoutHistoricalAssessment() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 24), completedThrough: 14)

        XCTAssertNil(assessment.trend)
    }

    func testHighestPriorityAttentionItemPrefersHighRiskKeyWorkout() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 24), completedThrough: 3)
        let primary = try XCTUnwrap(GoalAssessmentBuilder.primaryAttentionItem(for: assessment))

        XCTAssertEqual(primary.type, .keyWorkoutPerformance)
        XCTAssertEqual(primary.severity, .highRisk)
        XCTAssertNotEqual(primary.titleKey, .needsAdjustment)
    }

    func testEvidenceAndImpactAreStructured() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 24), completedThrough: 3)
        let primary = try XCTUnwrap(GoalAssessmentBuilder.primaryAttentionItem(for: assessment))

        XCTAssertFalse(primary.evidence.isEmpty)
        XCTAssertNotNil(primary.impactExplanationKey)
        XCTAssertEqual(CoachLanguage.vi.goalAssessmentText(primary.titleKey), "Buổi tập trọng điểm chưa hoàn thành")
    }

    func testNumericalImpactCanBeHiddenForInsufficientData() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 5), completedThrough: 0, includeFitnessHistory: false)
        let dataItem = try XCTUnwrap(assessment.attentionItems.first { $0.type == .dataQuality })

        XCTAssertNil(dataItem.estimatedImpactPoints)
        XCTAssertEqual(dataItem.impactExplanationKey, .dataMissingImpact)
    }

    func testNoAttentionCardForOnTrackAssessment() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 17), completedThrough: 10)

        XCTAssertEqual(assessment.summaryStatus, .onTrack)
        XCTAssertNil(GoalAssessmentBuilder.primaryAttentionItem(for: assessment))
    }

    func testInsufficientDataExplainsMissingRuns() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 5), completedThrough: 0, includeFitnessHistory: false)
        let item = try XCTUnwrap(assessment.attentionItems.first)

        XCTAssertEqual(item.titleKey, .dataMissingTitle)
        XCTAssertEqual(item.evidence.first?.kind, .missingQualifyingRuns)
    }

    func testCoachCTAContextHasStructuredIdentifiers() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 24), completedThrough: 3)
        let primary = try XCTUnwrap(GoalAssessmentBuilder.primaryAttentionItem(for: assessment))

        XCTAssertEqual(primary.recommendedAction?.id, "coach_recommendation_\(primary.id)")
    }

    func testVietnameseAndEnglishTerminology() {
        XCTAssertEqual(CoachLanguage.vi.goalAssessmentText(.targetTime), "Thời gian mục tiêu")
        XCTAssertEqual(CoachLanguage.vi.goalAssessmentText(.currentPrediction), "Dự đoán hiện tại")
        XCTAssertEqual(CoachLanguage.en.goalAssessmentText(.viewRecommendation), "View recommendation")
    }

    func testPredictionGapRendersSevenMinutes() {
        let target = 3 * 3600.0 + 59 * 60
        let predicted = 4 * 3600.0 + 6 * 60

        XCTAssertEqual(
            RaceGoalStatusCard.targetGapText(predictedSeconds: predicted, targetSeconds: target, language: .vi),
            "+7 phút so với mục tiêu"
        )
    }

    func testReadinessScoreDoesNotCollapseFromOneFactor() throws {
        let assessment = try makeAssessment(today: date(2026, 9, 7), completedThrough: 0)
        let score = try XCTUnwrap(assessment.readiness.score)

        XCTAssertGreaterThan(score, 0)
        XCTAssertLessThanOrEqual(score, 100)
    }

    func testMissingComponentsAreRenormalized() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 24), completedThrough: 10)
        let available = assessment.readiness.components.filter { $0.value != nil }
        let totalWeight = available.reduce(0) { $0 + $1.weight }
        let expected = Int(available.reduce(0) { partial, component in
            partial + min(max(component.value ?? 0, 0), 100) * (component.weight / totalWeight)
        }.rounded())

        XCTAssertEqual(assessment.readiness.score, expected)
        XCTAssertTrue(assessment.readiness.components.contains { $0.id == "recovery" && $0.value == nil })
    }

    func testMissingPredictionDoesNotRenderZero() throws {
        let assessment = try makeAssessment(today: date(2026, 8, 5), completedThrough: 0, includeFitnessHistory: false)

        XCTAssertNil(assessment.raceTimePrediction)
        XCTAssertNil(assessment.readiness.score)
    }

    private func makeAssessment(today: Date, completedThrough dueRuns: Int, includeFitnessHistory: Bool = true) throws -> GoalAssessment {
        let fixture = makeFixture(today: date(2026, 8, 3))
        let dueWorkouts = fixture.plan.workouts
            .filter { calendar.startOfDay(for: $0.date) <= calendar.startOfDay(for: today) }
            .sorted { $0.date < $1.date }
        let completed = Array(dueWorkouts.prefix(dueRuns)).map(activity)
        let history = includeFitnessHistory ? historicalActivities(endingAt: today) : []
        return try XCTUnwrap(GoalAssessmentBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: completed + history,
            today: today,
            calendar: calendar
        ))
    }

    private struct Fixture {
        var goal: Goal
        var plan: TrainingPlan
    }

    private func makeFixture(today: Date) -> Fixture {
        let goalSpec = GoalSpec(
            distance: .marathon,
            targetTimeSeconds: 4 * 3600 - 1,
            raceDate: date(2026, 10, 25),
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday
        )
        let fitness = FitnessProfile(vdot: 47, weeklyVolumeKm: 32, volumeTrend: 0.04, longestRecentRunKm: 18)
        let spec = PlanGenerator.generate(goal: goalSpec, fitness: fitness, today: today, calendar: calendar)
        let goal = Goal(spec: goalSpec, createdAt: today)
        let plan = TrainingPlan(spec: spec, generatedAt: today)
        for week in spec.weeks {
            for workoutSpec in week.workouts {
                let workout = PlannedWorkout(spec: workoutSpec, weekIndex: week.index, phase: week.phase)
                workout.plan = plan
                plan.workouts.append(workout)
            }
        }
        return Fixture(goal: goal, plan: plan)
    }

    private func activity(for workout: PlannedWorkout) -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: workout.date,
            distanceMeters: workout.distanceKm * 1000,
            durationSeconds: workout.expectedDurationSeconds ?? workout.distanceKm * 360,
            avgHeartRate: 145,
            maxHeartRate: 168,
            avgPaceSecondsPerKm: (workout.expectedDurationSeconds ?? workout.distanceKm * 360) / max(workout.distanceKm, 0.1),
            sourceName: "Unit Test"
        )
    }

    private func historicalActivities(endingAt today: Date) -> [CompletedActivity] {
        PlanEngineTestSupport.history(
            weeks: 8,
            runsPerWeek: 2,
            distanceKm: 8,
            paceSecondsPerKm: 330,
            endingAt: today
        ).map { sample in
            CompletedActivity(
                hkUUID: UUID(),
                date: sample.date,
                distanceMeters: sample.distanceKm * 1000,
                durationSeconds: sample.durationSeconds,
                avgHeartRate: 145,
                maxHeartRate: 168,
                avgPaceSecondsPerKm: sample.durationSeconds / sample.distanceKm,
                sourceName: "History"
            )
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 8) -> Date {
        PlanEngineTestSupport.date(year, month, day, hour: hour)
    }
}
