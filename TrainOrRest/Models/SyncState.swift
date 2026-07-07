import Foundation
import SwiftData

/// Per-domain sync bookkeeping: serialized HKQueryAnchor (workouts) and the
/// timestamp of the last successful sync, which drives the freshness indicator.
@Model
final class SyncState {
    @Attribute(.unique) var domain: String
    var anchorData: Data?
    var lastSyncAt: Date?

    init(domain: String, anchorData: Data? = nil, lastSyncAt: Date? = nil) {
        self.domain = domain
        self.anchorData = anchorData
        self.lastSyncAt = lastSyncAt
    }
}

extension SyncState {
    static let workoutsDomain = "workouts"
    static let wellnessDomain = "wellness"
}
