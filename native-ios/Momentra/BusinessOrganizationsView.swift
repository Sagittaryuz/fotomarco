import SwiftUI

struct BusinessOrganizationsView: View {
    @ObservedObject var profiles: StampProfilesStore
    @ObservedObject private var identity = BusinessIdentity.shared
    @State private var organizations: [BusinessAPIClient.OrganizationSummary] = []
    @State private var busy = false
    @State private var message: String?
    @State private var showCreate = false
    @State private var organizationName = ""
    @State private var organizationEmail = ""

    private var client: BusinessAPIClient? {
        BusinessAPIClient.configured()
    }

    var body: some View {
        Group {
            if identity.userID == nil {
                BusinessAccountView()
            } else {
                List {
                    Section("Conta") {
                        NavigationLink(identity.email ?? "Conta Business") { BusinessAccountView() }
                        if !identity.emailVerified {
                            Text("Confirme seu e-mail para acessar organizações.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("Organizações") {
                        if client == nil {
                            Text("O serviço de organizações ainda não está configurado.").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(organizations) { organization in
                                NavigationLink(organization.name) {
                                    organizationMenu(organization)
                                }
                            }
                            if busy { ProgressView("Carregando…") }
                            Button("Criar organização") {
                                organizationEmail = identity.email ?? ""
                                showCreate = true
                            }.disabled(!identity.emailVerified || busy)
                        }
                    }
                }
            }
        }
        .navigationTitle("Organização e equipe")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(identity.userID ?? "")-\(identity.emailVerified)") { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCreate) { createSheet }
        .alert("Organização", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    @ViewBuilder private func organizationMenu(_ org: BusinessAPIClient.OrganizationSummary) -> some View {
        if let client {
            List {
                NavigationLink("Fotos da organização") {
                    BusinessTeamPhotosView(api: client, organizationID: org.id)
                }
                if org.role == "owner" || org.role == "administrator" {
                    NavigationLink("Carimbo da equipe") {
                        BusinessPublishProfileView(api: client, organizationID: org.id, profiles: profiles)
                    }
                    NavigationLink("Dados da organização") {
                        BusinessOrganizationSettingsView(api: client, organizationID: org.id,
                            accessToken: { try await identity.verifiedToken() }, didSave: { Task { await load() } })
                    }
                    NavigationLink("Membros e acesso") {
                        BusinessMembersView(api: client, organizationID: org.id,
                            accessToken: { try await identity.verifiedToken() })
                    }
                    if org.role == "owner" {
                        NavigationLink("OneDrive da organização") {
                            BusinessOneDriveView(api: client, organizationID: org.id)
                        }
                        NavigationLink("E-mail de convites") {
                            BusinessOrganizationEmailView(api: client, organizationID: org.id)
                        }
                    }
                }
                if org.role == "member" {
                    NavigationLink("Conectar conta Microsoft") {
                        BusinessMemberOneDriveView(api: client, organizationID: org.id)
                    }
                }
                Text(org.captureReady == true ? "O carimbo da equipe pode ser selecionado na câmera." :
                     "A pasta da equipe ainda precisa ser configurada para habilitar capturas.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle(org.name)
        }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                TextField("Nome da organização", text: $organizationName)
                TextField("E-mail da organização", text: $organizationEmail)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                if busy { ProgressView() }
            }
            .navigationTitle("Nova organização")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { showCreate = false }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { Task { await create() } }
                        .disabled(busy || organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || organizationEmail.isEmpty)
                }
            }
        }
    }

    @MainActor private func load() async {
        guard identity.userID != nil, identity.emailVerified, let client, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            organizations = try await client.myOrganizations(token: identity.verifiedToken()).organizations
            await BusinessProfileSync.refresh(into: profiles)
        }
        catch { message = "Não foi possível carregar as organizações. Confira sua conexão e seu acesso." }
    }

    @MainActor private func create() async {
        guard let client, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await client.createOrganization(name: organizationName, contactEmail: organizationEmail,
                                                     token: identity.verifiedToken())
            showCreate = false
            // Refresh after releasing the busy flag.
            busy = false
            await load()
        } catch { message = "Não foi possível criar a organização. Confira seus dados e o acesso Business." }
    }
}
