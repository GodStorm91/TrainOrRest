import Foundation

struct ResponsesSSEParser {
    struct Message: Equatable {
        var event: String?
        var data: String
    }

    private var buffer = ""

    init() {}

    mutating func feed(_ chunk: String) -> [Message] {
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var messages: [Message] = []
        drainCompleteFrames(into: &messages)
        drainLineSeparatedFrames(into: &messages)
        return messages
    }

    mutating func finish() -> [Message] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            buffer = ""
            return []
        }
        let frame = buffer
        buffer = ""
        return Self.parseFrame(frame)
    }

    private mutating func drainCompleteFrames(into messages: inout [Message]) {
        while let range = buffer.range(of: "\n\n") {
            let frame = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            messages += Self.parseFrame(frame)
        }
    }

    private mutating func drainLineSeparatedFrames(into messages: inout [Message]) {
        // `URLSession.AsyncBytes.lines` can elide blank SSE separator lines.
        // A following event line is therefore a safe boundary for the prior frame.
        while let nextEvent = Self.nextEventBoundary(in: buffer) {
            let frame = String(buffer[..<nextEvent.lowerBound])
            guard !frame.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                buffer.removeSubrange(buffer.startIndex..<nextEvent.upperBound)
                buffer = "event:" + buffer
                continue
            }
            buffer.removeSubrange(buffer.startIndex..<nextEvent.upperBound)
            buffer = "event:" + buffer
            messages += Self.parseFrame(frame)
        }
    }

    private static func nextEventBoundary(in text: String) -> Range<String.Index>? {
        guard let firstEvent = text.range(of: "event:") else { return nil }
        let searchStart = firstEvent.upperBound
        guard searchStart < text.endIndex,
              let nextEvent = text.range(of: "\nevent:", range: searchStart..<text.endIndex) else {
            return nil
        }
        return nextEvent
    }

    private static func parseFrame(_ frame: String) -> [Message] {
        var event: String?
        var dataLines: [String] = []

        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty || line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
                event = fieldValue(line, prefix: "event:")
            } else if line.hasPrefix("data:") {
                dataLines.append(fieldValue(line, prefix: "data:"))
            }
        }

        let data = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !data.isEmpty, data != "[DONE]" else { return [] }

        // Responses puts the event name in the payload as well. Event headers are
        // optional, so use that field only when a header did not name the frame.
        if event == nil,
           let payload = try? JSONDecoder().decode(EventNamePayload.self, from: Data(data.utf8)) {
            event = payload.type
        }

        return [Message(event: event, data: data)]
    }

    private static func fieldValue(_ line: Substring, prefix: String) -> String {
        var value = line.dropFirst(prefix.count)
        if value.first == " " {
            value = value.dropFirst()
        }
        return String(value)
    }
}

private struct EventNamePayload: Decodable {
    var type: String?
}
