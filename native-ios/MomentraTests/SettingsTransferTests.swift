import XCTest
@testable import Momentra

final class SettingsTransferTests: XCTestCase {
    private func payload(storage: String = "local", gallery: Bool = true) throws -> Data {
        let profile: [String: Any] = ["title": "Exemplo", "note": "", "hasLogo": false]
        let settings: [String: Any] = ["profile": "HAMOA", "stamp": true, "gps": false, "map": false,
                                       "aspectRatio": "4:3", "storageMode": storage, "allowGallery": gallery,
                                       "profiles": ["HAMOA": profile, "PIRESCO": profile, "PESSOAL": profile]]
        return try JSONSerialization.data(withJSONObject: ["format": "momentra-settings", "version": 1, "settings": settings])
    }

    func testAcceptsValidTransfer() throws {
        let transfer = try SettingsTransfer.decode(payload())
        XCTAssertEqual(transfer.settings.profiles["HAMOA"]?.title, "Exemplo")
        XCTAssertFalse(transfer.settings.gps)
    }

    func testRejectsUnsupportedStorageAndInvalidFiles() throws {
        XCTAssertThrowsError(try SettingsTransfer.decode(payload(storage: "cloud")))
        XCTAssertThrowsError(try SettingsTransfer.decode(Data(repeating: 0, count: 65_537)))
        XCTAssertThrowsError(try SettingsTransfer.decode(Data("{}".utf8)))
    }

    func testPreservesLocalStorageWithoutGalleryCopy() throws {
        let transfer = try SettingsTransfer.decode(payload(gallery: false))
        XCTAssertEqual(transfer.settings.storageMode, "local")
        XCTAssertFalse(transfer.settings.allowGallery)
    }
}
