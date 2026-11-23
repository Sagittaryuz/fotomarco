import XCTest
@testable import Momentra

final class BusinessAPIClientTests: XCTestCase {
    func testInvitationUsesFirebaseTokenAndEncodedPayload() async throws {
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://business.example/v1/organizations/org-1/invitations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer signed.token")
            let body = try XCTUnwrap(request.httpBody)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(payload, ["email": "member@example.com"])
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 201, httpVersion: nil, headerFields: nil))
            return (Data(#"{"id":"invitation-1","expiresAt":1800000000000}"#.utf8), response)
        }
        let receipt = try await client.invite(organizationID: "org-1", email: "member@example.com", token: "signed.token")
        XCTAssertEqual(receipt.id, "invitation-1")
    }

    func testRejectsInsecureEndpointAndUnsafeIdentifier() async throws {
        XCTAssertThrowsError(try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "http://example.com"))))
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://example.com"))) { _ in
            XCTFail("Invalid identifiers must not send requests")
            throw BusinessAPIClient.Failure.invalidRequest
        }
        do {
            _ = try await client.invite(organizationID: "../foreign", email: "member@example.com", token: "token")
            XCTFail("Expected invalid request")
        } catch BusinessAPIClient.Failure.invalidRequest { } catch { XCTFail("Unexpected error") }
    }
}
