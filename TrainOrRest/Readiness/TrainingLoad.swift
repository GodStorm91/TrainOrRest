import Foundation

/// Session training load and acute:chronic workload ratio. Pure functions;
/// caller supplies samples, `today`, and a calendar.
enum TrainingLoad {
    enum Tuning {
        /// Intensity factors by pace zone (pace vs current training paces).
        static let hardFactor = 1.6      // threshold pace or faster
        static let moderateFactor = 1.3  // marathon-pace zone
        static let easyFactor = 1.0      // easy zone
        static let recoveryFactor = 0.8  // slower than easy
        static let acuteWindowDays = 7
        static let chronicWindowDays = 28
    }

    /// Load = duration (minutes) × intensity factor. Intensity comes from
    /// average pace against the runner's current zones; without pace or
    /// zones the session counts as easy.
    static func sessionLoad(
        durationSeconds: Double,
        avgPaceSecondsPerKm: Double?,
        paces: TrainingPaces?
    ) -> Double {
        durationSeconds / 60 * intensityFactor(avgPaceSecondsPerKm: avgPaceSecondsPerKm, paces: paces)
    }

    static func intensityFactor(avgPaceSecondsPerKm: Double?, paces: TrainingPaces?) -> Double {
        guard let pace = avgPaceSecondsPerKm, pace > 0, let paces else { return Tuning.easyFactor }
        if pace <= paces.threshold.slowSecondsPerKm { return Tuning.hardFactor }
        if pace <= paces.marathon.slowSecondsPerKm { return Tuning.moderateFactor }
        if pace <= paces.easy.slowSecondsPerKm { return Tuning.easyFactor }
        return Tuning.recoveryFactor
    }

    /// Acute (7-day mean) over chronic (28-day mean) load. Nil until a full
    /// chronic window of history exists — ACWR on sparse history is noise.
    static func acuteChronicRatio(
        loads: [(date: Date, load: Double)],
        today: Date,
        calendar: Calendar
    ) -> Double? {
        let dayStart = calendar.startOfDay(for: today)
        guard let chronicStart = calendar.date(byAdding: .day, value: -(Tuning.chronicWindowDays - 1), to: dayStart),
              let acuteStart = calendar.date(byAdding: .day, value: -(Tuning.acuteWindowDays - 1), to: dayStart),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return nil }

        // Require history reaching back a full chronic window.
        guard let oldest = loads.map(\.date).min(),
              oldest <= chronicStart else { return nil }

        let chronic = loads
            .filter { $0.date >= chronicStart && $0.date < dayEnd }
            .reduce(0) { $0 + $1.load } / Double(Tuning.chronicWindowDays)
        guard chronic > 0 else { return nil }

        let acute = loads
            .filter { $0.date >= acuteStart && $0.date < dayEnd }
            .reduce(0) { $0 + $1.load } / Double(Tuning.acuteWindowDays)
        return acute / chronic
    }
}
