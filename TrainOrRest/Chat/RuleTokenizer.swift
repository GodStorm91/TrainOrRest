import Foundation

struct RuleTokenSpan: Equatable {
    let code: String
    let ruleID: ReadinessRuleID
    let lowerBound: Int
    let upperBound: Int

    var range: Range<Int> { lowerBound..<upperBound }
}

enum RuleTokenizer {
    private static let pattern = #"(?<![A-Za-z0-9_])R(?:10|[1-9])(?![A-Za-z0-9_])"#

    static func tokens(in text: String) -> [RuleTokenSpan] {
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern)
        else { return [] }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let code = String(text[range])
            guard let ruleID = ReadinessRuleID(rawValue: code) else { return nil }
            return RuleTokenSpan(
                code: code,
                ruleID: ruleID,
                lowerBound: match.range.location,
                upperBound: match.range.location + match.range.length
            )
        }
    }
}

enum RuleTokenURL {
    private static let scheme = "trainorrest"
    private static let host = "readiness-rule"

    static func url(for ruleID: ReadinessRuleID) -> URL {
        URL(string: "\(scheme)://\(host)/\(ruleID.code)")!
    }

    static func ruleID(from url: URL) -> ReadinessRuleID? {
        guard url.scheme == scheme, url.host == host else { return nil }
        return url.pathComponents.dropFirst().first.flatMap(ReadinessRuleID.init(rawValue:))
    }
}

extension ReadinessRuleID: Identifiable {
    var id: String { code }
}
