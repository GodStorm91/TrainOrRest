import Foundation

/// Consecutive-day training streak from completed activities. Pure and
/// deterministic. Rest today doesn't break the streak — it stays alive as long
/// as there was a run yesterday (today is still "in progress"); it only breaks
/// once a full day passes with no run.
enum TrainingStreak {
    /// `activityDates` may contain duplicates and any time-of-day.
    static func current(activityDates: [Date], today: Date, calendar: Calendar) -> Int {
        let days = Set(activityDates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let todayStart = calendar.startOfDay(for: today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        // Anchor on the most recent day that actually has a run. If neither
        // today nor yesterday has one, the streak is broken.
        var cursor: Date
        if days.contains(todayStart) {
            cursor = todayStart
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }
}
