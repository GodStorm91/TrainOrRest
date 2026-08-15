import Foundation

enum AnthropicStreamEvent: Equatable {
    enum BlockKind: Equatable {
        case text
        case toolUse(id: String, name: String)
    }

    case messageStart
    case contentBlockStart(index: Int, kind: BlockKind)
    case textDelta(index: Int, String)
    case inputJSONDelta(index: Int, String)
    case contentBlockStop(index: Int)
    case passthroughBlock(index: Int, JSONValue)
    case messageDelta(stopReason: String?)
    case messageStop
    case error(String)
}

enum CoachStreamEvent: Equatable {
    case textDelta(String)
    case ruleRefFinal(String)
    case intentFinal(PlanEditIntent)
    case explanationFinal(CoachExplanation)
    case messageDone(stopReason: String?)
    case messageStopped
    case messageError(String)
}

actor CoachStreamAccumulator {
    private struct ToolBlock {
        var name: String
        var inputJSON: String = ""
    }

    private var toolBlocks: [Int: ToolBlock] = [:]
    private var stopReason: String?

    func ingest(_ event: AnthropicStreamEvent) -> [CoachStreamEvent] {
        switch event {
        case .messageStart:
            stopReason = nil
            toolBlocks.removeAll()
            return []
        case .contentBlockStart(let index, let kind):
            if case .toolUse(_, let name) = kind {
                toolBlocks[index] = ToolBlock(name: name)
            }
            return []
        case .textDelta(_, let text):
            return [.textDelta(text)]
        case .inputJSONDelta(let index, let fragment):
            toolBlocks[index]?.inputJSON += fragment
            return []
        case .contentBlockStop(let index):
            guard let block = toolBlocks.removeValue(forKey: index) else { return [] }
            return [decode(block)]
        case .passthroughBlock:
            return []
        case .messageDelta(let stopReason):
            self.stopReason = stopReason
            return []
        case .messageStop:
            if !toolBlocks.isEmpty {
                toolBlocks.removeAll()
                return [.messageStopped]
            }
            return [.messageDone(stopReason: stopReason)]
        case .error(let message):
            return [.messageError(message)]
        }
    }

    private func decode(_ block: ToolBlock) -> CoachStreamEvent {
        let data = Data(block.inputJSON.utf8)
        switch block.name {
        case CoachToolCatalog.planEditDraftName:
            do {
                let proposal = try JSONDecoder().decode(PlanAdjustmentProposal.self, from: data)
                return .intentFinal(PlanEditIntent(proposal: proposal))
            } catch {
                return .messageError("Couldn't read that proposal")
            }
        case CoachToolCatalog.explainOnlyName:
            do {
                return .explanationFinal(try JSONDecoder().decode(CoachExplanation.self, from: data))
            } catch {
                return .messageError("Couldn't read that explanation")
            }
        case CoachToolCatalog.ruleRefName:
            do {
                let citation = try JSONDecoder().decode(RuleCitation.self, from: data)
                return .ruleRefFinal(citation.code)
            } catch {
                return .messageError("Couldn't read that rule")
            }
        default:
            return .messageError("Couldn't read that tool")
        }
    }
}

private struct RuleCitation: Decodable {
    var code: String
}
