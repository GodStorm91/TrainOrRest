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
    var shoeID: UUID?
    var shoeAssignmentSourceRaw: String?
    var externalProviderShoeID: String?
    /// User's subjective post-run note. Optional so existing SwiftData stores
    /// can lightweight-migrate after this field is added.
    var reviewNote: String?
    /// Once set, Today stops auto-presenting the post-run review sheet for
    /// this activity. The detail screen can still show the review anytime.
    var postRunReviewDismissedAt: Date?

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
        self.shoeID = nil
        self.shoeAssignmentSourceRaw = ShoeAssignmentSource.none.rawValue
        self.externalProviderShoeID = nil
        self.reviewNote = nil
        self.postRunReviewDismissedAt = nil
    }
}
