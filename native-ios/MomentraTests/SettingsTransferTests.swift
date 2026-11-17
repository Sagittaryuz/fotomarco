import XCTest
@testable import Momentra

final class SettingsTransferTests: XCTestCase {
    private func payload(storage: String = "local", gallery: Bool = true, extra: [String: Any] = [:]) throws -> Data {
        let profile: [String: Any] = ["title": "Exemplo", "note": "", "hasLogo": false]
        var settings: [String: Any] = ["profile": "HAMOA", "stamp": true, "gps": false, "map": false,
                                       "aspectRatio": "4:3", "storageMode": storage, "allowGallery": gallery,
                                       "profiles": ["HAMOA": profile, "PIRESCO": profile, "PESSOAL": profile]]
        settings.merge(extra) { _, new in new }
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

    func testValidatesOptionalDisplayPreferencesAndAcceptsOlderExports() throws {
        let old = try SettingsTransfer.decode(payload())
        XCTAssertNil(old.settings.size)
        let selected = try SettingsTransfer.decode(payload(extra: ["size": "compact", "timestampFormat": "long", "timestampFont": "mono", "mapScale": "large"]))
        XCTAssertEqual(selected.settings.size, "compact")
        XCTAssertEqual(selected.settings.timestampFormat, "long")
        XCTAssertEqual(selected.settings.mapScale, "large")
        XCTAssertEqual(selected.settings.timestampFont, "mono")
        XCTAssertThrowsError(try SettingsTransfer.decode(payload(extra: ["size": "invalid"])))
        XCTAssertThrowsError(try SettingsTransfer.decode(payload(extra: ["timestampFormat": "invalid"])))
        XCTAssertThrowsError(try SettingsTransfer.decode(payload(extra: ["mapScale": "invalid"])))
        XCTAssertThrowsError(try SettingsTransfer.decode(payload(extra: ["timestampFont": "invalid"])))
    }
}
