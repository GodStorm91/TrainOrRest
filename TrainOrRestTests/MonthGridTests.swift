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

    func testWeekVolumeSumsOnlyVisibleDays() {
        let sunday = date(2026, 9, 6)
        let monday = date(2026, 9, 7)
        let nextSunday = date(2026, 9, 13)
        let volume = MonthGrid.weekVolume(
            days: [sunday, monday],
            plannedKmByDay: [sunday: 14, monday: 8, nextSunday: 99],
            completedKmByDay: [sunday: 12.4]
        )
        XCTAssertEqual(volume.plannedKm, 22)
        XCTAssertEqual(volume.completedKm, 12.4)
        XCTAssertEqual(volume.plannedDisplay, 22)
        XCTAssertEqual(volume.completedDisplay, 12)
        XCTAssertTrue(volume.hasWork)
        XCTAssertEqual(volume.displayLabel, "12/22")
    }

    func testWeekVolumeProgressIsTowardThisWeeksPlan() {
        let day = date(2026, 9, 6)
        let half = MonthGrid.weekVolume(
            days: [day],
            plannedKmByDay: [day: 40],
            completedKmByDay: [day: 10]
        )
        XCTAssertEqual(half.progress, 0.25, accuracy: 0.0001)

        let over = MonthGrid.weekVolume(
            days: [day],
            plannedKmByDay: [day: 10],
            completedKmByDay: [day: 15]
        )
        XCTAssertEqual(over.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(over.completedDisplay, 15)
        XCTAssertEqual(over.plannedDisplay, 10)
        XCTAssertEqual(over.displayLabel, "15/10")
    }

    func testWeekVolumeFutureWeekHasNoProgress() {
        let day = date(2026, 9, 20)
        let volume = MonthGrid.weekVolume(
            days: [day],
            plannedKmByDay: [day: 37],
            completedKmByDay: [:]
        )
        XCTAssertEqual(volume.progress, 0)
        XCTAssertEqual(volume.plannedDisplay, 37)
        XCTAssertEqual(volume.completedDisplay, 0)
        XCTAssertEqual(volume.displayLabel, "37")
        XCTAssertTrue(volume.hasWork)
    }

    func testWeekVolumeUnplannedCompletedRunStillCounts() {
        let day = date(2026, 9, 6)
        let volume = MonthGrid.weekVolume(
            days: [day],
            plannedKmByDay: [:],
            completedKmByDay: [day: 8]
        )
        XCTAssertEqual(volume.plannedKm, 0)
        XCTAssertEqual(volume.completedDisplay, 8)
        XCTAssertEqual(volume.progress, 1)
        XCTAssertTrue(volume.hasWork)
        XCTAssertEqual(volume.displayLabel, "8")
    }

    func testWeekVolumeEmptyRowHasNoWork() {
        let volume = MonthGrid.weekVolume(
            days: [date(2026, 9, 1)],
            plannedKmByDay: [:],
            completedKmByDay: [:]
        )
        XCTAssertFalse(volume.hasWork)
        XCTAssertEqual(volume.progress, 0)
    }
}
