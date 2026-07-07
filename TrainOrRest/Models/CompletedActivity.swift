import Foundation
import SwiftData

/// A completed running workout imported from HealthKit (written by Garmin Connect).
@Model
final class CompletedActivity {
    /// HealthKit workout UUID; uniqueness prevents duplicate imports across syncs.
    @Attribute(.unique) var hkUUID: UUID
    var date: Date
    var distanceMeters: Double?
    var durationSeconds: Double
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var avgPaceSecondsPerKm: Double?
    var sourceName: String

    init(
        hkUUID: UUID,
        date: Date,
        distanceMeters: Double?,
        durationSeconds: Double,
        avgHeartRate: Double?,
        maxHeartRate: Double?,
        avgPaceSecondsPerKm: Double?,
        sourceName: String
    ) {
        self.hkUUID = hkUUID
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.avgPaceSecondsPerKm = avgPaceSecondsPerKm
        self.sourceName = sourceName
    }
}
