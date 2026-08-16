import Foundation

enum PersonalCoachSettings {
    static let ageKey = "personalCoachAge"
    static let heightCmKey = "personalCoachHeightCm"
    static let weightKgKey = "personalCoachWeightKg"
    static let storageKey = "personalCoachSettings"
    static let maxNotesCharacters = 1000

    static var current: String {
        var lines: [String] = []
        let defaults = UserDefaults.standard
        append("Age", defaults.string(forKey: ageKey), unit: "years", to: &lines)
        append("Height", defaults.string(forKey: heightCmKey), unit: "cm", to: &lines)
        append("Weight", defaults.string(forKey: weightKgKey), unit: "kg", to: &lines)
        let notes = sanitizedNotes(defaults.string(forKey: storageKey) ?? "")
        if !notes.isEmpty { lines.append("Notes: \(notes)") }
        return lines.joined(separator: "\n")
    }

    static func sanitizedNumber(_ value: String, allowsDecimal: Bool = false) -> String {
        var hasDecimalSeparator = false
        let filtered = value.filter { character in
            if character.isNumber { return true }
            if allowsDecimal && (character == "." || character == ",") && !hasDecimalSeparator {
                hasDecimalSeparator = true
                return true
            }
            return false
        }.replacingOccurrences(of: ",", with: ".")
        return String(filtered.prefix(6))
    }

    static func sanitizedNotes(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxNotesCharacters else { return trimmed }
        return String(trimmed.prefix(maxNotesCharacters))
    }

    private static func append(_ label: String, _ rawValue: String?, unit: String, to lines: inout [String]) {
        let value = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        lines.append("\(label): \(value) \(unit)")
    }
}
