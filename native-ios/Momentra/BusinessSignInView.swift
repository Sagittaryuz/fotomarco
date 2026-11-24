import SwiftUI

/// Authentication is injected so this screen never accesses storage-account credentials.
struct BusinessSignInView: View {
    enum Provider { case google, microsoft }
    let submit: (String, String, String, Bool) async throws -> Void
    let signInWithProvider: (Provider) async throws -> Void
    let continueWithoutAccount: () -> Void

    @State private var email = ""
    @State private var fullName = ""
    @State private var password = ""
    @State private var registering = false
    @State private var busy = false
    @State private var message: String?
    @State private var showPlans = false
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Image("IconPreviewOriginal").resizable().scaledToFit()
                        .frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 25))
                        .accessibilityHidden(true)
                    MomentraWordmark().scaleEffect(1.3).padding(.bottom, 8)
                    Text(registering ? "Criar conta" : "Entrar")
                        .font(.title2.bold()).foregroundStyle(.white)
                    VStack(spacing: 12) {
                        if registering {
                            TextField("Nome e sobrenome", text: $fullName)
                                .textContentType(.name).textInputAutocapitalization(.words)
                                .padding(16).background(.white.opacity(0.12), in: Capsule())
                        }
                        TextField("E-mail", text: $email)
                            .keyboardType(.emailAddress).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: .email).submitLabel(.next)
                            .onSubmit { focus = .password }
                            .padding(16).background(.white.opacity(0.12), in: Capsule())
                        SecureField("Senha", text: $password)
                            .textContentType(registering ? .newPassword : .password)
                            .focused($focus, equals: .password).submitLabel(.go)
                            .onSubmit { performEmail() }
                            .padding(16).background(.white.opacity(0.12), in: Capsule())
                    }.foregroundStyle(.white)
                    Button(registering ? "Cadastrar" : "Entrar") { performEmail() }
                        .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                        .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty ||
                                  (registering && fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    Button(registering ? "Já tenho conta" : "Criar uma conta") {
                        FotomarcoHaptics.play(.buttons); password = ""; registering.toggle()
                    }.disabled(busy)
                    Text("ou").foregroundStyle(.secondary)
                    Button { performProvider(.google) } label: {
                        Text("Continuar com Google").frame(maxWidth: .infinity).padding(14)
                    }.buttonStyle(.plain).modifier(GalleryControlSurface(rounded: true)).disabled(busy)
                    Button { performProvider(.microsoft) } label: {
                        Text("Continuar com Microsoft").frame(maxWidth: .infinity).padding(14)
                    }.buttonStyle(.plain).modifier(GalleryControlSurface(rounded: true)).disabled(busy)
                    Button("Continuar sem conta") { FotomarcoHaptics.play(.buttons); continueWithoutAccount() }
                        .foregroundStyle(.secondary).disabled(busy)
                    Button("Conhecer os planos") { FotomarcoHaptics.play(.buttons); showPlans = true }
                        .foregroundStyle(.secondary).disabled(busy)
                    if busy { ProgressView().tint(.white) }
                }
                .frame(maxWidth: 420).padding(24).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPlans) {
            NavigationStack {
                BusinessPlansView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Concluído") { showPlans = false } }
                }
            }
        }
        .alert("Não foi possível entrar", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func performEmail() {
        guard !busy, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty,
              !registering || !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        FotomarcoHaptics.play(.buttons)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = password
        busy = true; focus = nil
        Task { @MainActor in
            defer { busy = false; password = "" }
            do { try await submit(address, secret, fullName, registering) }
            catch { message = "Confira seus dados e tente novamente." }
        }
    }

    private func performProvider(_ provider: Provider) {
        guard !busy else { return }
        FotomarcoHaptics.play(.buttons)
        busy = true; focus = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await signInWithProvider(provider) }
            catch { message = "Não foi possível concluir a conexão. Tente novamente." }
        }
    }
}
