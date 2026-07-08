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

    /// Very-short weekday symbols ordered to the calendar's first weekday
    /// (e.g. ["S","M","T","W","T","F","S"] for a Sunday-start Gregorian calendar).
    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
