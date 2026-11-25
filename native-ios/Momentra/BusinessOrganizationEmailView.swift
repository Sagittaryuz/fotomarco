import SwiftUI
import UIKit

struct BusinessOrganizationEmailView: View {
    let api: BusinessAPIClient
    let organizationID: String
    @State private var oauth = CloudArchiveOAuth()
    @State private var pending: CloudArchiveOAuth.AuthorizedAccount?
    @State private var pendingMicrosoft = false
    @State private var confirming = false
    @State private var busy = false
    @State private var connected = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("E-mail de convites") {
                Text("Escolha o serviço do e-mail cadastrado na organização. Será solicitada permissão para enviar convites em nome dessa conta.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("A conexão não altera as contas pessoais de armazenamento.").font(.footnote).foregroundStyle(.secondary)
                Button("Gmail") { Task { await connect(microsoft: false) } }.disabled(busy)
                Button("Outlook / Microsoft") { Task { await connect(microsoft: true) } }.disabled(busy)
                if busy { ProgressView("Confirmando a conta…") }
                if connected { Label("Conta conectada", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .navigationTitle("E-mail da equipe")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Usar esta conta para enviar convites?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Usar \(pending?.label ?? "esta conta")") { Task { await save() } }
            Button("Cancelar", role: .cancel) { pending = nil }
        } message: { Text("Ela deve corresponder ao e-mail cadastrado na organização.") }
        .onDisappear { pending = nil }
        .alert("E-mail da organização", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    @MainActor private func connect(microsoft: Bool) async {
        guard !busy, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }
        busy = true
        defer { busy = false }
        do {
            let configuration = try CloudArchiveOAuth.Configuration(provider: microsoft ? .oneDrive : .googleDrive,
                forBusiness: true, microsoftMail: microsoft)
            pending = try await oauth.connect(configuration, presenting: window, knownDestinations: [])
            pendingMicrosoft = microsoft
            confirming = true
        } catch { message = "Não foi possível conectar o e-mail. Confira as permissões e tente novamente." }
    }

    @MainActor private func save() async {
        guard !busy, let account = pending else { return }
        busy = true
        defer { busy = false; pending = nil }
        do {
            let token = try await BusinessIdentity.shared.verifiedToken()
            if pendingMicrosoft {
                connected = try await api.connectMicrosoftMail(organizationID: organizationID,
                    refreshToken: account.credential.refreshToken, token: token).connected
            } else {
                connected = try await api.connectGoogleMail(organizationID: organizationID,
                    refreshToken: account.credential.refreshToken, token: token).connected
            }
        } catch BusinessAPIClient.Failure.mailboxMismatch {
            message = "Esta conta não corresponde ao e-mail cadastrado para a organização."
        } catch { message = "Não foi possível confirmar a conta. Tente novamente." }
    }
}
