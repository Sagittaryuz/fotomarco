import SwiftUI
import GoogleSignIn

@main
struct MomentraApp: App {
    var body: some Scene {
        WindowGroup {
            AppWelcomeGate().task {
                if #available(iOS 18.0, *) { await LockedCaptureImporter.watch() }
            }.onOpenURL { url in
                if url.scheme == "momentra" {
                    Task { await DirectUpdateAccess.shared.activate(url) }
                } else if NativeGoogleAuth.configured { _ = GIDSignIn.sharedInstance.handle(url) }
            }
        }
    }
}
