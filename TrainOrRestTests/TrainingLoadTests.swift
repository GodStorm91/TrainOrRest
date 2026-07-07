import XCTest
@testable import TrainOrRest

final class TrainingLoadTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 8)
    private let paces = VDOTTable.trainingPaces(vdot: 50)

    func testIntensityLadder() {
        let tempo = paces.threshold.fastSecondsPerKm
        let easy = (paces.easy.fastSecondsPerKm + paces.easy.slowSecondsPerKm) / 2
        let crawl = paces.easy.slowSecondsPerKm + 60

        XCTAssertEqual(TrainingLoad.intensityFactor(avgPaceSecondsPerKm: tempo, paces: paces), TrainingLoad.Tuning.hardFactor)
        XCTAssertEqual(TrainingLoad.intensityFactor(avgPaceSecondsPerKm: easy, paces: paces), TrainingLoad.Tuning.easyFactor)
        XCTAssertEqual(TrainingLoad.intensityFactor(avgPaceSecondsPerKm: crawl, paces: paces), TrainingLoad.Tuning.recoveryFactor)
        // No pace or no zones → easy.
        XCTAssertEqual(TrainingLoad.intensityFactor(avgPaceSecondsPerKm: nil, paces: paces), TrainingLoad.Tuning.easyFactor)
        XCTAssertEqual(TrainingLoad.intensityFactor(avgPaceSecondsPerKm: easy, paces: nil), TrainingLoad.Tuning.easyFactor)
    }

    func testSessionLoadIsMinutesTimesIntensity() {
        let load = TrainingLoad.sessionLoad(
            durationSeconds: 3600,
            avgPaceSecondsPerKm: paces.threshold.fastSecondsPerKm,
            paces: paces
        )
        XCTAssertEqual(load, 60 * TrainingLoad.Tuning.hardFactor, accuracy: 0.001)
    }

    func testBalancedLoadRatioNearOne() {
        // Identical load every day for 5 weeks → ACWR = 1.
        let loads = (0..<35).map { daysBack in
            (
                date: calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!,
                load: 50.0
            )
        }
        let ratio = TrainingLoad.acuteChronicRatio(loads: loads, today: today, calendar: calendar)
        XCTAssertEqual(ratio!, 1.0, accuracy: 0.001)
    }

    func testSpikedRecentLoadRaisesRatio() {
        var loads = (7..<35).map { daysBack in
            (
                date: calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!,
                load: 30.0
            )
        }
        loads += (0..<7).map { daysBack in
            (
                date: calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!,
                load: 90.0
            )
        }
        let ratio = TrainingLoad.acuteChronicRatio(loads: loads, today: today, calendar: calendar)!
        XCTAssertGreaterThan(ratio, 1.3)
    }

    func testInsufficientHistoryReturnsNil() {
        let loads = (0..<14).map { daysBack in
            (
                date: calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!,
                load: 50.0
            )
        }
        XCTAssertNil(TrainingLoad.acuteChronicRatio(loads: loads, today: today, calendar: calendar))
    }
}
