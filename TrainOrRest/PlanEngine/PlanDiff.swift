import Foundation

/// Day-by-day comparison of two plan states over the upcoming window,
/// explaining what changed and why. Pure.
enum PlanDiff {
    static let windowDays = 14

    /// One workout's diff-relevant fields.
    struct Entry: Equatable {
        var date: Date
        var kind: WorkoutKind
        var distanceKm: Double
        var paceBand: PaceBand?
    }

    enum Reason: Equatable {
        case readiness(ReadinessVerdict)
        case volumeRefit
    }

    struct DayChange: Equatable {
        var date: Date
        var before: Entry?
        var after: Entry?
        var reason: Reason
    }

    /// Changed days in [today, today+window). `todayVerdict` attributes
    /// today's change to readiness; everything else is a volume re-fit from
    /// completed training.
    static func changes(
        previous: [Entry],
        current: [Entry],
        today: Date,
        todayVerdict: ReadinessVerdict,
        calendar: Calendar
    ) -> [DayChange] {
        let windowStart = calendar.startOfDay(for: today)
        guard let windowEnd = calendar.date(byAdding: .day, value: windowDays, to: windowStart) else { return [] }

        func byDay(_ entries: [Entry]) -> [Date: Entry] {
            Dictionary(
                entries
                    .filter { $0.date >= windowStart && $0.date < windowEnd }
                    .map { (calendar.startOfDay(for: $0.date), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        let before = byDay(previous)
        let after = byDay(current)

        return Set(before.keys).union(after.keys).sorted().compactMap { day in
            let old = before[day]
            let new = after[day]
            guard !isSameWorkout(old, new) else { return nil }
            let isToday = day == windowStart
            let readinessDriven = isToday && (todayVerdict == .goEasy || todayVerdict == .rest)
            return DayChange(
                date: day,
                before: old,
                after: new,
                reason: readinessDriven ? .readiness(todayVerdict) : .volumeRefit
            )
        }
    }

    private static func isSameWorkout(_ a: Entry?, _ b: Entry?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (a?, b?):
            return a.kind == b.kind
                && abs(a.distanceKm - b.distanceKm) < 0.05
                && isSamePace(a.paceBand, b.paceBand)
        default:
            return false
        }
    }

    private static func isSamePace(_ a: PaceBand?, _ b: PaceBand?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (a?, b?):
            return abs(a.fastSecondsPerKm - b.fastSecondsPerKm) < 1
                && abs(a.slowSecondsPerKm - b.slowSecondsPerKm) < 1
        default:
            return false
        }
    }
}
