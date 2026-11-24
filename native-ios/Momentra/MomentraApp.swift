import SwiftUI
import GoogleSignIn

@main
struct MomentraApp: App {
    @UIApplicationDelegateAdaptor(MomentraAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            AppWelcomeGate().task {
                BusinessIdentity.shared.start()
                if #available(iOS 18.0, *) { await LockedCaptureImporter.watch() }
            }.onOpenURL { url in
                if BusinessGoogleOAuth.shared.handle(url) {
                    return
                } else if url.scheme == "momentra" {
                    Task { await DirectUpdateAccess.shared.activate(url) }
                } else if NativeGoogleAuth.configured { _ = GIDSignIn.sharedInstance.handle(url) }
            }
        }
    }
}
