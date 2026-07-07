import Foundation
import SwiftData

/// A workout's diff-relevant fields, frozen for comparison.
struct SnapshotDay: Codable, Equatable {
    var date: Date
    var kindRaw: String
    var distanceKm: Double
    var paceFastSecondsPerKm: Double?
    var paceSlowSecondsPerKm: Double?
}

/// Yesterday's effective plan, captured once per day before the first
/// regeneration, so the diff view can explain what changed overnight.
@Model
final class PlanSnapshot {
    @Attribute(.unique) var key: String
    var capturedOn: Date
    var days: [SnapshotDay]

    init(capturedOn: Date, days: [SnapshotDay]) {
        self.key = PlanSnapshot.previousKey
        self.capturedOn = capturedOn
        self.days = days
    }

    static let previousKey = "previous"
}
