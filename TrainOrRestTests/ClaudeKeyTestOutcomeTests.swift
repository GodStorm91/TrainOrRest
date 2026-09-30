import XCTest
@testable import TrainOrRest

final class ClaudeKeyTestOutcomeTests: XCTestCase {
    func testMapsKeyCheckErrorsToTheirFix() {
        XCTAssertEqual(ClaudeKeyTestOutcome(error: nil), .connected)
        XCTAssertEqual(ClaudeKeyTestOutcome(error: ClaudeClientError.badKey), .rejected)
        XCTAssertEqual(
            ClaudeKeyTestOutcome(error: ClaudeClientError.api("Your credit balance is too low to access the Anthropic API.")),
            .needsCredits
        )
        XCTAssertEqual(
            ClaudeKeyTestOutcome(error: ClaudeClientError.api("max_tokens: field required")),
            .failed("max_tokens: field required")
        )
        XCTAssertEqual(ClaudeKeyTestOutcome(error: ClaudeClientError.rateLimited), .rateLimited)
        XCTAssertEqual(ClaudeKeyTestOutcome(error: ClaudeClientError.offline), .offline)
    }

    func testPastedKeyMustLookLikeAClaudeKey() {
        XCTAssertEqual(ClaudeKeyTestOutcome.claudeKey(fromPasted: "  sk-ant-api03-abc\n"), "sk-ant-api03-abc")
        XCTAssertNil(ClaudeKeyTestOutcome.claudeKey(fromPasted: ""))
        XCTAssertNil(ClaudeKeyTestOutcome.claudeKey(fromPasted: " \n"))
        XCTAssertNil(ClaudeKeyTestOutcome.claudeKey(fromPasted: "sk-ant-"))
        XCTAssertNil(ClaudeKeyTestOutcome.claudeKey(fromPasted: "sk-proj-abc123"))
    }
}
