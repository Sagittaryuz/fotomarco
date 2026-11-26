import XCTest
@testable import Momentra

final class GalleryDateFilterTests: XCTestCase {
    func testCalendarUsesBrazilianPortugueseWithoutChangingTimeZone() throws {
        var source = Calendar(identifier: .gregorian)
        source.locale = Locale(identifier: "en_US")
        source.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        let calendar = GalleryDateSelection.brazilianCalendar(basedOn: source)
        XCTAssertEqual(calendar.locale?.identifier, "pt_BR")
        XCTAssertEqual(calendar.timeZone.identifier, source.timeZone.identifier)
        XCTAssertEqual(calendar.weekdaySymbols.first?.lowercased(), "domingo")
        XCTAssertTrue(calendar.weekdaySymbols.contains { $0.lowercased().contains("segunda") })
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12)))
        var format = Date.FormatStyle().weekday(.wide).locale(GalleryDateSelection.brazilianLocale)
        format.timeZone = calendar.timeZone
        let formatted = day.formatted(format)
        XCTAssertEqual(formatted.lowercased(), "sexta-feira")
    }

    func testOneDayTwoDaysAndStartingANewRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        let a = DateComponents(year: 2026, month: 11, day: 20)
        let b = DateComponents(year: 2026, month: 11, day: 22)
        let c = DateComponents(year: 2026, month: 11, day: 25)
        let one = try XCTUnwrap(GalleryDateSelection.filter(from: [a], calendar: calendar))
        XCTAssertTrue(calendar.isDate(one.start, inSameDayAs: one.end))
        let interval = try XCTUnwrap(GalleryDateSelection.filter(from: [b, a], calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: interval.start), 20)
        XCTAssertEqual(calendar.component(.day, from: interval.end), 22)
        XCTAssertEqual(GalleryDateSelection.limited([a, b, c], previous: [a, b]), [c])
        XCTAssertNil(GalleryDateSelection.filter(from: [], calendar: calendar))
    }
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
