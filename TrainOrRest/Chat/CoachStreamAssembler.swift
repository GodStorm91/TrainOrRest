import Foundation

struct AssembledResponse {
    var response: ClaudeResponse
    var error: String?
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
                guard case .text(var block)? = openBlocks[index] else {
                    streamError = "Received text for an unopened content block."
                    continue
                }
                block.text += text
                openBlocks[index] = .text(block)
                await onText(text)
            case .inputJSONDelta(let index, let fragment):
                guard case .tool(var block)? = openBlocks[index] else {
                    streamError = "Received tool input for an unopened content block."
                    continue
                }
                block.inputJSON += fragment
                openBlocks[index] = .tool(block)
            case .contentBlockStop(let index):
                guard let block = openBlocks.removeValue(forKey: index) else {
                    streamError = "Stopped an unopened content block."
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
            case .error(let message):
                streamError = message
            }
        }

        if !openBlocks.isEmpty {
            streamError = "Stream ended before all content blocks finished."
        }

        let response = ClaudeResponse(
            content: blocks.keys.sorted().compactMap { blocks[$0] },
            stopReason: stopReason
        )
        return AssembledResponse(response: response, error: streamError)
    }
}
