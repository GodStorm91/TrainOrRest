import Foundation
import SwiftData

@MainActor
final class CoachChatStore: ObservableObject {
    @Published private(set) var isSending = false
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
            lastError = "Add your \(CoachModelProvider.displayName(for: model)) API key in Settings first."
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
        let today = now()
        let snapshot: GroundingSnapshot
        do {
            if let groundingSnapshot {
                snapshot = groundingSnapshot
            } else {
                snapshot = try CoachGrounding.snapshot(
                    evidence: evidence ?? EvidenceSelection(attachments: attachments),
                    in: context,
                    today: today,
                    calendar: calendar
                )
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        isSending = true
        lastError = nil
        context.insert(ChatMessage(
            role: .user,
            text: CoachAttachmentContextBuilder.displayText(
                text: trimmed,
                attachments: attachments,
                in: context,
                today: today,
                calendar: calendar
            ),
            date: .now,
            threadID: threadID
        ))
        updateThread(threadID, titleFrom: trimmed, in: context)
        try? context.save()

        do {
            try await runLoop(
                apiKey: apiKey,
                model: model,
                attachments: attachments,
                groundingSnapshot: snapshot,
                today: today,
                threadID: threadID,
                in: context
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            if shouldPersistFailure(error) {
                context.insert(assistantMessage(text: message, groundingSnapshot: snapshot, threadID: threadID))
                try? context.save()
            }
        }
        isSending = false
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
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runLoop(
        apiKey: String,
        model: String,
        attachments: [CoachContextAttachment],
        groundingSnapshot: GroundingSnapshot,
        today: Date,
        threadID: UUID?,
        in context: ModelContext
    ) async throws {
        var system = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)
        let directive = CoachLanguage.current.systemPromptDirective
        if !directive.isEmpty {
            system += "\n\n\(directive)"
        }
        var conversation = try messageHistory(threadID: threadID, in: context)
        if !attachments.isEmpty, var last = conversation.last, last.role == "user" {
            let text = last.content.textContent
                .components(separatedBy: "\n\nAttached:")
                .first ?? last.content.textContent
            last.content = CoachAttachmentContextBuilder.content(
                text: text,
                attachments: attachments,
                in: context,
                today: today,
                calendar: calendar
            )
            conversation[conversation.count - 1] = last
        }
        var applied: [String] = []
        var lastToolRejection: String?

        for _ in 0..<CoachChatConfig.maxToolRounds {
            let request = ClaudeRequest(model: model, system: system, tools: [CoachTools.tool], messages: conversation)
            let client = CoachModelProvider.client(for: model, anthropicClient: anthropicClient, openAIClient: openAIClient)
            let events = try await client.stream(request, apiKey: apiKey)
            var streamingMessage: ChatMessage?
            var lastStreamSave = Date.distantPast
            let streamSaveInterval: TimeInterval = 0.15
            let assembler = CoachStreamAssembler(
                onText: { delta in
                    if streamingMessage == nil {
                        let message = self.assistantMessage(text: "", groundingSnapshot: groundingSnapshot, threadID: threadID)
                        streamingMessage = message
                        context.insert(message)
                    }
                    streamingMessage?.text += delta
                    let saveTime = Date()
                    if saveTime.timeIntervalSince(lastStreamSave) >= streamSaveInterval {
                        lastStreamSave = saveTime
                        try? context.save()
                    }
                }
            )
            let assembled: AssembledResponse
            do {
                assembled = try await assembler.assemble(events)
            } catch {
                if let streamingMessage {
                    context.delete(streamingMessage)
                    try? context.save()
                }
                throw error
            }
            if let error = assembled.error {
                if let streamingMessage {
                    context.delete(streamingMessage)
                    try? context.save()
                }
                throw CoachTools.ValidationError(error)
            }
            let response = assembled.response

            // A truncated turn can carry a half-written tool input. Never decode
            // or apply it; a refusal must not be treated as a plan edit either.
            if response.stopReason == "max_tokens" {
                if let streamingMessage {
                    context.delete(streamingMessage)
                    try? context.save()
                }
                throw CoachTools.ValidationError(
                    "Claude's reply was cut off before the plan edit was complete. Ask again."
                )
            }
            if response.stopReason == "refusal" {
                let text = response.content.textContent
                if let streamingMessage {
                    streamingMessage.text = text.isEmpty ? "Claude declined to answer that." : text
                } else {
                    context.insert(assistantMessage(
                        text: text.isEmpty ? "Claude declined to answer that." : text,
                        groundingSnapshot: groundingSnapshot,
                        threadID: threadID
                    ))
                }
                try context.save()
                return
            }

            let toolUses = response.content.compactMap { block -> (String, String, JSONValue)? in
                if case let .toolUse(id, name, input) = block { return (id, name, input) }
                return nil
            }
            if toolUses.isEmpty {
                let text = response.content.textContent
                if Self.containsCalendarImportDetour(text) {
                    if let streamingMessage {
                        context.delete(streamingMessage)
                        try context.save()
                    }
                    lastToolRejection = Self.calendarImportDetourMessage
                    conversation.append(ClaudeMessageParam(
                        role: "user",
                        content: [.text("Rejected: \(Self.calendarImportDetourMessage) Call \(CoachTools.toolName) with the concrete calendar changes instead.")]
                    ))
                    continue
                }
                if let streamingMessage {
                    streamingMessage.text = text.isEmpty ? "I could not produce a response." : text
                    streamingMessage.appliedAdjustment = applied.isEmpty ? nil : applied.joined(separator: "; ")
                } else {
                    context.insert(assistantMessage(
                        text: text.isEmpty ? "I could not produce a response." : text,
                        appliedAdjustment: applied.isEmpty ? nil : applied.joined(separator: "; "),
                        groundingSnapshot: groundingSnapshot,
                        threadID: threadID
                    ))
                }
                try context.save()
                return
            }

            if let streamingMessage {
                context.delete(streamingMessage)
                try context.save()
            }
            conversation.append(ClaudeMessageParam(role: "assistant", content: response.content))
            guard toolUses.count == 1 else {
                lastToolRejection = "Submit one plan adjustment at a time."
                conversation.append(ClaudeMessageParam(role: "user", content: toolUses.map {
                    .toolResult(
                        toolUseID: $0.0,
                        content: "Rejected: submit one plan adjustment at a time.",
                        isError: true
                    )
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
                if let replacement = try CoachTools.pendingReplacement(
                    for: proposal,
                    in: context,
                    today: today,
                    calendar: calendar,
                    language: .current
                ) {
                    guard let replacementCoordinator else {
                        throw CoachTools.ValidationError("Workout replacement confirmation is unavailable.")
                    }
                    replacementCoordinator.stage(replacement)
                    return
                }

                guard let replacementCoordinator else {
                    throw CoachTools.ValidationError("Plan update confirmation is unavailable.")
                }
                let summary = CoachTools.summary(for: proposal)
                context.insert(assistantMessage(
                    text: "I prepared this calendar update. Review it below before I save it: \(summary)",
                    groundingSnapshot: groundingSnapshot,
                    threadID: threadID
                ))
                try context.save()
                replacementCoordinator.stage(proposal, summary: summary, threadID: threadID)
                return
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                lastToolRejection = message
                conversation.append(ClaudeMessageParam(role: "user", content: [
                    .toolResult(toolUseID: toolUse.0, content: "Rejected: \(message)", isError: true)
                ]))
            }
        }

        if !applied.isEmpty {
            context.insert(assistantMessage(
                text: "Applied: \(applied.joined(separator: "; "))",
                appliedAdjustment: applied.joined(separator: "; "),
                groundingSnapshot: groundingSnapshot,
                threadID: threadID
            ))
        } else if let lastToolRejection {
            context.insert(assistantMessage(
                text: "I could not safely apply that plan change. Last validation error: \(lastToolRejection)",
                groundingSnapshot: groundingSnapshot,
                threadID: threadID
            ))
        } else {
            context.insert(assistantMessage(
                text: "I could not safely finish the plan adjustment. Please try one specific change at a time.",
                groundingSnapshot: groundingSnapshot,
                threadID: threadID
            ))
        }
        try context.save()
    }

    private static let calendarImportDetourMessage = "Training schedule changes must update TrainOrRest Calendar through the plan tool, then sync intervals.icu from the app. Do not provide ICS/iCalendar/import instructions."

    private static func containsCalendarImportDetour(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let needles = [
            "begin:vcalendar",
            "end:vcalendar",
            "dtstart",
            "dtend",
            "vevent",
            ".ics",
            "icalendar",
            "google calendar",
            "import calendar",
            "calendar import",
            "import ics"
        ]
        return needles.contains { lowercased.contains($0) }
    }

    private func shouldPersistFailure(_ error: Error) -> Bool {
        guard let clientError = error as? ClaudeClientError else { return true }
        switch clientError {
        case .offline, .connectionLost, .rateLimited, .badKey, .invalidResponse:
            return false
        case .api:
            return true
        }
    }

    private func assistantMessage(
        text: String,
        appliedAdjustment: String? = nil,
        groundingSnapshot: GroundingSnapshot,
        threadID: UUID? = nil
    ) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            text: text,
            date: .now,
            appliedAdjustment: appliedAdjustment,
            groundingFootnote: groundingSnapshot.footnoteLine,
            groundingSummary: groundingSnapshot.summary,
            threadID: threadID
        )
    }

    private func messageHistory(threadID: UUID?, in context: ModelContext) throws -> [ClaudeMessageParam] {
        var descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = CoachChatConfig.historyLimit * 4
        return try context.fetch(descriptor)
            .filter { $0.threadID == threadID }
            .prefix(CoachChatConfig.historyLimit)
            .reversed()
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
