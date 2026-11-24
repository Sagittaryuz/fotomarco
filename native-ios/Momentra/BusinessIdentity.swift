import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import UIKit

/// Business identity is independent of the user's Google Drive and OneDrive sessions.
@MainActor
final class BusinessIdentity: ObservableObject {
    enum IdentityError: Error {
        case notConfigured, signedOut, unverifiedEmail
    }

    static let shared = BusinessIdentity()
    @Published private(set) var userID: String?
    @Published private(set) var email: String?
    @Published private(set) var emailVerified = false
    private var listener: AuthStateDidChangeListenerHandle?

    private init() {}

    /// Do not initialize FirebaseAuth if the build has no bundled configuration.
    func start() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        guard listener == nil else { return }
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.update(user) }
        }
    }

    private func update(_ user: User?) {
        userID = user?.uid
        email = user?.email
        emailVerified = user?.isEmailVerified ?? false
    }

    private func auth() throws -> Auth {
        guard FirebaseApp.app() != nil else { throw IdentityError.notConfigured }
        return Auth.auth()
    }

    func signIn(email: String, password: String) async throws {
        let result = try await auth().signIn(withEmail: email, password: password)
        update(result.user)
    }

    func register(email: String, password: String, fullName: String) async throws {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 160, name.rangeOfCharacter(from: .controlCharacters) == nil else { throw IdentityError.notConfigured }
        let result = try await auth().createUser(withEmail: email, password: password)
        let changes = result.user.createProfileChangeRequest()
        changes.displayName = name
        try await changes.commitChanges()
        update(result.user)
        try await result.user.sendEmailVerification()
    }

    func signInMicrosoft() async throws {
        let provider = OAuthProvider(providerID: "microsoft.com")
        let credential = try await provider.credential(with: nil)
        let result = try await auth().signIn(with: credential)
        update(result.user)
    }

    /// Sign in separately without replacing the Google Drive session.
    func signInGoogle(presenting controller: UIViewController) async throws {
        let tokens = try await BusinessGoogleOAuth.shared.authorize(presenting: controller)
        let credential = GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken)
        let result = try await auth().signIn(with: credential)
        update(result.user)
    }

    func verifiedToken() async throws -> String {
        guard let user = try auth().currentUser else { throw IdentityError.signedOut }
        try await user.reload()
        update(user)
        guard user.isEmailVerified else { throw IdentityError.unverifiedEmail }
        return try await user.getIDToken(forcingRefresh: true)
    }

    /// Reuses Firebase's cached token for repeated image requests; the server
    /// still checks the signature and current organization membership each time.
    func cachedVerifiedToken() async throws -> String {
        guard let user = try auth().currentUser else { throw IdentityError.signedOut }
        guard user.isEmailVerified else { throw IdentityError.unverifiedEmail }
        return try await user.getIDToken(forcingRefresh: false)
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
