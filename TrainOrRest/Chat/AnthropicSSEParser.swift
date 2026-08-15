import Foundation

struct AnthropicSSEParser {
    private var buffer = ""

    init() {}

    mutating func feed(_ chunk: String) -> [AnthropicStreamEvent] {
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var events: [AnthropicStreamEvent] = []
        while let range = buffer.range(of: "\n\n") {
            let frame = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            events += Self.parseFrame(frame)
        }
        return events
    }

    mutating func finish() -> [AnthropicStreamEvent] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            buffer = ""
            return []
        }
        let frame = buffer
        buffer = ""
        return Self.parseFrame(frame)
    }

    static func parse(_ text: String) -> [AnthropicStreamEvent] {
        var parser = AnthropicSSEParser()
        return parser.feed(text) + parser.finish()
    }

    private static func parseFrame(_ frame: String) -> [AnthropicStreamEvent] {
        var eventName: String?
        var dataLines: [String] = []

        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty || line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
                eventName = fieldValue(line, prefix: "event:")
            } else if line.hasPrefix("data:") {
                dataLines.append(fieldValue(line, prefix: "data:"))
            }
        }

        guard !dataLines.isEmpty else {
            return [.error("Malformed SSE frame.")]
        }

        let data = dataLines.joined(separator: "\n")
        guard data != "[DONE]" else { return [] }
        guard let payload = data.data(using: .utf8) else {
            return [.error("Malformed SSE frame.")]
        }

        do {
            let decoded = try JSONDecoder().decode(StreamPayload.self, from: payload)
            return [map(decoded, eventName: eventName)]
        } catch {
            return [.error("Malformed SSE frame.")]
        }
    }

    private static func fieldValue(_ line: Substring, prefix: String) -> String {
        var value = line.dropFirst(prefix.count)
        if value.first == " " {
            value = value.dropFirst()
        }
        return String(value)
    }

    private static func map(_ payload: StreamPayload, eventName: String?) -> AnthropicStreamEvent {
        switch payload.type {
        case "message_start":
            return .messageStart
        case "content_block_start":
            guard let index = payload.index, let block = payload.contentBlock else {
                return .error("Malformed content_block_start.")
            }
            switch block.type {
            case "text":
                return .contentBlockStart(index: index, kind: .text)
            case "tool_use":
                guard let id = block.id, let name = block.name else {
                    return .error("Malformed tool_use block.")
                }
                return .contentBlockStart(index: index, kind: .toolUse(id: id, name: name))
            default:
                return .error("Unsupported content block.")
            }
        case "content_block_delta":
            guard let index = payload.index, let delta = payload.delta else {
                return .error("Malformed content_block_delta.")
            }
            switch delta.type {
            case "text_delta":
                return .textDelta(index: index, delta.text ?? "")
            case "input_json_delta":
                return .inputJSONDelta(index: index, delta.partialJSON ?? "")
            default:
                return .error("Unsupported content delta.")
            }
        case "content_block_stop":
            guard let index = payload.index else { return .error("Malformed content_block_stop.") }
            return .contentBlockStop(index: index)
        case "message_delta":
            return .messageDelta(stopReason: payload.delta?.stopReason)
        case "message_stop":
            return .messageStop
        case "error":
            return .error(payload.error?.message ?? "Anthropic stream error.")
        default:
            if eventName == "error" {
                return .error(payload.error?.message ?? "Anthropic stream error.")
            }
            return .error("Unsupported stream event.")
        }
    }
}

private struct StreamPayload: Decodable {
    var type: String
    var index: Int?
    var contentBlock: StreamContentBlock?
    var delta: StreamDelta?
    var error: StreamError?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, error
        case contentBlock = "content_block"
    }
}

private struct StreamContentBlock: Decodable {
    var type: String
    var id: String?
    var name: String?
}

private struct StreamDelta: Decodable {
    var type: String?
    var text: String?
    var partialJSON: String?
    var stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type, text
        case partialJSON = "partial_json"
        case stopReason = "stop_reason"
    }
}

private struct StreamError: Decodable {
    var message: String?
}
