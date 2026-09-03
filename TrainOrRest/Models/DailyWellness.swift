import Foundation
import SwiftData

/// One row per calendar day of wellness metrics read from HealthKit.
/// Recomputed wholesale over a rolling window on each sync, so a nil field
/// means HealthKit had no data for that day.
@Model
final class DailyWellness {
    /// Start of day in the current calendar.
    @Attribute(.unique) var date: Date
    /// Heart-rate variability (SDNN) in milliseconds; overnight/first value of the day.
    var hrvSDNN: Double?
    var hrvPrimarySource: String?
    var hrvAltValue: Double?
    var hrvAltSource: String?
    var hrvDisputed: Bool = false
    /// Resting heart rate in beats per minute.
    var restingHeartRate: Double?
    /// Total asleep hours attributed to this date: the night ending on this
    /// morning plus any same-day naps.
    var sleepHours: Double?
    /// VO2max in ml/kg/min.
    var vo2Max: Double?
    /// Sleep-stage hours for the night ending on this date (nil when the
    /// source provided no staged sleep).
    var deepSleepHours: Double?
    var remSleepHours: Double?
    var lightSleepHours: Double?

    init(
        date: Date,
        hrvSDNN: Double? = nil,
        hrvPrimarySource: String? = nil,
        hrvAltValue: Double? = nil,
        hrvAltSource: String? = nil,
        hrvDisputed: Bool = false,
        restingHeartRate: Double? = nil,
        sleepHours: Double? = nil,
        vo2Max: Double? = nil,
        deepSleepHours: Double? = nil,
        remSleepHours: Double? = nil,
        lightSleepHours: Double? = nil
    ) {
        self.date = date
        self.hrvSDNN = hrvSDNN
        self.hrvPrimarySource = hrvPrimarySource
        self.hrvAltValue = hrvAltValue
        self.hrvAltSource = hrvAltSource
        self.hrvDisputed = hrvDisputed
        self.restingHeartRate = restingHeartRate
        self.sleepHours = sleepHours
        self.vo2Max = vo2Max
        self.deepSleepHours = deepSleepHours
        self.remSleepHours = remSleepHours
        self.lightSleepHours = lightSleepHours
    }
}
