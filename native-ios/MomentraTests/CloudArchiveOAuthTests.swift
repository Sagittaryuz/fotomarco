import XCTest
@testable import Momentra

final class CloudArchiveOAuthTests: XCTestCase {
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
