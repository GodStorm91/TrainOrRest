import Foundation

struct AssembledResponse {
    var response: ClaudeResponse
    var error: String?
    var truncated: Bool = false
}

struct CoachStreamAssembler {
    private struct TextBlock {
        var text = ""
    }

    private struct ToolBlock {
        var id: String
        var name: String
        var inputJSON = ""
    }

    private enum OpenBlock {
        case text(TextBlock)
        case tool(ToolBlock)
    }

    var onText: @MainActor (String) -> Void = { _ in }

    func assemble(_ events: AsyncThrowingStream<AnthropicStreamEvent, Error>) async throws -> AssembledResponse {
        var blocks: [Int: ClaudeContentBlock] = [:]
        var openBlocks: [Int: OpenBlock] = [:]
        var stopReason: String?
        var streamError: String?
        var truncated = false

        for try await event in events {
            switch event {
            case .messageStart:
                blocks.removeAll()
                openBlocks.removeAll()
                stopReason = nil
                streamError = nil
            case .contentBlockStart(let index, let kind):
                switch kind {
                case .text:
                    openBlocks[index] = .text(TextBlock())
                case let .toolUse(id, name):
                    openBlocks[index] = .tool(ToolBlock(id: id, name: name))
                }
            case .textDelta(let index, let text):
                let block: TextBlock
                if case .text(let existing)? = openBlocks[index] {
                    block = existing
                } else {
                    // Real SSE streams can occasionally arrive without a
                    // matching content_block_start in our local state, usually
                    // after transport retries or shape drift. Text is safe to
                    // preserve, so recover instead of surfacing an internal
                    // state-machine error to the user.
                    block = TextBlock()
                }
                var updated = block
                updated.text += text
                openBlocks[index] = .text(updated)
                await onText(text)
            case .inputJSONDelta(let index, let fragment):
                guard case .tool(var block)? = openBlocks[index] else {
                    // Without the tool start frame we do not know which schema
                    // to decode. Drop the orphaned fragment and let the model
                    // complete the turn with text or a clean retry.
                    continue
                }
                block.inputJSON += fragment
                openBlocks[index] = .tool(block)
            case .contentBlockStop(let index):
                guard let block = openBlocks.removeValue(forKey: index) else {
                    // Duplicate or orphaned stop frames are harmless. Treat them
                    // as transport noise, not as chat-visible assistant errors.
                    continue
                }
                switch block {
                case .text(let textBlock):
                    blocks[index] = .text(textBlock.text)
                case .tool(let toolBlock):
                    guard let data = toolBlock.inputJSON.data(using: .utf8),
                          let input = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                        streamError = "Couldn't read that tool input."
                        continue
                    }
                    blocks[index] = .toolUse(id: toolBlock.id, name: toolBlock.name, input: input)
                }
            case .passthroughBlock(let index, let value):
                blocks[index] = .passthrough(value)
            case .messageDelta(let reason):
                stopReason = reason
            case .messageStop:
                break
            case .ping:
                continue
            case .error(let message):
                streamError = message
            }
        }

        if !openBlocks.isEmpty {
            for (index, block) in openBlocks {
                switch block {
                case .text(let textBlock):
                    if !textBlock.text.isEmpty {
                        blocks[index] = .text(textBlock.text)
                    }
                case .tool:
                    truncated = true
                }
            }
        }

        let response = ClaudeResponse(
            content: blocks.keys.sorted().compactMap { blocks[$0] },
            stopReason: stopReason
        )
        return AssembledResponse(response: response, error: streamError, truncated: truncated)
    }
}
