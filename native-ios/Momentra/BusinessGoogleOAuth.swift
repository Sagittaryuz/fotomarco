import Foundation
import UIKit
import AppAuth
import FirebaseCore

/// An independent OAuth authorization, so the Google storage SDK session is untouched.
@MainActor
final class BusinessGoogleOAuth {
    static let shared = BusinessGoogleOAuth()
    private var currentFlow: OIDExternalUserAgentSession?

    func handle(_ url: URL) -> Bool {
        guard let flow = currentFlow else { return false }
        return (try? flow.resumeExternalUserAgentFlow(url)) == true
    }

    func authorize(presenting controller: UIViewController) async throws -> (idToken: String, accessToken: String) {
        guard currentFlow == nil, let clientID = FirebaseApp.app()?.options.clientID,
              let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: plistPath),
              let scheme = plist["REVERSED_CLIENT_ID"] as? String,
              scheme == clientID.split(separator: ".").reversed().joined(separator: "."),
              let redirect = URL(string: "\(scheme):/oauth2redirect"),
              let authorization = URL(string: "https://accounts.google.com/o/oauth2/v2/auth"),
              let token = URL(string: "https://oauth2.googleapis.com/token") else {
            throw BusinessIdentity.IdentityError.notConfigured
        }
        let configuration = OIDServiceConfiguration(authorizationEndpoint: authorization, tokenEndpoint: token)
        let request = OIDAuthorizationRequest(configuration: configuration, clientId: clientID, clientSecret: nil,
            scopes: [OIDScopeOpenID, OIDScopeProfile, OIDScopeEmail], redirectURL: redirect,
            responseType: OIDResponseTypeCode, additionalParameters: nil)
        return try await withCheckedThrowingContinuation { continuation in
            currentFlow = OIDAuthState.authState(byPresenting: request, presenting: controller) { [weak self] state, error in
                Task { @MainActor in
                    self?.currentFlow = nil
                    if let response = state?.lastTokenResponse,
                       let idToken = response.idToken, let accessToken = response.accessToken {
                        continuation.resume(returning: (idToken, accessToken))
                    } else {
                        continuation.resume(throwing: error ?? BusinessIdentity.IdentityError.signedOut)
                    }
                }
            }
        }
    }
}
