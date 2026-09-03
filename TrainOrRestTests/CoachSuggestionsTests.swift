import XCTest
@testable import TrainOrRest

final class CoachSuggestionsTests: XCTestCase {
    private func context(
        hasMessages: Bool = true,
        lastMessageIsAssistant: Bool = true,
        hasRecentRun: Bool = false,
        recentRunWasHard: Bool = false,
        todayWorkoutKind: WorkoutKind? = nil
    ) -> CoachSuggestions.Context {
        .init(
            hasMessages: hasMessages,
            lastMessageIsAssistant: lastMessageIsAssistant,
            hasRecentRun: hasRecentRun,
            recentRunWasHard: recentRunWasHard,
            todayWorkoutKind: todayWorkoutKind
        )
    }

    func testAlwaysReturnsUpToLimitUniquePrompts() {
        let prompts = CoachSuggestions.prompts(for: context())
        XCTAssertFalse(prompts.isEmpty)
        XCTAssertLessThanOrEqual(prompts.count, 4)
        XCTAssertEqual(Set(prompts).count, prompts.count, "prompts must be de-duplicated")
    }

    func testRecentRunLeadsWithRecoveryFollowUp() {
        let prompts = CoachSuggestions.prompts(for: context(hasRecentRun: true))
        XCTAssertEqual(prompts.first, "How do I recover from this run?")
    }

    func testHardRunAsksIfTooHard() {
        let prompts = CoachSuggestions.prompts(for: context(hasRecentRun: true, recentRunWasHard: true))
        XCTAssertTrue(prompts.contains("Was that session too hard?"))
        XCTAssertFalse(prompts.contains("Should I push harder next time?"))
    }

    func testEasyRunAsksAboutPushingHarder() {
        let prompts = CoachSuggestions.prompts(for: context(hasRecentRun: true, recentRunWasHard: false))
        XCTAssertTrue(prompts.contains("Should I push harder next time?"))
        XCTAssertFalse(prompts.contains("Was that session too hard?"))
    }

    func testTodayWorkoutSurfacesSessionQuestion() {
        let prompts = CoachSuggestions.prompts(for: context(todayWorkoutKind: .tempo))
        XCTAssertTrue(prompts.contains("Why is today's tempo right for me?"))
    }

    func testRecentRunFollowUpsSuppressedWhenLastMessageIsUser() {
        // User just spoke; don't lead with a recovery follow-up to their own line.
        let prompts = CoachSuggestions.prompts(for: context(lastMessageIsAssistant: false, hasRecentRun: true))
        XCTAssertNotEqual(prompts.first, "How do I recover from this run?")
    }

    func testGeneralFallbacksWhenNoContext() {
        let prompts = CoachSuggestions.prompts(for: context(hasRecentRun: false, todayWorkoutKind: nil))
        XCTAssertEqual(prompts.first, "How's my training load trending?")
    }

    // MARK: - Localization

    func testDefaultLanguageIsEnglish() {
        let explicit = CoachSuggestions.prompts(for: context(hasRecentRun: true), language: .en)
        let defaulted = CoachSuggestions.prompts(for: context(hasRecentRun: true))
        XCTAssertEqual(explicit, defaulted)
    }

    func testJapaneseRecentRunPrompt() {
        let prompts = CoachSuggestions.prompts(for: context(hasRecentRun: true), language: .ja)
        XCTAssertEqual(prompts.first, "どうやって回復すればいい？")
    }

    func testVietnameseRecentRunPrompt() {
        let prompts = CoachSuggestions.prompts(for: context(hasRecentRun: true), language: .vi)
        XCTAssertEqual(prompts.first, "Làm sao để hồi phục?")
    }

    func testJapaneseLocalizesWorkoutKind() {
        let prompts = CoachSuggestions.prompts(for: context(todayWorkoutKind: .tempo), language: .ja)
        XCTAssertTrue(prompts.contains("今日のテンポ走はなぜ自分に合ってるの？"))
    }

    func testEveryLanguageProducesFullNonEmptyRow() {
        for language in CoachLanguage.allCases {
            let prompts = CoachSuggestions.prompts(for: context(hasRecentRun: true, todayWorkoutKind: .long), language: language)
            XCTAssertFalse(prompts.isEmpty, "\(language) produced no prompts")
            XCTAssertEqual(Set(prompts).count, prompts.count, "\(language) prompts not unique")
            XCTAssertFalse(prompts.contains(where: \.isEmpty), "\(language) has an empty prompt")
        }
    }
}
