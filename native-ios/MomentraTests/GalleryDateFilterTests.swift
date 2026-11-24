import XCTest
@testable import Momentra

final class GalleryDateFilterTests: XCTestCase {
    func testInclusiveDaysAndMissingDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        let filter = GalleryDateFilter(start: date(20, 12), end: date(22, 1))
        XCTAssertFalse(filter.includes(date(19, 23), calendar: calendar))
        XCTAssertTrue(filter.includes(date(20, 0), calendar: calendar))
        XCTAssertTrue(filter.includes(date(22, 23), calendar: calendar))
        XCTAssertFalse(filter.includes(date(23, 0), calendar: calendar))
        XCTAssertFalse(filter.includes(nil, calendar: calendar))
    }
}
