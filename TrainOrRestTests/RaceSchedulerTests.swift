import XCTest
@testable import TrainOrRest

final class RaceSchedulerTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 1)

    func testEachPriorityAndDistanceUsesTableRecoveryAndMiniTaperCounts() {
        let expectations: [(RacePriority, RaceDistance, Int, Int)] = [
            (.a, .fiveK, 2, 0),
            (.a, .tenK, 3, 0),
            (.a, .halfMarathon, 4, 0),
            (.a, .marathon, 12, 0),
            (.b, .fiveK, 2, 3),
            (.b, .tenK, 3, 3),
            (.b, .halfMarathon, 4, 3),
            (.b, .marathon, 12, 3),
            (.c, .fiveK, 2, 0),
            (.c, .tenK, 2, 0),
            (.c, .halfMarathon, 2, 0),
            (.c, .marathon, 2, 0)
        ]

        for (index, expectation) in expectations.enumerated() {
            let race = makeRace(
                name: "Race \(index)",
                date: date(2026, 2, 1),
                distance: expectation.1,
                priority: expectation.0,
                id: uuid(index + 1)
            )
            let change = RaceScheduler.schedule(
                races: [race],
                planDays: [],
                today: today,
                calendar: calendar
            )

            XCTAssertEqual(
                change.dayChanges.filter { $0.intent == .recovery }.count,
                expectation.2,
                "\(expectation.0.rawValue) \(expectation.1.rawValue)"
            )
            XCTAssertEqual(
                change.dayChanges.filter { $0.intent == .miniTaper }.count,
                expectation.3,
                "\(expectation.0.rawValue) \(expectation.1.rawValue)"
            )
        }
    }

    func testARaceTaperReplacesOnlyQualitySessionsAtSixtyPercent() {
        let race = makeRace(
            name: "Anchor",
            date: date(2026, 2, 10),
            distance: .tenK,
            priority: .a,
            id: uuid(20)
        )
        let planDays = [
            planDay(2026, 2, 3, kind: .tempo, kilometers: 10, summary: "Tempo 10.0 km"),
            planDay(2026, 2, 4, kind: .long, kilometers: 16, summary: "Long 16.0 km"),
            planDay(2026, 2, 5, kind: .easy, kilometers: 8, summary: "Easy 8.0 km")
        ]

        let changes = RaceScheduler.schedule(
            races: [race],
            planDays: planDays,
            today: today,
            calendar: calendar
        ).dayChanges.filter { $0.intent == .taper }

        XCTAssertEqual(changes, [
            RaceDayChange(
                date: date(2026, 2, 3),
                intent: .taper,
                raceID: race.id,
                beforeSummary: "Tempo 10.0 km",
                afterSummary: "Easy 6.0 km",
                afterKilometers: 6
            )
        ])
    }

    func testARaceRecoverySkipsDaysWithoutAPlannedWorkout() {
        let race = makeRace(
            name: "Anchor",
            date: date(2026, 2, 10),
            distance: .halfMarathon,
            priority: .a,
            id: uuid(21)
        )
        let changes = RaceScheduler.schedule(
            races: [race],
            planDays: [planDay(2026, 2, 13, kind: .easy, kilometers: 8, summary: "Easy 8.0 km")],
            today: today,
            calendar: calendar
        ).dayChanges.filter { $0.intent == .recovery }

        XCTAssertEqual(changes, [
            RaceDayChange(date: date(2026, 2, 13), intent: .recovery, raceID: race.id, beforeSummary: "Easy 8.0 km", afterSummary: "Easy 4.0 km", afterKilometers: 4)
        ])
    }

    func testBRaceMiniTaperKeepsOneLargestQualitySessionScaled() {
        let race = makeRace(
            name: "Tune Up",
            date: date(2026, 2, 10),
            distance: .halfMarathon,
            priority: .b,
            id: uuid(22)
        )
        let planDays = [
            planDay(2026, 2, 7, kind: .tempo, kilometers: 10, summary: "Tempo 10.0 km"),
            planDay(2026, 2, 8, kind: .threshold, kilometers: 12, summary: "Threshold 12.0 km"),
            planDay(2026, 2, 9, kind: .intervals, kilometers: 8, summary: "Intervals 8.0 km"),
            planDay(2026, 2, 13, kind: .easy, kilometers: 6, summary: "Easy 6.0 km")
        ]
        let schedule = RaceScheduler.schedule(
            races: [race],
            planDays: planDays,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(schedule.dayChanges.filter { $0.intent == .miniTaper }, [
            RaceDayChange(date: date(2026, 2, 7), intent: .miniTaper, raceID: race.id, beforeSummary: "Tempo 10.0 km", afterSummary: "Easy 6.5 km", afterKilometers: 6.5),
            RaceDayChange(date: date(2026, 2, 8), intent: .miniTaper, raceID: race.id, beforeSummary: "Threshold 12.0 km", afterSummary: "Threshold 7.8 km", afterKilometers: 7.8),
            RaceDayChange(date: date(2026, 2, 9), intent: .miniTaper, raceID: race.id, beforeSummary: "Intervals 8.0 km", afterSummary: "Easy 5.2 km", afterKilometers: 5.2)
        ])
        XCTAssertEqual(schedule.dayChanges.filter { $0.intent == .recovery }, [
            RaceDayChange(date: date(2026, 2, 13), intent: .recovery, raceID: race.id, beforeSummary: "Easy 6.0 km", afterSummary: "Easy 3.0 km", afterKilometers: 3)
        ])
    }

    func testCRaceReplacesHardSessionAndEasesTheDayAfter() {
        let race = makeRace(
            name: "Park 5K",
            date: date(2026, 2, 10),
            distance: .fiveK,
            priority: .c,
            id: uuid(23)
        )
        let changes = RaceScheduler.schedule(
            races: [race],
            planDays: [
                planDay(2026, 2, 10, kind: .long, kilometers: 18, summary: "Long 18.0 km"),
                planDay(2026, 2, 11, kind: .easy, kilometers: 8, summary: "Easy 8.0 km")
            ],
            today: today,
            calendar: calendar
        ).dayChanges

        XCTAssertEqual(changes, [
            RaceDayChange(date: date(2026, 2, 10), intent: .replacesQuality, raceID: race.id, beforeSummary: "Long 18.0 km", afterSummary: "Race: Park 5K 5.0 km", afterKilometers: 5),
            RaceDayChange(date: date(2026, 2, 11), intent: .recovery, raceID: race.id, beforeSummary: "Easy 8.0 km", afterSummary: "Easy 4.0 km", afterKilometers: 4)
        ])
    }

    func testARacePriorityWinsWhenRacesTouchTheSameDay() {
        let aRace = makeRace(
            name: "Anchor",
            date: date(2026, 2, 10),
            distance: .fiveK,
            priority: .a,
            id: uuid(24)
        )
        let bRace = makeRace(
            name: "Tune Up",
            date: date(2026, 2, 10),
            distance: .tenK,
            priority: .b,
            id: uuid(25)
        )
        let changes = RaceScheduler.schedule(
            races: [bRace, aRace],
            planDays: [],
            today: today,
            calendar: calendar
        ).dayChanges

        XCTAssertEqual(changes.first { $0.date == date(2026, 2, 10) }, RaceDayChange(
            date: date(2026, 2, 10),
            intent: .raceDay,
            raceID: aRace.id,
            beforeSummary: nil,
            afterSummary: "Race: Anchor 5.0 km",
            afterKilometers: 5
        ))
        XCTAssertEqual(changes.map(\.date), changes.map(\.date).sorted())
    }

    func testBRacePriorityWinsOverCRaceWhenRacesTouchTheSameDay() {
        let bRace = makeRace(
            name: "Tune Up",
            date: date(2026, 2, 10),
            distance: .tenK,
            priority: .b,
            id: uuid(26)
        )
        let cRace = makeRace(
            name: "Fun Run",
            date: date(2026, 2, 10),
            distance: .fiveK,
            priority: .c,
            id: uuid(27)
        )
        let changes = RaceScheduler.schedule(
            races: [cRace, bRace],
            planDays: [],
            today: today,
            calendar: calendar
        ).dayChanges

        XCTAssertEqual(changes.first { $0.date == date(2026, 2, 10) }, RaceDayChange(
            date: date(2026, 2, 10),
            intent: .raceDay,
            raceID: bRace.id,
            beforeSummary: nil,
            afterSummary: "Race: Tune Up 10.0 km",
            afterKilometers: 10
        ))
    }

    func testBRaceInsideATaperEmitsOneWarning() {
        let aRace = makeRace(
            name: "Anchor",
            date: date(2026, 2, 20),
            distance: .marathon,
            priority: .a,
            id: uuid(30)
        )
        let bRace = makeRace(
            name: "Tune Up",
            date: date(2026, 2, 17),
            distance: .tenK,
            priority: .b,
            id: uuid(31)
        )
        let warnings = RaceScheduler.warnings(
            races: [aRace, bRace],
            today: today,
            calendar: calendar
        ).filter { $0.code == .insideARaceTaper }

        XCTAssertEqual(warnings, [RaceWarning(
            code: .insideARaceTaper,
            raceID: bRace.id,
            otherRaceID: aRace.id,
            dayGap: 3
        )])
    }

    func testHalfMarathonTwentyOneDaysAfterMarathonWarnsWithGap() {
        let marathon = makeRace(
            name: "Marathon",
            date: date(2026, 2, 1),
            distance: .marathon,
            priority: .a,
            id: uuid(32)
        )
        let half = makeRace(
            name: "Half",
            date: date(2026, 2, 22),
            distance: .halfMarathon,
            priority: .b,
            id: uuid(33)
        )

        XCTAssertEqual(RaceScheduler.warnings(
            races: [marathon, half],
            today: today,
            calendar: calendar
        ), [RaceWarning(
            code: .tooSoonAfterMarathon,
            raceID: half.id,
            otherRaceID: marathon.id,
            dayGap: 21
        )])
    }

    func testHalfMarathonThirtyFiveDaysAfterMarathonHasNoEarlyMarathonWarning() {
        let marathon = makeRace(
            name: "Marathon",
            date: date(2026, 2, 1),
            distance: .marathon,
            priority: .a,
            id: uuid(34)
        )
        let half = makeRace(
            name: "Half",
            date: date(2026, 3, 8),
            distance: .halfMarathon,
            priority: .b,
            id: uuid(35)
        )
        let warnings = RaceScheduler.warnings(
            races: [marathon, half],
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(warnings.filter { $0.code == .tooSoonAfterMarathon }, [])
    }

    func testRacesFiveDaysApartWarnOnLaterRace() {
        let earlier = makeRace(
            name: "First",
            date: date(2026, 2, 1),
            distance: .fiveK,
            priority: .c,
            id: uuid(36)
        )
        let later = makeRace(
            name: "Second",
            date: date(2026, 2, 6),
            distance: .tenK,
            priority: .c,
            id: uuid(37)
        )

        XCTAssertEqual(RaceScheduler.warnings(
            races: [earlier, later],
            today: today,
            calendar: calendar
        ), [RaceWarning(
            code: .racesTooClose,
            raceID: later.id,
            otherRaceID: earlier.id,
            dayGap: 5
        )])
    }

    func testRaceInsideEarlierRecoveryWindowEmitsWarning() {
        let earlier = makeRace(
            name: "First",
            date: date(2026, 2, 1),
            distance: .fiveK,
            priority: .b,
            id: uuid(38)
        )
        let later = makeRace(
            name: "Second",
            date: date(2026, 2, 3),
            distance: .tenK,
            priority: .c,
            id: uuid(39)
        )
        let warnings = RaceScheduler.warnings(
            races: [earlier, later],
            today: today,
            calendar: calendar
        ).filter { $0.code == .insideRecoveryWindow }

        XCTAssertEqual(warnings, [RaceWarning(
            code: .insideRecoveryWindow,
            raceID: later.id,
            otherRaceID: earlier.id,
            dayGap: 2
        )])
    }

    func testSuggestPriorityReturnsAWhenNoUpcomingARaceExists() {
        XCTAssertEqual(RaceScheduler.suggestPriority(
            for: date(2026, 2, 10),
            races: [],
            today: today,
            calendar: calendar
        ), RacePrioritySuggestion(priority: .a, reason: .noARaceYet, weeksToARace: nil))
    }

    func testSuggestPriorityReturnsBFarFromARaceAfterTwentyOneDays() {
        let aRace = makeRace(
            name: "Anchor",
            date: date(2026, 2, 1),
            distance: .tenK,
            priority: .a,
            id: uuid(40)
        )

        XCTAssertEqual(RaceScheduler.suggestPriority(
            for: date(2026, 2, 22),
            races: [aRace],
            today: today,
            calendar: calendar
        ), RacePrioritySuggestion(priority: .b, reason: .farFromARace, weeksToARace: 3))
    }

    func testSuggestPriorityReturnsCInsideATaper() {
        let aRace = makeRace(
            name: "Anchor",
            date: date(2026, 2, 10),
            distance: .tenK,
            priority: .a,
            id: uuid(41)
        )

        XCTAssertEqual(RaceScheduler.suggestPriority(
            for: date(2026, 2, 7),
            races: [aRace],
            today: today,
            calendar: calendar
        ), RacePrioritySuggestion(priority: .c, reason: .insideARaceTaper, weeksToARace: nil))
    }

    func testSuggestPriorityReturnsCInsideRecoveryWindow() {
        let bRace = makeRace(
            name: "Tune Up",
            date: date(2026, 2, 1),
            distance: .fiveK,
            priority: .b,
            id: uuid(42)
        )
        let aRace = makeRace(
            name: "Anchor",
            date: date(2026, 3, 1),
            distance: .tenK,
            priority: .a,
            id: uuid(43)
        )

        XCTAssertEqual(RaceScheduler.suggestPriority(
            for: date(2026, 2, 2),
            races: [bRace, aRace],
            today: today,
            calendar: calendar
        ), RacePrioritySuggestion(priority: .c, reason: .insideRecoveryWindow, weeksToARace: nil))
    }

    func testSuggestPriorityReturnsCCloseToARace() {
        let aRace = makeRace(
            name: "Anchor",
            date: date(2026, 2, 1),
            distance: .tenK,
            priority: .a,
            id: uuid(44)
        )

        XCTAssertEqual(RaceScheduler.suggestPriority(
            for: date(2026, 1, 20),
            races: [aRace],
            today: today,
            calendar: calendar
        ), RacePrioritySuggestion(priority: .c, reason: .closeToARace, weeksToARace: 1))
    }

    func testTokyoRaceAndPlanDayOnSameLocalDayProduceOneRaceDayChange() {
        let race = makeRace(
            name: "Evening 5K",
            date: date(2026, 2, 10, hour: 23),
            distance: .fiveK,
            priority: .c,
            id: uuid(45)
        )
        let schedule = RaceScheduler.schedule(
            races: [race],
            planDays: [planDay(2026, 2, 10, hour: 6, kind: .easy, kilometers: 8, summary: "Easy 8.0 km")],
            today: today,
            calendar: calendar
        )
        let raceDay = date(2026, 2, 10)

        XCTAssertEqual(schedule.dayChanges.filter { $0.date == raceDay }, [RaceDayChange(
            date: raceDay,
            intent: .raceDay,
            raceID: race.id,
            beforeSummary: "Easy 8.0 km",
            afterSummary: "Race: Evening 5K 5.0 km",
            afterKilometers: 5
        )])
    }

    func testScheduleIsDeterministic() {
        let aRace = makeRace(
            name: "Anchor",
            date: date(2026, 2, 10),
            distance: .halfMarathon,
            priority: .a,
            id: uuid(46)
        )
        let bRace = makeRace(
            name: "Tune Up",
            date: date(2026, 2, 1),
            distance: .tenK,
            priority: .b,
            id: uuid(47)
        )
        let planDays = [
            planDay(2026, 1, 29, kind: .tempo, kilometers: 10, summary: "Tempo 10.0 km"),
            planDay(2026, 2, 7, kind: .intervals, kilometers: 8, summary: "Intervals 8.0 km")
        ]

        let first = RaceScheduler.schedule(
            races: [bRace, aRace],
            planDays: planDays,
            today: today,
            calendar: calendar
        )
        let second = RaceScheduler.schedule(
            races: [bRace, aRace],
            planDays: planDays,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(first, second)
    }

    private func makeRace(
        name: String,
        date: Date,
        distance: RaceDistance,
        priority: RacePriority,
        id: UUID
    ) -> RaceSpec {
        RaceSpec(
            id: id,
            name: name,
            date: date,
            distanceMeters: distance.meters,
            priority: priority
        )
    }

    private func planDay(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 8,
        kind: WorkoutKind,
        kilometers: Double,
        summary: String
    ) -> RaceScheduler.PlanDay {
        RaceScheduler.PlanDay(
            date: date(year, month, day, hour: hour),
            kind: kind,
            kilometers: kilometers,
            summary: summary
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        PlanEngineTestSupport.date(year, month, day, hour: hour)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
