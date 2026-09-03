import Foundation

enum CoachGlossaryTokenURL {
    static func url(for termId: String) -> URL {
        var components = URLComponents()
        components.scheme = "trainorrest"
        components.host = "glossary"
        components.path = "/\(termId)"
        return components.url!
    }

    static func termID(from url: URL) -> String? {
        guard url.scheme == "trainorrest", url.host == "glossary" else { return nil }
        return url.path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
    }
}

enum CoachGlossaryMarkup {
    static func parse(_ text: String) -> [CoachGlossarySegment] {
        guard !text.isEmpty else { return [] }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = structuredTermRegex.matches(in: text, range: fullRange)
        var segments: [CoachGlossarySegment] = []
        var cursor = fullRange.location

        for match in matches where match.range.location >= cursor {
            appendPlainText(text, range: NSRange(location: cursor, length: match.range.location - cursor), to: &segments)

            guard
                let idRange = Range(match.range(at: 1), in: text),
                let labelRange = Range(match.range(at: 2), in: text)
            else {
                cursor = NSMaxRange(match.range)
                continue
            }

            let id = String(text[idRange])
            let label = String(text[labelRange])
            if CoachGlossary.term(id: id) != nil, !label.isEmpty {
                segments.append(.term(id: id.lowercased(), label: label))
            } else {
                appendPlainText(label, to: &segments)
            }
            cursor = NSMaxRange(match.range)
        }

        let trailingRange = NSRange(location: cursor, length: NSMaxRange(fullRange) - cursor)
        if let unclosedMarkerLocation = firstUnclosedOpening(in: text, range: trailingRange) {
            appendPlainText(
                text,
                range: NSRange(location: cursor, length: unclosedMarkerLocation - cursor),
                to: &segments
            )
        } else {
            appendPlainText(text, range: trailingRange, to: &segments)
        }

        return segments
    }

    static func legacySegments(_ text: String) -> [CoachGlossarySegment] {
        guard !text.isEmpty, let legacyAliasRegex else { return text.isEmpty ? [] : [.text(text)] }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let excludedRanges = excludedRanges(in: text, fullRange: fullRange)
        let matches = legacyAliasRegex.matches(in: text, range: fullRange)
        var segments: [CoachGlossarySegment] = []
        var seenTermIDs = Set<String>()
        var cursor = fullRange.location

        for match in matches {
            guard !excludedRanges.contains(where: { rangesOverlap(match.range, $0) }),
                  let matchRange = Range(match.range, in: text)
            else { continue }

            let label = String(text[matchRange])
            guard let term = CoachGlossary.term(matchingAlias: label) else { continue }

            appendText(text, range: NSRange(location: cursor, length: match.range.location - cursor), to: &segments)
            if seenTermIDs.insert(term.id.lowercased()).inserted {
                segments.append(.term(id: term.id, label: label))
            } else {
                appendText(label, to: &segments)
            }
            cursor = NSMaxRange(match.range)
        }

        appendText(text, range: NSRange(location: cursor, length: NSMaxRange(fullRange) - cursor), to: &segments)
        return segments
    }

    static func firstOccurrenceOnly(_ segments: [CoachGlossarySegment]) -> [CoachGlossarySegment] {
        var deduplicated: [CoachGlossarySegment] = []
        var seenTermIDs = Set<String>()

        for segment in segments {
            switch segment {
            case let .text(text):
                appendText(text, to: &deduplicated)
            case let .term(id, label):
                if seenTermIDs.insert(id.lowercased()).inserted {
                    deduplicated.append(segment)
                } else {
                    appendText(label, to: &deduplicated)
                }
            }
        }

        return deduplicated
    }

    private static let structuredTermRegex = try! NSRegularExpression(
        pattern: #"\[\[term:([A-Za-z0-9_]+)\|([^\]]*)\]\]"#
    )

    private static let legacyAliasRegex: NSRegularExpression? = {
        var aliases: [String] = []
        for term in CoachGlossary.terms {
            aliases.append(term.canonicalLabel)
            aliases.append(contentsOf: term.aliases)
        }
        aliases.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        let escaped = aliases.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = escaped.joined(separator: "|")
        return try? NSRegularExpression(
            pattern: "(?<![A-Za-z0-9])(?:\(pattern))(?![A-Za-z0-9])",
            options: .caseInsensitive
        )
    }()

    private static let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`]*`")
    private static let urlRegex = try! NSRegularExpression(pattern: #"https?://\S+"#, options: .caseInsensitive)

    private static func appendPlainText(_ text: String, to segments: inout [CoachGlossarySegment]) {
        appendPlainText(text, range: NSRange(text.startIndex..<text.endIndex, in: text), to: &segments)
    }

    private static func appendPlainText(_ source: String, range: NSRange, to segments: inout [CoachGlossarySegment]) {
        guard range.length > 0, let sourceRange = Range(range, in: source) else { return }

        var cursor = sourceRange.lowerBound
        while cursor < sourceRange.upperBound,
              let markerRange = source.range(of: "[[term:", range: cursor..<sourceRange.upperBound) {
            appendText(String(source[cursor..<markerRange.lowerBound]), to: &segments)

            guard let closingRange = source.range(of: "]]", range: markerRange.upperBound..<sourceRange.upperBound) else {
                return
            }

            let contentRange = markerRange.upperBound..<closingRange.lowerBound
            if let separator = source[contentRange].firstIndex(of: "|") {
                appendText(String(source[source.index(after: separator)..<contentRange.upperBound]), to: &segments)
            }
            cursor = closingRange.upperBound
        }

        appendText(String(source[cursor..<sourceRange.upperBound]), to: &segments)
    }

    private static func appendText(_ source: String, range: NSRange, to segments: inout [CoachGlossarySegment]) {
        guard range.length > 0, let sourceRange = Range(range, in: source) else { return }
        appendText(String(source[sourceRange]), to: &segments)
    }

    private static func appendText(_ text: String, to segments: inout [CoachGlossarySegment]) {
        guard !text.isEmpty else { return }

        if let last = segments.last, case let .text(previousText) = last {
            segments[segments.count - 1] = .text(previousText + text)
        } else {
            segments.append(.text(text))
        }
    }

    private static func excludedRanges(in text: String, fullRange: NSRange) -> [NSRange] {
        inlineCodeRegex.matches(in: text, range: fullRange).map(\.range)
            + urlRegex.matches(in: text, range: fullRange).map(\.range)
    }

    private static func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }

    private static func firstUnclosedOpening(in source: String, range: NSRange) -> Int? {
        guard let sourceRange = Range(range, in: source) else { return nil }

        var cursor = sourceRange.lowerBound
        while cursor < sourceRange.upperBound,
              let openingRange = source.range(of: "[[", range: cursor..<sourceRange.upperBound) {
            if source.range(of: "]]", range: openingRange.upperBound..<sourceRange.upperBound) == nil {
                return NSRange(openingRange, in: source).location
            }
            cursor = openingRange.upperBound
        }

        return nil
    }
}
