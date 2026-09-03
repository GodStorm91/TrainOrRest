import Foundation
import SwiftData

enum CoachMemorySource: String, Codable, CaseIterable {
    case manual
    case chat
    case system
}

@Model
final class CoachMemoryItem {
    @Attribute(.unique) var uuid: UUID
    var text: String
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        uuid: UUID = UUID(),
        text: String,
        source: CoachMemorySource,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.uuid = uuid
        self.text = text
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var source: CoachMemorySource {
        get { CoachMemorySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

enum PersonalCoachSettings {
    static let ageKey = "personalCoachAge"
    static let heightCmKey = "personalCoachHeightCm"
    static let weightKgKey = "personalCoachWeightKg"
    static let storageKey = "personalCoachSettings"
    static let memoryMigrationKey = "personalCoachMemoryItemsMigrationCompleted"
    static let maxNotesCharacters = 1000
    static let maxMemoryItemCharacters = 500

    static var current: String {
        var lines: [String] = []
        let defaults = UserDefaults.standard
        append("Age", defaults.string(forKey: ageKey), unit: "years", to: &lines)
        append("Height", defaults.string(forKey: heightCmKey), unit: "cm", to: &lines)
        append("Weight", defaults.string(forKey: weightKgKey), unit: "kg", to: &lines)
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func migrateLegacyCoachMemoryIfNeeded(
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) throws {
        guard !defaults.bool(forKey: memoryMigrationKey) else { return }
        let legacyText = sanitizedNotes(defaults.string(forKey: storageKey) ?? "")
        guard !legacyText.isEmpty else {
            defaults.set(true, forKey: memoryMigrationKey)
            return
        }

        let existing = try coachMemoryItems(in: context)
        let chunks = legacyMemoryChunks(from: legacyText)
        var inserted = false
        for chunk in chunks where !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if existing.contains(where: { normalizedMemoryText($0.text) == normalizedMemoryText(chunk) }) {
                continue
            }
            context.insert(CoachMemoryItem(
                text: sanitizedMemoryText(chunk),
                source: .manual,
                createdAt: now,
                updatedAt: now
            ))
            inserted = true
        }
        if inserted {
            try context.save()
        }
        defaults.set(true, forKey: memoryMigrationKey)
    }

    @MainActor
    static func coachMemoryItems(in context: ModelContext) throws -> [CoachMemoryItem] {
        let items = try context.fetch(FetchDescriptor<CoachMemoryItem>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        ))
        return items.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.uuid.uuidString < rhs.uuid.uuidString
        }
    }

    @MainActor
    @discardableResult
    static func addCoachMemory(
        _ rawText: String,
        source: CoachMemorySource,
        in context: ModelContext,
        now: Date = .now
    ) throws -> CoachMemoryItem? {
        let text = sanitizedMemoryText(rawText)
        guard !text.isEmpty else { return nil }
        let normalized = normalizedMemoryText(text)
        let items = try coachMemoryItems(in: context)
        if let existing = items.first(where: { normalizedMemoryText($0.text) == normalized }) {
            return existing
        }
        let item = CoachMemoryItem(text: text, source: source, createdAt: now, updatedAt: now)
        context.insert(item)
        try context.save()
        return item
    }

    @MainActor
    static func updateCoachMemory(
        _ item: CoachMemoryItem,
        text rawText: String,
        in context: ModelContext,
        now: Date = .now
    ) throws {
        let text = sanitizedMemoryText(rawText)
        guard !text.isEmpty else { return }
        guard normalizedMemoryText(item.text) != normalizedMemoryText(text) else { return }
        item.text = text
        item.updatedAt = now
        try context.save()
    }

    @MainActor
    static func deleteCoachMemory(_ item: CoachMemoryItem, in context: ModelContext) throws {
        context.delete(item)
        try context.save()
    }

    @MainActor
    static func clearCoachMemory(in context: ModelContext) throws {
        for item in try coachMemoryItems(in: context) {
            context.delete(item)
        }
        try context.save()
    }

    static func sanitizedMemoryText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxMemoryItemCharacters else { return trimmed }
        return String(trimmed.prefix(maxMemoryItemCharacters))
    }

    static func normalizedMemoryText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
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

    static func legacyMemoryChunks(from legacyText: String) -> [String] {
        let paragraphs = legacyText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if paragraphs.count > 1 {
            return paragraphs
        }

        let lines = legacyText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let bulletPrefixes = ["- ", "• ", "* "]
        if lines.count > 1, lines.allSatisfy({ line in bulletPrefixes.contains { line.hasPrefix($0) } }) {
            return lines.map { line in
                bulletPrefixes.reduce(line) { partial, prefix in
                    partial.hasPrefix(prefix) ? String(partial.dropFirst(prefix.count)) : partial
                }
            }
        }

        return [legacyText]
    }

    private static func append(_ label: String, _ rawValue: String?, unit: String, to lines: inout [String]) {
        let value = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        lines.append("\(label): \(value) \(unit)")
    }
}
