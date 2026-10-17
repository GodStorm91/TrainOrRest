import XCTest
@testable import TrainOrRest

final class CoachDistanceCommandTests: XCTestCase {
    func testSuggestionTextNeverBecomesAPlanEdit() {
        XCTAssertNil(CoachDistanceCommand.parse("Đề xuất Threshold 7 km"))
        XCTAssertNil(CoachDistanceCommand.parse("Gợi ý bài ngưỡng 7 km cho hôm nay"))
        XCTAssertNil(CoachDistanceCommand.parse("Suggest a threshold 7 km today"))
    }

    func testBlockDistancesNeverBecomeTheNewTotal() {
        let text = "Đổi buổi hôm nay thành buổi ngưỡng: 2 km khởi động, 3 km ngưỡng, 2 km thả lỏng"
        XCTAssertNil(CoachDistanceCommand.parse(text))
    }

    func testExplicitTargetWinsOverBlockDistances() {
        let command = CoachDistanceCommand.parse("Đổi buổi hôm nay thành 7 km, gồm 2 km khởi động")
        XCTAssertEqual(command?.targetKm, 7.0)
    }

    func testSentenceNamingTwoKindsPicksTheRequestedOne() {
        XCTAssertEqual(CoachDistanceCommand.parse("đổi buổi chạy dài hôm nay thành bài ngưỡng 7 km")?.kind, .threshold)
        XCTAssertEqual(CoachDistanceCommand.parse("change the long run tomorrow to a threshold 7 km")?.kind, .threshold)
    }

    func testTwoKindsWithoutAChangeCueGiveUp() {
        XCTAssertNil(CoachDistanceCommand.workoutKind(inFolded: CoachDistanceCommand.fold("bài ngưỡng và bài chạy dài")))
    }

    func testPlainEditsStillParse() {
        let viet = CoachDistanceCommand.parse("đổi buổi hôm nay thành 7 km")
        XCTAssertEqual(viet?.targetKm, 7.0)
        XCTAssertEqual(viet?.relativeDay, .today)

        let english = CoachDistanceCommand.parse("change today to 7 km")
        XCTAssertEqual(english?.targetKm, 7.0)
        XCTAssertEqual(english?.relativeDay, .today)

        let dated = CoachDistanceCommand.parse("giảm 2025-10-17 từ 10 km xuống 7 km")
        XCTAssertEqual(dated?.targetKm, 7.0)
        XCTAssertEqual(dated?.sourceKm, 10.0)
        XCTAssertEqual(dated?.absoluteDay, "2025-10-17")
    }

    func testCueMatchingRespectsWordBoundaries() {
        XCTAssertNil(CoachDistanceCommand.parse("chạy nhanh 7 km"))
        XCTAssertFalse(CoachDistanceCommand.hasEditCue(in: CoachDistanceCommand.fold("lệnh nhanh")))
    }

    func testVietnameseDecimalCommaParses() {
        XCTAssertEqual(CoachDistanceCommand.parse("đổi buổi hôm nay thành 7,5 km")?.targetKm, 7.5)
    }
}
