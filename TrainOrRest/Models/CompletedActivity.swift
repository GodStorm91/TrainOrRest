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
    /// Per-kilometer splits reconstructed from HealthKit, JSON-encoded so the
    /// store can lightweight-migrate. `nil` means not computed yet and the
    /// sync backfill should try again; an empty array means it was computed
    /// and the samples were too coarse to split, so it should not retry.
    var splitsData: Data?

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
        self.splitsData = nil
    }
}
