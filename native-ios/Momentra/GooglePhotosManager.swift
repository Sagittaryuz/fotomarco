import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class GooglePhotosManager: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var pendingCloudCaptures = 0
    @Published private(set) var cloudNeedsAttention = false
    @Published var message: String?
    @Published private(set) var cloudPhotos: [CloudPhoto] = []
    @Published private(set) var cloudNextPage: String?
    @Published private(set) var cloudLoaded = false
    @Published private(set) var cloudError: String?
    private let auth = NativeGoogleAuth()

    init() {
        guard NativeGoogleAuth.configured, GIDSignIn.sharedInstance.currentUser == nil,
              GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        busy = true
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] _, _ in
            Task { @MainActor in
                // A failed restore leaves the local camera and photos available.
                self?.busy = false
                self?.objectWillChange.send()
            }
        }
    }

    /// Retry a previously authorized session after temporary offline startup.
    func restoreForQueuedPhotos() {
        guard NativeGoogleAuth.configured, !busy, GIDSignIn.sharedInstance.currentUser == nil,
              GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        busy = true
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] _, _ in
            Task { @MainActor in
                self?.busy = false
                self?.objectWillChange.send()
            }
        }
    }

    var configured: Bool { NativeGoogleAuth.configured }
    var ownerID: String? { GIDSignIn.sharedInstance.currentUser?.userID }
    var connected: Bool {
        guard let user = GIDSignIn.sharedInstance.currentUser, user.userID != nil,
              let granted = user.grantedScopes else { return false }
        return NativeGoogleAuth.scopes.allSatisfy(granted.contains)
    }

    func connect(presenting: UIViewController) {
        guard configured, !busy else { return }
        busy = true
        auth.connect(presenting: presenting, personalConsent: true) { [weak self] success in
            self?.busy = false
            self?.message = success ? "Google Fotos conectado. Nenhuma foto foi enviada." : "Não foi possível conectar o Google Fotos."
        }
    }

    func signOut() {
        guard !busy else { return }
        CloudStoragePreference.disable()
        auth.signOut()
        cloudPhotos = []; cloudNextPage = nil; cloudLoaded = false; cloudError = nil
        objectWillChange.send()
        message = "Conta desconectada do Momentra. Fotos e permissões na conta Google não foram apagadas."
    }

    func loadCloudPhotos(nextPage: Bool = false) {
        guard configured, connected, !busy, let owner = GIDSignIn.sharedInstance.currentUser?.userID else { return }
        if nextPage && cloudNextPage == nil { return }
        let pageToken = nextPage ? cloudNextPage : nil
        busy = true
        cloudError = nil
        Task {
            defer { busy = false }
            let token: String? = await withCheckedContinuation { continuation in
                auth.freshToken(for: owner) { continuation.resume(returning: $0) }
            }
            guard let token, GIDSignIn.sharedInstance.currentUser?.userID == owner else {
                cloudPhotos = []; cloudNextPage = nil; cloudLoaded = false
                cloudError = "A sessão expirou. Reconecte sua conta Google."
                return
            }
            do {
                let page = try await GooglePersonalPhotoTransport(token: token).listAppPhotos(pageToken: pageToken)
                guard GIDSignIn.sharedInstance.currentUser?.userID == owner else {
                    cloudPhotos = []; cloudNextPage = nil; cloudLoaded = false
                    cloudError = "A conta foi alterada. Atualize a galeria."
                    return
                }
                var updated = nextPage ? cloudPhotos : []
                var seen = Set(updated.map(\.id))
                for item in page.photos where seen.insert(item.id).inserted { updated.append(item) }
                cloudPhotos = updated
                cloudNextPage = page.nextPageToken == pageToken ? nil : page.nextPageToken
                cloudLoaded = true
            } catch {
                cloudError = "Não foi possível carregar as fotos. Verifique a conexão e tente novamente."
            }
        }
    }

    /// Starts a bounded foreground pass. Pending receipts stay durable across
    /// offline errors, suspension, account changes and future retries.
    func drainCloudQueue(expectedOwnerHash: String, personalConsent: Bool) {
        guard personalConsent, connected, !busy, let owner = ownerID,
              CloudCaptureQueue.ownerHash(owner) == expectedOwnerHash,
              CloudStoragePreference.enabled(for: owner) else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let queue = CloudCaptureQueue(directory: documents.appendingPathComponent("CloudPending"))
                let previous = try queue.entries(for: owner)
                for item in previous where item.phase == .awaitingPhoto {
                    try? CloudCaptureStager.stage(root: documents, captureID: item.id,
                                                 ownerHash: expectedOwnerHash, originalExtension: item.originalExtension)
                }
                let items = try queue.entries(for: owner).filter { $0.phase != .cleaned }
                pendingCloudCaptures = items.count
                cloudNeedsAttention = items.contains { $0.phase == .uncertain }
                guard items.contains(where: { $0.phase == .ready || $0.phase == .verified || $0.phase == .cleaning }) else { return }
                let token: String? = await withCheckedContinuation { continuation in
                    auth.freshToken(for: owner) { continuation.resume(returning: $0) }
                }
                guard let token, GIDSignIn.sharedInstance.currentUser?.userID == owner else { return }
                let isCurrent: (String) async -> Bool = { expected in
                    await MainActor.run {
                        GIDSignIn.sharedInstance.currentUser?.userID == expected &&
                        CloudStoragePreference.enabled(for: expected)
                    }
                }
                let albumID = try await GoogleAlbumCoordinator.shared.resolve(
                    directory: documents.appendingPathComponent("GooglePhotoAlbums", isDirectory: true),
                    owner: owner, transport: GooglePersonalPhotoTransport(token: token), accountIsCurrent: isCurrent)
                let receipts = documents.appendingPathComponent("GooglePhotoReceipts", isDirectory: true)
                let coordinator = CloudPairUploadCoordinator(queue: queue, root: documents,
                    accountIsCurrent: isCurrent) { bytes, receipt, account, filename, format in
                    let uploader = PersonalPhotoUploader(directory: receipts,
                        transport: GooglePersonalPhotoTransport(token: token, albumID: albumID, photoFormat: format),
                        accountIsCurrent: isCurrent)
                    return await uploader.upload(jpeg: bytes, captureID: receipt, owner: account,
                                                 personalConsent: true, filename: filename, format: format)
                }
                let verificationTransport = GooglePersonalPhotoTransport(token: token, albumID: albumID)
                let cleanup = CloudCaptureCleanup(queue: queue, root: documents, accountIsCurrent: isCurrent) { id in
                    (try? await verificationTransport.verifyItem(id: id)) == true
                }
                for item in items {
                    guard await isCurrent(owner) else { break }
                    if item.phase == .ready {
                        let profile = PhotoProfileIndex.load().captures[item.id]
                        let originalName = profile.map {
                            CloudProfileFilename.encode(captureID: item.id, profile: $0, originalExtension: item.originalExtension)
                        } ?? item.id.uuidString + ".original." + item.originalExtension
                        let stampedName = profile.map {
                            CloudProfileFilename.encode(captureID: item.id, profile: $0)
                        } ?? item.id.uuidString + ".jpg"
                        switch await coordinator.send(id: item.id, owner: owner, personalConsent: personalConsent,
                                                      originalFilename: originalName, stampedFilename: stampedName) {
                        case .verified(_, let stampedID):
                            try? PhotoProfileIndex.bindCloud(captureID: item.id, owner: owner, mediaID: stampedID)
                        case .uncertain:
                            try? queue.markUncertain(id: item.id)
                            cloudNeedsAttention = true
                            continue
                        case .pending, .unavailable:
                            continue
                        }
                    } else if item.phase != .verified && item.phase != .cleaning {
                        continue
                    }
                    guard await isCurrent(owner) else { break }
                    if await cleanup.clean(id: item.id, owner: owner, cloudOnlyEnabled: true) == .cleaned {
                        pendingCloudCaptures = max(0, pendingCloudCaptures - 1)
                    }
                }
            } catch {
                // The queue and local files remain available for a future pass.
                return
            }
        }
    }

    func sendProcessedPhoto(_ url: URL) {
        guard configured, !busy, let owner = GIDSignIn.sharedInstance.currentUser?.userID else {
            message = "Conecte o Google Fotos antes de enviar."
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let processed = documents.appendingPathComponent("Processed", isDirectory: true).standardizedFileURL
                let file = url.standardizedFileURL
                guard file.deletingLastPathComponent() == processed, file.pathExtension.lowercased() == "jpg",
                      let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { throw CocoaError(.fileReadInvalidFileName) }
                let data = try await Task.detached(priority: .utility) {
                    let folder = try processed.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard folder.isDirectory == true, folder.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true,
                          let size = values.fileSize, size >= 4, size <= 20 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: 20 * 1024 * 1024 + 1) ?? Data()
                    guard bytes.count == size else { throw CocoaError(.fileReadCorruptFile) }
                    return bytes
                }.value
                let token: String? = await withCheckedContinuation { continuation in
                    auth.freshToken(for: owner) { continuation.resume(returning: $0) }
                }
                guard let token, GIDSignIn.sharedInstance.currentUser?.userID == owner else {
                    message = "A sessão mudou ou expirou. O arquivo local foi preservado."
                    return
                }
                let isCurrent: (String) async -> Bool = { expected in
                    await MainActor.run { GIDSignIn.sharedInstance.currentUser?.userID == expected }
                }
                let albumID: String
                do {
                    albumID = try await GoogleAlbumCoordinator.shared.resolve(
                        directory: documents.appendingPathComponent("GooglePhotoAlbums", isDirectory: true),
                        owner: owner, transport: GooglePersonalPhotoTransport(token: token), accountIsCurrent: isCurrent)
                } catch {
                    message = "Não foi possível confirmar o álbum Momentra. A foto continua no aparelho."
                    return
                }
                guard await isCurrent(owner) else {
                    message = "A conta Google mudou. O arquivo local foi preservado."
                    return
                }
                let uploader = PersonalPhotoUploader(directory: documents.appendingPathComponent("GooglePhotoReceipts", isDirectory: true),
                    transport: GooglePersonalPhotoTransport(token: token, albumID: albumID), accountIsCurrent: isCurrent)
                let profile = PhotoProfileIndex.load().captures[id]
                let filename = profile.map { CloudProfileFilename.encode(captureID: id, profile: $0) }
                let outcome = await uploader.upload(jpeg: data, captureID: id, owner: owner, personalConsent: true, filename: filename)
                switch outcome {
                case .verified(let mediaID):
                    try? PhotoProfileIndex.bindCloud(captureID: id, owner: owner, mediaID: mediaID)
                    message = "Foto pessoal confirmada no Google Fotos. O arquivo local foi preservado."
                case .verificationPending: message = "O item foi criado, mas a verificação está pendente. Tente novamente para verificar, sem reenviar."
                case .uncertain: message = "O resultado do envio é incerto. Confira no Google Fotos; o reenvio automático está bloqueado. Arquivo local preservado."
                case .failed: message = "Não foi possível enviar. O arquivo local foi preservado."
                }
            } catch {
                message = "Não foi possível abrir a foto processada. O arquivo local foi preservado."
            }
        }
    }
}
