import Foundation
import SwiftData

/// The single active race goal. Raw storage mirrors `GoalSpec`; the app
/// enforces one instance (saving a new goal replaces the old one and its plan).
@Model
final class Goal {
    var distanceRaw: String
    var targetTimeSeconds: Double
    var raceDate: Date
    var availableDayNumbers: [Int]
    var longRunDayNumber: Int
    var createdAt: Date

    init(spec: GoalSpec, createdAt: Date) {
        self.distanceRaw = spec.distance.rawValue
        self.targetTimeSeconds = spec.targetTimeSeconds
        self.raceDate = spec.raceDate
        self.availableDayNumbers = spec.availableDays.map(\.rawValue).sorted()
        self.longRunDayNumber = spec.longRunDay.rawValue
        self.createdAt = createdAt
    }

    /// Nil only if stored raw values are corrupt (unknown enum case).
    var spec: GoalSpec? {
        guard let distance = RaceDistance(rawValue: distanceRaw),
              let longRunDay = Weekday(rawValue: longRunDayNumber) else { return nil }
        let days = Set(availableDayNumbers.compactMap(Weekday.init(rawValue:)))
        guard !days.isEmpty else { return nil }
        return GoalSpec(
            distance: distance,
            targetTimeSeconds: targetTimeSeconds,
            raceDate: raceDate,
            availableDays: days,
            longRunDay: longRunDay
        )
    }
}
