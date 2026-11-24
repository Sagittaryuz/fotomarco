import SwiftUI
import UIKit

struct BusinessOneDriveView: View {
    let api: BusinessAPIClient
    let organizationID: String
    @State private var oauth = CloudArchiveOAuth()
    @State private var busy = false
    @State private var connected = false
    @State private var folderReady = false
    @State private var message: String?
    @State private var pendingAccount: CloudArchiveOAuth.AuthorizedAccount?
    @State private var confirmAccount = false

    var body: some View {
        Form {
            Section("OneDrive da organização") {
                Text("Conecte a conta que guardará as fotos da equipe. A Microsoft solicitará acesso para ler e alterar arquivos do OneDrive e compartilhar pastas da organização.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Essa conexão é separada das contas de armazenamento pessoal já adicionadas.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(connected ? "Reconectar OneDrive" : "Conectar OneDrive") {
                    FotomarcoHaptics.play(.buttons)
                    Task { await connect() }
                }.disabled(busy)
                Button("Preparar minha pasta") {
                    FotomarcoHaptics.play(.buttons)
                    Task { await prepareFolder() }
                }.disabled(busy)
                if busy { ProgressView("Confirmando a conta…") }
                if connected { Label("Conta conectada", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if folderReady { Label("Pasta preparada", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .navigationTitle("Armazenamento")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Usar esta conta para a organização?", isPresented: $confirmAccount, titleVisibility: .visible) {
            Button("Usar \(pendingAccount?.label ?? "esta conta")") { Task { await saveAccount() } }
            Button("Cancelar", role: .cancel) { pendingAccount = nil }
        } message: {
            Text("As fotos da equipe serão associadas a esta conta OneDrive.")
        }
        .onDisappear { pendingAccount = nil }
        .alert("OneDrive da organização", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
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
            let configuration = try CloudArchiveOAuth.Configuration(provider: .oneDrive, forBusiness: true)
            let account = try await oauth.connect(configuration, presenting: window, knownDestinations: [])
            pendingAccount = account
            confirmAccount = true
        } catch let error as CloudArchiveOAuth.Failure {
            message = error.errorDescription
        } catch {
            message = "Não foi possível conectar a conta. Confira as permissões e tente novamente."
        }
    }

    @MainActor private func saveAccount() async {
        guard !busy, let account = pendingAccount else { return }
        busy = true
        defer { busy = false; pendingAccount = nil }
        do {
            let token = try await BusinessIdentity.shared.verifiedToken()
            let result = try await api.connectOneDrive(organizationID: organizationID,
                refreshToken: account.credential.refreshToken, token: token)
            connected = result.connected
            if connected {
                let folder = try await api.provisionOwnerFolder(organizationID: organizationID, token: token)
                folderReady = folder.ready
                if !folderReady { message = "Conta conectada. Não foi possível confirmar a pasta." }
            } else { message = "Não foi possível confirmar a conexão." }
        } catch BusinessAPIClient.Failure.storageAccountChangeRequiresMigration {
            message = "Esta organização já utiliza outra conta OneDrive. A troca exige uma migração para preservar as fotos."
        } catch BusinessAPIClient.Failure.unauthorized {
            message = "A sessão ou a permissão da organização não foi confirmada. Entre novamente e tente conectar o OneDrive."
        } catch BusinessAPIClient.Failure.unavailable {
            message = "Não foi possível confirmar o OneDrive no servidor. Confira a conexão e tente novamente."
        } catch {
            message = connected ? "Conta conectada. Não foi possível preparar a pasta; confira as permissões e tente novamente." : "Não foi possível conectar a conta. Confira as permissões e tente novamente."
        }
    }

    @MainActor private func prepareFolder() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let token = try await BusinessIdentity.shared.verifiedToken()
            folderReady = try await api.provisionOwnerFolder(organizationID: organizationID, token: token).ready
            if !folderReady { message = "Não foi possível confirmar a pasta." }
        } catch {
            message = "Não foi possível preparar a pasta. Conecte o OneDrive e confira suas permissões."
        }
    }
}
