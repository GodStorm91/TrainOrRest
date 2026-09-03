import Foundation

struct AnthropicSSEParser {
    private var buffer = ""

    init() {}

    mutating func feed(_ chunk: String) -> [AnthropicStreamEvent] {
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var events: [AnthropicStreamEvent] = []
        drainCompleteFrames(into: &events)
        drainLineSeparatedFrames(into: &events)
        return events
    }

    private mutating func drainCompleteFrames(into events: inout [AnthropicStreamEvent]) {
        while let range = buffer.range(of: "\n\n") {
            let frame = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            events += Self.parseFrame(frame)
        }
    }

    private mutating func drainLineSeparatedFrames(into events: inout [AnthropicStreamEvent]) {
        // URLSession.AsyncBytes.lines can make SSE blank-line delimiters awkward in
        // practice. If the stream arrives as `event/data/event/data` separated by
        // single newlines, flush the complete frame before the next `event:` line
        // instead of waiting until finish() and treating multiple JSON payloads as
        // one malformed blob.
        while let nextEvent = Self.nextEventBoundary(in: buffer) {
            let frame = String(buffer[..<nextEvent.lowerBound])
            guard !frame.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
                buffer.removeSubrange(buffer.startIndex..<nextEvent.upperBound)
                buffer = "event:" + buffer
                continue
            }
            buffer.removeSubrange(buffer.startIndex..<nextEvent.upperBound)
            buffer = "event:" + buffer
            events += Self.parseFrame(frame)
        }
    }

    private static func nextEventBoundary(in text: String) -> Range<String.Index>? {
        guard let firstEvent = text.range(of: "event:") else { return nil }
        let searchStart = firstEvent.upperBound
        guard searchStart < text.endIndex,
              let next = text.range(of: "\nevent:", range: searchStart..<text.endIndex) else {
            return nil
        }
        return next
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
            // SSE streams may include heartbeat/comment frames, named pings, or
            // other event-only keep-alives with no payload. They are transport
            // noise, not assistant failures, so never render them in chat.
            return []
        }

        let data = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if eventName == "ping" { return data.isEmpty ? [] : [.ping] }
        guard !data.isEmpty else { return [] }
        guard data != "[DONE]" else { return [] }
        guard let payload = data.data(using: .utf8) else {
            return [.error("Claude sent an unreadable stream frame. Try again.")]
        }

        do {
            let decoded = try JSONDecoder().decode(StreamPayload.self, from: payload)
            guard let event = map(decoded, eventName: eventName) else { return [] }
            return [event]
        } catch {
            if let fallback = fallbackEvent(for: eventName, payload: payload) {
                return [fallback]
            }
            return [.error("Claude sent an unreadable stream frame. Try again.")]
        }
    }

    private static func fallbackEvent(for eventName: String?, payload: Data) -> AnthropicStreamEvent? {
        // Anthropic's SSE event name is authoritative enough for frames whose
        // payload is only metadata. If a future payload shape stops matching our
        // narrow decoder, keep the stream alive for structural events instead of
        // surfacing a parser-internal "malformed SSE" bubble to the user.
        guard let eventName,
              let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            return nil
        }
        switch eventName {
        case "message_start":
            return .messageStart
        case "content_block_stop":
            guard let index = object["index"] as? Int else { return nil }
            return .contentBlockStop(index: index)
        case "message_delta":
            let delta = object["delta"] as? [String: Any]
            return .messageDelta(stopReason: delta?["stop_reason"] as? String)
        case "message_stop":
            return .messageStop
        case "ping":
            return .ping
        default:
            return nil
        }
    }

    private static func fieldValue(_ line: Substring, prefix: String) -> String {
        var value = line.dropFirst(prefix.count)
        if value.first == " " {
            value = value.dropFirst()
        }
        return String(value)
    }

    private static func map(_ payload: StreamPayload, eventName: String?) -> AnthropicStreamEvent? {
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
                // New Anthropic models/features may emit content blocks that are
                // not user-visible text and not one of our supported tool calls
                // (for example thinking/citation-style blocks). Ignore the block
                // start and let later unknown deltas/stops be ignored too, rather
                // than rendering parser internals in chat.
                return nil
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
                // Anthropic can add non-user-visible deltas such as citations,
                // thinking, or signatures depending on model/features. They are
                // safe to ignore here; surfacing them as chat errors leaks parser
                // internals and breaks otherwise-valid replies.
                return nil
            }
        case "content_block_stop":
            guard let index = payload.index else { return .error("Malformed content_block_stop.") }
            return .contentBlockStop(index: index)
        case "message_delta":
            return .messageDelta(stopReason: payload.delta?.stopReason)
        case "message_stop":
            return .messageStop
        case "ping":
            return .ping
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
