import SwiftUI
import GoogleSignIn
import AVFoundation

enum ReleaseNews {
    static let version = "0.1.65"
    static let items = [
        "A câmera agora reúne seus controles em uma bandeja de opções.",
        "O botão destaca em amarelo quando um ajuste da bandeja está ativo.",
        "O mapa continua acessível pela bandeja da câmera.",
        "Os estilos podem ser personalizados com ajustes de tom, cor e paleta.",
        "A galeria abre nas capturas de hoje e o mapa mostra miniaturas individuais."
    ]

    static func items(for version: String) -> [String] {
        version == Self.version ? items : []
    }
}

/// The welcome is only for new installations. Existing users keep their access.
struct AppWelcomeGate: View {
    @AppStorage("welcomeCompletedV1") private var completed = false
    @AppStorage("lastPresentedVersion") private var lastPresentedVersion = ""
    @AppStorage("onboardingStartedV2") private var onboardingStarted = false
    @State private var page = 0
    @State private var showNews = false
    @State private var signingIn = false
    @State private var message: String?

    var body: some View {
        Group {
            if completed {
                CameraScreen()
                    .sheet(isPresented: $showNews) { news }
            } else if page == 0 {
                OnboardingIntroView { page = 1 }
            } else if page == 1 {
                OnboardingPermissionsView { page = 2 }
            } else if page == 2 {
                accountWelcome
            } else {
                BusinessPlansView(onContinue: { lastPresentedVersion = currentVersion; completed = true })
            }
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--onboarding-preview"), args.indices.contains(index + 1),
               let previewPage = Int(args[index + 1]), (0...3).contains(previewPage) {
                completed = false
                page = previewPage
                return
            }
            #endif
            restoreExistingUser()
        }
    }

    private var accountWelcome: some View {
        BusinessSignInView(submit: { email, password, name, registering in
            let identity = BusinessIdentity.shared
            identity.start()
            if registering { try await identity.register(email: email, password: password, fullName: name) }
            else { try await identity.signIn(email: email, password: password) }
            finishOnboarding()
        }, signInWithProvider: { provider in
            let identity = BusinessIdentity.shared
            identity.start()
            switch provider {
            case .microsoft: try await identity.signInMicrosoft()
            case .google:
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                      var controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { throw BusinessIdentity.IdentityError.notConfigured }
                while let presented = controller.presentedViewController { controller = presented }
                try await identity.signInGoogle(presenting: controller)
            }
            finishOnboarding()
        }, continueWithoutAccount: { finishOnboarding() })
    }

    private func finishOnboarding() {
        lastPresentedVersion = currentVersion
        completed = true
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func restoreExistingUser() {
        let existing = completed || (!onboardingStarted && AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        guard existing else { onboardingStarted = true; return }
        let version = currentVersion
        let updated = !version.isEmpty && lastPresentedVersion != version
        completed = true
        if updated {
            lastPresentedVersion = version
            showNews = !ReleaseNews.items(for: version).isEmpty
        }
    }

    private var news: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 48)).accessibilityHidden(true)
                Text("Novidades do Photomark").font(.title.bold())
                Text("Versão \(currentVersion)").font(.subheadline).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(ReleaseNews.items(for: currentVersion).enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1). ").fontWeight(.semibold)
                                Text(item).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.foregroundStyle(.secondary)
                }
                Button("Continuar") { welcomeTap(); showNews = false }.buttonStyle(.borderedProminent)
            }.padding(30)
        }.presentationDetents([.medium, .large])
    }

    private func welcomeTap() {
        FotomarcoHaptics.play(.buttons)
    }

}

struct GoogleWelcomeButton: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> GIDSignInButton {
        let button = GIDSignInButton()
        button.style = .wide
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: GIDSignInButton, context: Context) { context.coordinator.action = action }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// Uses the Google SDK's own icon-only artwork, avoiding a hand-drawn brand mark.
struct GoogleAccountMark: UIViewRepresentable {
    func makeUIView(context: Context) -> GIDSignInButton {
        let button = GIDSignInButton()
        button.style = .iconOnly
        button.isUserInteractionEnabled = false
        button.accessibilityElementsHidden = true
        return button
    }
    func updateUIView(_ button: GIDSignInButton, context: Context) {}
}
