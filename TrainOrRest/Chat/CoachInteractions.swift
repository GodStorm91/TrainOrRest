import Foundation
import SwiftData

enum CoachPromptSuggestionStatus: String, Codable, Equatable {
    case available
    case consumed
    case dismissed
}

struct CoachPromptSuggestion: Identifiable, Equatable {
    var id: String
    var workoutId: UUID?
    var conversationId: UUID
    var title: String
    var description: String?
    var prompt: String
    var status: CoachPromptSuggestionStatus

    var scopeKey: String {
        Self.scopeKey(conversationId: conversationId, workoutId: workoutId, suggestionId: id)
    }

    static func scopeKey(conversationId: UUID, workoutId: UUID?, suggestionId: String) -> String {
        "\(conversationId.uuidString)|\(workoutId?.uuidString ?? "none")|\(suggestionId)"
    }
}

@Model
final class CoachPromptSuggestionRecord {
    @Attribute(.unique) var scopeKey: String
    var conversationId: UUID
    var workoutId: UUID?
    var suggestionId: String
    var statusRaw: String
    var updatedAt: Date

    init(
        scopeKey: String,
        conversationId: UUID,
        workoutId: UUID?,
        suggestionId: String,
        status: CoachPromptSuggestionStatus,
        updatedAt: Date = .now
    ) {
        self.scopeKey = scopeKey
        self.conversationId = conversationId
        self.workoutId = workoutId
        self.suggestionId = suggestionId
        self.statusRaw = status.rawValue
        self.updatedAt = updatedAt
    }

    var status: CoachPromptSuggestionStatus {
        get { CoachPromptSuggestionStatus(rawValue: statusRaw) ?? .available }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}

enum CoachChoiceInteractionType: String, Codable, Equatable {
    case singleChoice = "single_choice"
}

enum CoachResponseInteractionStatus: String, Codable, Equatable {
    case pending
    case resolved
}

struct CoachChoiceOption: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var description: String?
    var value: String
}

struct CoachResponseInteraction: Codable, Equatable, Identifiable {
    var id: String
    var type: CoachChoiceInteractionType
    var title: String?
    var options: [CoachChoiceOption]
    var allowOther: Bool
    var otherLabel: String?
    var otherPlaceholder: String?
    var status: CoachResponseInteractionStatus
    var selectedOptionId: String?
    var resolvedWithOther: Bool?

    var selectedOption: CoachChoiceOption? {
        guard let selectedOptionId else { return nil }
        return options.first { $0.id == selectedOptionId }
    }

    mutating func normalizeForNewAssistantMessage(fallbackLanguage: CoachLanguage) {
        status = .pending
        selectedOptionId = nil
        resolvedWithOther = false
        if title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            title = fallbackLanguage.choiceDefaultTitle
        }
        if otherLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            otherLabel = fallbackLanguage.choiceOtherLabel
        }
        if otherPlaceholder?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            otherPlaceholder = fallbackLanguage.choiceOtherPlaceholder
        }
        options = options
            .map {
                CoachChoiceOption(
                    id: $0.id.trimmingCharacters(in: .whitespacesAndNewlines),
                    label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: $0.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                    value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.id.isEmpty && !$0.label.isEmpty && !$0.value.isEmpty }
    }

    func resolvedSummary(language: CoachLanguage) -> String {
        if resolvedWithOther == true {
            return language.choiceResolvedOtherLabel
        }
        let label = selectedOption?.label ?? selectedOptionId ?? ""
        return language.choiceResolvedSelectedLabel(option: label)
    }
}

struct CoachStructuredResponsePayload: Codable, Equatable {
    var content: String
    var interaction: CoachResponseInteraction?
}

enum CoachInteractionCodec {
    static func encode(_ interaction: CoachResponseInteraction?) -> String? {
        guard let interaction,
              let data = try? JSONEncoder().encode(interaction) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> CoachResponseInteraction? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CoachResponseInteraction.self, from: data)
    }
}
