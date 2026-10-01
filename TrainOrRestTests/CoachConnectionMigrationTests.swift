import XCTest
@testable import TrainOrRest

final class CoachConnectionMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CoachConnectionMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func keys(_ accounts: Set<String>) -> (String) -> Bool {
        { accounts.contains($0) }
    }

    func testClaudeUserKeepsClaudeAndTheirModel() {
        defaults.set("claude-opus-4-8", forKey: CoachCredentialResolver.legacyModelKey)

        CoachCredentialResolver.migrateIfNeeded(defaults, hasStoredKey: keys([KeychainStore.apiKeyAccount]))

        let selection = CoachCredentialResolver.current(defaults)
        XCTAssertEqual(selection.connection, .anthropicKey)
        XCTAssertEqual(selection.model, "claude-opus-4-8")
        XCTAssertNil(defaults.string(forKey: CoachCredentialResolver.legacyModelKey))
    }

    func testOpenAIModelUserMovesToOpenAIKeyConnection() {
        defaults.set("gpt-5-nano", forKey: CoachCredentialResolver.legacyModelKey)

        CoachCredentialResolver.migrateIfNeeded(defaults, hasStoredKey: keys([KeychainStore.openAIAPIKeyAccount]))

        let selection = CoachCredentialResolver.current(defaults)
        XCTAssertEqual(selection.connection, .openAIKey)
        XCTAssertEqual(selection.model, "gpt-5-nano")
    }

    func testStoredKeyWithoutModelChoiceStaysOnClaudeDefault() {
        CoachCredentialResolver.migrateIfNeeded(defaults, hasStoredKey: keys([KeychainStore.apiKeyAccount]))

        let selection = CoachCredentialResolver.current(defaults)
        XCTAssertEqual(selection.connection, .anthropicKey)
        XCTAssertEqual(selection.model, CoachChatConfig.defaultModel)
    }

    func testFreshInstallStartsOnChatGPTWithCatalogResolvedModel() {
        CoachCredentialResolver.migrateIfNeeded(defaults, hasStoredKey: keys([]))

        let selection = CoachCredentialResolver.current(defaults)
        XCTAssertEqual(selection.connection, .chatGPT)
        XCTAssertEqual(selection.model, "", "the ChatGPT catalog picks the model once signed in")
    }

    func testMigrationRunsOnceAndKeepsLaterChoices() {
        defaults.set("claude-haiku-4-5", forKey: CoachCredentialResolver.legacyModelKey)
        CoachCredentialResolver.migrateIfNeeded(defaults, hasStoredKey: keys([KeychainStore.apiKeyAccount]))

        defaults.set(CoachConnection.chatGPT.rawValue, forKey: CoachConnection.storageKey)
        defaults.set("gpt-4o-mini", forKey: CoachCredentialResolver.legacyModelKey)
        CoachCredentialResolver.migrateIfNeeded(defaults, hasStoredKey: keys([KeychainStore.openAIAPIKeyAccount]))

        XCTAssertEqual(CoachCredentialResolver.current(defaults).connection, .chatGPT)
        XCTAssertEqual(CoachCredentialResolver.model(for: .anthropicKey, defaults: defaults), "claude-haiku-4-5")
        XCTAssertEqual(CoachCredentialResolver.model(for: .openAIKey, defaults: defaults), CoachChatConfig.defaultOpenAIModel)
    }
}
