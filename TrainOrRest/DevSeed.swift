#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only launch seam used for visual verification of the coach chat.
///
/// The app is onboarding-gated and its Coach screen is not scriptable in the
/// simulator, so there is otherwise no way to screenshot rendered assistant
/// markdown. When the process is launched with `TOR_DEV_SEED=1` (see the
/// `--seed` path in `scripts/smoke.sh`) this seam:
///   1. marks onboarding complete so `RootView` lands on `.ready`,
///   2. preloads an API key so `ChatView` shows the message feed instead of
///      `missingKeyView`, and
///   3. inserts a deterministic coach thread whose assistant turns exercise the
///      ordered/unordered list + multi-line rendering paths.
///
/// The whole type is compiled out of release builds by `#if DEBUG`.
enum DevSeed {
    /// Stable id so relaunching a booted simulator reuses one thread instead of
    /// piling up duplicates.
    private static let threadID = UUID(uuidString: "00000000-0000-0000-0000-00000DE75EED")!

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["TOR_DEV_SEED"] == "1"
    }

    /// DEBUG-only launch route. When set alongside `TOR_DEV_SEED=1`, the app
    /// opens straight to a specific Settings destination so its redesigned
    /// layout can be screenshotted without the onboarding-gated tab flow.
    enum DevScreen: String {
        case settings
        case provider
        case delivery
    }

    /// The requested launch screen, or `nil` for the normal tab shell.
    static var requestedScreen: DevScreen? {
        guard isRequested else { return nil }
        return ProcessInfo.processInfo.environment["TOR_DEV_SCREEN"]
            .flatMap(DevScreen.init(rawValue:))
    }

    /// Seeds when requested and returns the thread the coach tab should open.
    /// Returns `nil` when seeding is off so the normal launch is untouched.
    @discardableResult
    static func seedIfRequested(_ context: ModelContext) -> UUID? {
        guard isRequested else { return nil }

        OnboardingGate.markCompleted()
        preloadAPIKey()

        let id = threadID
        let alreadySeeded = (try? context.fetch(
            FetchDescriptor<ChatThread>(predicate: #Predicate { $0.uuid == id })
        ).isEmpty == false) ?? false
        if alreadySeeded { return id }

        let thread = ChatThread(uuid: id, title: "Coach preview", mode: .general)
        context.insert(thread)

        let base = Date(timeIntervalSinceNow: -600)
        let turns: [(role: ChatRole, text: String, offset: TimeInterval)] = [
            (.user, "Design my session for today please.", 0),
            (.assistant, orderedListReply, 1),
            (.user, "Anything I should keep in mind out there?", 2),
            (.assistant, unorderedListReply, 3),
        ]
        for turn in turns {
            context.insert(ChatMessage(
                role: turn.role,
                text: turn.text,
                date: base.addingTimeInterval(turn.offset),
                threadID: id,
                status: turn.role == .assistant ? .completed : nil
            ))
        }
        try? context.save()
        return id
    }

    private static func preloadAPIKey() {
        let env = ProcessInfo.processInfo.environment["TOR_ANTHROPIC_KEY"]
        let key = (env?.isEmpty == false) ? env! : "dev-seed-preview-key"
        try? KeychainStore.save(key, account: CoachModelProvider.apiKeyAccount(for: CoachChatConfig.defaultModel))
    }

    // Numbered steps must keep "1." "2." "3." — the exact ordering the parser
    // fix preserves instead of collapsing every line to an identical bullet.
    private static let orderedListReply = """
    Here is today's tempo session:

    1. Warm up 15 min easy, building to steady by the end.
    2. 4 x 6 min at threshold, 90s easy float between reps.
    3. Cool down 10 min easy, then a few relaxed strides.

    Keep the middle reps controlled — even effort beats a fast first rep.
    """

    // Unordered lists still render as bullets, and the surrounding prose keeps
    // its author line breaks rather than folding into one wall of text.
    private static let unorderedListReply = """
    A few reminders before you head out:

    - Hydrate well; it is warm today.
    - Pick a flat loop so your pace stays honest.
    - Cut it short if anything sharp shows up.
    """
}
#endif
