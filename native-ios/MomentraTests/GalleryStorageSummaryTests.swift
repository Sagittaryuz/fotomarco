import XCTest
@testable import Momentra

final class GalleryStorageSummaryTests: XCTestCase {
    func testSegmentsUseKnownTotalAndNeverOverfill() throws {
        let totals = try XCTUnwrap(StorageTotals(total: 100, used: 70, primary: 20))
        XCTAssertEqual(totals.other, 50)
        XCTAssertEqual(totals.primaryFraction, 0.2, accuracy: 0.001)
        XCTAssertEqual(totals.otherFraction, 0.5, accuracy: 0.001)
    }

    func testInconsistentOrMissingQuotaDoesNotProduceAFakeBar() {
        XCTAssertNil(StorageTotals(total: 0, used: 0, primary: 0))
        XCTAssertNil(StorageTotals(total: 100, used: 110, primary: 1))
        XCTAssertNil(StorageTotals(total: 100, used: 30, primary: 40))
    }
}
