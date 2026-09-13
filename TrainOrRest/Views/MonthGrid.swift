import Foundation

/// Pure month-grid layout: leading/trailing blanks plus the day dates of a
/// calendar month, ordered to the calendar's first weekday. No view or app
/// state, so it can be unit-tested directly.
enum MonthGrid {
    /// Day cells for the month containing `anchor`, padded to whole weeks.
    /// `nil` entries are the blanks before the 1st and after the last day.
    static func cells(for anchor: Date, calendar: Calendar) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: anchor),
              let dayRange = calendar.range(of: .day, in: .month, for: anchor) else {
            return []
        }
        let firstOfMonth = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in dayRange {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }


    static func weekdays(_ calendar: Calendar) -> [Weekday] {
        (0..<7).compactMap { offset in
            Weekday(rawValue: (calendar.firstWeekday - 1 + offset) % 7 + 1)
        }
    }
    /// Very-short weekday symbols ordered to the calendar's first weekday
    /// (e.g. ["S","M","T","W","T","F","S"] for a Sunday-start Gregorian calendar).
    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Planned vs completed kilometers for the days actually shown in a week
    /// row. Blank leading/trailing cells are not in `days`, so a partial first
    /// or last week of the month only counts what the grid displays.
    struct WeekVolume: Equatable {
        var plannedKm: Double
        var completedKm: Double

        var plannedDisplay: Int { Int(plannedKm.rounded()) }
        var completedDisplay: Int { Int(completedKm.rounded()) }
        var hasWork: Bool { plannedKm > 0 || completedKm > 0 }

        var displayLabel: String {
            if plannedKm > 0 && completedKm > 0 {
                "\(completedDisplay)/\(plannedDisplay)"
            } else if completedKm > 0 {
                "\(completedDisplay)"
            } else {
                "\(plannedDisplay)"
            }
        }

        /// Fill toward this week's plan, capped at 1. Over-distance stays in
        /// the numbers; the bar does not grow past the track.
        var progress: Double {
            guard plannedKm > 0 else { return completedKm > 0 ? 1 : 0 }
            return min(1, completedKm / plannedKm)
        }
    }

    static func weekVolume(
        days: [Date],
        plannedKmByDay: [Date: Double],
        completedKmByDay: [Date: Double]
    ) -> WeekVolume {
        WeekVolume(
            plannedKm: days.reduce(0) { $0 + (plannedKmByDay[$1] ?? 0) },
            completedKm: days.reduce(0) { $0 + (completedKmByDay[$1] ?? 0) }
        )
    }
}
