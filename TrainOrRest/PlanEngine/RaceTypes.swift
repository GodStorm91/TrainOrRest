import Foundation

// Pure value types for the race season. No SwiftData, no I/O. Same inputs
// always produce identical output.

enum RacePriority: String, Codable, CaseIterable, Identifiable, Comparable {
    case a = "A", b = "B", c = "C"

    var id: String { rawValue }

    static func < (lhs: RacePriority, rhs: RacePriority) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int {
        switch self {
        case .a: 0
        case .b: 1
        case .c: 2
        }
    }
}

enum RaceStatus: String, Codable, CaseIterable {
    case upcoming, completed, skipped
}

struct RaceResultSpec: Equatable, Codable {
    var finishTimeSeconds: Double
    var averageHeartRate: Double?
    var healthKitWorkoutID: UUID?

    init(
        finishTimeSeconds: Double,
        averageHeartRate: Double? = nil,
        healthKitWorkoutID: UUID? = nil
    ) {
        self.finishTimeSeconds = finishTimeSeconds
        self.averageHeartRate = averageHeartRate
        self.healthKitWorkoutID = healthKitWorkoutID
    }
}

/// One race in the season, as the engine sees it.
///
/// Distance is stored in meters rather than as a `RaceDistance` case so a
/// custom distance needs no new enum case. `standardDistance` recovers the
/// matching case when the meters land on a standard race.
struct RaceSpec: Equatable, Codable, Identifiable {
    var id: UUID
    var name: String
    /// Race day at day precision. The engine normalizes to start of day.
    var date: Date
    var distanceMeters: Double
    var targetTimeSeconds: Double?
    var priority: RacePriority
    var notes: String?
    var status: RaceStatus
    var result: RaceResultSpec?

    init(
        id: UUID = UUID(),
        name: String,
        date: Date,
        distanceMeters: Double,
        targetTimeSeconds: Double? = nil,
        priority: RacePriority,
        notes: String? = nil,
        status: RaceStatus = .upcoming,
        result: RaceResultSpec? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.distanceMeters = distanceMeters
        self.targetTimeSeconds = targetTimeSeconds
        self.priority = priority
        self.notes = notes
        self.status = status
        self.result = result
    }

    var kilometers: Double { distanceMeters / 1000 }

    /// The standard race this distance matches, within 50 meters.
    var standardDistance: RaceDistance? {
        RaceDistance.allCases.first { abs($0.meters - distanceMeters) <= 50 }
    }

    var goalPaceSecondsPerKm: Double? {
        guard let targetTimeSeconds, kilometers > 0 else { return nil }
        return targetTimeSeconds / kilometers
    }
}

extension RaceDistance {
    /// The standard race whose length matches these meters, within 50 meters.
    static func matching(meters: Double) -> RaceDistance? {
        allCases.first { abs($0.meters - meters) <= 50 }
    }
}

/// How many days the engine protects around a race, by distance.
///
/// The A-race taper lengths equal the whole-week tapers `PlanGenerator`
/// already applies: one week for 5K and 10K, two for a half, three for a
/// marathon. See `PlanGenerator.taperWeeks` in PlanGenerator.swift.
enum RaceTaperTable {
    static func taperDays(meters: Double) -> Int {
        switch RaceDistance.matching(meters: meters) {
        case .marathon: 21
        case .halfMarathon: 14
        case .tenK: 7
        case .fiveK: 7
        case nil: meters >= 30_000 ? 21 : (meters >= 15_000 ? 14 : 7)
        }
    }

    /// Days of reduced volume before a B race.
    static let miniTaperDays = 3

    /// Share of planned volume kept during a B-race mini-taper.
    static let miniTaperVolumeFactor = 0.65

    static func recoveryDays(meters: Double, priority: RacePriority) -> Int {
        switch priority {
        case .c:
            return 2
        case .a, .b:
            switch RaceDistance.matching(meters: meters) {
            case .marathon: return 12
            case .halfMarathon: return 4
            case .tenK: return 3
            case .fiveK: return 2
            case nil: return meters >= 30_000 ? 12 : (meters >= 15_000 ? 4 : 2)
            }
        }
    }
}

/// A conflict the engine reports. The engine never fixes a conflict silently.
struct RaceWarning: Equatable, Identifiable {
    enum Code: String, Codable {
        /// A B or C race falls inside the A race taper window.
        case insideARaceTaper
        /// A half or longer race falls too soon after a marathon.
        case tooSoonAfterMarathon
        /// Two races fall seven days apart or less.
        case racesTooClose
        /// A race falls inside the recovery window of an earlier race.
        case insideRecoveryWindow
    }

    var code: Code
    /// The race the warning is about.
    var raceID: UUID
    /// The race that causes the conflict, when a second race is involved.
    var otherRaceID: UUID?
    /// Days between the two races, when a second race is involved.
    var dayGap: Int?

    var id: String {
        "\(code.rawValue)-\(raceID.uuidString)-\(otherRaceID?.uuidString ?? "")"
    }
}

/// The priority the engine suggests for a race the athlete is adding.
struct RacePrioritySuggestion: Equatable {
    enum Reason: String, Codable {
        /// No upcoming A race exists, so this race anchors the plan.
        case noARaceYet
        /// Far enough from the A race to race hard.
        case farFromARace
        /// Inside the A race taper window.
        case insideARaceTaper
        /// Close to the A race but outside its taper.
        case closeToARace
        /// Inside the recovery window of an earlier race.
        case insideRecoveryWindow
    }

    var priority: RacePriority
    var reason: Reason
    /// Whole weeks to the A race, when the reason references it.
    var weeksToARace: Int?
}

/// One day the scheduler changes, with the workout before and after.
struct RaceDayChange: Equatable, Identifiable {
    enum Intent: String, Codable {
        /// A full taper day before the A race.
        case taper
        /// A reduced-volume day before a B race.
        case miniTaper
        /// The race itself.
        case raceDay
        /// A rest or easy day after a race.
        case recovery
        /// A C race replaces the week's quality or long session.
        case replacesQuality
    }

    var date: Date
    var intent: Intent
    var raceID: UUID
    /// What the plan holds today. Nil when the day is empty.
    var beforeSummary: String?
    /// What the scheduler puts there.
    var afterSummary: String
    /// Planned kilometers after the change. Zero means a rest day.
    var afterKilometers: Double

    var id: String { "\(intent.rawValue)-\(date.timeIntervalSince1970)" }
}

/// Everything the scheduler produces for one evaluation.
struct RaceScheduleChange: Equatable {
    var dayChanges: [RaceDayChange]
    var warnings: [RaceWarning]

    static let empty = RaceScheduleChange(dayChanges: [], warnings: [])

    var isEmpty: Bool { dayChanges.isEmpty && warnings.isEmpty }
}

/// The season as a sorted view over the stored races. No separate model.
struct RaceSeason: Equatable {
    var races: [RaceSpec]

    init(races: [RaceSpec]) {
        self.races = races
    }

    /// Upcoming races, earliest first.
    var upcoming: [RaceSpec] {
        races.filter { $0.status == .upcoming }.sorted { $0.date < $1.date }
    }

    var aRace: RaceSpec? {
        upcoming.first { $0.priority == .a }
    }

    /// The completed race with the latest date.
    var lastCompleted: RaceSpec? {
        races.filter { $0.status == .completed }.max { $0.date < $1.date }
    }
}
