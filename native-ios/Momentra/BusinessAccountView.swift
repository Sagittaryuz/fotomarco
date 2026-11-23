import SwiftUI
import UIKit

/// Account access remains separate from the connected storage destinations.
struct BusinessAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var identity = BusinessIdentity.shared
    @State private var message: String?

    var body: some View {
        Group {
            if let userID = identity.userID {
                Form {
                    Section("Conta") {
                        LabeledContent("E-mail", value: identity.email ?? "Indisponível")
                        Text(identity.emailVerified ? "E-mail verificado" : "Verifique seu e-mail para acessar uma organização.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !identity.emailVerified {
                            Button("Reenviar e-mail de verificação") {
                                Task {
                                    do { try await identity.sendVerification(); message = "Confira sua caixa de entrada." }
                                    catch { message = "Não foi possível enviar o e-mail agora." }
                                }
                            }
                            Button("Atualizar verificação") {
                                Task {
                                    do { _ = try await identity.verifiedToken() }
                                    catch { message = "Confirme o e-mail recebido e tente novamente." }
                                }
                            }
                        }
                    }
                    Section {
                        Button("Sair da conta Business", role: .destructive) {
                            do { try identity.signOut() }
                            catch { message = "Não foi possível sair da conta." }
                        }
                        .accessibilityIdentifier("business.signout.\(userID.isEmpty ? "empty" : "available")
                        Text("Suas contas de armazenamento continuam conectadas.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                BusinessSignInView(submit: { email, password, registering in
                    if registering { try await identity.register(email: email, password: password) }
                    else { try await identity.signIn(email: email, password: password) }
                }, signInWithProvider: { provider in
                    switch provider {
                    case .microsoft: try await identity.signInMicrosoft()
                    case .google:
                        guard let controller = Self.presentingController() else { throw BusinessIdentity.IdentityError.notConfigured }
                        try await identity.signInGoogle(presenting: controller)
                    }
                }, continueWithoutAccount: { dismiss() })
            }
        }
        .navigationTitle("Conta Business")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { identity.start() }
        .alert("Conta Business", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private static func presentingController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        while let presented = controller.presentedViewController { controller = presented }
        return controller
    }
}
