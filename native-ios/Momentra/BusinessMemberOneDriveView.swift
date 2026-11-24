import SwiftUI
import UIKit

struct BusinessMemberOneDriveView: View {
    let api: BusinessAPIClient
    let organizationID: String
    @State private var oauth = CloudArchiveOAuth()
    @State private var busy = false
    @State private var message: String?
    @State private var pendingAccount: CloudArchiveOAuth.AuthorizedAccount?
    @State private var confirmAccount = false

    var body: some View {
        Form {
            Section("Conta Microsoft") {
                Text("Conecte a conta que receberá acesso à sua pasta da organização. O aplicativo solicita apenas a identificação da conta nesta etapa.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Conectar conta Microsoft") {
                    FotomarcoHaptics.play(.buttons)
                    Task { await connect() }
                }.disabled(busy)
                if busy { ProgressView("Confirmando a conta…") }
            }
        }
        .navigationTitle("Conta Microsoft")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Usar esta conta?", isPresented: $confirmAccount, titleVisibility: .visible) {
            Button("Usar \(pendingAccount?.label ?? "esta conta")") { Task { await bind() } }
            Button("Cancelar", role: .cancel) { pendingAccount = nil }
        } message: {
            Text("A organização poderá associar sua pasta a esta conta.")
        }
        .onDisappear { pendingAccount = nil }
        .alert("Conta Microsoft", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    @MainActor private func connect() async {
        guard !busy, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }
        busy = true
        defer { busy = false }
        do {
            let configuration = try CloudArchiveOAuth.Configuration(provider: .oneDrive, identityOnly: true)
            pendingAccount = try await oauth.connect(configuration, presenting: window, knownDestinations: [])
            confirmAccount = true
        } catch {
            message = "Não foi possível confirmar a conta Microsoft. Tente novamente."
        }
    }

    @MainActor private func bind() async {
        guard !busy, let account = pendingAccount else { return }
        busy = true
        defer { busy = false; pendingAccount = nil }
        do {
            let token = try await BusinessIdentity.shared.verifiedToken()
            let result = try await api.bindMemberOneDrive(organizationID: organizationID,
                accessToken: account.credential.accessToken, token: token)
            if result.linked {
                let folder = try await api.provisionMemberOneDrive(organizationID: organizationID,
                    accessToken: account.credential.accessToken, token: token)
                message = folder.ready ? "Conta conectada e pasta da organização preparada." : "Conta confirmada. A pasta ainda não está pronta."
            } else {
                message = "Não foi possível confirmar a conta."
            }
        } catch BusinessAPIClient.Failure.storageAccountChangeRequiresMigration {
            message = "Outra conta já está associada. A troca exige uma migração para preservar as fotos."
        } catch {
            message = "Não foi possível associar a conta. Confira seu acesso à organização e tente novamente."
        }
    }
}
