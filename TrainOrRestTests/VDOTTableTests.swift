import XCTest
@testable import TrainOrRest

/// Spot-checks the Daniels–Gilbert implementation against published rows of
/// the VDOT tables in "Daniels' Running Formula" (2% tolerance — the tables
/// are rounded outputs of the same model).
final class VDOTTableTests: XCTestCase {
    private func assertPredicted(vdot: Double, meters: Double, seconds: Double, file: StaticString = #filePath, line: UInt = #line) {
        let predicted = VDOTTable.predictedTimeSeconds(distanceMeters: meters, vdot: vdot)
        XCTAssertEqual(predicted, seconds, accuracy: seconds * 0.02, file: file, line: line)
    }

    func testPublishedRaceTimesMatchTableRows() {
        // VDOT 50 row
        assertPredicted(vdot: 50, meters: 5000, seconds: 19 * 60 + 57)
        assertPredicted(vdot: 50, meters: 10000, seconds: 41 * 60 + 21)
        assertPredicted(vdot: 50, meters: 21097.5, seconds: 91 * 60 + 35)
        assertPredicted(vdot: 50, meters: 42195, seconds: 3 * 3600 + 10 * 60 + 49)
        // VDOT 40 row
        assertPredicted(vdot: 40, meters: 5000, seconds: 24 * 60 + 8)
        assertPredicted(vdot: 40, meters: 42195, seconds: 3 * 3600 + 49 * 60 + 45)
        // VDOT 60 row
        assertPredicted(vdot: 60, meters: 5000, seconds: 17 * 60 + 3)
    }

    func testVDOTRoundTripsThroughPredictedTime() {
        for vdot in [35.0, 45.0, 55.0, 65.0] {
            let time = VDOTTable.predictedTimeSeconds(distanceMeters: 10000, vdot: vdot)
            let recovered = VDOTTable.vdot(distanceMeters: 10000, timeSeconds: time)
            XCTAssertEqual(recovered, vdot, accuracy: 0.05)
        }
    }

    func testThresholdPaceNearPublishedValue() {
        // Published T pace for VDOT 50 ≈ 4:15 min/km.
        let paces = VDOTTable.trainingPaces(vdot: 50)
        let published = 4.0 * 60 + 15
        XCTAssertLessThan(paces.threshold.fastSecondsPerKm, published + 8)
        XCTAssertGreaterThan(paces.threshold.slowSecondsPerKm, published - 8)
        XCTAssertLessThan(paces.threshold.fastSecondsPerKm, paces.threshold.slowSecondsPerKm)
    }

    func testPaceZonesAreOrdered() {
        let paces = VDOTTable.trainingPaces(vdot: 48)
        XCTAssertGreaterThan(paces.easy.fastSecondsPerKm, paces.marathon.fastSecondsPerKm)
        XCTAssertGreaterThan(paces.marathon.fastSecondsPerKm, paces.threshold.fastSecondsPerKm)
        XCTAssertGreaterThan(paces.threshold.fastSecondsPerKm, paces.interval.fastSecondsPerKm)
    }
}
