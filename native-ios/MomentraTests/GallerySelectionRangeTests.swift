import XCTest
@testable import Momentra

final class GallerySelectionRangeTests: XCTestCase {
    func testDragSelectsContiguousRangeInEitherDirection() {
        let items = ["a", "b", "c", "d", "e"]
        XCTAssertEqual(GallerySelectionRange.applying(items, from: 1, through: 3, initial: ["e"], selecting: true), ["b", "c", "d", "e"])
        XCTAssertEqual(GallerySelectionRange.applying(items, from: 3, through: 1, initial: [], selecting: true), ["b", "c", "d"])
    }

    func testReverseDragRestoresOriginalSelectionAndSupportsDeselect() {
        let items = ["a", "b", "c", "d"]
        XCTAssertEqual(GallerySelectionRange.applying(items, from: 0, through: 1, initial: ["d"], selecting: true), ["a", "b", "d"])
        XCTAssertEqual(GallerySelectionRange.applying(items, from: 1, through: 2, initial: ["a", "b", "c", "d"], selecting: false), ["a", "d"])
        XCTAssertEqual(GallerySelectionRange.applying(items, from: -1, through: 2, initial: ["d"], selecting: true), ["d"])
    }
}
