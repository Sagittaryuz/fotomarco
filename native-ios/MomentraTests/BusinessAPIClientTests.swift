import XCTest
@testable import Momentra

final class BusinessAPIClientTests: XCTestCase {
    func testMemberListDecodesOnlyServerResponse() async throws {
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.url?.path, "/v1/organizations/org/members/list")
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(#"{"members":[{"userId":"member","role":"member","email":"member@example.com"}]}"#.utf8), response)
        }
        let result = try await client.listMembers(organizationID: "org", token: "token")
        XCTAssertEqual(result.members.first?.email, "member@example.com")
    }
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

    func testAssetUploadPreservesImageAndRejectsOversizedInput() async throws {
        let image = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.url?.path, "/v1/organizations/org/assets/upload")
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
            XCTAssertEqual(payload["base64"], image.base64EncodedString())
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 201, httpVersion: nil, headerFields: nil))
            return (Data(#"{"assetId":"logo-1"}"#.utf8), response)
        }
        let receipt = try await client.uploadAsset(organizationID: "org", mimeType: "image/png", imageData: image, token: "token")
        XCTAssertEqual(receipt.assetId, "logo-1")
        do {
            _ = try await client.uploadAsset(organizationID: "org", mimeType: "image/png", imageData: Data(count: 262145), token: "token")
            XCTFail("Expected invalid request")
        } catch BusinessAPIClient.Failure.invalidRequest { } catch { XCTFail("Unexpected error") }
    }

    func testOrganizationSettingsAreSentWithoutChangingAccountCredentials() async throws {
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.url?.path, "/v1/organizations/org/settings/update")
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
            XCTAssertEqual(payload, ["name": "Equipe", "contactEmail": "team@example.com", "photoAssetId": "logo-1"])
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(#"{"id":"org","name":"Equipe","contactEmail":"team@example.com","photoAssetId":"logo-1"}"#.utf8), response)
        }
        let settings = try await client.updateOrganization(organizationID: "org", name: "Equipe", contactEmail: "team@example.com", photoAssetID: "logo-1", token: "token")
        XCTAssertEqual(settings.photoAssetId, "logo-1")
    }
}
