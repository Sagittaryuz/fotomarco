import SwiftUI

struct BusinessInvitationView: View {
    let invitation: BusinessInvitationRouter.Invitation
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var identity = BusinessIdentity.shared
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Convite para uma organização") {
                    Text("Entre com o e-mail que recebeu o convite. O acesso será confirmado antes de ingressar.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let email = identity.email {
                        LabeledContent("Conta", value: email)
                        if !identity.emailVerified {
                            Text("Confirme seu e-mail antes de aceitar.").font(.footnote).foregroundStyle(.secondary)
                        }
                        NavigationLink("Gerenciar conta") { BusinessAccountView() }
                        Button("Aceitar convite") { Task { await accept() } }
                            .disabled(!identity.emailVerified || busy)
                        if busy { ProgressView("Confirmando acesso…") }
                    } else {
                        NavigationLink("Entrar ou criar conta") { BusinessAccountView() }
                    }
                }
            }
            .navigationTitle("Convite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() }.disabled(busy) } }
            .alert("Convite", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    @MainActor private func accept() async {
        guard !busy, let api = BusinessAPIClient.configured() else {
            message = "O serviço de organizações ainda não está disponível."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let token = try await identity.verifiedToken()
            _ = try await api.accept(organizationID: invitation.organizationID, invitationID: invitation.invitationID, token: token)
            NotificationCenter.default.post(name: .businessOrganizationsDidChange, object: nil)
            dismiss()
        } catch {
            message = "Não foi possível aceitar. Confira se esta é a conta convidada e se o convite ainda é válido."
        }
    }
}
