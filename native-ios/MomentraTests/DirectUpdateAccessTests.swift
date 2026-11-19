import XCTest
@testable import Momentra

@MainActor
final class DirectUpdateAccessTests: XCTestCase {
    func testAcceptsOnlyExpectedActivationLink() {
        let token = String(repeating: "a", count: 64)
        XCTAssertEqual(DirectUpdateAccess.token(from: URL(string: "momentra://updates/activate?token=\(token)")!), token)
        XCTAssertNil(DirectUpdateAccess.token(from: URL(string: "momentra://other/activate?token=\(token)")!))
        XCTAssertNil(DirectUpdateAccess.token(from: URL(string: "https://updates/activate?token=\(token)")!))
        XCTAssertNil(DirectUpdateAccess.token(from: URL(string: "momentra://updates/activate?token=bad")!))
        XCTAssertNil(DirectUpdateAccess.token(from: URL(string: "momentra://updates/activate?token=\(token)&extra=1")!))
    }

    func testAcceptsOnlyScopedManifestOnInstallerHost() {
        let ticket = "1234567890123." + String(repeating: "a", count: 32) + "." + String(repeating: "b", count: 64)
        let valid = "https://momentra-instalacao.vercel.app/api/install?stage=manifest&ticket=" + ticket
        XCTAssertNotNil(DirectUpdateAccess.manifestURL(valid))
        XCTAssertNil(DirectUpdateAccess.manifestURL(valid.replacingOccurrences(of: "momentra-instalacao.vercel.app", with: "example.com")))
        XCTAssertNil(DirectUpdateAccess.manifestURL(valid.replacingOccurrences(of: "https:", with: "http:")))
        XCTAssertNil(DirectUpdateAccess.manifestURL(valid + "&extra=1"))
        XCTAssertNil(DirectUpdateAccess.manifestURL(valid.replacingOccurrences(of: "manifest", with: "package")))
    }

    func testTransitionHostIsRestrictedToOneConfiguredHTTPSOrigin() {
        let host = "momentra-atualizacoes.example.com"
        let ticket = "1234567890123." + String(repeating: "a", count: 32) + "." + String(repeating: "b", count: 64)
        let manifest = "https://\(host)/api/install?stage=manifest&ticket=" + ticket
        XCTAssertEqual(DirectUpdateAccess.configuredInstallerHost(host), host)
        XCTAssertNotNil(DirectUpdateAccess.manifestURL(manifest, expectedHost: host))
        XCTAssertNil(DirectUpdateAccess.manifestURL(manifest))
        XCTAssertNil(DirectUpdateAccess.manifestURL(manifest.replacingOccurrences(of: host, with: host + ".example.org"), expectedHost: host))
        for value in ["", "https://" + host, host + ":443", host + "/ota", "account@" + host] {
            XCTAssertEqual(DirectUpdateAccess.configuredInstallerHost(value), "momentra-instalacao.vercel.app")
        }
    }
}
