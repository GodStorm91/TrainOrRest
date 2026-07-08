import Foundation

/// Pure aggregates for the Run History overview card, computed from real
/// completed runs. No stored/fabricated metrics — every field is a reduction
/// over the runs passed in.
struct RunHistorySummary: Equatable {
    var runCount: Int
    var totalDistanceMeters: Double
    var totalDurationSeconds: Double
    var longestDistanceMeters: Double?
    /// Distance-weighted average pace (s/km) over runs that have both distance
    /// and duration — weighting by distance avoids short runs skewing the mean.
    var averagePaceSecondsPerKm: Double?

    init(activities: [CompletedActivity]) {
        runCount = activities.count
        totalDistanceMeters = activities.compactMap(\.distanceMeters).reduce(0, +)
        totalDurationSeconds = activities.map(\.durationSeconds).reduce(0, +)
        longestDistanceMeters = activities.compactMap(\.distanceMeters).max()

        // Sum distance and time only over runs that have distance, so pace is
        // total-time-over-total-distance for those runs.
        let paced = activities.filter { ($0.distanceMeters ?? 0) > 0 }
        let meters = paced.compactMap(\.distanceMeters).reduce(0, +)
        let seconds = paced.map(\.durationSeconds).reduce(0, +)
        averagePaceSecondsPerKm = meters > 0 ? seconds / (meters / 1000) : nil
    }
}
