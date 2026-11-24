import SwiftUI
import UIKit

struct BusinessOneDriveView: View {
    let api: BusinessAPIClient
    let organizationID: String
    @State private var oauth = CloudArchiveOAuth()
    @State private var busy = false
    @State private var connected = false
    @State private var message: String?

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
                if busy { ProgressView("Confirmando a conta…") }
                if connected { Label("Conta conectada", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .navigationTitle("Armazenamento")
        .navigationBarTitleDisplayMode(.inline)
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
            let token = try await BusinessIdentity.shared.verifiedToken()
            let result = try await api.connectOneDrive(organizationID: organizationID,
                refreshToken: account.credential.refreshToken, token: token)
            connected = result.connected
            if !connected { message = "Não foi possível confirmar a conexão." }
        } catch BusinessAPIClient.Failure.storageAccountChangeRequiresMigration {
            message = "Esta organização já utiliza outra conta OneDrive. A troca exige uma migração para preservar as fotos."
        } catch {
            message = "Não foi possível conectar a conta. Confira as permissões e tente novamente."
        }
    }
}
