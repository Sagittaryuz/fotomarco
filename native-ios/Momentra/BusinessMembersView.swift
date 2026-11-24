import SwiftUI

/// The server rechecks the caller's membership before returning this list.
struct BusinessMembersView: View {
    let api: BusinessAPIClient
    let organizationID: String
    let accessToken: () async throws -> String
    @State private var members: [BusinessAPIClient.Member] = []
    @State private var busy = false
    @State private var loadError: String?

    var body: some View {
        List {
            if busy && members.isEmpty { ProgressView("Carregando membros…") }
            ForEach(members) { member in
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.email ?? "Usuário da organização")
                        Text(roleName(member.role)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let loadError {
                Text(loadError).font(.footnote).foregroundStyle(.secondary)
                Button("Tentar novamente") { Task { await load() } }
            }
        }
        .navigationTitle("Membros e acesso")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: organizationID) { await load() }
        .refreshable { await load() }
    }

    private func roleName(_ role: String) -> String {
        switch role {
        case "owner": return "Proprietário"
        case "administrator": return "Administrador"
        default: return "Membro"
        }
    }

    @MainActor private func load() async {
        guard !busy else { return }
        busy = true; loadError = nil
        defer { busy = false }
        do {
            let token = try await accessToken()
            members = try await api.listMembers(organizationID: organizationID, token: token).members
        } catch {
            loadError = "Não foi possível carregar os membros. Verifique sua conexão e seu acesso."
        }
    }
}
