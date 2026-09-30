import XCTest
@testable import TrainOrRest

final class CoachConnectionStatusTests: XCTestCase {
    private let copy = CoachLanguage.en.settings

    private func status(
        _ selected: CoachConnection,
        _ chatGPT: ChatGPTConnectionState,
        anthropicKey: Bool = false,
        openAIKey: Bool = false
    ) -> CoachConnectionStatus {
        CoachConnectionStatus(selected: selected, chatGPT: chatGPT, hasAnthropicKey: anthropicKey, hasOpenAIKey: openAIKey)
    }

    func testEveryChatGPTStateMapsToItsTitleAndAction() {
        let expectations: [(ChatGPTConnectionState, String, CoachConnectionStatus.Action)] = [
            (.signedOut, "Connect your coach", .none),
            (.connected(email: "runner@example.com"), "Coach connected", .none),
            (.planUsageDisabled, "ChatGPT plan use is off", .allowPlanUse),
            (.usageLimited(until: nil), "ChatGPT limit reached", .manageUsage),
            (.notEligible, "ChatGPT plan not available", .none),
            (.needsReconnect, "Reconnect ChatGPT", .reconnect)
        ]
        for (state, title, action) in expectations {
            for keys in [false, true] {
                let result = status(.chatGPT, state, anthropicKey: keys, openAIKey: keys)
                XCTAssertEqual(result.title(copy), title, "\(state), keys: \(keys)")
                XCTAssertEqual(result.action, action, "\(state), keys: \(keys)")
            }
        }
    }

    func testChatGPTAttentionStatesKeepHistoryVisible() {
        XCTAssertFalse(status(.chatGPT, .signedOut).isChatGPTAttention)
        XCTAssertFalse(status(.chatGPT, .connected(email: nil)).isChatGPTAttention)
        XCTAssertTrue(status(.chatGPT, .planUsageDisabled).isChatGPTAttention)
        XCTAssertTrue(status(.chatGPT, .usageLimited(until: nil)).isChatGPTAttention)
        XCTAssertTrue(status(.chatGPT, .notEligible).isChatGPTAttention)
        XCTAssertTrue(status(.chatGPT, .needsReconnect).isChatGPTAttention)
    }

    func testKeyConnectionsIgnoreChatGPTStateAndFollowTheirOwnKey() {
        for state: ChatGPTConnectionState in [.signedOut, .needsReconnect, .usageLimited(until: nil)] {
            XCTAssertEqual(status(.anthropicKey, state, anthropicKey: true).kind, .keyConnected(.anthropicKey))
            XCTAssertEqual(status(.anthropicKey, state, openAIKey: true).kind, .notConnected)
            XCTAssertEqual(status(.openAIKey, state, openAIKey: true).kind, .keyConnected(.openAIKey))
            XCTAssertEqual(status(.openAIKey, state, anthropicKey: true).kind, .notConnected)
        }
    }

    func testConnectedChatGPTMessageNamesPlanEmailAndModel() {
        let result = status(.chatGPT, .connected(email: "runner@example.com"))
        XCTAssertEqual(
            result.message(copy, model: "GPT-5.5"),
            "Using your ChatGPT plan · runner@example.com · GPT-5.5"
        )
        XCTAssertEqual(status(.chatGPT, .connected(email: nil)).message(copy, model: nil), "Using your ChatGPT plan")
    }
}
