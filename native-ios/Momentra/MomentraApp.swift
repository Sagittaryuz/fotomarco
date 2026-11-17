import SwiftUI
import GoogleSignIn

@main
struct MomentraApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen().onOpenURL { url in
                if NativeGoogleAuth.configured { _ = GIDSignIn.sharedInstance.handle(url) }
            }
        }
    }
}
