import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
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

    func register(email: String, password: String) async throws {
        let result = try await auth().createUser(withEmail: email, password: password)
        update(result.user)
        try await result.user.sendEmailVerification()
    }

    func signInMicrosoft() async throws {
        let provider = OAuthProvider(providerID: "microsoft.com")
        let credential = try await provider.credential(with: nil)
        let result = try await auth().signIn(with: credential)
        update(result.user)
    }

    /// Reuse an existing Google session so enabling Business does not replace
    /// the Google account already used for cloud storage.
    func signInGoogle(presenting controller: UIViewController) async throws {
        guard NativeGoogleAuth.configured else { throw IdentityError.notConfigured }
        let google = GIDSignIn.sharedInstance
        let account: GIDGoogleUser
        if let current = google.currentUser {
            account = current
        } else if google.hasPreviousSignIn() {
            account = try await withCheckedThrowingContinuation { continuation in
                google.restorePreviousSignIn { user, error in
                    if let user { continuation.resume(returning: user) }
                    else { continuation.resume(throwing: error ?? IdentityError.signedOut) }
                }
            }
        } else {
            account = try await withCheckedThrowingContinuation { continuation in
                google.signIn(withPresenting: controller) { result, error in
                    if let user = result?.user { continuation.resume(returning: user) }
                    else { continuation.resume(throwing: error ?? IdentityError.signedOut) }
                }
            }
        }
        guard let googleID = account.idToken?.tokenString else { throw IdentityError.signedOut }
        let credential = GoogleAuthProvider.credential(withIDToken: googleID, accessToken: account.accessToken.tokenString)
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

    func sendVerification() async throws {
        guard let user = try auth().currentUser else { throw IdentityError.signedOut }
        try await user.sendEmailVerification()
    }

    func signOut() throws {
        try auth().signOut()
        update(nil)
    }
}
