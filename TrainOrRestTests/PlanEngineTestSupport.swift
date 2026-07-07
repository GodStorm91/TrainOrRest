import Foundation
@testable import TrainOrRest

/// Shared fixtures for engine tests: fixed calendar, date builder, seeded RNG.
enum PlanEngineTestSupport {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 8) -> Date {
        DateComponents(
            calendar: calendar, year: year, month: month, day: day, hour: hour
        ).date!
    }

    /// Regular training history: `runsPerWeek` runs/week for `weeks` weeks
    /// ending at `today`, each `distanceKm` at `paceSecondsPerKm`.
    static func history(
        weeks: Int,
        runsPerWeek: Int,
        distanceKm: Double,
        paceSecondsPerKm: Double,
        endingAt today: Date
    ) -> [RunSample] {
        var samples: [RunSample] = []
        for week in 0..<weeks {
            for run in 0..<runsPerWeek {
                let daysBack = week * 7 + run * (7 / max(runsPerWeek, 1)) + 1
                let date = calendar.date(byAdding: .day, value: -daysBack, to: today)!
                samples.append(RunSample(
                    date: date,
                    distanceKm: distanceKm,
                    durationSeconds: distanceKm * paceSecondsPerKm
                ))
            }
        }
        return samples
    }
}

/// Deterministic RNG for property tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
