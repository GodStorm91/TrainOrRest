import Foundation

/// One typed request to change a planned session's distance, its type, or both.
///
/// The coach answers most messages with the model. This parser exists so that a
/// plain edit such as "đổi buổi hôm nay thành 7 km" lands in about 0.1 seconds
/// with no round trip. It therefore holds a plan mutation behind a regular
/// sentence, and a wrong reading rewrites the wrong workout. Every rule below
/// prefers to return nil and let the model answer.
struct CoachDistanceCommand: Equatable {
    enum RelativeDay: Equatable {
        case today
        case tomorrow
    }

    var targetKm: Double
    var sourceKm: Double?
    var kind: WorkoutKind?
    var absoluteDay: String?
    var relativeDay: RelativeDay?

    func day(relativeTo today: Date, calendar: Calendar) -> Date? {
        if let absoluteDay {
            return Self.date(from: absoluteDay, calendar: calendar)
        }
        switch relativeDay {
        case .today:
            return calendar.startOfDay(for: today)
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))
        case nil:
            return nil
        }
    }

    private static func date(from value: String, calendar: Calendar) -> Date? {
        guard value.count == 10 else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        let dayStart = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        let rendered = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return rendered == value ? dayStart : nil
    }

    /// Vietnamese keeps `đ`, so this folds accents, lowercases, and turns the
    /// Vietnamese decimal comma into a dot.
    static func fold(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: ",", with: ".")
            .lowercased()
    }

    static func parse(_ text: String) -> CoachDistanceCommand? {
        parse(folded: fold(text))
    }

    static func parse(folded lower: String) -> CoachDistanceCommand? {
        // A sentence that only names a distance is a question. "Suggest a 7 km
        // threshold" must reach the coach, not silently rewrite Saturday.
        guard hasEditCue(in: lower) else { return nil }

        let kmValues = distanceValues(in: lower)
        let chosen: (value: Double, location: Int)
        if let explicit = explicitTarget(in: lower) {
            chosen = explicit
        } else if kmValues.count == 1 {
            chosen = kmValues[0]
        } else {
            // Several distances and no "to N km" phrase. A structured session
            // lists a warm up, the work, and a cool down, so the last number is
            // the cool down rather than the new total.
            return nil
        }
        guard chosen.value > 0 else { return nil }

        return CoachDistanceCommand(
            targetKm: chosen.value,
            sourceKm: kmValues.first { $0.location < chosen.location && $0.value != chosen.value }?.value,
            kind: workoutKind(inFolded: lower),
            absoluteDay: absoluteDayString(in: lower),
            relativeDay: relativeDay(in: lower)
        )
    }

    /// Verbs and directions that make a sentence a command. A day name such as
    /// "hôm nay" says which session the user means, so it never appears here.
    /// "Suggest a 7 km threshold for today" is still a question.
    private static let editCues = [
        "doi", "chuyen", "thay", "tang", "giam", "nang", "ha", "cap nhat", "sua",
        "change", "update", "set", "make", "increase", "decrease",
        "cu li", "cu ly", "quang duong",
        "thanh", "to", "len", "xuong"
    ]

    static func hasEditCue(in lower: String) -> Bool {
        editCues.contains { containsWord($0, in: lower) }
    }

    /// Matches a whole word only. "ha" must not fire inside "nhanh", and "len"
    /// must not fire inside "lenh".
    private static func containsWord(_ needle: String, in lower: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: needle))(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        return regex.firstMatch(in: lower, options: [], range: range) != nil
    }

    private static let targetPatterns = [
        #"(?:thanh|to|len|xuong|set|make|increase\s+to|decrease\s+to)\s+(\d+(?:\.\d+)?)\s*(?:km|kilometer|kilometre|k)?"#,
        #"(?:from|tu)\s+\d+(?:\.\d+)?\s*(?:km|kilometer|kilometre|k)?\s+(?:to|den|thanh)\s+(\d+(?:\.\d+)?)\s*(?:km|kilometer|kilometre|k)?"#
    ]

    private static func explicitTarget(in lower: String) -> (value: Double, location: Int)? {
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        return targetPatterns.compactMap { pattern -> (value: Double, location: Int)? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            guard let match = regex.firstMatch(in: lower, options: [], range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: lower),
                  let value = Double(lower[valueRange]),
                  value > 0
            else { return nil }
            return (value, match.range(at: 1).location)
        }.first
    }

    static func distanceValues(in lower: String) -> [(value: Double, location: Int)] {
        let pattern = #"(?<![\d.])(\d+(?:\.\d+)?)\s*(?:km|kilometer|kilometre|k)(?![a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        return regex.matches(in: lower, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: lower),
                  let value = Double(lower[valueRange]),
                  value > 0
            else { return nil }
            return (value, match.range(at: 1).location)
        }
    }

    private static let kindNeedles: [(needle: String, kind: WorkoutKind)] = [
        ("long run", .long), ("bai dai", .long), ("chay dai", .long), ("buoi dai", .long),
        ("threshold", .threshold), ("nguong", .threshold),
        ("tempo", .tempo),
        ("interval", .intervals), ("bien toc", .intervals),
        ("easy", .easy), ("nhe", .easy), ("hoi phuc", .easy), ("phuc hoi", .easy)
    ]

    private static let kindChangeCues = ["thanh", "sang", "chuyen", "doi", "to", "into", "switch"]

    /// "Change the long run to a threshold" names two kinds. The sentence asks
    /// for the second one. A fixed priority order answers with the first one and
    /// rewrites the wrong session, so two names without a cue return nil.
    static func workoutKind(inFolded lower: String) -> WorkoutKind? {
        var hits: [(kind: WorkoutKind, location: Int)] = []
        for entry in kindNeedles {
            var searchStart = lower.startIndex
            while let found = lower.range(of: entry.needle, range: searchStart..<lower.endIndex) {
                hits.append((entry.kind, lower.distance(from: lower.startIndex, to: found.lowerBound)))
                searchStart = found.upperBound
            }
        }
        hits.sort { $0.location < $1.location }
        guard let first = hits.first else { return nil }
        guard Set(hits.map(\.kind)).count > 1 else { return first.kind }

        let cueEnd = kindChangeCues.compactMap { cue -> Int? in
            lastWordEnd(of: cue, in: lower)
        }.max()
        guard let cueEnd else { return nil }
        let after = hits.filter { $0.location >= cueEnd }
        guard let target = after.first, after.allSatisfy({ $0.kind == target.kind }) else { return nil }
        return target.kind
    }

    private static func lastWordEnd(of needle: String, in lower: String) -> Int? {
        let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: needle))(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.matches(in: lower, options: [], range: range).last else { return nil }
        return match.range.location + match.range.length
    }

    static func relativeDay(in lower: String) -> RelativeDay? {
        if lower.contains("ngay mai") || lower.contains("tomorrow") || lower.contains("tmr") {
            return .tomorrow
        }
        if lower.contains("hom nay") || lower.contains("hnay") || lower.contains("h nay") || lower.contains("today") {
            return .today
        }
        return nil
    }

    static func absoluteDayString(in lower: String) -> String? {
        let pattern = #"\b\d{4}-\d{2}-\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              let dateRange = Range(match.range, in: lower)
        else { return nil }
        return String(lower[dateRange])
    }
}
