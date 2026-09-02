#if DEBUG
import Foundation
import SwiftData
import UIKit

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
    /// Stable id for the empty thread used by the live coach verification seam.
    private static let liveThreadID = UUID(uuidString: "00000000-0000-0000-0000-00000C0AC11E")!

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["TOR_DEV_SEED"] == "1"
    }

    /// DEBUG-only launch route. When set alongside `TOR_DEV_SEED=1`, the app
    /// opens straight to a specific redesigned destination so its layout can
    /// be screenshotted without the onboarding-gated tab flow.
    enum DevScreen: String {
        case settings
        case provider
        case delivery
        case profile
        case coach
    }

    /// The requested launch screen, or `nil` for the normal tab shell.
    static var requestedScreen: DevScreen? {
        guard isRequested else { return nil }
        return ProcessInfo.processInfo.environment["TOR_DEV_SCREEN"]
            .flatMap(DevScreen.init(rawValue:))
    }

    /// When set with `TOR_DEV_SEED=1` and `TOR_DEV_SCREEN=coach`, the coach
    /// seam fires one live read-only turn so the real answer card can be
    /// verified against the provider.
    static var isLiveRequested: Bool {
        isRequested && ProcessInfo.processInfo.environment["TOR_DEV_LIVE"] == "1"
    }

    /// `TOR_DEV_TAB=calendar|chat|profile` picks the tab the seeded shell
    /// opens on so each root destination can be screenshotted directly.
    static var requestedTab: String? {
        guard isRequested else { return nil }
        return ProcessInfo.processInfo.environment["TOR_DEV_TAB"]
    }

    /// `TOR_DEV_ORIENTATION=landscape` asks the window scene for a landscape
    /// geometry at launch. Simulator rotation is otherwise only reachable via
    /// UI scripting, so this is the only headless route to landscape captures.
    static var wantsLandscape: Bool {
        isRequested && ProcessInfo.processInfo.environment["TOR_DEV_ORIENTATION"] == "landscape"
    }

    /// Applies `TOR_DEV_ORIENTATION` to every connected window scene. iPhone
    /// honors the request; multitasking-capable iPad builds follow the device
    /// orientation instead, so iPad landscape still needs a rotated simulator.
    @MainActor
    static func applyRequestedGeometry() {
        guard wantsLandscape else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
    }

    /// The prompt for the live coach turn; a read-only question by default so
    /// the forced `coach_response` tool path is exercised.
    static var livePrompt: String {
        let custom = ProcessInfo.processInfo.environment["TOR_DEV_LIVE_PROMPT"]
        if let custom, !custom.isEmpty { return custom }
        return "Give me a brief read on my recent recovery and readiness."
    }

    /// Seeds when requested and returns the thread the coach tab should open.
    /// Returns `nil` when seeding is off so the normal launch is untouched.
    @discardableResult
    @MainActor
    static func seedIfRequested(_ context: ModelContext) -> UUID? {
        guard isRequested else { return nil }

        OnboardingGate.markCompleted()
        preloadAPIKey()
        seedPlanIfRequested(context)
        seedHistoryIfRequested(context)
        if isLiveRequested { return seedLiveThread(context) }

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
        let anthropic = ProcessInfo.processInfo.environment["TOR_ANTHROPIC_KEY"]
        let anthropicKey = (anthropic?.isEmpty == false) ? anthropic! : "dev-seed-preview-key"
        try? KeychainStore.save(anthropicKey, account: KeychainStore.apiKeyAccount)
        if let openAI = ProcessInfo.processInfo.environment["TOR_OPENAI_KEY"], !openAI.isEmpty {
            try? KeychainStore.save(openAI, account: KeychainStore.openAIAPIKeyAccount)
        }
    }

    /// `TOR_DEV_PLAN=1` seeds a half-marathon goal ten weeks out so the
    /// calendar month grid and week list render populated instead of the
    /// empty state. Idempotent: an existing plan is left alone.
    @MainActor
    private static func seedPlanIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.environment["TOR_DEV_PLAN"] == "1" else { return }
        let hasPlan = (try? context.fetch(FetchDescriptor<TrainingPlan>()).isEmpty == false) ?? false
        if hasPlan { return }
        let today = Date()
        let calendar = Calendar.current
        let spec = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: calendar.date(byAdding: .weekOfYear, value: 10, to: today) ?? today,
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday
        )
        let fitness = FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0, longestRecentRunKm: 16)
        try? PlanStore.replaceGoal(spec: spec, fitness: fitness, today: today, calendar: calendar, in: context)
    }

    /// `TOR_DEV_HISTORY=1` seeds six months of wellness, runs, and readiness
    /// rows so launch, scrolling, and trends are measured against a realistic
    /// store instead of an empty one. Deterministic; idempotent.
    @MainActor
    private static func seedHistoryIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.environment["TOR_DEV_HISTORY"] == "1" else { return }
        let hasHistory = ((try? context.fetch(FetchDescriptor<DailyWellness>()).count) ?? 0) > 30
        if hasHistory { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for offset in 1...180 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let wave = sin(Double(offset) / 9)
            context.insert(DailyWellness(
                date: day,
                hrvSDNN: 48 + wave * 6,
                hrvPrimarySource: "Garmin",
                restingHeartRate: 49 - wave * 2,
                sleepHours: 7.2 + wave * 0.6,
                vo2Max: 52,
                deepSleepHours: 1.4,
                remSleepHours: 1.6,
                lightSleepHours: 4.2
            ))
            // Run on five of every seven days; long run every seventh.
            let weekday = offset % 7
            guard weekday != 1 && weekday != 4 else { continue }
            let km = weekday == 0 ? 18.0 : 8.0 + Double(weekday)
            let pace = weekday == 0 ? 320.0 : 290.0 - wave * 10
            context.insert(CompletedActivity(
                hkUUID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset))!,
                date: day.addingTimeInterval(7 * 3600),
                distanceMeters: km * 1000,
                durationSeconds: km * pace,
                avgHeartRate: 148 + wave * 4,
                maxHeartRate: 172,
                avgPaceSecondsPerKm: pace,
                sourceName: "Garmin"
            ))
            let verdict: ReadinessVerdict = wave < -0.7 ? .rest : (wave < 0 ? .goEasy : .train)
            let snapshot = ReadinessAssessment.Snapshot(
                hrvMean7: 48 + wave * 6, hrvMean28: 48, rhrMean7: 49 - wave * 2, rhrMean28: 49,
                sleepLastNight: 7.2 + wave * 0.6, sleepMean14: 7.2, acuteChronicRatio: 1.0 + wave * 0.2,
                hrvBaseline: 48, hrvSD: 5, rhrBaseline: 49, rhrSD: 2
            )
            context.insert(DailyReadiness(
                date: day,
                assessment: ReadinessAssessment(
                    verdict: verdict,
                    score: ReadinessScore.score(snapshot: snapshot, verdict: verdict),
                    reasons: [],
                    baselineDayCount: min(offset, 28),
                    snapshot: snapshot
                ),
                computedAt: day.addingTimeInterval(6 * 3600)
            ))
        }
        try? context.save()
    }

    /// Live-coach verification seam: an empty thread so one real read-only
    /// turn's answer card can be screenshotted against the provider.
    private static func seedLiveThread(_ context: ModelContext) -> UUID {
        let id = liveThreadID
        let exists = (try? context.fetch(
            FetchDescriptor<ChatThread>(predicate: #Predicate { $0.uuid == id })
        ).isEmpty == false) ?? false
        if exists { return id }
        context.insert(ChatThread(uuid: id, title: "Coach live", mode: .general))
        try? context.save()
        return id
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
