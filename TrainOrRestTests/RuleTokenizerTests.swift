import XCTest
@testable import TrainOrRest

final class RuleTokenizerTests: XCTestCase {
    func testFindsCatalogRulesInRepresentativeProse() {
        let text = "Back off per R4, then reassess if symptoms persist (R7)."

        let tokens = RuleTokenizer.tokens(in: text)

        XCTAssertEqual(tokens.map(\.code), ["R4", "R7"])
        XCTAssertEqual(tokens.map(\.ruleID), [.hrvLow, .illness])
        XCTAssertEqual(tokens.map(\.range), [13..<15, 52..<54])
    }

    func testIgnoresUnknownAndInlineCodes() {
        let text = "R11 R0 R4X AR4 easyR7 R10a foo_R4 R7_suffix"

        XCTAssertTrue(RuleTokenizer.tokens(in: text).isEmpty)
    }

    func testReturnsSpansInSourceOrder() {
        let text = "Use R10 after R1; R4/R7 are separate citations."

        let tokens = RuleTokenizer.tokens(in: text)

        XCTAssertEqual(tokens.map(\.code), ["R10", "R1", "R4", "R7"])
        XCTAssertEqual(tokens.map(\.range), [4..<7, 14..<16, 18..<20, 21..<23])
    }

    func testEmptyWhenNoRulesArePresent() {
        XCTAssertTrue(RuleTokenizer.tokens(in: "Keep this as easy aerobic work.").isEmpty)
        XCTAssertTrue(RuleTokenizer.tokens(in: "").isEmpty)
    }
}
