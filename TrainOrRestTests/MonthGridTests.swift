import XCTest
@testable import TrainOrRest

final class MonthGridTests: XCTestCase {
    // Sunday-start Gregorian calendar in a fixed zone for deterministic layout.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testJuly2026HasThreeLeadingBlanks() {
        // July 1, 2026 is a Wednesday (weekday 4); Sunday-start grid → 3 blanks.
        let cells = MonthGrid.cells(for: date(2026, 7, 15), calendar: calendar)
        let leading = cells.prefix { $0 == nil }.count
        XCTAssertEqual(leading, 3)
    }

    func testCellCountIsWholeWeeks() {
        let cells = MonthGrid.cells(for: date(2026, 7, 15), calendar: calendar)
        XCTAssertEqual(cells.count % 7, 0)
    }

    func testAllMonthDaysPresentInOrder() {
        let cells = MonthGrid.cells(for: date(2026, 7, 15), calendar: calendar)
        let days = cells.compactMap { $0 }.map { calendar.component(.day, from: $0) }
        XCTAssertEqual(days, Array(1...31))
    }

    func testFirstRealCellIsFirstOfMonth() {
        let cells = MonthGrid.cells(for: date(2026, 7, 15), calendar: calendar)
        let firstDay = cells.compactMap { $0 }.first!
        XCTAssertTrue(calendar.isDate(firstDay, inSameDayAs: date(2026, 7, 1)))
    }

    func testWeekdaySymbolsStartOnSunday() {
        let symbols = MonthGrid.weekdaySymbols(calendar)
        XCTAssertEqual(symbols.count, 7)
        // Gregorian very-short standalone symbols start at index 0 = Sunday.
        XCTAssertEqual(symbols.first, calendar.veryShortStandaloneWeekdaySymbols.first)
    }

    func testFebruary2026Layout() {
        // Feb 1, 2026 is a Sunday → no leading blanks; 28 days.
        let cells = MonthGrid.cells(for: date(2026, 2, 10), calendar: calendar)
        XCTAssertNotNil(cells.first ?? nil)
        XCTAssertEqual(cells.compactMap { $0 }.count, 28)
    }
}
