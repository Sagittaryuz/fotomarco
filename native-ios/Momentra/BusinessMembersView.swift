import SwiftUI

/// The server rechecks the caller's membership before returning this list.
struct BusinessMembersView: View {
    let api: BusinessAPIClient
    let organizationID: String
    let accessToken: () async throws -> String
    @State private var members: [BusinessAPIClient.Member] = []
    @State private var busy = false
    @State private var loadError: String?
    @State private var showInvite = false
    @State private var email = ""
    @State private var sending = false
    @State private var notice: String?
    @State private var removal: BusinessAPIClient.Member?

    var body: some View {
        List {
            Button {
                FotomarcoHaptics.play(.buttons)
                showInvite = true
            } label: { Label("Convidar", systemImage: "plus.circle.fill") }
            if busy && members.isEmpty { ProgressView("Carregando membros…") }
            ForEach(members) { member in
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.displayName ?? member.email ?? "Usuário da organização")
                        if let displayName = member.displayName, !displayName.isEmpty, let email = member.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(roleName(member.role)).font(.caption).foregroundStyle(.secondary)
                        if member.revocationPending == true {
                            Text("Remoção pendente no OneDrive").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if member.role != "owner" && member.userId != BusinessIdentity.shared.userID {
                        Button(member.revocationPending == true ? "Concluir" : "Remover", role: .destructive) { removal = member }
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
        .sheet(isPresented: $showInvite) {
            NavigationStack {
                Form {
                    TextField("E-mail da pessoa", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("A pessoa precisará aceitar o convite usando esse mesmo e-mail verificado.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if sending { ProgressView("Enviando convite…") }
                }
                .navigationTitle("Convidar membro")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { showInvite = false }.disabled(sending) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enviar") { Task { await invite() } }
                            .disabled(sending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .confirmationDialog("Remover membro da organização?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            Button("Remover membro", role: .destructive) {
                guard let target = removal else { return }
                Task { await remove(target) }
            }
            Button("Cancelar", role: .cancel) { removal = nil }
        } message: { Text("As fotos existentes serão preservadas. O acesso ao OneDrive será revogado quando possível.") }
        .alert("Convite", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: { Text(notice ?? "") }
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

    @MainActor private func invite() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        do {
            let token = try await accessToken()
            _ = try await api.invite(organizationID: organizationID, email: email, token: token)
            showInvite = false
            email = ""
            notice = "Convite enviado."
        } catch BusinessAPIClient.Failure.mailNotConfigured {
            showInvite = false
            notice = "O proprietário precisa conectar o e-mail da organização antes de enviar convites."
        } catch {
            showInvite = false
            notice = "Não foi possível confirmar o envio. Confira se a pessoa recebeu o e-mail antes de tentar novamente."
        }
    }

    @MainActor private func remove(_ member: BusinessAPIClient.Member) async {
        defer { removal = nil }
        do {
            let token = try await accessToken()
            let result = try await api.removeMember(organizationID: organizationID, userID: member.userId, token: token)
            await load()
            notice = result.complete ? "Membro removido. As fotos foram preservadas." :
                "O acesso ao aplicativo foi suspenso. A revogação no OneDrive está pendente; tente concluir novamente."
        } catch { notice = "Não foi possível remover o membro. Confira sua conexão e seu acesso." }
    }
}
