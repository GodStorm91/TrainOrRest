import Foundation

struct ReadinessWidgetSnapshot: Codable, Equatable {
    static let appGroupIdentifier = "group.com.khanhnguyen.TrainOrRest"
    static let storageKey = "readinessWidgetSnapshot"

    var score: Int?
    var verdictRaw: String
    var verdictText: String
    var reason: String
    var computedAt: Date?
    var updatedAt: Date

    static let placeholder = ReadinessWidgetSnapshot(
        score: 78,
        verdictRaw: "train",
        verdictText: "Train",
        reason: "Ready for the planned session",
        computedAt: Date(timeIntervalSinceReferenceDate: 0),
        updatedAt: Date(timeIntervalSinceReferenceDate: 0)
    )

    static let unavailable = ReadinessWidgetSnapshot(
        score: nil,
        verdictRaw: "insufficientData",
        verdictText: "Baseline",
        reason: "Open the app to compute readiness",
        computedAt: nil,
        updatedAt: .now
    )

    var scoreText: String {
        score.map(String.init) ?? "--"
    }

    var footerText: String {
        guard let computedAt else { return "No fresh data" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: computedAt, relativeTo: .now))"
    }

    static func load(
        defaults: UserDefaults = widgetDefaults(),
        decoder: JSONDecoder = JSONDecoder()
    ) -> ReadinessWidgetSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? decoder.decode(ReadinessWidgetSnapshot.self, from: data)
        else { return .unavailable }
        return snapshot
    }

    static func save(
        _ snapshot: ReadinessWidgetSnapshot,
        defaults: UserDefaults = widgetDefaults(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func widgetDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
