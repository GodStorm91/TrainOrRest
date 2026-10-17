import Foundation

/// Pulls one top level string property out of a tool input stream while the
/// stream is still arriving.
///
/// Anthropic delivers tool input as `input_json_delta` fragments. A fragment
/// is not valid JSON on its own, so this reader tracks the parse state itself.
/// It releases only text it can decode completely. An unterminated escape, an
/// unfinished `\uXXXX`, half of a surrogate pair, or a split UTF-8 sequence
/// stays buffered until a later fragment completes it.
struct PartialToolTextReader {
    private enum Phase {
        case scanning
        case reading
        case finished
    }

    private let key: String
    private var phase: Phase = .scanning
    private var depth = 0
    private var inString = false
    private var escaped = false
    private var token: [UInt8] = []
    private var lastKey: String?
    private var expectsValue = false
    private var value: [UInt8] = []
    private var decodedBytes = 0

    init(key: String) {
        self.key = key
    }

    /// True once the property's closing quote arrived.
    var isFinished: Bool { phase == .finished }

    /// Appends a fragment and returns the text that became readable.
    mutating func consume(_ fragment: String) -> String {
        for byte in fragment.utf8 {
            step(byte)
        }
        guard phase != .scanning, decodedBytes < value.count else { return "" }
        let (text, consumed) = Self.decode(value, from: decodedBytes)
        decodedBytes = consumed
        return text
    }

    private mutating func step(_ byte: UInt8) {
        switch phase {
        case .finished:
            return
        case .reading:
            if escaped {
                value.append(byte)
                escaped = false
            } else if byte == 0x5C {
                value.append(byte)
                escaped = true
            } else if byte == 0x22 {
                phase = .finished
            } else {
                value.append(byte)
            }
        case .scanning:
            scan(byte)
        }
    }

    private mutating func scan(_ byte: UInt8) {
        if inString {
            if escaped {
                token.append(byte)
                escaped = false
            } else if byte == 0x5C {
                token.append(byte)
                escaped = true
            } else if byte == 0x22 {
                inString = false
                if depth == 1, !expectsValue {
                    lastKey = String(decoding: token, as: UTF8.self)
                }
                expectsValue = false
            } else {
                token.append(byte)
            }
            return
        }
        switch byte {
        case 0x22:
            if depth == 1, expectsValue, lastKey == key {
                phase = .reading
                return
            }
            inString = true
            token.removeAll(keepingCapacity: true)
        case 0x7B, 0x5B:
            depth += 1
            expectsValue = false
        case 0x7D, 0x5D:
            depth -= 1
            expectsValue = false
        case 0x3A:
            expectsValue = depth == 1
        case 0x2C:
            expectsValue = false
        default:
            break
        }
    }

    /// Decodes JSON string body bytes from `offset`. Returns the decoded text
    /// and the byte count that is now safe to skip. A trailing fragment that
    /// cannot stand alone is left for the next call.
    private static func decode(_ bytes: [UInt8], from offset: Int) -> (String, Int) {
        var scalars = String.UnicodeScalarView()
        var index = offset
        var consumed = offset
        loop: while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x5C {
                guard index + 1 < bytes.count else { break loop }
                let code = bytes[index + 1]
                switch code {
                case 0x22: scalars.append("\""); index += 2
                case 0x5C: scalars.append("\\"); index += 2
                case 0x2F: scalars.append("/"); index += 2
                case 0x62: scalars.append("\u{08}"); index += 2
                case 0x66: scalars.append("\u{0C}"); index += 2
                case 0x6E: scalars.append("\n"); index += 2
                case 0x72: scalars.append("\r"); index += 2
                case 0x74: scalars.append("\t"); index += 2
                case 0x75:
                    guard let first = hex(bytes, at: index + 2) else { break loop }
                    if (0xD800...0xDBFF).contains(first) {
                        guard index + 11 < bytes.count,
                              bytes[index + 6] == 0x5C,
                              bytes[index + 7] == 0x75,
                              let second = hex(bytes, at: index + 8),
                              (0xDC00...0xDFFF).contains(second) else { break loop }
                        let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                        if let scalar = Unicode.Scalar(combined) { scalars.append(scalar) }
                        index += 12
                    } else if (0xDC00...0xDFFF).contains(first) {
                        index += 6
                    } else {
                        if let scalar = Unicode.Scalar(first) { scalars.append(scalar) }
                        index += 6
                    }
                default:
                    if let scalar = Unicode.Scalar(UInt32(code)) { scalars.append(scalar) }
                    index += 2
                }
            } else if byte < 0x80 {
                scalars.append(Unicode.Scalar(byte))
                index += 1
            } else {
                let width = utf8Width(byte)
                guard width > 0, index + width <= bytes.count,
                      let text = String(bytes: bytes[index..<(index + width)], encoding: .utf8) else { break loop }
                scalars.append(contentsOf: text.unicodeScalars)
                index += width
            }
            consumed = index
        }
        return (String(scalars), consumed)
    }

    private static func hex(_ bytes: [UInt8], at index: Int) -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        var value: UInt32 = 0
        for offset in 0..<4 {
            let byte = bytes[index + offset]
            let digit: UInt32
            switch byte {
            case 0x30...0x39: digit = UInt32(byte - 0x30)
            case 0x41...0x46: digit = UInt32(byte - 0x41) + 10
            case 0x61...0x66: digit = UInt32(byte - 0x61) + 10
            default: return nil
            }
            value = value << 4 | digit
        }
        return value
    }

    private static func utf8Width(_ byte: UInt8) -> Int {
        switch byte {
        case 0xC2...0xDF: return 2
        case 0xE0...0xEF: return 3
        case 0xF0...0xF4: return 4
        default: return 0
        }
    }
}
