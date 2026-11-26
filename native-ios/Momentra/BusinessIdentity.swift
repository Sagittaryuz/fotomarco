import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import UIKit
import CryptoKit

private final class MicrosoftPhotoRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Rejects a token if its capture owner changes while the async operation runs.
@MainActor enum BusinessTokenBinding {
    static func acquire(expectedUserID: String, currentUserID: () -> String?,
                        operation: () async throws -> String) async throws -> String {
        guard currentUserID() == expectedUserID else { throw BusinessIdentity.IdentityError.signedOut }
        let token = try await operation()
        guard currentUserID() == expectedUserID else { throw BusinessIdentity.IdentityError.signedOut }
        return token
    }
}

/// Business identity is independent of the user's Google Drive and OneDrive sessions.
@MainActor
final class BusinessIdentity: ObservableObject {
    enum IdentityError: Error {
        case notConfigured, signedOut, unverifiedEmail
    }

    static let shared = BusinessIdentity()
    @Published private(set) var userID: String?
    @Published private(set) var email: String?
    @Published private(set) var displayName: String?
    @Published private(set) var photoURL: URL?
    @Published private(set) var profilePhoto: UIImage?
    @Published private(set) var emailVerified = false
    private var listener: AuthStateDidChangeListenerHandle?

    private init() {}

    /// Do not initialize FirebaseAuth if the build has no bundled configuration.
    func start() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        guard listener == nil else { return }
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self, let service = try? self.auth(), service.currentUser?.uid == user?.uid else { return }
                self.update(user)
            }
        }
    }

    private func update(_ user: User?) {
        userID = user?.uid
        email = user?.email
        displayName = user?.displayName ?? user?.providerData.compactMap(\.displayName).first
        let providerPhoto = user?.providerData.compactMap(\.photoURL).first { $0.scheme?.lowercased() == "https" }
        photoURL = user?.photoURL?.scheme?.lowercased() == "https" ? user?.photoURL : providerPhoto
        profilePhoto = user.flatMap { Self.cachedMicrosoftPhoto(userID: $0.uid) }
        emailVerified = user?.isEmailVerified ?? false
    }

    private func auth() throws -> Auth {
        guard FirebaseApp.app() != nil else { throw IdentityError.notConfigured }
        return Auth.auth()
    }

    func signIn(email: String, password: String) async throws {
        let service = try auth()
        let result = try await service.signIn(withEmail: email, password: password)
        guard service.currentUser?.uid == result.user.uid else { throw IdentityError.signedOut }
        update(result.user)
    }

    func register(email: String, password: String, fullName: String) async throws {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 160, name.rangeOfCharacter(from: .controlCharacters) == nil else { throw IdentityError.notConfigured }
        let service = try auth()
        let result = try await service.createUser(withEmail: email, password: password)
        let changes = result.user.createProfileChangeRequest()
        changes.displayName = name
        try await changes.commitChanges()
        guard service.currentUser?.uid == result.user.uid else { throw IdentityError.signedOut }
        update(result.user)
        try await result.user.sendEmailVerification()
    }

    func signInMicrosoft() async throws {
        let provider = OAuthProvider(providerID: "microsoft.com")
        provider.scopes = ["User.Read"]
        let credential = try await provider.credential(with: nil)
        let service = try auth()
        let result = try await service.signIn(with: credential)
        guard service.currentUser?.uid == result.user.uid else { throw IdentityError.signedOut }
        update(result.user)
        if let token = (result.credential as? OAuthCredential)?.accessToken {
            let uid = result.user.uid
            Task { await self.loadMicrosoftPhoto(accessToken: token, userID: uid) }
        }
    }

    private static func photoCacheURL(userID: String) -> URL? {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let key = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("business-profile-\(key).jpg")
    }

    private static func cachedMicrosoftPhoto(userID: String) -> UIImage? {
        guard let url = photoCacheURL(userID: userID), let data = try? Data(contentsOf: url), data.count <= 2_000_000 else { return nil }
        return UIImage(data: data)
    }

    private func loadMicrosoftPhoto(accessToken: String, userID: String) async {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/photo/$value")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let session = URLSession(configuration: .ephemeral, delegate: MicrosoftPhotoRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000,
              let photo = UIImage(data: data), self.userID == userID else { return }
        profilePhoto = photo
        if let url = Self.photoCacheURL(userID: userID) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Sign in separately without replacing the Google Drive session.
    func signInGoogle(presenting controller: UIViewController) async throws {
        let tokens = try await BusinessGoogleOAuth.shared.authorize(presenting: controller)
        let credential = GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken)
        let service = try auth()
        let result = try await service.signIn(with: credential)
        guard service.currentUser?.uid == result.user.uid else { throw IdentityError.signedOut }
        update(result.user)
    }

    func verifiedToken(expectedUserID: String? = nil) async throws -> String {
        let service = try auth()
        guard let user = service.currentUser,
              expectedUserID == nil || user.uid == expectedUserID else { throw IdentityError.signedOut }
        let uid = user.uid
        try await user.reload()
        guard service.currentUser?.uid == uid else { throw IdentityError.signedOut }
        update(user)
        guard user.isEmailVerified else { throw IdentityError.unverifiedEmail }
        return try await BusinessTokenBinding.acquire(expectedUserID: uid, currentUserID: { service.currentUser?.uid }) {
            try await user.getIDToken(forcingRefresh: true)
        }
    }

    /// Reuses Firebase's cached token for repeated image requests; the server
    /// still checks the signature and current organization membership each time.
    func cachedVerifiedToken() async throws -> String {
        let service = try auth()
        guard let user = service.currentUser else { throw IdentityError.signedOut }
        guard user.isEmailVerified else { throw IdentityError.unverifiedEmail }
        return try await BusinessTokenBinding.acquire(expectedUserID: user.uid, currentUserID: { service.currentUser?.uid }) {
            try await user.getIDToken(forcingRefresh: false)
        }
    }

    func requireCurrentUser(_ expectedUserID: String) throws {
        guard try auth().currentUser?.uid == expectedUserID else { throw IdentityError.signedOut }
    }

    func sendPasswordReset(email: String) async throws {
        try await auth().sendPasswordReset(withEmail: email)
    }

    func sendVerification() async throws {
        guard let user = try auth().currentUser else { throw IdentityError.signedOut }
        try await user.sendEmailVerification()
    }

    func signOut() throws {
        try auth().signOut()
        update(nil)
    }
}
