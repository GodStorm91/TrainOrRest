import Foundation
import SwiftData

@MainActor
final class CoachChatStore: ObservableObject {
    @Published private(set) var isSending = false
    @Published var lastError: String?

    private let client: ClaudeServicing
    private let calendar: Calendar
    private let now: () -> Date
    private let replacementCoordinator: WorkoutReplacementCoordinator?

    init(
        client: ClaudeServicing = ClaudeClient(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
        replacementCoordinator: WorkoutReplacementCoordinator? = nil
    ) {
        self.client = client
        self.calendar = calendar
        self.now = now
        self.replacementCoordinator = replacementCoordinator
    }

    func send(
        text: String,
        model: String,
        attachments: [CoachContextAttachment] = [],
        in context: ModelContext
    ) async {
        guard let apiKey = try? KeychainStore.load(), !apiKey.isEmpty else {
            lastError = "Add your Anthropic API key in Settings first."
            return
        }
        await send(text: text, model: model, attachments: attachments, apiKey: apiKey, in: context)
    }

    func send(
        text: String,
        model: String,
        attachments: [CoachContextAttachment] = [],
        apiKey: String,
        in context: ModelContext
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard replacementCoordinator?.pending == nil else {
            lastError = CoachLanguage.current.replacementPendingMessage
            return
        }
        let today = now()
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
            date: .now
        ))
        try? context.save()

        do {
            try await runLoop(apiKey: apiKey, model: model, attachments: attachments, today: today, in: context)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            context.insert(ChatMessage(role: .assistant, text: message, date: .now))
            try? context.save()
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
            _ = try await client.send(request, apiKey: apiKey)
            return "Connection OK"
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runLoop(
        apiKey: String,
        model: String,
        attachments: [CoachContextAttachment],
        today: Date,
        in context: ModelContext
    ) async throws {
        var system = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)
        let directive = CoachLanguage.current.systemPromptDirective
        if !directive.isEmpty {
            system += "\n\n\(directive)"
        }
        var conversation = try messageHistory(in: context)
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

        for _ in 0..<CoachChatConfig.maxToolRounds {
            let response = try await client.send(
                ClaudeRequest(model: model, system: system, tools: [CoachTools.tool], messages: conversation),
                apiKey: apiKey
            )

            // A truncated turn can carry a half-written tool input. Never decode
            // or apply it; a refusal must not be treated as a plan edit either.
            if response.stopReason == "max_tokens" {
                throw CoachTools.ValidationError(
                    "Claude's reply was cut off before the plan edit was complete. Ask again."
                )
            }
            if response.stopReason == "refusal" {
                let text = response.content.textContent
                context.insert(ChatMessage(
                    role: .assistant,
                    text: text.isEmpty ? "Claude declined to answer that." : text,
                    date: .now
                ))
                try context.save()
                return
            }

            let toolUses = response.content.compactMap { block -> (String, String, JSONValue)? in
                if case let .toolUse(id, name, input) = block { return (id, name, input) }
                return nil
            }
            if toolUses.isEmpty {
                let text = response.content.textContent
                context.insert(ChatMessage(
                    role: .assistant,
                    text: text.isEmpty ? "I could not produce a response." : text,
                    date: .now,
                    appliedAdjustment: applied.isEmpty ? nil : applied.joined(separator: "; ")
                ))
                try context.save()
                return
            }

            conversation.append(ClaudeMessageParam(role: "assistant", content: response.content))
            guard toolUses.count == 1 else {
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

                let result = try CoachTools.apply(
                    proposal: proposal, in: context, today: today, calendar: calendar
                )
                applied.append(result.summary)
                NotificationCenter.default.post(name: .planDidChange, object: nil)
                conversation.append(ClaudeMessageParam(role: "user", content: [
                    .toolResult(toolUseID: toolUse.0, content: "Applied: \(result.summary)", isError: false)
                ]))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                conversation.append(ClaudeMessageParam(role: "user", content: [
                    .toolResult(toolUseID: toolUse.0, content: "Rejected: \(message)", isError: true)
                ]))
            }
        }

        let fallback = "I could not safely finish the plan adjustment in three tool rounds."
        context.insert(ChatMessage(role: .assistant, text: fallback, date: .now))
        try context.save()
    }

    private func messageHistory(in context: ModelContext) throws -> [ClaudeMessageParam] {
        var descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = CoachChatConfig.historyLimit
        return try context.fetch(descriptor).reversed().map {
            ClaudeMessageParam(role: $0.role.rawValue, content: [.text($0.text)])
        }
    }
}
