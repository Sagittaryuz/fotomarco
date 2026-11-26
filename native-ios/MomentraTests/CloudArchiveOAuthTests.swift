import XCTest
import CryptoKit
@testable import Momentra

private final class StorageIdentityURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let body: String
        if url.host == "graph.microsoft.com", url.path == "/oidc/userinfo" { body = #"{"sub":"subject"}"# }
        else if url.host == "graph.microsoft.com", url.path == "/v1.0/me/drive/special/approot" {
            body = #"{"id":"folder","parentReference":{"driveId":"drive-A"}}"#
        } else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CloudArchiveOAuthTests: XCTestCase {
    @MainActor
    func testPersonalStorageIdentityRequiresMatchingOriginalAccount() async throws {
        let info: [String: Any] = ["MomentraMicrosoftClientID": "4befebdc-2a06-49a0-b14a-13de07c6ac08",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["msauth.br.com.momentra.camera"]]]]
        let provider = try CloudArchiveOAuth.Configuration(provider: .oneDrive, info: info)
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [StorageIdentityURLProtocol.self]
        let oauth = CloudArchiveOAuth(network: URLSession(configuration: settings))
        let hash = SHA256.hash(data: Data("7:subjectdrive-A".utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: hash))
        let result = try await oauth.storageFingerprint(accessToken: "test-token", destination: destination, userID: "user-A", configuration: provider)
        XCTAssertEqual(result, "dec8d46104fcfc5f754c8e94a8afcc5e7d029f413995c47e924270686f8a0234")
        let other = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: String(repeating: "a", count: 64)))
        do {
            _ = try await oauth.storageFingerprint(accessToken: "test-token", destination: other, userID: "user-A", configuration: provider)
            XCTFail("A different account must be rejected")
        } catch CloudArchiveOAuth.Failure.wrongAccount { }
    }
    @MainActor
    func testMicrosoftMailRequestsSendPermissionWithoutStorageAccess() throws {
        let info: [String: Any] = ["MomentraMicrosoftClientID": "4befebdc-2a06-49a0-b14a-13de07c6ac08",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["msauth.br.com.momentra.camera"]]]]
        let configuration = try CloudArchiveOAuth.Configuration(provider: .oneDrive, info: info, forBusiness: true, microsoftMail: true)
        XCTAssertEqual(configuration.requiredScope, "Mail.Send")
        XCTAssertTrue(configuration.scopes.contains("User.Read"))
        XCTAssertFalse(configuration.scopes.contains("Files.ReadWrite"))
        XCTAssertFalse(configuration.businessStorage)
    }
    @MainActor
    func testGoogleUsesExistingAppCallbackAndLeastPrivilegeScope() throws {
        let configuration = try CloudArchiveOAuth.Configuration(provider: .googleDrive, info: [
            "GIDClientID": "123-abc.apps.googleusercontent.com",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["com.googleusercontent.apps.123-abc"]]]
        ])
        XCTAssertEqual(configuration.callback.absoluteString, "com.googleusercontent.apps.123-abc:/oauth2callback")
        XCTAssertTrue(configuration.includesStorageScope("openid https://www.googleapis.com/auth/drive.file"))
        XCTAssertFalse(configuration.includesStorageScope("https://www.googleapis.com/auth/drive"))
    }

    @MainActor
    func testOrganizationMailUsesSendOnlyScopeWithoutChangingDriveScope() throws {
        let info: [String: Any] = ["GIDClientID": "123-abc.apps.googleusercontent.com",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["com.googleusercontent.apps.123-abc"]]]]
        let personal = try CloudArchiveOAuth.Configuration(provider: .googleDrive, info: info)
        let mail = try CloudArchiveOAuth.Configuration(provider: .googleDrive, info: info, forBusiness: true)
        let businessDrive = try CloudArchiveOAuth.Configuration(provider: .googleDrive, info: info, forBusiness: true, googleBusinessStorage: true)
        XCTAssertTrue(personal.includesStorageScope("https://www.googleapis.com/auth/drive.file"))
        XCTAssertFalse(personal.includesStorageScope("https://www.googleapis.com/auth/gmail.send"))
        XCTAssertTrue(mail.includesStorageScope("https://www.googleapis.com/auth/gmail.send"))
        XCTAssertFalse(mail.includesStorageScope("https://www.googleapis.com/auth/drive.file"))
        XCTAssertTrue(businessDrive.includesStorageScope("https://www.googleapis.com/auth/drive.file"))
        XCTAssertFalse(businessDrive.includesStorageScope("https://www.googleapis.com/auth/gmail.send"))
        XCTAssertThrowsError(try CloudArchiveOAuth.Configuration(provider: .googleDrive, info: info, googleBusinessStorage: true))
    }

    @MainActor
    func testMicrosoftRequiresRegisteredCallbackAndUsesAppFolder() throws {
        let clientID = "4befebdc-2a06-49a0-b14a-13de07c6ac08"
        XCTAssertThrowsError(try CloudArchiveOAuth.Configuration(provider: .oneDrive, info: [
            "MomentraMicrosoftClientID": clientID
        ]))
        let configuration = try CloudArchiveOAuth.Configuration(provider: .oneDrive, info: [
            "MomentraMicrosoftClientID": clientID,
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["msauth.br.com.momentra.camera"]]]
        ])
        XCTAssertEqual(configuration.callback.absoluteString, "msauth.br.com.momentra.camera://auth")
        XCTAssertEqual(configuration.authorizeURL.path, "/common/oauth2/v2.0/authorize")
        XCTAssertEqual(configuration.tokenURL.path, "/common/oauth2/v2.0/token")
        XCTAssertTrue(configuration.includesStorageScope("https://graph.microsoft.com/Files.ReadWrite.AppFolder"))
        XCTAssertFalse(configuration.includesStorageScope("Files.ReadWrite"))
    }

    @MainActor
    func testBusinessOneDriveRequestsBroaderScopeOnlyWhenExplicitlySelected() throws {
        let info: [String: Any] = [
            "MomentraMicrosoftClientID": "4befebdc-2a06-49a0-b14a-13de07c6ac08",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["msauth.br.com.momentra.camera"]]]
        ]
        let personal = try CloudArchiveOAuth.Configuration(provider: .oneDrive, info: info)
        let business = try CloudArchiveOAuth.Configuration(provider: .oneDrive, info: info, forBusiness: true)
        XCTAssertEqual(personal.requiredScope, "Files.ReadWrite.AppFolder")
        XCTAssertEqual(business.requiredScope, "Files.ReadWrite")
        XCTAssertFalse(personal.businessStorage)
        XCTAssertTrue(business.businessStorage)
        XCTAssertTrue(business.includesStorageScope("https://graph.microsoft.com/Files.ReadWrite"))
        XCTAssertFalse(business.includesStorageScope("Files.ReadWrite.AppFolder"))
    }

    @MainActor
    func testBusinessMemberIdentityDoesNotRequestFileAccess() throws {
        let info: [String: Any] = ["MomentraMicrosoftClientID": "4befebdc-2a06-49a0-b14a-13de07c6ac08",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["msauth.br.com.momentra.camera"]]]]
        let member = try CloudArchiveOAuth.Configuration(provider: .oneDrive, info: info, identityOnly: true)
        XCTAssertEqual(member.requiredScope, "User.Read")
        XCTAssertTrue(member.includesStorageScope("https://graph.microsoft.com/User.Read"))
        XCTAssertFalse(member.scopes.contains("Files.ReadWrite"))
        XCTAssertThrowsError(try CloudArchiveOAuth.Configuration(provider: .googleDrive, info: info, identityOnly: true))
    }

    @MainActor
    func testMicrosoftAppFolderCanResolveWithoutParentReference() throws {
        let folder = try JSONDecoder().decode(CloudArchiveOAuth.OneDriveFolder.self,
            from: Data(#"{"id":"app-folder-id","specialFolder":{"name":"approot"}}"#.utf8))
        XCTAssertEqual(folder.bindings(for: "subject"), ["folder:7:subjectapp-folder-id"])
    }

    @MainActor
    func testMicrosoftKeepsExistingDriveBindingWhenParentReferenceIsPresent() throws {
        let folder = try JSONDecoder().decode(CloudArchiveOAuth.OneDriveFolder.self,
            from: Data(#"{"id":"app-folder-id","parentReference":{"driveId":"drive-id"}}"#.utf8))
        XCTAssertEqual(folder.bindings(for: "subject"), ["7:subjectdrive-id", "folder:7:subjectapp-folder-id"])
        XCTAssertNotEqual(folder.bindings(for: "other"), folder.bindings(for: "subject"))
    }

    @MainActor
    func testMicrosoftCallbackAcceptsTheRootSlashReturnedByConsumerSignIn() throws {
        let redirect = "msauth.br.com.momentra.camera://auth"
        let expected = try XCTUnwrap(URL(string: redirect))
        func code(_ url: String) throws -> String {
            try CloudArchiveOAuth.authorizationCode(from: XCTUnwrap(URL(string: url)), expected: expected, state: "valid")
        }
        XCTAssertEqual(try code(redirect + "?code=example&state=valid"), "example")
        XCTAssertEqual(try code(redirect + "/?code=example&state=valid"), "example")
        XCTAssertThrowsError(try code(redirect + "/other?code=example&state=valid"))
        XCTAssertThrowsError(try code(redirect + "/?code=example&state=wrong"))
        XCTAssertThrowsError(try code("msauth.br.com.momentra.camera://another/?code=example&state=valid"))
        XCTAssertThrowsError(try code(redirect + "/?code=example&code=another&state=valid"))
    }

    @MainActor
    func testCallbackRejectsWrongPathStateAndRepeatedAuthorizationCode() throws {
        let scheme = "com.googleusercontent.apps.123-abc"
        let callback = URL(string: scheme + ":/oauth2callback")!
        func code(_ suffix: String) throws -> String {
            try CloudArchiveOAuth.authorizationCode(from: URL(string: scheme + suffix)!,
                                                     expected: callback, state: "valid")
        }
        XCTAssertEqual(try code(":/oauth2callback?code=example&state=valid"), "example")
        XCTAssertThrowsError(try code(":/wrong?code=example&state=valid"))
        XCTAssertThrowsError(try code(":/oauth2callback?code=example&state=wrong"))
        XCTAssertThrowsError(try code(":/oauth2callback?code=first&code=second&state=valid"))
        XCTAssertThrowsError(try code(":/oauth2callback?code=first&state=valid&state=valid"))
    }
}
