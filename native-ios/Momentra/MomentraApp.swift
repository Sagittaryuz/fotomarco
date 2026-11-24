import SwiftUI
import GoogleSignIn

@main
struct MomentraApp: App {
    @UIApplicationDelegateAdaptor(MomentraAppDelegate.self) private var appDelegate
    @StateObject private var invitations = BusinessInvitationRouter.shared
    var body: some Scene {
        WindowGroup {
            AppWelcomeGate().task {
                BusinessIdentity.shared.start()
                if #available(iOS 18.0, *) { await LockedCaptureImporter.watch() }
            }.sheet(item: $invitations.pending) { BusinessInvitationView(invitation: $0) }
            .onOpenURL { url in
                if BusinessGoogleOAuth.shared.handle(url) {
                    return
                } else if invitations.handle(url) {
                    return
                } else if url.scheme == "momentra" {
                    Task { await DirectUpdateAccess.shared.activate(url) }
                } else if NativeGoogleAuth.configured { _ = GIDSignIn.sharedInstance.handle(url) }
            }
        }
    }
}
