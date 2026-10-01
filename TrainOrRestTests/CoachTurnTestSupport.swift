import Foundation
import SwiftData
@testable import TrainOrRest

@MainActor
extension CoachChatStore {
    @discardableResult
    func submitTestTurn(
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
        expectedResponseInteraction: CoachResponseInteraction? = nil,
        displayText: String? = nil,
        contextSnapshotId: String? = nil,
        contextItems: [CoachContextItem] = [],
        interactionMessageID: UUID? = nil,
        promptSuggestion: CoachPromptSuggestion? = nil,
        followUpMessageID: UUID? = nil,
        in context: ModelContext
    ) async -> Bool {
        let origin: CoachTurnOrigin
        if let promptSuggestion {
            origin = .promptSuggestion(promptSuggestion)
        } else if let followUpMessageID {
            origin = .followUp(messageID: followUpMessageID)
        } else if let interactionId {
            origin = .interaction(
                messageID: interactionMessageID,
                interactionID: interactionId,
                selectedOptionID: selectedOptionId,
                isCustomResponse: isCustomInteractionResponse
            )
        } else {
            origin = .composer
        }
        return await submit(
            CoachTurnRequest(
                text: text,
                model: model,
                attachments: attachments,
                evidence: evidence,
                groundingSnapshot: groundingSnapshot,
                threadID: threadID,
                origin: origin,
                actionTypeOverride: actionTypeOverride,
                expectedResponseInteraction: expectedResponseInteraction,
                displayText: displayText,
                contextSnapshotID: contextSnapshotId,
                contextItems: contextItems
            ),
            access: CoachAccess(connection: .anthropicKey, credential: .apiKey(apiKey)),
            in: context
        )
    }
}
