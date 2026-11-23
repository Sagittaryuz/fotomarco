import SwiftUI
import PhotosUI
import UIKit

/// Drafts changes locally until Salvar is pressed; the service checks permissions again.
struct BusinessOrganizationSettingsView: View {
    let api: BusinessAPIClient
    let organizationID: String
    let accessToken: () async throws -> String
    let didSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var photoAssetID = ""
    @State private var photoData: Data?
    @State private var newPhoto: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var busy = true
    @State private var canEdit = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Group {
                            if let photoData, let image = UIImage(data: photoData) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "building.2.crop.circle").resizable().scaledToFit().padding(15)
                            }
                        }
                        .frame(width: 92, height: 92).clipShape(Circle())
                        .modifier(GalleryControlSurface(rounded: true))
                    }.disabled(!canEdit || busy).accessibilityLabel("Escolher foto da organização")
                    Spacer()
                }.listRowBackground(Color.clear)
            }
            Section("Dados da organização") {
                TextField("Nome da organização", text: $name).disabled(!canEdit || busy)
                TextField("E-mail da organização", text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(!canEdit || busy)
            }
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
        .navigationTitle("Organização")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Salvar") { FotomarcoHaptics.play(.buttons); Task { await save() } }
                    .disabled(!canEdit || busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.isEmpty)
            }
        }
        .task(id: organizationID) { await load() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            FotomarcoHaptics.play(.buttons)
            Task { await selectPhoto(item) }
        }
        .alert("Organização", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    @MainActor private func load() async {
        busy = true
        defer { busy = false }
        do {
            let token = try await accessToken()
            let info = try await api.readOrganization(organizationID: organizationID, token: token)
            guard info.id == organizationID, let contact = info.contactEmail else { throw BusinessAPIClient.Failure.unauthorized }
            name = info.name; email = contact; photoAssetID = info.photoAssetId; canEdit = true
            if !photoAssetID.isEmpty {
                let asset = try await api.readAsset(organizationID: organizationID, assetID: photoAssetID, token: token)
                guard ["image/png", "image/jpeg"].contains(asset.mimeType), let data = Data(base64Encoded: asset.base64), data.count <= 262144,
                      UIImage(data: data) != nil else { throw BusinessAPIClient.Failure.invalidResponse }
                photoData = data
            }
        } catch { canEdit = false; message = "Não foi possível carregar os dados da organização." }
    }

    @MainActor private func selectPhoto(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty, data.count <= 20_000_000,
                  let image = UIImage(data: data), let png = image.pngData() else { throw BusinessAPIClient.Failure.invalidRequest }
            let prepared = try BusinessProfileTransfer.uploadImage(png)
            newPhoto = prepared; photoData = prepared
        } catch { message = "Não foi possível usar essa imagem." }
    }

    @MainActor private func save() async {
        guard canEdit, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let token = try await accessToken()
            let assetID: String
            if let newPhoto {
                assetID = try await api.uploadAsset(organizationID: organizationID, mimeType: "image/png", imageData: newPhoto, token: token).assetId
            } else { assetID = photoAssetID }
            _ = try await api.updateOrganization(organizationID: organizationID, name: name, contactEmail: email, photoAssetID: assetID, token: token)
            didSave(); dismiss()
        } catch { message = "Não foi possível salvar. Confira os dados e tente novamente." }
    }
}
