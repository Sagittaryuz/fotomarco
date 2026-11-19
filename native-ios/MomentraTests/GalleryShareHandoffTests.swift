import UIKit
import XCTest
@testable import Momentra

final class GalleryShareHandoffTests: XCTestCase {
    private let whatsapp = UIActivity.ActivityType(rawValue: "net.whatsapp.WhatsApp.ShareExtension")

    func testCompletedWhatsAppShareOpensTheAppWithoutComposingAgain() {
        let url = GalleryShareHandoff.destination(for: whatsapp, completed: true, error: nil)
        XCTAssertEqual(url?.absoluteString, "whatsapp://app")
    }

    func testCancelledAndFailedSharesDoNotOpenAnApp() {
        XCTAssertNil(GalleryShareHandoff.destination(for: whatsapp, completed: false, error: nil))
        let error = NSError(domain: "GalleryShareHandoffTests", code: 1)
        XCTAssertNil(GalleryShareHandoff.destination(for: whatsapp, completed: true, error: error))
    }

    func testSystemActionsAndUnknownActivitiesKeepMomentraOpen() {
        XCTAssertNil(GalleryShareHandoff.destination(for: .copyToPasteboard, completed: true, error: nil))
        XCTAssertNil(GalleryShareHandoff.destination(for: .airDrop, completed: true, error: nil))
        XCTAssertNil(GalleryShareHandoff.destination(for: nil, completed: true, error: nil))
        let unknown = UIActivity.ActivityType(rawValue: "example.ShareExtension")
        XCTAssertNil(GalleryShareHandoff.destination(for: unknown, completed: true, error: nil))
    }
}
