import Foundation
import GoogleSignIn
import UIKit

// No sign-in occurs at launch. This component is not yet connected to the UI.
@MainActor
final class NativeGoogleAuth {
    static let scopes = [
        "https://www.googleapis.com/auth/photoslibrary.appendonly",
        "https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata"
    ]

    static var configured: Bool { validConfiguration(Bundle.main.infoDictionary ?? [:]) }

    static func validConfiguration(_ info: [String: Any]) -> Bool {
        guard let id = info["GIDClientID"] as? String, id.hasSuffix(".apps.googleusercontent.com"),
              id.utf8.count <= 255, !id.contains("$"),
              let types = info["CFBundleURLTypes"] as? [[String: Any]] else { return false }
        let reverse = id.split(separator: ".").reversed().joined(separator: ".")
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(reverse) == true }
    }

    private var busy = false

    func connect(presenting: UIViewController, personalConsent: Bool,
                 completion: @escaping (Bool) -> Void) {
        guard personalConsent, Self.configured, !busy else { completion(false); return }
        busy = true
        GIDSignIn.sharedInstance.signIn(withPresenting: presenting, hint: nil, additionalScopes: Self.scopes) { [weak self] result, error in
            Task { @MainActor in
                self?.busy = false
                guard error == nil, let user = result?.user, let owner = user.userID, !owner.isEmpty,
                      let granted = user.grantedScopes, Self.scopes.allSatisfy(granted.contains) else {
                    completion(false); return
                }
                completion(true)
            }
        }
    }

    func freshToken(for owner: String, completion: @escaping (String?) -> Void) {
        guard Self.configured, let user = GIDSignIn.sharedInstance.currentUser,
              user.userID == owner, let granted = user.grantedScopes,
              Self.scopes.allSatisfy(granted.contains) else { completion(nil); return }
        user.refreshTokensIfNeeded { updated, error in
            Task { @MainActor in
                guard error == nil, let updated, updated.userID == owner,
                      GIDSignIn.sharedInstance.currentUser?.userID == owner,
                      let granted = updated.grantedScopes, Self.scopes.allSatisfy(granted.contains) else {
                    completion(nil); return
                }
                completion(updated.accessToken.tokenString)
            }
        }
    }

    func signOut() { GIDSignIn.sharedInstance.signOut() }
}
