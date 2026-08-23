import XCTest
@testable import TrainOrRest

final class ReadinessWidgetSnapshotTests: XCTestCase {
    func testSaveAndLoadRoundTripsWidgetSnapshot() {
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: "ReadinessWidgetSnapshotTests"))
        defaults.removeObject(forKey: ReadinessWidgetSnapshot.storageKey)

        let snapshot = ReadinessWidgetSnapshot(
            score: 64,
            verdictRaw: "goEasy",
            verdictText: "Go easy",
            reason: "Sleep is below recent norm",
            computedAt: Date(timeIntervalSince1970: 1_785_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_785_000_300)
        )

        ReadinessWidgetSnapshot.save(snapshot, defaults: defaults)

        XCTAssertEqual(ReadinessWidgetSnapshot.load(defaults: defaults), snapshot)
    }

    func testLoadFallsBackToUnavailableWhenSnapshotIsMissing() {
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: "ReadinessWidgetSnapshotMissingTests"))
        defaults.removeObject(forKey: ReadinessWidgetSnapshot.storageKey)

        let snapshot = ReadinessWidgetSnapshot.load(defaults: defaults)

        XCTAssertNil(snapshot.score)
        XCTAssertEqual(snapshot.verdictRaw, "insufficientData")
        XCTAssertEqual(snapshot.verdictText, "Baseline")
    }
}
