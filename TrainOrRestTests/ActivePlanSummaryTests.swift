import XCTest
@testable import TrainOrRest

final class ActivePlanSummaryTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    func testNoActivePlanReturnsNil() {
        XCTAssertNil(ActivePlanSummaryBuilder.build(goal: nil, plan: nil, activities: [], today: date(2026, 8, 3), calendar: calendar))
    }

    func testActivePlanWithCompleteDataBuildsSummary() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: fixture.completedFirstTwoRuns,
            today: date(2026, 8, 12),
            calendar: calendar
        )

        XCTAssertEqual(summary?.title, "Sub-4:00 Marathon")
        XCTAssertEqual(summary?.totalWeeks, fixture.plan.weekTargetVolumesKm.count)
        XCTAssertEqual(summary?.currentWeek, 2)
        XCTAssertEqual(summary?.currentPhase?.phase, .base)
        XCTAssertNotNil(summary?.thisWeek)
        XCTAssertNotNil(summary?.nextWorkout)
        XCTAssertLessThanOrEqual(summary?.upcomingWorkouts.count ?? 99, 3)
    }

    func testPartialDataOmitsCurrentPhaseWhenPlanHasNoPhaseMetadata() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        fixture.plan.weekPhasesRaw = []

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 8, 4),
            calendar: calendar
        )

        XCTAssertNil(summary?.currentPhase)
        XCTAssertEqual(summary?.health.status, .active)
    }

    func testInsufficientAdherenceDataKeepsPlanActive() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 8, 3),
            calendar: calendar
        )

        XCTAssertEqual(summary?.health.status, .active)
        XCTAssertNil(summary?.health.adherenceRate)
    }

    func testOnTrackPlanRequiresCompletedDueWork() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        let dueActivities = activities(matching: Array(fixture.plan.workouts.prefix(4)))

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: dueActivities,
            today: date(2026, 8, 9),
            calendar: calendar
        )

        XCTAssertEqual(summary?.health.status, .onTrack)
        XCTAssertEqual(summary?.health.adherenceRate ?? -1, 1, accuracy: 0.01)
    }

    func testNeedsAttentionWhenSeveralDueSessionsAreMissed() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        let firstRun = activities(matching: [fixture.plan.workouts.sorted { $0.date < $1.date }[0]])

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: firstRun,
            today: date(2026, 8, 16),
            calendar: calendar
        )

        XCTAssertEqual(summary?.health.status, .needsAttention)
        XCTAssertTrue((summary?.health.missedKeySessions ?? 0) >= 1)
    }

    func testRaceDateTodayUsesRaceDayState() {
        let fixture = makeFixture(today: date(2026, 8, 3), raceDate: date(2026, 8, 30))

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 8, 30),
            calendar: calendar
        )

        XCTAssertTrue(summary?.isRaceDay == true)
        XCTAssertEqual(summary?.daysRemaining, 0)
        XCTAssertEqual(summary?.health.status, .active)
    }

    func testPastRaceMarksPlanCompleted() {
        let fixture = makeFixture(today: date(2026, 8, 3), raceDate: date(2026, 8, 30))

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 8, 31),
            calendar: calendar
        )

        XCTAssertEqual(summary?.health.status, .completed)
    }

    func testPausedPlanFreezesVisibleWeekAtPauseDate() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        fixture.plan.pausedAt = date(2026, 8, 10)

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 8, 24),
            calendar: calendar
        )

        XCTAssertEqual(summary?.health.status, .paused)
        XCTAssertEqual(summary?.currentWeek, 2)
    }

    func testMidWeekStartCalculatesFirstWeekFromPlanWeek() {
        let fixture = makeFixture(today: date(2026, 8, 5))

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 8, 6),
            calendar: calendar
        )

        XCTAssertEqual(summary?.currentWeek, 1)
        XCTAssertEqual(summary?.startDate, date(2026, 8, 3, hour: 0))
    }

    func testCurrentWeekAcrossTimeZoneBoundaryUsesCalendarDays() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let today = DateComponents(calendar: newYork, year: 2026, month: 11, day: 1, hour: 23).date!
        let race = DateComponents(calendar: newYork, year: 2026, month: 12, day: 13, hour: 8).date!
        let fixture = makeFixture(today: DateComponents(calendar: newYork, year: 2026, month: 10, day: 26, hour: 8).date!, raceDate: race, calendar: newYork)

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: today,
            calendar: newYork
        )

        XCTAssertEqual(summary?.currentWeek, 1)
    }

    func testNextWorkoutAndNoUpcomingWorkoutStates() {
        let fixture = makeFixture(today: date(2026, 8, 3))

        let withNext = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 8, 4),
            calendar: calendar
        )
        XCTAssertNotNil(withNext?.nextWorkout)

        let afterRace = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 10, 26),
            calendar: calendar
        )
        XCTAssertNil(afterRace?.nextWorkout)
    }

    func testCompletionUsesMatchedActivityReference() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        let workout = fixture.plan.workouts.sorted { $0.date < $1.date }[0]
        let activity = activity(on: workout.date, distanceKm: workout.distanceKm, duration: workout.expectedDurationSeconds ?? 1800)
        workout.matchedActivityUUID = activity.hkUUID

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [activity],
            today: workout.date,
            calendar: calendar
        )

        XCTAssertEqual(summary?.thisWeek?.completedSessions, 1)
    }

    func testUnmatchedCompletedActivityDoesNotSilentlyCountWhenAmbiguous() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        let sameDay = fixture.plan.workouts.sorted { $0.date < $1.date }[0].date
        let extra = PlannedWorkout(
            spec: PlannedWorkoutSpec(date: sameDay, kind: .easy, distanceKm: 5, paceBand: nil, details: "Extra"),
            weekIndex: 0,
            phase: .base
        )
        extra.plan = fixture.plan
        fixture.plan.workouts.append(extra)

        let activity = activity(on: sameDay, distanceKm: 12, duration: 10 * 3600)
        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [activity],
            today: sameDay,
            calendar: calendar
        )

        XCTAssertEqual(summary?.thisWeek?.completedSessions, 0)
    }

    func testPhaseTimelineUsesActualPlanPhases() {
        let fixture = makeFixture(today: date(2026, 8, 3))
        fixture.plan.weekPhasesRaw = [
            TrainingPhase.base.rawValue,
            TrainingPhase.base.rawValue,
            TrainingPhase.build.rawValue,
            TrainingPhase.taper.rawValue
        ]
        fixture.plan.weekTargetVolumesKm = [20, 22, 24, 12]

        let summary = ActivePlanSummaryBuilder.build(
            goal: fixture.goal,
            plan: fixture.plan,
            activities: [],
            today: date(2026, 8, 20),
            calendar: calendar
        )

        XCTAssertEqual(summary?.phases.map(\.phase), [.base, .build, .taper])
        XCTAssertEqual(summary?.currentPhase?.phase, .build)
    }

    private struct Fixture {
        var goal: Goal
        var plan: TrainingPlan
        var completedFirstTwoRuns: [CompletedActivity]
    }

    private func makeFixture(
        today: Date,
        raceDate: Date? = nil,
        calendar: Calendar? = nil
    ) -> Fixture {
        let calendar = calendar ?? self.calendar
        let goalSpec = GoalSpec(
            distance: .marathon,
            targetTimeSeconds: 4 * 3600 - 1,
            raceDate: raceDate ?? date(2026, 10, 25),
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
        let completedFirstTwoRuns = activities(matching: Array(plan.workouts.sorted { $0.date < $1.date }.prefix(2)))
        return Fixture(goal: goal, plan: plan, completedFirstTwoRuns: completedFirstTwoRuns)
    }

    private func activities(matching workouts: [PlannedWorkout]) -> [CompletedActivity] {
        workouts.map { workout in
            activity(
                on: workout.date,
                distanceKm: workout.distanceKm,
                duration: workout.expectedDurationSeconds ?? workout.distanceKm * 360
            )
        }
    }

    private func activity(on date: Date, distanceKm: Double, duration: Double) -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: date,
            distanceMeters: distanceKm * 1000,
            durationSeconds: duration,
            avgHeartRate: nil,
            maxHeartRate: nil,
            avgPaceSecondsPerKm: duration / max(distanceKm, 0.1),
            sourceName: "Unit Test"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 8) -> Date {
        PlanEngineTestSupport.date(year, month, day, hour: hour)
    }
}
