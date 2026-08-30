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

    var visibleSelectionText: String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLabel.isEmpty ? submissionText : trimmedLabel
    }

    var submissionText: String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return label.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trimmedValue.isMachineReadableChoiceToken ? label.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedValue
    }
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
    var title: String? = nil
    var summary: String? = nil
    var safetyNote: String? = nil
    var recommendations: [CoachRecommendation]? = nil
    var details: CoachResponseDetails? = nil
    var followUps: [CoachChoiceOption]? = nil
}

extension CoachStructuredResponsePayload {
    // The model authors this tool payload, so treat it as untrusted at the
    // decode boundary. A coach_response can legitimately carry only an
    // interaction with no prose, and a partially-formed interaction should
    // degrade to the snapshot fallback rather than fail the whole turn.
    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            content = ((try? container.decodeIfPresent(String.self, forKey: .content)) ?? nil) ?? ""
            interaction = ((try? container.decodeIfPresent(CoachResponseInteraction.self, forKey: .interaction)) ?? nil)
            title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil)
            summary = ((try? container.decodeIfPresent(String.self, forKey: .summary)) ?? nil)
            safetyNote = ((try? container.decodeIfPresent(String.self, forKey: .safetyNote)) ?? nil)
            recommendations = ((try? container.decodeIfPresent([CoachRecommendation].self, forKey: .recommendations)) ?? nil)
            details = ((try? container.decodeIfPresent(CoachResponseDetails.self, forKey: .details)) ?? nil)
            followUps = ((try? container.decodeIfPresent([CoachChoiceOption].self, forKey: .followUps)) ?? nil)
        } else {
            content = ""
            interaction = nil
            title = nil
            summary = nil
            safetyNote = nil
            recommendations = nil
            details = nil
            followUps = nil
        }
    }
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

private extension String {
    var isMachineReadableChoiceToken: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        guard trimmed.contains("_") || trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { character in
            character.isLowercase || character.isNumber || character == "_" || character == "-"
        }
    }
}
