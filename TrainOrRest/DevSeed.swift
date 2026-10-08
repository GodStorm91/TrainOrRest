#if DEBUG
import Foundation
import SwiftData
import UIKit

/// DEBUG-only launch seam used for deterministic visual verification.
///
/// The app is onboarding-gated and deep screens are not scriptable in the
/// simulator. `TOR_DEV_SEED=1` bypasses onboarding, preloads safe local data,
/// and can route directly to a screen selected with `TOR_DEV_SCREEN`.
///
/// The whole type is compiled out of release builds by `#if DEBUG`.
enum DevSeed {
    /// Stable id so relaunching a booted simulator reuses one thread instead of
    /// piling up duplicates.
    private static let threadID = UUID(uuidString: "00000000-0000-0000-0000-00000DE75EED")!
    /// Stable id for the empty thread used by the live coach verification seam.
    private static let liveThreadID = UUID(uuidString: "00000000-0000-0000-0000-00000C0AC11E")!
    private static let adaptiveReviewTriggerKey = "manual:00000000-0000-0000-0000-00000000ad17"

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
        case shoes
        case workout
        case chatGPTSpike
        case calendar
        case activity
    }

    /// The requested launch screen, or `nil` for the normal tab shell.
    static var requestedScreen: DevScreen? {
        guard isRequested else { return nil }
        return ProcessInfo.processInfo.environment["TOR_DEV_SCREEN"]
            .flatMap(DevScreen.init(rawValue:))
    }

    /// `TOR_DEV_ANALYSIS_TAB=splits` opens the activity analysis already
    /// expanded on that tab, since the disclosure toggle is not scriptable.
    static var expandedAnalysisTab: ActivityAnalysisTab? {
        guard isRequested else { return nil }
        return ProcessInfo.processInfo.environment["TOR_DEV_ANALYSIS_TAB"]
            .flatMap(ActivityAnalysisTab.init(rawValue:))
    }

    /// When set with `TOR_DEV_SEED=1` and `TOR_DEV_SCREEN=coach`, the coach
    /// seam fires one live read-only turn so the real answer card can be
    /// verified against the provider.
    static var isLiveRequested: Bool {
        isRequested && ProcessInfo.processInfo.environment["TOR_DEV_LIVE"] == "1"
    }

    /// `TOR_DEV_LIVE_EDIT=1` with `TOR_DEV_LIVE=1` and `TOR_DEV_PLAN=1` opens the
    /// live turn in "Edit with Coach" context on the next planned easy run so
    /// the plan-edit card can be verified against the provider.
    static var isLiveEditRequested: Bool {
        isLiveRequested && ProcessInfo.processInfo.environment["TOR_DEV_LIVE_EDIT"] == "1"
    }

    /// The workout the live edit turn attaches: the first planned, unlocked
    /// easy run on or after today.
    @MainActor
    static func liveEditWorkoutID(_ context: ModelContext) -> UUID? {
        guard isLiveEditRequested else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let rows = (try? context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))) ?? []
        return rows.first {
            $0.date >= start && $0.status == .planned && $0.kind == .easy && !$0.isScheduleLocked
        }?.uuid
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

    /// `TOR_DEV_LANG=en|ja|vi` pins the coach language for a seeded launch so
    /// every screen can be screenshotted in each supported language.
    private static func applyRequestedLanguage() {
        guard let raw = ProcessInfo.processInfo.environment["TOR_DEV_LANG"],
              CoachLanguage(rawValue: raw) != nil else { return }
        UserDefaults.standard.set(raw, forKey: CoachLanguage.storageKey)
    }

    /// Seeds when requested and returns the thread the coach tab should open.
    /// Returns `nil` when seeding is off so the normal launch is untouched.
    @discardableResult
    @MainActor
    static func seedIfRequested(_ context: ModelContext) -> UUID? {
        guard isRequested else { return nil }

        OnboardingGate.markCompleted()
        preloadAPIKey()
        applyRequestedChatGPTState()
        applyRequestedLanguage()
        seedPlanIfRequested(context)
        seedAdaptiveReviewIfRequested(context)
        seedTodayRunIfRequested(context)
        seedHistoryIfRequested(context)
        seedShoesIfRequested(context)
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

    /// `TOR_DEV_SCREEN=shoes` or `TOR_DEV_PLAN=1` seeds a small closet so the
    /// list and calendar show approaching wear copy, a healthy pair, and an
    /// automatic rotation over the planned runs.
    @MainActor
    private static func seedShoesIfRequested(_ context: ModelContext) {
        let wantsShoes = requestedScreen == .shoes
            || ProcessInfo.processInfo.environment["TOR_DEV_PLAN"] == "1"
        guard wantsShoes else { return }
        let hasShoes = (try? context.fetch(FetchDescriptor<RunningShoe>()).isEmpty == false) ?? false
        if !hasShoes {
            let now = Date()
            context.insert(RunningShoe(
                brand: "ASICS",
                model: "Gel-Nimbus 27",
                nickname: "Daily comfort",
                purchaseDate: now.addingTimeInterval(-120 * 86_400),
                initialMileageKm: 392,
                preferredWorkoutTypes: [.recovery, .easy, .longRun],
                primaryWorkoutType: .easy,
                expectedLifespanKm: 700,
                createdAt: now.addingTimeInterval(-120 * 86_400)
            ))
            context.insert(RunningShoe(
                brand: "New Balance",
                model: "FuelCell Rebel v5",
                nickname: "Speed day",
                purchaseDate: now.addingTimeInterval(-65 * 86_400),
                initialMileageKm: 188,
                preferredWorkoutTypes: [.tempo, .threshold, .intervals],
                primaryWorkoutType: .tempo,
                expectedLifespanKm: 550,
                createdAt: now.addingTimeInterval(-65 * 86_400)
            ))
            context.insert(RunningShoe(
                brand: "Nike",
                model: "Pegasus 41",
                nickname: "Inspect now",
                purchaseDate: now.addingTimeInterval(-250 * 86_400),
                initialMileageKm: 563,
                preferredWorkoutTypes: [.easy, .steady],
                primaryWorkoutType: .steady,
                expectedLifespanKm: 600,
                createdAt: now.addingTimeInterval(-250 * 86_400)
            ))
        }
        try? ShoeAssignmentService.reassignFutureAutomaticWorkouts(in: context)
        try? context.save()
    }

    private static func preloadAPIKey() {
        let anthropic = ProcessInfo.processInfo.environment["TOR_ANTHROPIC_KEY"]
        let anthropicKey = (anthropic?.isEmpty == false) ? anthropic! : "dev-seed-preview-key"
        try? KeychainStore.save(anthropicKey, account: KeychainStore.apiKeyAccount)
        if let openAI = ProcessInfo.processInfo.environment["TOR_OPENAI_KEY"], !openAI.isEmpty {
            try? KeychainStore.save(openAI, account: KeychainStore.openAIAPIKeyAccount)
        }
        UserDefaults.standard.set(CoachConnection.anthropicKey.rawValue, forKey: CoachConnection.storageKey)
    }

    /// `TOR_DEV_CHATGPT=signedOut|connected|planOff|limited|ineligible|reconnect` selects
    /// the ChatGPT connection and shows that state so every coach status can be screenshotted
    /// without a real sign-in. `connected` has no tokens, so sending still fails.
    private static func applyRequestedChatGPTState() {
        let state: ChatGPTConnectionState
        switch ProcessInfo.processInfo.environment["TOR_DEV_CHATGPT"] {
        case "signedOut": state = .signedOut
        case "connected": state = .connected(email: "runner@example.com")
        case "planOff": state = .planUsageDisabled
        case "limited": state = .usageLimited(until: nil)
        case "ineligible": state = .notEligible
        case "reconnect": state = .needsReconnect
        default: return
        }
        UserDefaults.standard.set(CoachConnection.chatGPT.rawValue, forKey: CoachConnection.storageKey)
        ChatGPTTokenStore.shared.debugOverrideState(state)
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

    /// `TOR_DEV_ADAPTIVE=queued|preparing|proposal|no-change|failed|stale|applied|reverted|superseded|needs-key|dismissed`
    /// paired with `TOR_DEV_PLAN=1` renders a deterministic next-week review state.
    @MainActor
    private static func seedAdaptiveReviewIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.environment["TOR_DEV_PLAN"] == "1",
              let raw = ProcessInfo.processInfo.environment["TOR_DEV_ADAPTIVE"],
              let phase = adaptivePhase(for: raw)
        else { return }
        guard (try? context.fetch(FetchDescriptor<AdaptivePlanReview>()).isEmpty) != false else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let activityID = UUID(uuidString: "00000000-0000-0000-0000-00000000ad18")!
        if (try? context.fetch(FetchDescriptor<CompletedActivity>()).contains(where: { $0.hkUUID == activityID })) != true {
            context.insert(CompletedActivity(
                hkUUID: activityID,
                date: calendar.date(byAdding: .hour, value: 7, to: today) ?? today,
                distanceMeters: 8_000,
                durationSeconds: 2_880,
                avgHeartRate: 148,
                maxHeartRate: 165,
                avgPaceSecondsPerKm: 360,
                sourceName: "Dev seed"
            ))
        }

        let review = AdaptivePlanReview(
            triggerKey: adaptiveReviewTriggerKey,
            origin: .manual,
            triggerActivityUUID: activityID,
            window: NextSevenDayWindow(start: today, end: end),
            createdAt: today
        )
        review.phaseRaw = phase.rawValue
        review.summary = phase == .noChange ? "No changes needed." : "Review fixture"

        if let proposal = adaptiveProposal(in: context, start: today, calendar: calendar),
           phase == .proposal || phase == .stale || phase == .applied || phase == .reverted {
            review.proposalJSON = try? String(decoding: JSONEncoder().encode(proposal), as: UTF8.self)
            review.basePlanRevision = try? CoachPlanRevision.current(in: context)
            if phase == .applied || phase == .reverted,
               let candidate = try? CoachPlanCandidateEngine.prepare(
                    proposal: proposal,
                    scope: review.scope,
                    in: context,
                    today: today,
                    calendar: calendar,
                    language: .en
               ),
               let result = try? CoachPlanCandidateEngine.commit(
                    candidate,
                    in: context,
                    today: today,
                    calendar: calendar,
                    language: .en
               ),
               case let .applied(receipt) = result {
                review.planEditID = receipt.id
                if phase == .reverted {
                    try? PlanEditStore.revert(receipt.id, in: context, today: today, calendar: calendar)
                }
            }
        }

        context.insert(review)
        try? context.save()
    }

    @MainActor
    static func preservesPreparingFixture(_ review: AdaptivePlanReview) -> Bool {
        ProcessInfo.processInfo.environment["TOR_DEV_ADAPTIVE"] == "preparing"
            && review.triggerKey == adaptiveReviewTriggerKey
    }

    private static func adaptivePhase(for raw: String) -> AdaptivePlanReviewPhase? {
        switch raw.lowercased() {
        case "queued": .queued
        case "preparing": .preparing
        case "proposal": .proposal
        case "no-change": .noChange
        case "failed": .failed
        case "stale": .stale
        case "applied": .applied
        case "reverted": .reverted
        case "superseded": .superseded
        case "needs-key": .needsKey
        case "dismissed": .dismissed
        default: nil
        }
    }

    @MainActor
    private static func adaptiveProposal(
        in context: ModelContext,
        start: Date,
        calendar: Calendar
    ) -> PlanAdjustmentProposal? {
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let workouts = (try? context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))) ?? []
        guard let workout = workouts.first(where: {
            $0.status == .planned
                && !$0.isScheduleLocked
                && $0.date >= start
                && $0.date < end
        }) else { return nil }
        return PlanAdjustmentProposal(changes: [.init(
            date: CoachContextBuilder.day(workout.date, calendar: calendar),
            action: .rest
        )])
    }

    @MainActor
    private static func seedTodayRunIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.environment["TOR_DEV_PLAN"] == "1",
              let mode = ProcessInfo.processInfo.environment["TOR_DEV_TODAY_RUN"],
              mode == "linked" || mode == "suggested" else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let activities = (try? context.fetch(FetchDescriptor<CompletedActivity>())) ?? []
        guard !activities.contains(where: { calendar.isDate($0.date, inSameDayAs: today) }) else { return }

        let workouts = (try? context.fetch(
            FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)])
        )) ?? []
        let workout: PlannedWorkout
        if let todayWorkout = workouts.first(where: {
            $0.status == .planned
                && $0.paceBand != nil
                && calendar.isDate($0.date, inSameDayAs: today)
        }) {
            workout = todayWorkout
        } else if let upcomingWorkout = workouts.first(where: {
            $0.status == .planned && $0.paceBand != nil && $0.date >= today
        }) {
            upcomingWorkout.date = calendar.date(
                bySettingHour: 8,
                minute: 0,
                second: 0,
                of: today
            ) ?? today
            workout = upcomingWorkout
        } else {
            return
        }

        let expectedDuration = workout.expectedDurationSeconds ?? 30 * 60
        func insertRun(hour: Int, minute: Int, distanceScale: Double, durationScale: Double) {
            let distanceKm = workout.distanceKm * distanceScale
            let duration = expectedDuration * durationScale
            let date = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: today
            ) ?? today
            context.insert(CompletedActivity(
                hkUUID: UUID(),
                date: date,
                distanceMeters: distanceKm * 1_000,
                durationSeconds: duration,
                avgHeartRate: 148,
                maxHeartRate: 165,
                avgPaceSecondsPerKm: duration / max(distanceKm, 0.1),
                sourceName: "Dev seed"
            ))
        }

        switch mode {
        case "linked":
            insertRun(hour: 7, minute: 12, distanceScale: 1.02, durationScale: 1.05)
        case "suggested":
            insertRun(hour: 6, minute: 30, distanceScale: 0.30, durationScale: 0.30)
            insertRun(hour: 18, minute: 10, distanceScale: 0.35, durationScale: 0.35)
        default:
            return
        }

        try? context.save()
        try? PlanStore.autoMatch(in: context, calendar: calendar)
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
            let km = weekday == 0 ? 18.0 : 8.0 + Double(weekday) + (weekday == 2 ? 0.42 : 0)
            let pace = weekday == 0 ? 320.0 : 290.0 - wave * 10
            let run = CompletedActivity(
                hkUUID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset))!,
                date: day.addingTimeInterval(7 * 3600),
                distanceMeters: km * 1000,
                durationSeconds: km * pace,
                avgHeartRate: 148 + wave * 4,
                maxHeartRate: 172,
                avgPaceSecondsPerKm: pace,
                sourceName: "Garmin"
            )
            run.splits = seededSplits(
                distanceKm: km,
                averagePace: pace,
                averageHeartRate: 148 + wave * 4,
                offset: offset
            )
            context.insert(run)
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

    /// Deterministic per-kilometer variation so every splits state can be
    /// screenshotted: measured, computed and refused, and not yet computed.
    private static func seededSplits(
        distanceKm: Double,
        averagePace: Double,
        averageHeartRate: Double,
        offset: Int
    ) -> [ActivitySplit]? {
        if offset % 11 == 0 { return nil }
        if offset % 7 == 3 { return [] }
        let fullKilometers = Int(distanceKm)
        guard fullKilometers >= 1 else { return [] }
        var splits: [ActivitySplit] = []
        for kilometer in 1...fullKilometers {
            let drift = sin(Double(kilometer) * 0.9 + Double(offset)) * 14 + Double(kilometer) * 1.4
            splits.append(ActivitySplit(
                kilometer: kilometer,
                distanceMeters: 1000,
                durationSeconds: averagePace + drift,
                averageHeartRate: averageHeartRate - drift * 0.2
            ))
        }
        let remainder = distanceKm - Double(fullKilometers)
        if remainder > 0.05 {
            splits.append(ActivitySplit(
                kilometer: fullKilometers + 1,
                distanceMeters: remainder * 1000,
                durationSeconds: remainder * (averagePace - 16),
                averageHeartRate: averageHeartRate + 7
            ))
        }
        return splits
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
