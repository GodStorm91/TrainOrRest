import Foundation

struct ReadinessWidgetSnapshot: Codable, Equatable {
    static let appGroupIdentifier = "group.com.khanhnguyen.TrainOrRest"
    static let storageKey = "readinessWidgetSnapshot"

    var score: Int?
    var verdictRaw: String
    /// Retained for snapshot wire compatibility; the widget localizes from `verdictRaw`.
    var verdictText: String
    var reason: String
    /// Language copied from the app's standard defaults when the snapshot is published.
    /// Optional keeps snapshots written by older app versions decodable.
    var languageRaw: String? = nil
    var computedAt: Date?
    var updatedAt: Date

    static let placeholder = ReadinessWidgetSnapshot(
        score: 78,
        verdictRaw: "train",
        verdictText: "Train",
        reason: "",
        languageRaw: "en",
        computedAt: Date(timeIntervalSinceReferenceDate: 0),
        updatedAt: Date(timeIntervalSinceReferenceDate: 0)
    )

    static func unavailable(languageRaw: String? = nil) -> ReadinessWidgetSnapshot {
        ReadinessWidgetSnapshot(
            score: nil,
            verdictRaw: "insufficientData",
            verdictText: "Baseline",
            reason: "",
            languageRaw: languageRaw,
            computedAt: nil,
            updatedAt: .now
        )
    }

    var scoreText: String {
        score.map(String.init) ?? "--"
    }

    static func load(
        defaults: UserDefaults = widgetDefaults(),
        decoder: JSONDecoder = JSONDecoder()
    ) -> ReadinessWidgetSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? decoder.decode(ReadinessWidgetSnapshot.self, from: data)
        else { return .unavailable() }
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
