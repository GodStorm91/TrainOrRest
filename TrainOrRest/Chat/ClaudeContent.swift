import Foundation

enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

enum ClaudeContentBlock: Codable, Equatable {
    case text(String)
    case image(mediaType: String, data: String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)
    /// Any block this app does not model — `thinking`, `redacted_thinking`, and
    /// future types. Kept byte-for-byte so the tool loop can replay the
    /// assistant turn exactly; signatures and opaque data must survive intact.
    case passthrough(JSONValue)

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, content, source
        case toolUseID = "tool_use_id"
        case isError = "is_error"
    }

    enum SourceKeys: String, CodingKey {
        case type, data
        case mediaType = "media_type"
    }

    /// Decodes from the raw JSON object so an unrecognized block can be
    /// preserved whole rather than collapsed into empty text.
    init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        guard case .object(let fields) = raw,
              case .string(let type)? = fields["type"] else {
            self = .passthrough(raw)
            return
        }
        switch type {
        case "text":
            guard case .string(let text)? = fields["text"] else { self = .passthrough(raw); return }
            self = .text(text)
        case "image":
            guard case .object(let source)? = fields["source"],
                  case .string(let mediaType)? = source["media_type"],
                  case .string(let data)? = source["data"] else {
                self = .passthrough(raw)
                return
            }
            self = .image(mediaType: mediaType, data: data)
        case "tool_use":
            guard case .string(let id)? = fields["id"],
                  case .string(let name)? = fields["name"],
                  let input = fields["input"] else {
                self = .passthrough(raw)
                return
            }
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            guard case .string(let toolUseID)? = fields["tool_use_id"],
                  case .string(let content)? = fields["content"] else {
                self = .passthrough(raw)
                return
            }
            var isError = false
            if case .bool(let flag)? = fields["is_error"] { isError = flag }
            self = .toolResult(toolUseID: toolUseID, content: content, isError: isError)
        default:
            self = .passthrough(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        if case .passthrough(let raw) = self {
            try raw.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .passthrough:
            return // handled above
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(mediaType, data):
            try container.encode("image", forKey: .type)
            var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encode(data, forKey: .data)
        case let .toolUse(id, name, input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case let .toolResult(toolUseID, content, isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(true, forKey: .isError)
            }
        }
    }
}

extension Array where Element == ClaudeContentBlock {
    var textContent: String {
        compactMap {
            if case .text(let text) = $0 { return text }
            return nil
        }
        .joined(separator: "\n")
    }
}
