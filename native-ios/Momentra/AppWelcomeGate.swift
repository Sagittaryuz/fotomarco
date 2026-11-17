import SwiftUI
import GoogleSignIn
import AVFoundation

/// The welcome is only for new installations. Existing users keep their access.
struct AppWelcomeGate: View {
    @AppStorage("welcomeCompletedV1") private var completed = false
    @AppStorage("lastPresentedVersion") private var lastPresentedVersion = ""
    @State private var page = 0
    @State private var showNews = false
    @State private var signingIn = false
    @State private var message: String?

    var body: some View {
        Group {
            if completed {
                CameraScreen()
                    .sheet(isPresented: $showNews) { news }
            } else {
                welcome
            }
        }
        .onAppear { restoreExistingUser() }
    }

    private var welcome: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 35)
                    Image(systemName: icon)
                        .font(.system(size: 62, weight: .light))
                        .foregroundStyle(.white)
                        .frame(height: 100)
                        .accessibilityHidden(true)
                    Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text(description).font(.body).foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if page == 0 {
                        GoogleWelcomeButton(action: signIn)
                            .frame(height: 48).disabled(signingIn)
                        if signingIn { ProgressView().tint(.white) }
                        if !NativeGoogleAuth.configured {
                            Text("O login do Google ainda não está configurado nesta versão.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                        }
                        Button("Continuar por enquanto") { page = 1 }
                            .foregroundStyle(.white.opacity(0.8))
                    } else {
                        Button {
                            if page == 3 { lastPresentedVersion = currentVersion; completed = true } else { page += 1 }
                        } label: {
                            Text(page == 3 ? "Começar a usar" : "Continuar")
                                .font(.headline).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(.white, in: Capsule()).contentShape(Capsule())
                        }.buttonStyle(.plain)
                        Button("Voltar") { page -= 1 }.foregroundStyle(.white.opacity(0.8))
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<4) { index in
                            Circle().fill(index == page ? Color.white : Color.white.opacity(0.25))
                                .frame(width: 7, height: 7)
                        }
                    }.accessibilityLabel("Página \(page + 1) de 4")
                    Spacer(minLength: 30)
                }.padding(.horizontal, 28).frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func restoreExistingUser() {
        let existing = completed || AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        guard existing else { return }
        let version = currentVersion
        let updated = !version.isEmpty && lastPresentedVersion != version
        completed = true
        if updated { lastPresentedVersion = version; showNews = true }
    }

    private var news: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "sparkles").font(.system(size: 48)).accessibilityHidden(true)
                Text("Novidades do Momentra").font(.title.bold())
                Text("Esta versão melhora a abertura da câmera e a instalação das atualizações.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Continuar") { showNews = false }.buttonStyle(.borderedProminent)
            }.padding(30)
        }.presentationDetents([.medium, .large])
    }

    private var icon: String { ["person.crop.circle", "camera.aperture", "location.viewfinder", "photo.on.rectangle.angled"][page] }
    private var title: String { ["Bem-vindo ao Momentra", "Registre seus momentos", "Localização no carimbo", "Suas fotos, do seu jeito"][page] }
    private var description: String {
        ["Entre com sua conta Google para começar. A conexão com o Google Fotos é uma escolha separada e não envia fotos automaticamente.",
         "Use a câmera para fotografar e gravar. O iPhone pedirá acesso à câmera; o microfone será solicitado ao gravar vídeos.",
         "Ao ativar o GPS, permita a localização para incluir os dados disponíveis no carimbo. Você pode alterar essa escolha nos ajustes.",
         "O acesso ao Fotos permite escolher e salvar imagens. Você decide quais permissões conceder e pode alterá-las nos Ajustes do iPhone."][page]
    }

    private func signIn() {
        guard NativeGoogleAuth.configured else {
            message = "O login Google ainda precisa ser configurado para este aplicativo."; return
        }
        guard !signingIn,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            message = "Não foi possível abrir o login. Tente novamente."; return
        }
        while let presented = controller.presentedViewController { controller = presented }
        signingIn = true
        GIDSignIn.sharedInstance.signIn(withPresenting: controller) { result, error in
            Task { @MainActor in
                signingIn = false
                if error == nil, result?.user.userID != nil { page = 1 }
                else { message = "Não foi possível entrar com o Google. Você pode tentar novamente." }
            }
        }
    }
}

private struct GoogleWelcomeButton: UIViewRepresentable {
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
