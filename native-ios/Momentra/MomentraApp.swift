import SwiftUI
import GoogleSignIn

@main
struct MomentraApp: App {
    var body: some Scene {
        WindowGroup {
            AppWelcomeGate().onOpenURL { url in
                if NativeGoogleAuth.configured { _ = GIDSignIn.sharedInstance.handle(url) }
            }
        }
    }
}
