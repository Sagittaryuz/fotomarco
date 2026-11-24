import SwiftUI

struct BusinessPublishProfileView: View {
    let api: BusinessAPIClient
    let organizationID: String
    @ObservedObject var profiles: StampProfilesStore
    @State private var selectedID: UUID?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Carimbo da organização") {
                Picker("Perfil pessoal", selection: $selectedID) {
                    ForEach(profiles.profiles) { profile in
                        Text(profile.name.isEmpty ? "Sem nome" : profile.name).tag(Optional(profile.id))
                    }
                }
                Text("Uma cópia do perfil escolhido será disponibilizada à equipe. Os membros não poderão editá-la.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Salvar carimbo da organização") { Task { await publish() } }
                    .disabled(busy || selectedID == nil)
                if busy { ProgressView("Salvando…") }
            }
        }
        .navigationTitle("Carimbo da equipe")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selectedID == nil { selectedID = profiles.profiles.first?.id } }
        .alert("Carimbo da organização", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    @MainActor private func publish() async {
        guard !busy, let profile = profiles.profiles.first(where: { $0.id == selectedID }) else { return }
        busy = true
        defer { busy = false }
        do {
            let token = try await BusinessIdentity.shared.verifiedToken()
            _ = try await BusinessProfileTransfer(api: api).publish(profile, organizationID: organizationID, token: token)
            await BusinessProfileSync.refresh(into: profiles)
            message = "Carimbo salvo para a equipe."
        } catch {
            message = "Não foi possível salvar o carimbo. Confira sua conexão e seu acesso."
        }
    }
}
