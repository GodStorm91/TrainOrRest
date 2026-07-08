import Foundation

// Value types for the plan engine. This module is pure Swift: no HealthKit,
// no SwiftData, no I/O — same inputs always produce identical output.

/// Day of week using Calendar's weekday numbering (1 = Sunday … 7 = Saturday).
enum Weekday: Int, Codable, CaseIterable, Comparable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

enum RaceDistance: String, Codable, CaseIterable, Identifiable {
    case fiveK, tenK, halfMarathon, marathon

    var id: String { rawValue }

    var meters: Double {
        switch self {
        case .fiveK: 5000
        case .tenK: 10000
        case .halfMarathon: 21097.5
        case .marathon: 42195
        }
    }

    var kilometers: Double { meters / 1000 }

    var displayName: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half Marathon"
        case .marathon: "Marathon"
        }
    }
}

/// A race goal as entered by the user.
struct GoalSpec: Equatable, Codable {
    var distance: RaceDistance
    var targetTimeSeconds: Double
    /// Race day (day precision; engine normalizes to start of day).
    var raceDate: Date
    /// Weekdays the user can run (3–7 days).
    var availableDays: Set<Weekday>
    /// Preferred long-run day; must be a member of `availableDays`.
    var longRunDay: Weekday

    var goalPaceSecondsPerKm: Double { targetTimeSeconds / distance.kilometers }
}

/// A completed run reduced to what fitness estimation needs.
struct RunSample: Equatable {
    var date: Date
    var distanceKm: Double
    var durationSeconds: Double
}

/// Current fitness derived from recent training history.
struct FitnessProfile: Equatable {
    /// Daniels VDOT estimated from the best recent training effort.
    var vdot: Double
    /// Average weekly volume over the last 4 weeks, km.
    var weeklyVolumeKm: Double
    /// Last-4-weeks volume vs. the 4 weeks before, as a fraction (+0.1 = +10%).
    var volumeTrend: Double
    var longestRecentRunKm: Double
}

/// A pace band in seconds per km; `fast` is the lower (quicker) bound.
struct PaceBand: Equatable, Codable {
    var fastSecondsPerKm: Double
    var slowSecondsPerKm: Double
}

/// Training paces derived from VDOT (Daniels zones used by the templates).
struct TrainingPaces: Equatable {
    var easy: PaceBand
    var marathon: PaceBand
    var threshold: PaceBand
    var interval: PaceBand
}

enum WorkoutKind: String, Codable, CaseIterable {
    case easy, long, tempo, intervals, race

    /// Hard sessions that need a recovery day between them.
    var isQuality: Bool {
        switch self {
        case .easy: false
        case .long, .tempo, .intervals, .race: true
        }
    }
}

enum TrainingPhase: String, Codable, CaseIterable {
    case base, build, peak, taper

    var displayName: String { rawValue.capitalized }
}

struct PlannedWorkoutSpec: Equatable {
    var date: Date
    var kind: WorkoutKind
    var distanceKm: Double
    var paceBand: PaceBand?
    var details: String
    var structure: [WorkoutStepGroup] = []
}

struct WeekPlan: Equatable {
    /// Start of the week (Monday), start-of-day.
    var startDate: Date
    var index: Int
    var phase: TrainingPhase
    var isDownWeek: Bool
    /// First week is partial when the plan starts mid-week; exempt from ramp checks.
    var isPartial: Bool
    /// Training volume for the week, km. Excludes the race itself.
    var targetVolumeKm: Double
    var workouts: [PlannedWorkoutSpec]
}

struct TrainingPlanSpec: Equatable {
    var goal: GoalSpec
    /// The `today` the plan was generated for (start of day).
    var anchorDate: Date
    var weeks: [WeekPlan]
}

enum FeasibilityVerdict: String, Codable {
    case ok, stretch, unrealistic
}
