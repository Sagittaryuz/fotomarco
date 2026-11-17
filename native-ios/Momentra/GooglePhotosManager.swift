import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class GooglePhotosManager: ObservableObject {
    @Published private(set) var busy = false
    @Published var message: String?
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

    var configured: Bool { NativeGoogleAuth.configured }
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
        auth.signOut()
        objectWillChange.send()
        message = "Conta desconectada do Momentra. Fotos e permissões na conta Google não foram apagadas."
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
                let uploader = PersonalPhotoUploader(directory: documents.appendingPathComponent("GooglePhotoReceipts", isDirectory: true),
                    transport: GooglePersonalPhotoTransport(token: token), accountIsCurrent: { expected in
                        await MainActor.run { GIDSignIn.sharedInstance.currentUser?.userID == expected }
                    })
                let outcome = await uploader.upload(jpeg: data, captureID: id, owner: owner, personalConsent: true)
                switch outcome {
                case .verified: message = "Foto pessoal confirmada no Google Fotos. O arquivo local foi preservado."
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
