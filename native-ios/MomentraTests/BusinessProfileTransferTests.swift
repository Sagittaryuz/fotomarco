import XCTest
@testable import Momentra

@MainActor
final class BusinessProfileTransferTests: XCTestCase {
    func testProfileWithoutLogoRoundTripsWithoutChangingPersonalProfile() async throws {
        let personal = StampProfile(name: "Equipe", note: "Nota")
        let profileData = try JSONEncoder().encode(personal)
        let profileJSON = try XCTUnwrap(String(data: profileData, encoding: .utf8))
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            let status = request.url?.path.hasSuffix("/publish") == true ? 201 : 200
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil))
            let data: Data
            if status == 201 {
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
                let sentJSON = try XCTUnwrap(payload["layoutJSON"])
                XCTAssertEqual(try JSONDecoder().decode(StampProfile.self, from: Data(sentJSON.utf8)), personal)
                data = Data(#"{"versionId":"version-1"}"#.utf8)
            } else {
                data = try JSONSerialization.data(withJSONObject: ["organizationId": "org", "versionId": "version-1", "layoutJSON": profileJSON])
            }
            return (data, response)
        }
        let transfer = BusinessProfileTransfer(api: client)
        let version = try await transfer.publish(personal, organizationID: "org", token: "token")
        XCTAssertEqual(version, "version-1")
        let received = try await transfer.fetch(organizationID: "org", token: "token")
        XCTAssertEqual(received, personal)
        XCTAssertTrue(personal.logoName.isEmpty)
    }
}
