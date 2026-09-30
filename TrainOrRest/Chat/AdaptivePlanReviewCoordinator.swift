import Foundation
import SwiftData
import UIKit

@MainActor
final class AdaptivePlanReviewCoordinator: ObservableObject {
    private let anthropicClient: ClaudeServicing
    private let openAIClient: ClaudeServicing
    private let chatGPTClient: ClaudeServicing
    private let now: () -> Date
    private let isSceneActive: @MainActor () -> Bool
    private let isAutomaticEnabled: @MainActor () -> Bool
    private let calendar = Calendar.current
    private var candidates: [UUID: CoachPlanCandidate] = [:]
    private var inFlightReviewID: UUID?
    private var checkedInterruptedAttempts = false
    var beforeApplySaveForTesting: ((CoachPlanReceipt) throws -> Void)?

    init(
        anthropicClient: ClaudeServicing,
        openAIClient: ClaudeServicing,
        chatGPTClient: ClaudeServicing = ChatGPTResponsesClient(),
        now: @escaping () -> Date = Date.init,
        isSceneActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
        isAutomaticEnabled: @escaping @MainActor () -> Bool = { UserDefaults.standard.bool(forKey: AdaptivePlanReviewSettings.automaticKey) }
    ) {
        self.anthropicClient = anthropicClient
        self.openAIClient = openAIClient
        self.chatGPTClient = chatGPTClient
        self.now = now
        self.isSceneActive = isSceneActive
        self.isAutomaticEnabled = isAutomaticEnabled
    }

    func recordAutomaticRuns(_ runs: [NewRun], in context: ModelContext) throws {
        guard isAutomaticEnabled() else { return }
        let timestamp = now()
        let cutoff = timestamp.addingTimeInterval(-86_400)
        guard let run = runs
            .filter({ $0.endDate > cutoff && $0.endDate <= timestamp })
            .max(by: { $0.endDate < $1.endDate })
        else { return }

        let triggerKey = "automatic:\(run.hkUUID.uuidString.lowercased())"
        guard review(triggerKey: triggerKey, in: context) == nil else { return }

        let review = AdaptivePlanReview(
            triggerKey: triggerKey,
            origin: .automatic,
            triggerActivityUUID: run.hkUUID,
            window: try nextWeekWindow(from: timestamp),
            createdAt: timestamp
        )
        supersedeEarlierReviews(with: review.id, at: timestamp, in: context)
        context.insert(review)
        try context.save()
    }

    func beginManualReview(activityID: UUID?, in context: ModelContext) async {
        let timestamp = now()
        guard let window = try? nextWeekWindow(from: timestamp) else { return }
        let review = AdaptivePlanReview(
            triggerKey: "manual:\(UUID().uuidString.lowercased())",
            origin: .manual,
            triggerActivityUUID: activityID,
            window: window,
            createdAt: timestamp
        )
        supersedeEarlierReviews(with: review.id, at: timestamp, in: context)
        context.insert(review)
        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }
        await attempt(reviewID: review.id, kind: .manual, in: context)
    }

    func syncDidSettle(in context: ModelContext) async {
        preparePersistedState(in: context)
        refreshRevertedReceipts(in: context)
        rehydratePersistedCandidates(in: context)
        guard isAutomaticEnabled() else {
            dismissQueuedAutomaticReviews(in: context)
            return
        }
        guard inFlightReviewID == nil, isSceneActive(),
              let review = newestQueuedAutomaticReview(in: context) else { return }
        await attempt(reviewID: review.id, kind: .automatic, in: context)
    }

    func planDidChange(in context: ModelContext) {
        refreshRevertedReceipts(in: context)
    }

    func handle(_ action: AdaptivePlanReviewAction, reviewID: UUID, in context: ModelContext) async {
        guard let review = review(id: reviewID, in: context) else { return }

        switch action {
        case .dismiss:
            review.activeAttemptToken = nil
            review.transition(to: .dismissed, at: now())
            try? context.save()

        case .retry:
            guard inFlightReviewID == nil else { return }
            await attempt(reviewID: review.id, kind: .manual, in: context)

        case .apply(let acknowledging):
            apply(review, acknowledging: acknowledging, in: context)
        }
    }

    func candidateForPresentation(reviewID: UUID, in context: ModelContext) -> CoachPlanCandidate? {
        rehydratePersistedCandidates(in: context)
        return candidates[reviewID]
    }

    func selectedCoachIsConnected() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOR_DEV_ADAPTIVE"] == "needs-key" {
            return false
        }
        #endif
        return CoachCredentialResolver.isConnected(CoachCredentialResolver.current().connection)
    }

    private func attempt(
        reviewID: UUID,
        kind: AdaptivePlanReviewAttemptKind,
        in context: ModelContext
    ) async {
        guard inFlightReviewID == nil,
              let review = review(id: reviewID, in: context),
              review.phase == .queued || review.phase == .needsKey || review.phase == .failed
        else { return }

        let selection = CoachCredentialResolver.current()
        let model = selection.model
        guard let credential = CoachCredentialResolver.credential(for: selection.connection) else {
            review.activeAttemptToken = nil
            review.transition(to: .needsKey, at: now())
            try? context.save()
            return
        }

        let token = UUID()
        let timestamp = now()
        review.activeAttemptToken = token
        review.latestAttemptKindRaw = kind.rawValue
        if kind == .automatic {
            review.autoAttemptedAt = timestamp
        } else {
            review.manualRetryCount += 1
        }
        review.transition(to: .preparing, at: timestamp)
        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }

        inFlightReviewID = review.id

        do {
            let request = try request(for: review, model: model, in: context)
            let client = CoachClientRouter.client(
                for: selection.connection,
                anthropicClient: anthropicClient,
                openAIClient: openAIClient,
                chatGPTClient: chatGPTClient
            )
            let response = try await client.send(request, credential: credential)
            guard let current = self.review(id: reviewID, in: context),
                  current.phase == .preparing,
                  current.activeAttemptToken == token else {
                inFlightReviewID = nil
                await drainAutomaticQueue(in: context)
                return
            }
            guard kind != .automatic || isSceneActive() else {
                current.activeAttemptToken = nil
                current.transition(to: .queued, at: now())
                try? context.save()
                inFlightReviewID = nil
                return
            }
            guard kind != .automatic || isAutomaticEnabled() else {
                current.activeAttemptToken = nil
                current.transition(to: .dismissed, at: now())
                try? context.save()
                inFlightReviewID = nil
                return
            }

            try consume(response, for: current, in: context)
        } catch {
            guard let current = self.review(id: reviewID, in: context),
                  current.phase == .preparing,
                  current.activeAttemptToken == token else {
                inFlightReviewID = nil
                await drainAutomaticQueue(in: context)
                return
            }
            current.activeAttemptToken = nil
            current.transition(to: .failed, at: now(), error: error.localizedDescription)
            try? context.save()
        }

        inFlightReviewID = nil
        await drainAutomaticQueue(in: context)
    }

    private func consume(_ response: ClaudeResponse, for review: AdaptivePlanReview, in context: ModelContext) throws {
        guard let input = response.content.compactMap({ block -> JSONValue? in
            guard case let .toolUse(_, name, input) = block, name == AdaptiveReviewTool.name else { return nil }
            return input
        }).first else {
            throw CoachTools.ValidationError("The Coach did not return a next-week review.")
        }

        let envelope = try input.decoded(AdaptiveReviewProposalResponse.self)
        review.activeAttemptToken = nil
        review.summary = envelope.summary

        switch envelope.outcome {
        case .noChanges:
            guard envelope.changes.isEmpty else {
                throw CoachTools.ValidationError("A no-change review cannot include plan changes.")
            }
            review.proposalJSON = nil
            review.basePlanRevision = try CoachPlanRevision.current(in: context)
            review.candidateID = nil
            review.transition(to: .noChange, at: now())
            try context.save()

        case .proposal:
            guard (1...CoachTools.maxChangesPerProposal).contains(envelope.changes.count) else {
                throw CoachTools.ValidationError("A review proposal must contain one to five changes.")
            }
            let proposal = PlanAdjustmentProposal(changes: envelope.changes)
            let candidate = try CoachPlanCandidateEngine.prepare(
                proposal: proposal,
                scope: review.scope,
                in: context,
                today: now(),
                calendar: calendar,
                language: .current
            )
            review.proposalJSON = try encodedProposal(proposal)
            review.basePlanRevision = candidate.baseRevision
            review.candidateID = candidate.id
            review.transition(to: .proposal, at: now())
            candidates[review.id] = candidate
            try context.save()
        }
    }

    private func apply(
        _ review: AdaptivePlanReview,
        acknowledging: [PlanValidator.Issue],
        in context: ModelContext
    ) {
        let previousPhase = review.phase
        let previousPlanEditID = review.planEditID
        do {
            let candidate = try candidate(for: review, in: context)
            switch try CoachPlanCandidateEngine.commit(
                candidate,
                in: context,
                today: now(),
                calendar: calendar,
                language: .current,
                acknowledging: acknowledging,
                beforeSave: { receipt in
                    review.planEditID = receipt.id
                    review.activeAttemptToken = nil
                    review.transition(to: .applied, at: receipt.appliedAt)
                    try self.beforeApplySaveForTesting?(receipt)
                }
            ) {
            case .applied:
                candidates[review.id] = nil
            case .stale(let fresh):
                review.candidateID = fresh.id
                review.basePlanRevision = fresh.baseRevision
                review.activeAttemptToken = nil
                review.transition(to: .stale, at: now())
                candidates[review.id] = fresh
                try context.save()
            }
        } catch {
            review.planEditID = previousPlanEditID
            review.activeAttemptToken = nil
            review.transition(to: previousPhase, at: now(), error: error.localizedDescription)
            try? context.save()
        }
    }

    private func candidate(for review: AdaptivePlanReview, in context: ModelContext) throws -> CoachPlanCandidate {
        if let candidate = candidates[review.id] { return candidate }
        guard let proposal = decodedProposal(from: review) else {
            throw CoachTools.ValidationError("This review no longer has a proposal to apply.")
        }
        let candidate = try CoachPlanCandidateEngine.prepare(
            proposal: proposal,
            scope: review.scope,
            in: context,
            today: now(),
            calendar: calendar,
            language: .current
        )
        review.candidateID = candidate.id
        review.basePlanRevision = candidate.baseRevision
        candidates[review.id] = candidate
        try context.save()
        return candidate
    }

    private func preparePersistedState(in context: ModelContext) {
        guard !checkedInterruptedAttempts else { return }
        checkedInterruptedAttempts = true
        let timestamp = now()
        var didChange = false
        for review in reviews(in: context) where review.phase == .preparing {
            #if DEBUG
            if DevSeed.preservesPreparingFixture(review) {
                continue
            }
            #endif
            review.activeAttemptToken = nil
            review.transition(to: .failed, at: timestamp, error: "The previous review was interrupted.")
            didChange = true
        }
        if didChange { try? context.save() }
    }
    private func rehydratePersistedCandidates(in context: ModelContext) {
        for review in reviews(in: context) where review.phase == .proposal || review.phase == .stale {
            guard candidates[review.id] == nil else { continue }
            guard let proposal = decodedProposal(from: review) else {
                review.candidateID = nil
                review.transition(to: .failed, at: now(), error: "The saved review proposal could not be read.")
                try? context.save()
                continue
            }
            do {
                let candidate = try CoachPlanCandidateEngine.prepare(
                    proposal: proposal,
                    scope: review.scope,
                    in: context,
                    today: now(),
                    calendar: calendar,
                    language: .current
                )
                review.candidateID = candidate.id
                review.basePlanRevision = candidate.baseRevision
                candidates[review.id] = candidate
                try context.save()
            } catch {
                review.candidateID = nil
                review.transition(to: review.phase == .proposal ? .failed : .stale, at: now(), error: error.localizedDescription)
                try? context.save()
            }
        }
    }

    private func refreshRevertedReceipts(in context: ModelContext) {
        let receipts = (try? context.fetch(FetchDescriptor<PlanEdit>())) ?? []
        let reverted = Set(receipts.compactMap { receipt in receipt.revertedAt == nil ? nil : receipt.id })
        var didChange = false
        for review in reviews(in: context) where review.phase == .applied {
            guard let receiptID = review.planEditID, reverted.contains(receiptID) else { continue }
            review.transition(to: .reverted, at: now())
            didChange = true
        }
        if didChange { try? context.save() }
    }

    private func drainAutomaticQueue(in context: ModelContext) async {
        guard inFlightReviewID == nil else { return }
        guard isAutomaticEnabled() else {
            dismissQueuedAutomaticReviews(in: context)
            return
        }
        guard isSceneActive(), let next = newestQueuedAutomaticReview(in: context) else { return }
        await attempt(reviewID: next.id, kind: .automatic, in: context)
    }

    private func dismissQueuedAutomaticReviews(in context: ModelContext) {
        let timestamp = now()
        var didChange = false
        for review in reviews(in: context) where review.origin == .automatic && review.phase == .queued {
            review.activeAttemptToken = nil
            review.transition(to: .dismissed, at: timestamp)
            didChange = true
        }
        if didChange { try? context.save() }
    }

    private func newestQueuedAutomaticReview(in context: ModelContext) -> AdaptivePlanReview? {
        reviews(in: context).first { $0.origin == .automatic && $0.phase == .queued }
    }

    private func supersedeEarlierReviews(with replacementID: UUID, at timestamp: Date, in context: ModelContext) {
        for existing in reviews(in: context) where existing.phase.canBeSuperseded {
            existing.supersededByID = replacementID
            existing.activeAttemptToken = nil
            existing.transition(to: .superseded, at: timestamp)
            candidates[existing.id] = nil
        }
    }

    private func nextWeekWindow(from date: Date) throws -> NextSevenDayWindow {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            throw CoachTools.ValidationError("Could not calculate the next-week review window.")
        }
        return NextSevenDayWindow(start: start, end: end)
    }

    private func reviews(in context: ModelContext) -> [AdaptivePlanReview] {
        ((try? context.fetch(FetchDescriptor<AdaptivePlanReview>())) ?? []).sorted {
            $0.createdAt > $1.createdAt
        }
    }

    private func review(id: UUID, in context: ModelContext) -> AdaptivePlanReview? {
        reviews(in: context).first { $0.id == id }
    }

    private func review(triggerKey: String, in context: ModelContext) -> AdaptivePlanReview? {
        reviews(in: context).first { $0.triggerKey == triggerKey }
    }

    private func encodedProposal(_ proposal: PlanAdjustmentProposal) throws -> String {
        let data = try JSONEncoder().encode(proposal)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CoachTools.ValidationError("Could not persist the review proposal.")
        }
        return string
    }

    private func decodedProposal(from review: AdaptivePlanReview) -> PlanAdjustmentProposal? {
        guard let json = review.proposalJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlanAdjustmentProposal.self, from: data)
    }

    private func request(for review: AdaptivePlanReview, model: String, in context: ModelContext) throws -> ClaudeRequest {
        let payload = try AdaptiveReviewPromptPayload.build(
            review: review,
            now: now(),
            calendar: calendar,
            context: context
        )
        let payloadData = try JSONEncoder().encode(payload)
        let evidence = String(decoding: payloadData, as: UTF8.self)
        return ClaudeRequest(
            model: model,
            system: "You are the adaptive next-week plan reviewer. Use only the evidence JSON. Return exactly one \(AdaptiveReviewTool.name) tool call. A proposal must contain 1 to 5 changes; no_changes must contain none. Do not make edits yourself.\n\nEvidence:\n\(evidence)",
            tools: [AdaptiveReviewTool.tool],
            toolChoice: .tool(name: AdaptiveReviewTool.name),
            messages: [.init(role: "user", content: [.text("Review the next seven days.")])]
        )
    }
}

private struct AdaptiveReviewPromptPayload: Encodable {
    struct Run: Encodable {
        var uuid: String
        var localDate: String
        var distanceKm: Double?
        var durationSeconds: Double
        var paceSecondsPerKm: Double?
        var averageHeartRate: Double?
        var maxHeartRate: Double?
    }

    struct Planned: Encodable {
        var uuid: String
        var localDate: String
        var status: String
        var manuallyOverridden: Bool
        var scheduleLocked: Bool
        var kind: String
        var distanceKm: Double
        var paceFastSecondsPerKm: Double?
        var paceSlowSecondsPerKm: Double?
        var structure: [WorkoutStepGroup]
        var raceProtected: Bool
    }

    struct Readiness: Encodable {
        var verdict: String
        var score: Int?
        var reasons: [String]
        var computedAt: Date
    }

    var schemaVersion = 1
    var triggerActivityUUID: String?
    var windowStart: Date
    var windowEnd: Date
    var triggerRun: Run?
    var recentCompletedRuns: [Run]
    var plannedWindow: [Planned]
    var planRevision: String
    var activeGoalRaceDate: String?
    var readiness: Readiness?

    @MainActor
    static func build(
        review: AdaptivePlanReview,
        now: Date,
        calendar: Calendar,
        context: ModelContext
    ) throws -> Self {
        let activities = try context.fetch(FetchDescriptor<CompletedActivity>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        let trigger = review.triggerActivityUUID.flatMap { id in activities.first { $0.hkUUID == id } }
        let historyStart = calendar.date(byAdding: .day, value: -7, to: review.requestedWindowStart) ?? .distantPast
        let historical = activities
            .filter { $0.date >= historyStart && $0.date < review.requestedWindowStart }
            .prefix(7)
            .map { Run(activity: $0, calendar: calendar) }
        let planRows = try context.fetch(FetchDescriptor<PlannedWorkout>())
            .filter { $0.date >= review.requestedWindowStart && $0.date < review.requestedWindowEnd }
        let goal = try PlanStore.activeGoal(in: context)?.spec
        let raceDay = goal.map { calendar.startOfDay(for: $0.raceDate) }
        let readiness = try context.fetch(FetchDescriptor<DailyReadiness>(sortBy: [SortDescriptor(\.date, order: .reverse)])).first

        return Self(
            triggerActivityUUID: review.triggerActivityUUID?.uuidString,
            windowStart: review.requestedWindowStart,
            windowEnd: review.requestedWindowEnd,
            triggerRun: trigger.map { Run(activity: $0, calendar: calendar) },
            recentCompletedRuns: Array(historical),
            plannedWindow: planRows.map { row in
                Planned(
                    uuid: row.uuid.uuidString,
                    localDate: localDay(row.date, calendar: calendar),
                    status: row.statusRaw,
                    manuallyOverridden: row.manuallyOverridden,
                    scheduleLocked: row.isScheduleLocked,
                    kind: row.kindRaw,
                    distanceKm: row.distanceKm,
                    paceFastSecondsPerKm: row.paceFastSecondsPerKm,
                    paceSlowSecondsPerKm: row.paceSlowSecondsPerKm,
                    structure: row.structure,
                    raceProtected: row.kind == .race || calendar.startOfDay(for: row.date) == raceDay
                )
            },
            planRevision: try CoachPlanRevision.current(in: context),
            activeGoalRaceDate: goal.map { localDay($0.raceDate, calendar: calendar) },
            readiness: readiness.map { row in
                Readiness(verdict: row.verdictRaw, score: row.score, reasons: row.reasons, computedAt: row.computedAt)
            }
        )
    }

    private init(
        triggerActivityUUID: String?,
        windowStart: Date,
        windowEnd: Date,
        triggerRun: Run?,
        recentCompletedRuns: [Run],
        plannedWindow: [Planned],
        planRevision: String,
        activeGoalRaceDate: String?,
        readiness: Readiness?
    ) {
        self.triggerActivityUUID = triggerActivityUUID
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.triggerRun = triggerRun
        self.recentCompletedRuns = recentCompletedRuns
        self.plannedWindow = plannedWindow
        self.planRevision = planRevision
        self.activeGoalRaceDate = activeGoalRaceDate
        self.readiness = readiness
    }

    private static func localDay(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private extension AdaptiveReviewPromptPayload.Run {
    init(activity: CompletedActivity, calendar: Calendar) {
        self.init(
            uuid: activity.hkUUID.uuidString,
            localDate: AdaptiveReviewPromptPayload.localDay(activity.date, calendar: calendar),
            distanceKm: activity.distanceMeters.map { $0 / 1000 },
            durationSeconds: activity.durationSeconds,
            paceSecondsPerKm: activity.avgPaceSecondsPerKm,
            averageHeartRate: activity.avgHeartRate,
            maxHeartRate: activity.maxHeartRate
        )
    }
}
