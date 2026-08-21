import Foundation
import SwiftData

private struct CoachRetryUnavailableError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class CoachChatStore: ObservableObject {
    @Published private(set) var isSending = false
    @Published private(set) var isRetrying = false
    @Published var lastError: String?

    private let anthropicClient: ClaudeServicing
    private let openAIClient: ClaudeServicing
    private let calendar: Calendar
    private let now: () -> Date
    private let replacementCoordinator: WorkoutReplacementCoordinator?

    init(
        client: ClaudeServicing? = nil,
        anthropicClient: ClaudeServicing = ClaudeClient(),
        openAIClient: ClaudeServicing = OpenAIClient(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
        replacementCoordinator: WorkoutReplacementCoordinator? = nil
    ) {
        self.anthropicClient = client ?? anthropicClient
        self.openAIClient = client ?? openAIClient
        self.calendar = calendar
        self.now = now
        self.replacementCoordinator = replacementCoordinator
    }

    func send(
        text: String,
        model: String,
        attachments: [CoachContextAttachment] = [],
        evidence: EvidenceSelection? = nil,
        groundingSnapshot: GroundingSnapshot? = nil,
        threadID: UUID? = nil,
        in context: ModelContext
    ) async {
        let account = CoachModelProvider.apiKeyAccount(for: model)
        guard let apiKey = try? KeychainStore.load(account: account), !apiKey.isEmpty else {
            lastError = CoachLanguage.current.missingCoachKeyError(provider: CoachModelProvider.displayName(for: model))
            return
        }
        await send(
            text: text,
            model: model,
            attachments: attachments,
            evidence: evidence,
            groundingSnapshot: groundingSnapshot,
            apiKey: apiKey,
            threadID: threadID,
            in: context
        )
    }

    func send(
        text: String,
        model: String,
        attachments: [CoachContextAttachment] = [],
        evidence: EvidenceSelection? = nil,
        groundingSnapshot: GroundingSnapshot? = nil,
        apiKey: String,
        threadID: UUID? = nil,
        in context: ModelContext
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard replacementCoordinator?.hasPendingDecision != true else {
            lastError = CoachLanguage.current.replacementPendingMessage
            return
        }

        let submittedAt = now()
        let messageDate = Date()
        let selectedEvidence = evidence ?? EvidenceSelection(attachments: attachments)
        let grounding: GroundingSnapshot
        do {
            grounding = try groundingSnapshot ?? CoachGrounding.snapshot(
                evidence: selectedEvidence,
                in: context,
                today: submittedAt,
                calendar: calendar
            )
        } catch {
            lastError = technicalErrorMessage(error)
            return
        }

        isSending = true
        lastError = nil

        let userTurn = ChatMessage(role: .user, text: trimmed, date: messageDate, threadID: threadID)
        context.insert(userTurn)
        let snapshot = CoachRequestSnapshot(
            userTurnID: userTurn.turnID,
            messageText: trimmed,
            attachmentReferences: attachments.map(CoachAttachmentReference.init),
            selectedEvidenceSources: selectedEvidence,
            contextBoundaryMessageID: userTurn.turnID,
            locale: CoachLanguage.current.rawValue,
            createdAt: submittedAt,
            actionType: classifyAction(trimmed),
            groundingSnapshot: grounding,
            threadID: threadID
        )
        context.insert(snapshot)
        let assistantTurn = ChatMessage(
            role: .assistant,
            text: "",
            date: messageDate.addingTimeInterval(0.001),
            groundingFootnote: grounding.footnoteLine,
            groundingSummary: grounding.summary,
            threadID: threadID,
            parentUserTurnID: userTurn.turnID,
            requestSnapshotID: snapshot.id,
            status: .queued,
            operationID: snapshot.operationID
        )
        context.insert(assistantTurn)
        updateThread(threadID, titleFrom: trimmed, in: context)

        do {
            if try handleContextualDistanceShortcut(
                trimmed,
                attachments: attachments,
                snapshot: snapshot,
                assistantTurn: assistantTurn,
                in: context
            ) {
                isSending = false
                return
            }
        } catch {
            assistantTurn.text = Self.userFacingPlanToolRejection(technicalErrorMessage(error))
            assistantTurn.assistantStatus = .completed
            assistantTurn.isIncomplete = false
            assistantTurn.errorCategory = nil
            assistantTurn.errorMessage = nil
            assistantTurn.activeAttemptID = nil
            try? context.save()
            isSending = false
            return
        }

        try? context.save()

        await executeAttempt(
            assistantTurn,
            snapshot: snapshot,
            model: model,
            apiKey: apiKey,
            in: context,
            statusBeforeStreaming: .streaming
        )
        isSending = false
    }

    private func handleContextualDistanceShortcut(
        _ text: String,
        attachments: [CoachContextAttachment],
        snapshot: CoachRequestSnapshot,
        assistantTurn: ChatMessage,
        in context: ModelContext
    ) throws -> Bool {
        guard let replacementCoordinator,
              let workoutID = attachments.compactMap({ attachment -> UUID? in
                  if case .plannedWorkout(let uuid) = attachment { return uuid }
                  return nil
              }).first,
              let targetKm = Self.contextualDistanceTarget(from: text),
              let workout = try context.fetch(FetchDescriptor<PlannedWorkout>()).first(where: { $0.uuid == workoutID }),
              workout.status == .planned,
              workout.isScheduleLocked == false,
              workout.kind != .race,
              let kind = workout.kind,
              let payload = Self.sameKindPayload(kind: kind, distanceKm: targetKm)
        else {
            return false
        }

        let proposal = PlanAdjustmentProposal(changes: [.init(
            date: CoachContextBuilder.day(workout.date, calendar: calendar),
            action: .replace,
            workout: payload
        )])
        let replacement = try CoachTools.pendingReplacement(
            for: proposal,
            in: context,
            today: snapshot.createdAt,
            calendar: calendar,
            language: CoachLanguage(rawValue: snapshot.locale) ?? .current
        )
        guard let replacement else { return false }

        assistantTurn.text = "Em đã chuẩn bị đề xuất đổi cự li cho buổi này. Anh xem card bên dưới rồi xác nhận trước khi em lưu vào lịch."
        assistantTurn.assistantStatus = .completed
        assistantTurn.isIncomplete = false
        assistantTurn.errorCategory = nil
        assistantTurn.errorMessage = nil
        assistantTurn.activeAttemptID = nil
        replacementCoordinator.stage(replacement)
        try context.save()
        return true
    }

    func retryFailedResponse(_ assistantTurnID: UUID, model: String, apiKey: String, in context: ModelContext) async {
        guard !isSending, !isRetrying,
              let assistantTurn = message(assistantTurnID, in: context),
              assistantTurn.role == .assistant,
              let snapshot = snapshot(assistantTurn.requestSnapshotID, in: context) else { return }
        guard assistantTurn.assistantStatus == .failed else { return }

        guard isLatestUnresolvedAssistantTurn(assistantTurn, in: context) else {
            assistantTurn.errorCategory = .nonRetryable
            assistantTurn.errorMessage = CoachLanguage.current.olderFailureRetryMessage
            try? context.save()
            return
        }

        isRetrying = true
        isSending = true
        await executeAttempt(
            assistantTurn,
            snapshot: snapshot,
            model: model,
            apiKey: apiKey,
            in: context,
            statusBeforeStreaming: .retrying
        )
        isSending = false
        isRetrying = false
    }

    func retryFailedResponse(_ assistantTurnID: UUID, model: String, in context: ModelContext) async {
        let account = CoachModelProvider.apiKeyAccount(for: model)
        guard let apiKey = try? KeychainStore.load(account: account), !apiKey.isEmpty else {
            lastError = CoachLanguage.current.missingCoachKeyError(provider: CoachModelProvider.displayName(for: model))
            return
        }
        await retryFailedResponse(assistantTurnID, model: model, apiKey: apiKey, in: context)
    }

    func dismissFailedResponse(_ assistantTurnID: UUID, in context: ModelContext) {
        guard let assistantTurn = message(assistantTurnID, in: context), assistantTurn.role == .assistant else { return }
        assistantTurn.assistantStatus = .dismissed
        assistantTurn.errorCategory = nil
        assistantTurn.errorMessage = nil
        assistantTurn.activeAttemptID = nil
        try? context.save()
    }

    func cancelRetry(_ assistantTurnID: UUID, in context: ModelContext) {
        guard let assistantTurn = message(assistantTurnID, in: context), assistantTurn.assistantStatus == .retrying else { return }
        assistantTurn.assistantStatus = .failed
        assistantTurn.errorCategory = .retryableResponse
        assistantTurn.errorMessage = CoachLanguage.current.interruptedFailureMessage
        assistantTurn.activeAttemptID = nil
        try? context.save()
    }

    func resetError() {
        lastError = nil
    }

    func presentError(_ message: String) {
        lastError = message
    }

    func testConnection(apiKey: String, model: String) async -> String {
        let request = ClaudeRequest(
            model: model,
            system: "Reply with a short health check.",
            tools: [],
            messages: [ClaudeMessageParam(role: "user", content: [.text("Say OK.")])]
        )
        do {
            _ = try await CoachModelProvider.client(for: model, anthropicClient: anthropicClient, openAIClient: openAIClient).send(request, apiKey: apiKey)
            return "Connection OK"
        } catch {
            return technicalErrorMessage(error)
        }
    }

    private func executeAttempt(
        _ assistantTurn: ChatMessage,
        snapshot: CoachRequestSnapshot,
        model: String,
        apiKey: String,
        in context: ModelContext,
        statusBeforeStreaming: AssistantTurnStatus
    ) async {
        let attemptID = UUID()
        assistantTurn.activeAttemptID = attemptID
        assistantTurn.attemptCount += 1
        assistantTurn.assistantStatus = statusBeforeStreaming
        assistantTurn.errorCategory = nil
        assistantTurn.errorMessage = nil
        try? context.save()

        do {
            try await runLoop(
                apiKey: apiKey,
                model: model,
                snapshot: snapshot,
                assistantTurn: assistantTurn,
                attemptID: attemptID,
                in: context
            )
            guard assistantTurn.activeAttemptID == attemptID else { return }
            assistantTurn.assistantStatus = .completed
            assistantTurn.isIncomplete = false
            assistantTurn.errorCategory = nil
            assistantTurn.errorMessage = nil
            assistantTurn.activeAttemptID = nil
            lastError = nil
            try context.save()
        } catch {
            guard assistantTurn.activeAttemptID == attemptID else { return }
            markFailure(error, on: assistantTurn, snapshot: snapshot, in: context)
        }
    }

    private func runLoop(
        apiKey: String,
        model: String,
        snapshot: CoachRequestSnapshot,
        assistantTurn: ChatMessage,
        attemptID: UUID,
        in context: ModelContext
    ) async throws {
        let today = snapshot.createdAt
        var system = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)
        let directive = CoachLanguage(rawValue: snapshot.locale)?.systemPromptDirective ?? CoachLanguage.current.systemPromptDirective
        if !directive.isEmpty {
            system += "\n\n\(directive)"
        }
        let attachments = try attachments(from: snapshot, in: context)
        var conversation = try messageHistory(
            threadID: snapshot.threadID,
            boundaryMessageID: snapshot.contextBoundaryMessageID,
            in: context
        )
        if !attachments.isEmpty, var last = conversation.last, last.role == "user" {
            last.content = CoachAttachmentContextBuilder.content(
                text: snapshot.messageText,
                attachments: attachments,
                in: context,
                today: today,
                calendar: calendar
            )
            conversation[conversation.count - 1] = last
        }
        let applied: [String] = []
        var lastToolRejection: String?

        for _ in 0..<CoachChatConfig.maxToolRounds {
            let request = ClaudeRequest(model: model, system: system, tools: [CoachTools.tool], messages: conversation)
            let client = CoachModelProvider.client(for: model, anthropicClient: anthropicClient, openAIClient: openAIClient)
            let events = try await client.stream(request, apiKey: apiKey)
            var replacementStarted = false
            var lastStreamSave = Date.distantPast
            let streamSaveInterval: TimeInterval = 0.15
            let assembler = CoachStreamAssembler(
                onText: { delta in
                    guard assistantTurn.activeAttemptID == attemptID else { return }
                    if !replacementStarted {
                        assistantTurn.text = ""
                        assistantTurn.assistantStatus = .streaming
                        assistantTurn.isIncomplete = false
                        replacementStarted = true
                    }
                    assistantTurn.text += delta
                    let saveTime = Date()
                    if saveTime.timeIntervalSince(lastStreamSave) >= streamSaveInterval {
                        lastStreamSave = saveTime
                        try? context.save()
                    }
                }
            )
            let assembled = try await assembler.assemble(events)
            if let error = assembled.error {
                throw CoachTools.ValidationError(error)
            }
            let response = assembled.response

            if response.stopReason == "max_tokens" {
                throw CoachTools.ValidationError(
                    "Claude's reply was cut off before the plan edit was complete. Ask again."
                )
            }
            if response.stopReason == "refusal" {
                assistantTurn.text = response.content.textContent.isEmpty ? "Claude declined to answer that." : response.content.textContent
                assistantTurn.appliedAdjustment = nil
                try context.save()
                return
            }

            let toolUses = response.content.compactMap { block -> (String, String, JSONValue)? in
                if case let .toolUse(id, name, input) = block { return (id, name, input) }
                return nil
            }
            if toolUses.isEmpty {
                let text = response.content.textContent
                if lastToolRejection != nil, Self.containsPlanToolRetryDetour(text) {
                    let retryMessage = "Plan edits must be submitted with \(CoachTools.toolName). Fix the rejected JSON and call the tool again; do not ask the user to confirm the tool schema."
                    lastToolRejection = retryMessage
                    conversation.append(ClaudeMessageParam(role: "user", content: [.text("Rejected: \(retryMessage)")]))
                    continue
                }
                if Self.containsCalendarImportDetour(text) {
                    lastToolRejection = Self.calendarImportDetourMessage
                    conversation.append(ClaudeMessageParam(
                        role: "user",
                        content: [.text("Rejected: \(Self.calendarImportDetourMessage) Call \(CoachTools.toolName) with the concrete calendar changes instead.")]
                    ))
                    continue
                }
                assistantTurn.text = text.isEmpty ? "I could not produce a response." : text
                assistantTurn.appliedAdjustment = applied.isEmpty ? nil : applied.joined(separator: "; ")
                try context.save()
                return
            }

            assistantTurn.text = ""
            conversation.append(ClaudeMessageParam(role: "assistant", content: response.content))
            guard toolUses.count == 1 else {
                lastToolRejection = "Submit one plan adjustment at a time."
                conversation.append(ClaudeMessageParam(role: "user", content: toolUses.map {
                    .toolResult(toolUseID: $0.0, content: "Rejected: submit one plan adjustment at a time.", isError: true)
                }))
                continue
            }

            let toolUse = toolUses[0]
            guard toolUse.1 == CoachTools.toolName else {
                lastToolRejection = "Unknown coach tool."
                conversation.append(ClaudeMessageParam(role: "user", content: [
                    .toolResult(toolUseID: toolUse.0, content: "Unknown tool.", isError: true)
                ]))
                continue
            }

            do {
                let proposal = try toolUse.2.decoded(PlanAdjustmentProposal.self)
                try validateContextualProposal(proposal, attachments: attachments, in: context)
                if let replacement = try CoachTools.pendingReplacement(for: proposal, in: context, today: today, calendar: calendar, language: .current) {
                    guard let replacementCoordinator else {
                        throw CoachTools.ValidationError("Workout replacement confirmation is unavailable.")
                    }
                    assistantTurn.text = "I prepared this workout replacement. Review it below before I save it."
                    replacementCoordinator.stage(replacement)
                    try context.save()
                    return
                }

                guard let replacementCoordinator else {
                    throw CoachTools.ValidationError("Plan update confirmation is unavailable.")
                }
                let validated = try CoachTools.validateForConfirmation(proposal: proposal, in: context, today: today, calendar: calendar)
                let summary = validated.summary.isEmpty ? CoachTools.summary(for: proposal) : validated.summary
                assistantTurn.text = "I prepared this calendar update. Review it below before I save it: \(summary)"
                try context.save()
                replacementCoordinator.stage(proposal, summary: summary, threadID: snapshot.threadID)
                return
            } catch {
                let message = technicalErrorMessage(error)
                lastToolRejection = message
                conversation.append(ClaudeMessageParam(role: "user", content: [
                    .toolResult(toolUseID: toolUse.0, content: "Rejected: \(message)", isError: true)
                ]))
            }
        }

        if !applied.isEmpty {
            assistantTurn.text = "Applied: \(applied.joined(separator: "; "))"
            assistantTurn.appliedAdjustment = applied.joined(separator: "; ")
        } else if let lastToolRejection {
            assistantTurn.text = Self.userFacingPlanToolRejection(lastToolRejection)
        } else {
            assistantTurn.text = "I could not safely finish the plan adjustment. Please try one specific change at a time."
        }
        try context.save()
    }

    private func markFailure(
        _ error: Error,
        on assistantTurn: ChatMessage,
        snapshot: CoachRequestSnapshot,
        in context: ModelContext
    ) {
        let message = technicalErrorMessage(error)
        let category = failureCategory(for: error, snapshot: snapshot)
        assistantTurn.assistantStatus = category == .mutationUnknown ? .reconciling : .failed
        assistantTurn.errorCategory = category
        assistantTurn.errorMessage = userFacingInlineError(for: category, raw: message)
        assistantTurn.isIncomplete = !assistantTurn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        assistantTurn.activeAttemptID = nil
        lastError = message
        try? context.save()
    }

    private func failureCategory(for error: Error, snapshot: CoachRequestSnapshot) -> CoachErrorCategory {
        if snapshot.actionType == .planMutation {
            return .mutationUnknown
        }
        if error is CoachRetryUnavailableError {
            return .missingAttachment
        }
        guard let clientError = error as? ClaudeClientError else { return .retryableResponse }
        switch clientError {
        case .offline:
            return .offline
        case .badKey:
            return .authentication
        case .connectionLost, .rateLimited, .invalidResponse, .api:
            return .retryableResponse
        }
    }

    private func userFacingInlineError(for category: CoachErrorCategory, raw: String) -> String {
        switch category {
        case .retryableResponse, .offline:
            return CoachLanguage.current.interruptedFailureMessage
        case .missingAttachment:
            return CoachLanguage.current.missingAttachmentFailureMessage
        case .authentication:
            return CoachLanguage.current.authenticationFailureMessage
        case .mutationUnknown:
            return CoachLanguage.current.mutationReconciliationMessage
        case .nonRetryable:
            return raw
        }
    }

    private func attachments(from snapshot: CoachRequestSnapshot, in context: ModelContext) throws -> [CoachContextAttachment] {
        try snapshot.attachmentReferences.map { reference in
            switch reference.kind {
            case .health:
                return .health
            case .plannedWorkout:
                guard let uuid = reference.uuid,
                      (try? context.fetch(FetchDescriptor<PlannedWorkout>()).contains(where: { $0.uuid == uuid })) == true else {
                    throw CoachRetryUnavailableError(message: CoachLanguage.current.missingAttachmentFailureMessage)
                }
                return .plannedWorkout(uuid)
            case .completedActivity:
                guard let uuid = reference.uuid,
                      (try? context.fetch(FetchDescriptor<CompletedActivity>()).contains(where: { $0.hkUUID == uuid })) == true else {
                    throw CoachRetryUnavailableError(message: CoachLanguage.current.missingAttachmentFailureMessage)
                }
                return .completedActivity(uuid)
            case .image:
                guard let data = reference.imageData, let mediaType = reference.mediaType, let filename = reference.filename else {
                    throw CoachRetryUnavailableError(message: CoachLanguage.current.missingAttachmentFailureMessage)
                }
                return .image(CoachImageAttachment(data: data, mediaType: mediaType, filename: filename))
            }
        }
    }

    private func validateContextualProposal(
        _ proposal: PlanAdjustmentProposal,
        attachments: [CoachContextAttachment],
        in context: ModelContext
    ) throws {
        if attachments.contains(where: {
            if case .completedActivity = $0 { return true }
            return false
        }) {
            throw CoachTools.ValidationError("Completed runs can be reviewed with Coach, but this flow cannot apply workout-plan changes to a completed activity.")
        }

        guard let selectedWorkoutID = attachments.compactMap({ attachment -> UUID? in
            if case .plannedWorkout(let uuid) = attachment { return uuid }
            return nil
        }).first else { return }

        guard let selected = try context.fetch(FetchDescriptor<PlannedWorkout>()).first(where: { $0.uuid == selectedWorkoutID }) else {
            throw CoachTools.ValidationError("The selected workout is no longer available.")
        }
        let selectedDay = calendar.startOfDay(for: selected.date)
        for change in proposal.changes {
            guard let proposalDay = Self.planToolDateFormatter.date(from: change.date) else {
                throw CoachTools.ValidationError("The contextual workout proposal used an invalid date.")
            }
            guard calendar.isDate(proposalDay, inSameDayAs: selectedDay) else {
                throw CoachTools.ValidationError("This proposal targets a different workout. Switch context before editing another workout.")
            }
            if selected.isScheduleLocked || selected.kind == .race {
                throw CoachTools.ValidationError("This workout is fixed. Ask Coach to review alternatives or explicitly unlock it before applying changes.")
            }
            guard selected.status == .planned else {
                throw CoachTools.ValidationError("Only planned workouts can be changed from this contextual edit flow.")
            }
        }
    }

    private static let planToolDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func classifyAction(_ text: String) -> CoachRequestActionType {
        let lower = text.lowercased()
        let mutationNeedles = [
            "create workout", "add workout", "update plan", "delete workout", "modify calendar",
            "save settings", "push workout", "thêm bài", "tạo bài", "sửa lịch", "đổi lịch", "xóa bài",
            "đổi cự li", "đổi cự ly", "đổi quãng đường", "change distance"
        ]
        return mutationNeedles.contains { lower.contains($0) } ? .planMutation : .readOnly
    }

    private static func contextualDistanceTarget(from text: String) -> Double? {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: ",", with: ".")
        let lower = folded.lowercased()
        let distanceNeedles = [
            "cu li", "cu ly", "quang duong", "distance", "kilometer", "kilometre",
            "thanh", "to ", "len", "xuong"
        ]
        guard distanceNeedles.contains(where: { lower.contains($0) }) else { return nil }

        let patterns = [
            #"(?<![\d.])(\d+(?:\.\d+)?)\s*(?:km|kilometer|kilometre|k)(?![a-z])"#,
            #"(?:thanh|to|len|xuong)\s+(\d+(?:\.\d+)?)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            guard let match = regex.firstMatch(in: lower, options: [], range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: lower),
                  let value = Double(lower[valueRange]),
                  value > 0
            else { continue }
            return value
        }
        return nil
    }

    private static func sameKindPayload(kind: WorkoutKind, distanceKm: Double) -> PlanAdjustmentProposal.CreateWorkout? {
        guard distanceKm.isFinite, distanceKm > 0 else { return nil }
        switch kind {
        case .easy, .long:
            return PlanAdjustmentProposal.CreateWorkout(
                kind: kind.rawValue,
                blocks: [
                    .init(repeatCount: 1, steps: [
                        .init(role: "work", targetType: "distance_km", targetValue: distanceKm, paceZone: "easy")
                    ])
                ]
            )
        case .tempo:
            let workKm = max(0.5, distanceKm - WorkoutFactory.warmupKm - WorkoutFactory.cooldownKm)
            return PlanAdjustmentProposal.CreateWorkout(
                kind: kind.rawValue,
                blocks: [
                    .init(repeatCount: 1, steps: [
                        .init(role: "warm_up", targetType: "distance_km", targetValue: WorkoutFactory.warmupKm, paceZone: "easy")
                    ]),
                    .init(repeatCount: 1, steps: [
                        .init(role: "work", targetType: "distance_km", targetValue: workKm, paceZone: "threshold")
                    ]),
                    .init(repeatCount: 1, steps: [
                        .init(role: "cool_down", targetType: "distance_km", targetValue: WorkoutFactory.cooldownKm, paceZone: "easy")
                    ])
                ]
            )
        case .intervals, .race:
            return nil
        }
    }

    private func message(_ id: UUID?, in context: ModelContext) -> ChatMessage? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<ChatMessage>()
        descriptor.fetchLimit = 200
        return (try? context.fetch(descriptor))?.first { $0.turnID == id }
    }

    private func snapshot(_ id: UUID?, in context: ModelContext) -> CoachRequestSnapshot? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<CoachRequestSnapshot>()
        descriptor.fetchLimit = 200
        return (try? context.fetch(descriptor))?.first { $0.id == id }
    }

    private func isLatestUnresolvedAssistantTurn(_ assistantTurn: ChatMessage, in context: ModelContext) -> Bool {
        let messages = ((try? context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { $0.threadID == assistantTurn.threadID && !$0.text.hasPrefix("Applied:") }
        guard let index = messages.firstIndex(where: { $0.turnID == assistantTurn.turnID }) else { return false }
        return !messages[(index + 1)...].contains { message in
            message.role == .user || (message.role == .assistant && message.assistantStatus == .completed)
        }
    }

    private static func userFacingPlanToolRejection(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("swap does not take a workout") || lower.contains("missing workout") || lower.contains("workout") {
            return "Coach chưa đọc được buổi chạy cần thay đổi. Anh thử nói rõ ngày, loại buổi và mục tiêu mới, hoặc để em tạo đề xuất từ kế hoạch hiện tại."
        }
        if lower.contains("volume") || lower.contains("load") || lower.contains("ramp") || lower.contains("safe") {
            return "Thay đổi này có thể làm tải tập tăng quá nhanh, nên em chưa áp dụng vào lịch. Anh có thể giảm quãng đường/cường độ rồi thử lại."
        }
        if lower.contains("stale") || lower.contains("changed") || lower.contains("current") {
            return "Kế hoạch đã thay đổi so với lúc Coach tạo đề xuất. Anh mở lại lịch hiện tại rồi gửi yêu cầu mới nhé."
        }
        return "Em chưa thể áp dụng thay đổi này vào lịch. Anh thử yêu cầu một thay đổi cụ thể hơn, ví dụ ngày nào, đổi sang buổi gì, quãng đường bao nhiêu."
    }

    private static let calendarImportDetourMessage = "Training schedule changes must update TrainOrRest Calendar through the plan tool, then sync intervals.icu from the app. Do not provide ICS/iCalendar/import instructions."

    private static func containsPlanToolRetryDetour(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let schemaNeedles = ["plan_adjustment", "tool", "json", "schema", "format", "định dạng", "cấu trúc"]
        let confirmationNeedles = ["confirm", "confirmation", "xác nhận", "cho mình biết", "bạn có thể"]
        return schemaNeedles.contains { lowercased.contains($0) }
            && confirmationNeedles.contains { lowercased.contains($0) }
    }

    private static func containsCalendarImportDetour(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let needles = [
            "begin:vcalendar", "end:vcalendar", "dtstart", "dtend", "vevent",
            ".ics", "icalendar", "google calendar", "import calendar", "calendar import", "import ics"
        ]
        return needles.contains { lowercased.contains($0) }
    }

    private func technicalErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func messageHistory(threadID: UUID?, boundaryMessageID: UUID, in context: ModelContext) throws -> [ClaudeMessageParam] {
        let all = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
            .filter { $0.threadID == threadID }
        guard let boundaryIndex = all.firstIndex(where: { $0.turnID == boundaryMessageID }) else { return [] }
        return all[...boundaryIndex]
            .suffix(CoachChatConfig.historyLimit)
            .filter { message in
                message.role == .user || message.assistantStatus == .completed
            }
            .map { ClaudeMessageParam(role: $0.role.rawValue, content: [.text($0.text)]) }
    }

    private func updateThread(_ threadID: UUID?, titleFrom text: String, in context: ModelContext) {
        guard let threadID else { return }
        var descriptor = FetchDescriptor<ChatThread>()
        descriptor.fetchLimit = 100
        guard let thread = (try? context.fetch(descriptor))?.first(where: { $0.uuid == threadID }) else { return }
        if thread.title == "New chat" || thread.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            thread.title = Self.threadTitle(from: text)
        }
        thread.updatedAt = now()
    }

    private static func threadTitle(from text: String) -> String {
        let clean = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "New chat" }
        return String(clean.prefix(48))
    }
}

enum CoachModelProvider {
    static func isOpenAIModel(_ model: String) -> Bool {
        model.hasPrefix("gpt-") || model.hasPrefix("o")
    }

    static func apiKeyAccount(for model: String) -> String {
        isOpenAIModel(model) ? KeychainStore.openAIAPIKeyAccount : KeychainStore.apiKeyAccount
    }

    static func displayName(for model: String) -> String {
        isOpenAIModel(model) ? "OpenAI" : "Anthropic"
    }

    static func client(
        for model: String,
        anthropicClient: ClaudeServicing,
        openAIClient: ClaudeServicing
    ) -> ClaudeServicing {
        isOpenAIModel(model) ? openAIClient : anthropicClient
    }
}

private extension EvidenceSelection {
    init(attachments: [CoachContextAttachment]) {
        self.init(
            readinessSnapshot: true,
            weekPlan: true,
            workout: attachments.compactMap(\.workoutSelection).first,
            hasPhoto: attachments.contains { attachment in
                if case .image = attachment { return true }
                return false
            }
        )
    }
}

private extension CoachContextAttachment {
    var workoutSelection: WorkoutContextSelection? {
        switch self {
        case .plannedWorkout(let uuid):
            return .planned(uuid)
        case .completedActivity(let uuid):
            return .completed(uuid)
        case .health, .image:
            return nil
        }
    }
}

private extension CoachAttachmentReference {
    init(_ attachment: CoachContextAttachment) {
        switch attachment {
        case .health:
            self.init(kind: .health, uuid: nil, filename: nil, mediaType: nil, imageData: nil)
        case .plannedWorkout(let uuid):
            self.init(kind: .plannedWorkout, uuid: uuid, filename: nil, mediaType: nil, imageData: nil)
        case .completedActivity(let uuid):
            self.init(kind: .completedActivity, uuid: uuid, filename: nil, mediaType: nil, imageData: nil)
        case .image(let image):
            self.init(kind: .image, uuid: nil, filename: image.filename, mediaType: image.mediaType, imageData: image.data)
        }
    }
}
