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

    @discardableResult
    func send(
        text: String,
        model: String,
        attachments: [CoachContextAttachment] = [],
        evidence: EvidenceSelection? = nil,
        groundingSnapshot: GroundingSnapshot? = nil,
        threadID: UUID? = nil,
        interactionId: String? = nil,
        selectedOptionId: String? = nil,
        isCustomInteractionResponse: Bool = false,
        actionTypeOverride: CoachRequestActionType? = nil,
        in context: ModelContext
    ) async -> Bool {
        let account = CoachModelProvider.apiKeyAccount(for: model)
        guard let apiKey = try? KeychainStore.load(account: account), !apiKey.isEmpty else {
            lastError = CoachLanguage.current.missingCoachKeyError(provider: CoachModelProvider.displayName(for: model))
            return false
        }
        return await send(
            text: text,
            model: model,
            attachments: attachments,
            evidence: evidence,
            groundingSnapshot: groundingSnapshot,
            apiKey: apiKey,
            threadID: threadID,
            interactionId: interactionId,
            selectedOptionId: selectedOptionId,
            isCustomInteractionResponse: isCustomInteractionResponse,
            actionTypeOverride: actionTypeOverride,
            in: context
        )
    }

    @discardableResult
    func send(
        text: String,
        model: String,
        attachments: [CoachContextAttachment] = [],
        evidence: EvidenceSelection? = nil,
        groundingSnapshot: GroundingSnapshot? = nil,
        apiKey: String,
        threadID: UUID? = nil,
        interactionId: String? = nil,
        selectedOptionId: String? = nil,
        isCustomInteractionResponse: Bool = false,
        actionTypeOverride: CoachRequestActionType? = nil,
        in context: ModelContext
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isSending else { return false }
        guard replacementCoordinator?.hasPendingDecision != true else {
            lastError = CoachLanguage.current.replacementPendingMessage
            return false
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
            return false
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
            actionType: actionTypeOverride ?? classifyAction(trimmed),
            groundingSnapshot: grounding,
            threadID: threadID,
            interactionId: interactionId,
            selectedOptionId: selectedOptionId,
            isCustomInteractionResponse: isCustomInteractionResponse
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
            ) || handleExplicitDistanceShortcut(
                trimmed,
                attachments: attachments,
                snapshot: snapshot,
                assistantTurn: assistantTurn,
                in: context
            ) {
                isSending = false
                return true
            }
        } catch {
            if attachments.contains(where: {
                if case .plannedWorkout = $0 { return true }
                return false
            }), let targetKm = Self.contextualDistanceTarget(from: trimmed) {
                assistantTurn.text = Self.userFacingContextualDistanceRejection(
                    targetKm: targetKm,
                    raw: technicalErrorMessage(error)
                )
            } else {
                assistantTurn.text = Self.userFacingPlanToolRejection(technicalErrorMessage(error))
            }
            assistantTurn.assistantStatus = .completed
            assistantTurn.isIncomplete = false
            assistantTurn.errorCategory = nil
            assistantTurn.errorMessage = nil
            assistantTurn.activeAttemptID = nil
            try? context.save()
            isSending = false
            return true
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
        return assistantTurn.assistantStatus == .completed
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

    private func handleExplicitDistanceShortcut(
        _ text: String,
        attachments: [CoachContextAttachment],
        snapshot: CoachRequestSnapshot,
        assistantTurn: ChatMessage,
        in context: ModelContext
    ) throws -> Bool {
        guard let replacementCoordinator,
              !attachments.contains(where: {
                if case .plannedWorkout = $0 { return true }
                return false
              }),
              let request = Self.distanceEditRequest(from: text),
              let day = request.day(relativeTo: snapshot.createdAt, calendar: calendar),
              let workout = try Self.matchPlannedWorkout(
                on: day,
                kind: request.kind,
                sourceKm: request.sourceKm,
                in: context,
                calendar: calendar
              ),
              workout.kind != .race,
              let kind = workout.kind,
              let payload = Self.sameKindPayload(kind: kind, distanceKm: request.targetKm)
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

        assistantTurn.text = "Em đã chuẩn bị đề xuất đổi cự li cho \(Self.dayLabel(for: day, relativeTo: snapshot.createdAt, calendar: calendar)). Anh xem card bên dưới rồi xác nhận trước khi em lưu vào lịch."
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

    func promptSuggestions(
        from candidates: [CoachPromptSuggestion],
        in context: ModelContext
    ) -> [CoachPromptSuggestion] {
        let records = ((try? context.fetch(FetchDescriptor<CoachPromptSuggestionRecord>())) ?? [])
            .reduce(into: [String: CoachPromptSuggestionRecord]()) { $0[$1.scopeKey] = $1 }
        return candidates.compactMap { suggestion in
            var suggestion = suggestion
            if let status = records[suggestion.scopeKey]?.status {
                suggestion.status = status
            }
            return suggestion.status == .available ? suggestion : nil
        }
    }

    func setPromptSuggestionStatus(
        _ status: CoachPromptSuggestionStatus,
        for suggestion: CoachPromptSuggestion,
        in context: ModelContext
    ) {
        let key = suggestion.scopeKey
        var descriptor = FetchDescriptor<CoachPromptSuggestionRecord>()
        descriptor.fetchLimit = 200
        if let record = (try? context.fetch(descriptor))?.first(where: { $0.scopeKey == key }) {
            record.status = status
        } else {
            context.insert(CoachPromptSuggestionRecord(
                scopeKey: key,
                conversationId: suggestion.conversationId,
                workoutId: suggestion.workoutId,
                suggestionId: suggestion.id,
                status: status
            ))
        }
        try? context.save()
    }

    func resolveInteraction(
        messageID: UUID,
        selectedOptionId: String?,
        resolvedWithOther: Bool = false,
        in context: ModelContext
    ) -> CoachResponseInteraction? {
        guard let message = message(messageID, in: context),
              var interaction = message.interaction,
              interaction.status == .pending else { return nil }
        interaction.status = .resolved
        interaction.selectedOptionId = selectedOptionId
        interaction.resolvedWithOther = resolvedWithOther
        message.interaction = interaction
        try? context.save()
        return interaction
    }

    func restoreInteraction(
        messageID: UUID,
        interaction: CoachResponseInteraction,
        in context: ModelContext
    ) {
        guard let message = message(messageID, in: context) else { return }
        message.interaction = interaction
        try? context.save()
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
        assistantTurn.interaction = nil
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
        system += """

When your reply asks the user to choose between next steps, call `\(CoachToolCatalog.coachResponseName)` with `content` and structured `interaction` metadata instead of writing the choices only as prose. Use `single_choice`, 2-4 concise options, and `allowOther: true` when a custom answer is useful. If no decision is needed, a normal text response is fine.
"""
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
        if let metadata = snapshot.interactionMetadataPrompt,
           var last = conversation.last,
           last.role == "user" {
            last.content.append(.text(metadata))
            conversation[conversation.count - 1] = last
        }
        let applied: [String] = []
        var lastToolRejection: String?
        let shouldPublishStreamingText = snapshot.actionType != .planMutation

        for _ in 0..<CoachChatConfig.maxToolRounds {
            let tools = tools(for: snapshot.actionType)
            let request = ClaudeRequest(
                model: model,
                system: system,
                tools: tools,
                toolChoice: toolChoice(for: snapshot.actionType),
                messages: conversation
            )
            let client = CoachModelProvider.client(for: model, anthropicClient: anthropicClient, openAIClient: openAIClient)
            let events = try await client.stream(request, apiKey: apiKey)
            var replacementStarted = false
            var lastStreamSave = Date.distantPast
            let streamSaveInterval: TimeInterval = 0.15
            let assembler = CoachStreamAssembler(
                onText: { delta in
                    guard shouldPublishStreamingText else { return }
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
                if snapshot.actionType == .planMutation {
                    lastToolRejection = lastToolRejection ?? "The model answered with text instead of submitting a plan adjustment tool call."
                    break
                }
                assistantTurn.text = text.isEmpty ? "I could not produce a response." : text
                assistantTurn.appliedAdjustment = applied.isEmpty ? nil : applied.joined(separator: "; ")
                try context.save()
                return
            }

            if toolUses.count == 1, toolUses[0].1 == CoachToolCatalog.coachResponseName {
                let payload = try toolUses[0].2.decoded(CoachStructuredResponsePayload.self)
                var interaction = payload.interaction
                interaction?.normalizeForNewAssistantMessage(
                    fallbackLanguage: CoachLanguage(rawValue: snapshot.locale) ?? .current
                )
                if interaction?.options.count ?? 0 < 2 {
                    interaction = nil
                }
                let content = payload.content.trimmingCharacters(in: .whitespacesAndNewlines)
                assistantTurn.text = content.isEmpty ? response.content.textContent : content
                assistantTurn.interaction = interaction
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

    private func tools(for actionType: CoachRequestActionType) -> [ClaudeTool] {
        switch actionType {
        case .readOnly:
            return [CoachToolCatalog.coachResponse]
        case .planMutation:
            return CoachToolCatalog.tools(allowProposals: true)
        }
    }

    private func toolChoice(for actionType: CoachRequestActionType) -> CoachToolCatalog.ToolChoice? {
        switch actionType {
        case .readOnly:
            return .tool(name: CoachToolCatalog.coachResponseName)
        case .planMutation:
            return .auto
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
            if selected.kind == .race {
                throw CoachTools.ValidationError("Race workouts cannot be replaced from this contextual edit flow.")
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
        let lower = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .lowercased()
        let mutationNeedles = [
            "create workout", "add workout", "update plan", "delete workout", "modify calendar",
            "save settings", "push workout", "thêm bài", "tạo bài", "sửa lịch", "đổi lịch", "xóa bài",
            "đổi cự li", "đổi cự ly", "đổi quãng đường", "change distance"
        ]
            .map {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
                    .lowercased()
            }
        if mutationNeedles.contains(where: { lower.contains($0) }) || Self.distanceEditRequest(from: text) != nil {
            return .planMutation
        }

        let actionNeedles = [
            "create", "add", "update", "delete", "modify", "replace", "move", "change", "set",
            "tao", "them", "sua", "chinh", "doi", "xoa", "chuyen", "cap nhat", "tang", "giam"
        ]
        let objectNeedles = [
            "workout", "run", "plan", "calendar", "schedule",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "today", "tomorrow", "hom nay", "ngay mai",
            "lich", "bai", "buoi", "cu li", "cu ly", "quang duong"
        ]
        let hasAction = actionNeedles.contains { lower.contains($0) }
        let hasObject = objectNeedles.contains { lower.contains($0) }
        return hasAction && hasObject ? .planMutation : .readOnly
    }

    private struct DistanceEditRequest {
        enum RelativeDay {
            case today
            case tomorrow
        }

        var targetKm: Double
        var sourceKm: Double?
        var kind: WorkoutKind?
        var absoluteDay: String?
        var relativeDay: RelativeDay?

        func day(relativeTo today: Date, calendar: Calendar) -> Date? {
            if let absoluteDay {
                return Self.date(from: absoluteDay, calendar: calendar)
            }
            switch relativeDay {
            case .today:
                return calendar.startOfDay(for: today)
            case .tomorrow:
                return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))
            case nil:
                return nil
            }
        }

        private static func date(from value: String, calendar: Calendar) -> Date? {
            guard value.count == 10 else { return nil }
            let parts = value.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
            else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
            let rendered = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
            return rendered == value ? dayStart : nil
        }
    }

    private static func contextualDistanceTarget(from text: String) -> Double? {
        distanceEditRequest(from: text)?.targetKm
    }

    private static func distanceEditRequest(from text: String) -> DistanceEditRequest? {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: ",", with: ".")
        let lower = folded.lowercased()
        let mutationNeedles = [
            "doi", "chuyen", "thay", "tang", "giam", "nang", "ha", "cap nhat", "sua",
            "change", "update", "set", "make", "increase", "decrease"
        ]
        let contextualNeedles = [
            "buoi nay", "buoi tap nay", "workout nay", "this workout",
            "hom nay", "hnay", "h nay", "today", "ngay mai", "tomorrow", "tmr"
        ]
        let distanceNeedles = [
            "cu li", "cu ly", "quang duong", "distance", "kilometer", "kilometre",
            "thanh", "to ", "len", "xuong"
        ]

        let hasEditCue = mutationNeedles.contains { lower.contains($0) }
            || distanceNeedles.contains { lower.contains($0) }
            || contextualNeedles.contains { lower.contains($0) }

        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        let targetPatterns = [
            #"(?:thanh|to|len|xuong|set|make|increase\s+to|decrease\s+to)\s+(\d+(?:\.\d+)?)\s*(?:km|kilometer|kilometre|k)?"#,
            #"(?:from|tu)\s+\d+(?:\.\d+)?\s*(?:km|kilometer|kilometre|k)?\s+(?:to|den|thanh)\s+(\d+(?:\.\d+)?)\s*(?:km|kilometer|kilometre|k)?"#
        ]
        let explicitTarget = targetPatterns.compactMap { pattern -> (value: Double, location: Int)? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            guard let match = regex.firstMatch(in: lower, options: [], range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: lower),
                  let value = Double(lower[valueRange]),
                  value > 0
            else { return nil }
            return (value, match.range(at: 1).location)
        }.first

        let kmValues = Self.distanceValues(in: lower)
        guard let target = explicitTarget?.value ?? kmValues.last?.value,
              target > 0,
              hasEditCue || !kmValues.isEmpty
        else { return nil }

        let targetLocation = explicitTarget?.location ?? kmValues.last?.location
        let source = kmValues.first { value in
            guard let targetLocation else { return value.value != target }
            return value.location < targetLocation && value.value != target
        }?.value

        return DistanceEditRequest(
            targetKm: target,
            sourceKm: source,
            kind: workoutKind(from: lower),
            absoluteDay: absoluteDayString(from: lower),
            relativeDay: relativeDay(from: lower)
        )
    }

    private static func distanceValues(in lower: String) -> [(value: Double, location: Int)] {
        let pattern = #"(?<![\d.])(\d+(?:\.\d+)?)\s*(?:km|kilometer|kilometre|k)(?![a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        return regex.matches(in: lower, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: lower),
                  let value = Double(lower[valueRange]),
                  value > 0
            else { return nil }
            return (value, match.range(at: 1).location)
        }
    }

    private static func workoutKind(from lower: String) -> WorkoutKind? {
        if lower.contains("long run") || lower.contains("bai dai") { return .long }
        if lower.contains("threshold") || lower.contains("nguong") || lower.contains("ngưỡng") { return .threshold }
        if lower.contains("tempo") { return .tempo }
        if lower.contains("interval") || lower.contains("intervals") || lower.contains("bien toc") { return .intervals }
        if lower.contains("easy") || lower.contains("nhe") { return .easy }
        return nil
    }

    private static func relativeDay(from lower: String) -> DistanceEditRequest.RelativeDay? {
        if lower.contains("ngay mai") || lower.contains("tomorrow") || lower.contains("tmr") {
            return .tomorrow
        }
        if lower.contains("hom nay") || lower.contains("hnay") || lower.contains("h nay") || lower.contains("today") {
            return .today
        }
        return nil
    }

    private static func absoluteDayString(from lower: String) -> String? {
        let pattern = #"\b\d{4}-\d{2}-\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              let dateRange = Range(match.range, in: lower)
        else { return nil }
        return String(lower[dateRange])
    }

    private static func matchPlannedWorkout(
        on day: Date,
        kind: WorkoutKind?,
        sourceKm: Double?,
        in context: ModelContext,
        calendar: Calendar
    ) throws -> PlannedWorkout? {
        var candidates = try context.fetch(FetchDescriptor<PlannedWorkout>()).filter {
            calendar.isDate($0.date, inSameDayAs: day)
                && $0.kind != .race
        }
        if let kind {
            candidates = candidates.filter { $0.kind == kind }
        }
        if let sourceKm {
            candidates = candidates.filter { abs($0.distanceKm - sourceKm) <= 0.15 }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func dayLabel(for day: Date, relativeTo today: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: today) { return "buổi hôm nay" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "buổi ngày mai"
        }
        return "buổi \(CoachContextBuilder.day(day, calendar: calendar))"
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
        case .tempo, .threshold:
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
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.uuid == id
            }
        )
        descriptor.fetchLimit = 1
        if let match = (try? context.fetch(descriptor))?.first {
            return match
        }

        return (try? context.fetch(FetchDescriptor<ChatMessage>()))?.first { $0.turnID == id }
    }

    private func snapshot(_ id: UUID?, in context: ModelContext) -> CoachRequestSnapshot? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<CoachRequestSnapshot>(
            predicate: #Predicate<CoachRequestSnapshot> { snapshot in
                snapshot.id == id
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
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
        return "Em chưa thể áp dụng thay đổi này vào lịch. Buổi tập chưa thay đổi; anh gửi lại với ngày và mục tiêu mới, hoặc mở đúng workout rồi dùng Edit with Coach."
    }

    private static func userFacingContextualDistanceRejection(targetKm: Double, raw: String) -> String {
        let lower = raw.lowercased()
        let target = targetKm.rounded() == targetKm
            ? "\(Int(targetKm)) km"
            : String(format: "%.1f km", targetKm)
        if lower.contains("volume") || lower.contains("load") || lower.contains("ramp") || lower.contains("safe") {
            return "Em hiểu anh muốn đổi buổi này lên \(target), nhưng validation đang chặn vì tải tập có thể tăng quá nhanh. Buổi tập chưa thay đổi."
        }
        if lower.contains("locked") || lower.contains("fixed") {
            return "Em hiểu anh muốn đổi buổi này lên \(target), nhưng buổi này đang được khóa nên chưa thể sửa trực tiếp. Buổi tập chưa thay đổi."
        }
        if lower.contains("stale") || lower.contains("changed") || lower.contains("current") {
            return "Em hiểu anh muốn đổi buổi này lên \(target), nhưng buổi tập đã thay đổi sau khi Coach mở màn hình này. Anh quay lại lịch rồi mở lại buổi mới nhất nhé."
        }
        return "Em hiểu anh muốn đổi buổi này lên \(target), nhưng chưa tạo được proposal an toàn từ lịch hiện tại. Buổi tập chưa thay đổi."
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
