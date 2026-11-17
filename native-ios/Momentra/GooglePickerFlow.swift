import SwiftUI
import GoogleSignIn

struct PickedCloudImage: Identifiable {
    let id = UUID()
    let data: Data
    let date: Date?
}

/// Session IDs and tokens live only while the user is actively picking.
@MainActor
final class GooglePickerFlow: ObservableObject {
    private static let scope = "https://www.googleapis.com/auth/photospicker.mediaitems.readonly"
    @Published private(set) var busy = false
    @Published private(set) var waitingForSelection = false
    @Published var message: String?
    @Published var picked: PickedCloudImage?
    private var sessionID: String?
    private var owner: String?
    private var cancellationRequested = false

    func start() {
        guard !busy, sessionID == nil, NativeGoogleAuth.configured,
              let user = GIDSignIn.sharedInstance.currentUser, let userID = user.userID,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            message = "Conecte sua conta Google para selecionar uma foto."; return
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        cancellationRequested = false
        busy = true
        user.addScopes([Self.scope], presenting: presenter) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                guard !self.cancellationRequested else { self.busy = false; return }
                guard error == nil, result?.user.userID == userID,
                      result?.user.grantedScopes?.contains(Self.scope) == true,
                      GIDSignIn.sharedInstance.currentUser?.userID == userID else {
                    self.busy = false; self.message = "A permissão para selecionar fotos não foi concedida."; return
                }
                await self.createSession(owner: userID)
            }
        }
    }

    private func token(for expected: String) async -> String? {
        guard let user = GIDSignIn.sharedInstance.currentUser, user.userID == expected,
              user.grantedScopes?.contains(Self.scope) == true else { return nil }
        return await withCheckedContinuation { continuation in
            user.refreshTokensIfNeeded { updated, error in
                Task { @MainActor in
                    guard error == nil, let updated, updated.userID == expected,
                          updated.grantedScopes?.contains(Self.scope) == true,
                          GIDSignIn.sharedInstance.currentUser?.userID == expected else {
                        continuation.resume(returning: nil); return
                    }
                    continuation.resume(returning: updated.accessToken.tokenString)
                }
            }
        }
    }

    private func createSession(owner expected: String) async {
        defer { busy = false }
        guard let token = await token(for: expected) else { message = "A sessão Google expirou."; return }
        do {
            let client = GooglePhotoPickerClient(token: token)
            let created = try await client.create()
            sessionID = created.id; owner = expected
            if cancellationRequested {
                try? await client.delete(id: created.id)
                sessionID = nil; owner = nil
                return
            }
            guard GIDSignIn.sharedInstance.currentUser?.userID == expected,
                  let url = created.pickerURL else {
                try? await client.delete(id: created.id)
                sessionID = nil; owner = nil
                message = "Não foi possível abrir o seletor do Google Fotos."; return
            }
            let opened = await UIApplication.shared.open(url)
            if cancellationRequested {
                try? await client.delete(id: created.id)
                sessionID = nil; owner = nil; waitingForSelection = false
            } else if opened { waitingForSelection = true }
            else {
                try? await client.delete(id: created.id)
                sessionID = nil; owner = nil
                message = "Não foi possível abrir o seletor do Google Fotos."
            }
        } catch { message = "Não foi possível iniciar a seleção no Google Fotos." }
    }

    func retrieve() {
        guard !busy, let id = sessionID, let expected = owner else { return }
        busy = true
        Task {
            defer { busy = false }
            guard let token = await token(for: expected) else {
                if cancellationRequested { sessionID = nil; owner = nil; waitingForSelection = false }
                else { message = "A sessão Google expirou. Cancele e tente novamente." }
                return
            }
            let client = GooglePhotoPickerClient(token: token)
            do {
                let status = try await client.status(id: id)
                if cancellationRequested { await finishCancellation(client: client, id: id); return }
                guard GIDSignIn.sharedInstance.currentUser?.userID == expected else { throw URLError(.userAuthenticationRequired) }
                guard status.mediaItemsSet == true else {
                    message = "A seleção ainda não foi concluída no Google Fotos."; return
                }
                guard let photo = try await client.selected(id: id), photo.downloadURL != nil else {
                    try? await client.delete(id: id)
                    sessionID = nil; owner = nil; waitingForSelection = false
                    message = "Nenhuma foto compatível foi selecionada."; return
                }
                if cancellationRequested { await finishCancellation(client: client, id: id); return }
                let bytes = try await client.download(photo)
                if cancellationRequested { await finishCancellation(client: client, id: id); return }
                guard GIDSignIn.sharedInstance.currentUser?.userID == expected else { throw URLError(.userAuthenticationRequired) }
                try? await client.delete(id: id)
                sessionID = nil; owner = nil; waitingForSelection = false
                picked = PickedCloudImage(data: bytes, date: photo.creationDate)
            } catch {
                if cancellationRequested { await finishCancellation(client: client, id: id) }
                else { message = "Não foi possível obter a foto selecionada. Confira a conexão e tente novamente." }
            }
        }
    }

    func cancel() {
        cancellationRequested = true
        guard !busy, let id = sessionID, let expected = owner else { return }
        busy = true
        Task {
            defer { busy = false }
            if let token = await token(for: expected) { try? await GooglePhotoPickerClient(token: token).delete(id: id) }
            sessionID = nil; owner = nil; waitingForSelection = false
        }
    }

    private func finishCancellation(client: GooglePhotoPickerClient, id: String) async {
        try? await client.delete(id: id)
        sessionID = nil; owner = nil; waitingForSelection = false
    }
}
