import XCTest
@testable import Momentra

final class BusinessAPIClientTests: XCTestCase {
    func testHistoricalMigrationRequiresExplicitOptIn() {
        XCTAssertFalse(BusinessAPIClient.legacyMigrationEnabled(info: [:]))
        XCTAssertFalse(BusinessAPIClient.legacyMigrationEnabled(info: ["PhotomarkLegacyMigrationEnabled": false]))
        XCTAssertFalse(BusinessAPIClient.legacyMigrationEnabled(info: ["PhotomarkLegacyMigrationEnabled": "true"]))
        XCTAssertTrue(BusinessAPIClient.legacyMigrationEnabled(info: ["PhotomarkLegacyMigrationEnabled": true]))
    }
    func testTeamPhotoListingAndThumbnailUseAuthenticatedBusinessEndpoint() async throws {
        let id = UUID().uuidString
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/list") {
                let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (Data("{\"photos\":[{\"captureId\":\"\(id)\",\"authorId\":\"user\",\"filename\":\"photo.jpg\",\"createdAt\":1000,\"byteCount\":10}],\"nextCursor\":\"\"}".utf8), response)
            }
            XCTAssertTrue(url.path.hasSuffix("/thumbnail"))
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"]))
            return (Data([1, 2, 3]), response)
        }
        let page = try await client.listTeamPhotos(organizationID: "org", token: "token")
        XCTAssertEqual(page.photos.first?.id, id)
        let bytes = try await client.teamPhotoData(organizationID: "org", captureID: id, thumbnail: true, token: "token")
        XCTAssertEqual(bytes, Data([1, 2, 3]))
    }
    func testPhotoChunkIsSentOnlyToBusinessAPI() async throws {
        let id = UUID(), bytes = Data([1, 2, 3])
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.url?.host, "business.example")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Upload-Offset"), "0")
            XCTAssertEqual(request.httpBody, bytes)
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(#"{"state":"verifying","nextOffset":3}"#.utf8), response)
        }
        let result = try await client.sendCaptureChunk(organizationID: "org", captureID: id, variant: "stamped", offset: 0, bytes: bytes, token: "token")
        XCTAssertEqual(result.state, "verifying")
    }
    func testCaptureReservationSendsFingerprintAndKeepsOriginalIdentifier() async throws {
        let id = UUID()
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.url?.path, "/v1/organizations/org/captures/reserve")
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(payload["captureId"] as? String, id.uuidString)
            XCTAssertEqual(payload["byteCount"] as? Int, 123)
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data("{\"captureId\":\"\(id.uuidString)\",\"variant\":\"stamped\",\"state\":\"reserved\"}".utf8), response)
        }
        let receipt = try await client.reserveCapture(organizationID: "org", captureID: id, filename: "photo.jpg",
            fingerprint: CloudFileFingerprint(byteCount: 123, sha256: String(repeating: "a", count: 64)), token: "token")
        XCTAssertEqual(receipt.captureId, id.uuidString)
    }
    func testOrganizationDiscoveryUsesAuthenticatedEndpoint() async throws {
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.url?.path, "/v1/organizations/mine")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(#"{"organizations":[{"id":"org","name":"Equipe","role":"member","photoAssetId":""}]}"#.utf8), response)
        }
        let result = try await client.myOrganizations(token: "token")
        XCTAssertEqual(result.organizations.first?.name, "Equipe")
    }
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

    func testOneDriveConnectionReportsOnlyRecognizedServerDiagnostics() async throws {
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 503, httpVersion: nil, headerFields: nil))
            return (Data(#"{"error":"provider-token-unavailable"}"#.utf8), response)
        }
        do {
            _ = try await client.connectOneDrive(organizationID: "org", refreshToken: "credential", token: "token")
            XCTFail("Expected provider diagnostic")
        } catch BusinessAPIClient.Failure.microsoftToken { } catch { XCTFail("Unexpected error") }
    }

    func testOneDriveReportsSafeDatabaseFailure() async throws {
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 503, httpVersion: nil, headerFields: nil))
            return (Data(#"{"error":"business-database-unavailable"}"#.utf8), response)
        }
        do {
            _ = try await client.connectOneDrive(organizationID: "org", refreshToken: "credential", token: "token")
            XCTFail("Expected database diagnostic")
        } catch BusinessAPIClient.Failure.businessDatabase { } catch { XCTFail("Unexpected error") }
    }

    func testGoogleBusinessStorageUsesVerifiedSessionAndSelectedFolder() async throws {
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
            let data: Data
            if request.url?.path.hasSuffix("/connect") == true {
                XCTAssertEqual(payload, ["refreshToken": "credential"])
                data = Data(#"{"connected":true}"#.utf8)
            } else {
                XCTAssertEqual(request.url?.path, "/v1/organizations/org/storage/google-drive/provision-owner")
                XCTAssertEqual(payload, ["imagesId": "selected-folder"])
                data = Data(#"{"ready":true}"#.utf8)
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (data, response)
        }
        let connected = try await client.connectGoogleDrive(organizationID: "org", refreshToken: "credential", token: "token")
        XCTAssertTrue(connected.connected)
        let folder = try await client.provisionGoogleOwnerFolder(organizationID: "org", imagesID: "selected-folder", token: "token")
        XCTAssertTrue(folder.ready)
        do {
            _ = try await client.provisionGoogleOwnerFolder(organizationID: "org", imagesID: "../unsafe", token: "token")
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
