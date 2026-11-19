import SwiftUI
import Photos

enum GalleryOrigin: String, CaseIterable, Identifiable {
    case local, google, oneDrive
    var id: Self { self }
    var title: String {
        switch self {
        case .local: "Local"
        case .google: "Google Drive"
        case .oneDrive: "OneDrive"
        }
    }
}

struct GalleryItem: Identifiable {
    enum Source {
        case capture(OriginalFile)
        case device(PHAsset)
        case cloud(GalleryCloudItem)
    }

    let source: Source
    let date: Date?
    let profile: CaptureProfileTag?

    var id: String {
        switch source {
        case .capture(let item): "capture/" + item.url.path
        case .device(let asset): "device/" + asset.localIdentifier
        case .cloud(let item): "cloud/" + item.id
        }
    }

    var origin: GalleryOrigin {
        switch source {
        case .capture, .device: .local
        case .cloud(let item): item.provider == .googleDrive ? .google : .oneDrive
        }
    }

    var isVideo: Bool {
        switch source {
        case .capture(let item): item.isVideo
        case .device(let asset): asset.mediaType == .video
        case .cloud: false
        }
    }

    var displaySource: String {
        switch source {
        case .capture: "Capturas do Momentra"
        case .device: "Fotos do iPhone"
        case .cloud(let item): "\(origin.title) · \(item.accountLabel)"
        }
    }

    var keywordText: String {
        let place: String
        if case .cloud(let item) = source { place = item.name } else { place = "" }
        return [isVideo ? "Vídeo" : "Foto", displaySource, profile?.name ?? "", place,
                date?.formatted(date: .long, time: .omitted) ?? ""].joined(separator: " ")
    }

    var trashedAt: Date? {
        switch source {
        case .capture(let item): item.trashedAt
        case .cloud(let item): item.trashedAt
        case .device: nil
        }
    }

    func daysRemaining(at now: Date = .now) -> Int? {
        guard let trashedAt else { return nil }
        let remaining = OriginalStore.retention - now.timeIntervalSince(trashedAt)
        return min(30, max(0, Int(ceil(remaining / 86_400))))
    }

    var canRestore: Bool {
        switch source {
        case .capture: true
        case .cloud(let item): item.canRestore
        case .device: false
        }
    }

    var canTrash: Bool {
        if case .device(let asset) = source { return asset.canPerform(.delete) }
        return true
    }

    var trashMessage: String {
        switch source {
        case .capture: "Restaure pela Lixeira do Momentra em até 30 dias."
        case .device: "O item vai para o álbum Apagados do app Fotos, onde pode ser recuperado por até 30 dias."
        case .cloud: "O arquivo vai para a lixeira da conta \(origin.title). As cópias em outros destinos ficam disponíveis."
        }
    }

    var canFavorite: Bool {
        if case .device(let asset) = source { return asset.canPerform(.properties) }
        return true
    }

    func isFavorite(in captures: Set<String>, cloud: Set<String>, device: [String: Bool]) -> Bool {
        switch source {
        case .capture(let item): captures.contains(Self.captureFavoriteKey(item))
        case .device(let asset): device[asset.localIdentifier] ?? asset.isFavorite
        case .cloud(let item): cloud.contains(item.favoriteKey)
        }
    }

    static func captureFavoriteKey(_ item: OriginalFile) -> String {
        item.url.deletingLastPathComponent().lastPathComponent + "/" + item.url.lastPathComponent
    }

    @MainActor @ViewBuilder func thumbnail() -> some View {
        switch source {
        case .capture(let item): Thumbnail(url: item.url, isVideo: item.isVideo)
        case .device(let asset): DeviceThumbnail(asset: asset)
        case .cloud(let item): item.thumb()
        }
    }

    @MainActor @ViewBuilder func preview(active: Bool) -> some View {
        switch source {
        case .capture(let item): CapturePage(item: item, active: active)
        case .device(let asset):
            if isVideo { DeviceVideoPreview(asset: asset, active: active) }
            else { DeviceThumbnail(asset: asset, fullView: true) }
        case .cloud(let item): item.fullImage(active: active)
        }
    }

    @MainActor func input() async throws -> PhotoEditorInput {
        switch source {
        case .capture(let item): PhotoEditorInput(url: item.url)
        case .device(let asset): try await DevicePhotoFile.editorInput(asset)
        case .cloud(let item): try await item.load()
        }
    }

    @MainActor func copy(to directory: URL) async throws -> URL {
        switch source {
        case .capture(let item):
            return try await Task.detached(priority: .utility) {
                let url = directory.appendingPathComponent(item.url.lastPathComponent)
                try FileManager.default.copyItem(at: item.url, to: url)
                return url
            }.value
        case .device(let asset):
            return try await DevicePhotoFile.copy(asset, to: directory.appendingPathComponent("Foto"))
        case .cloud(let item):
            return try await item.copy(to: directory)
        }
    }

    @MainActor func moveToTrash() async throws {
        switch source {
        case .capture(let item):
            try await Task.detached(priority: .utility) { try OriginalStore.moveToTrash(item) }.value
        case .device(let asset):
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([asset] as NSArray) }
        case .cloud(let item):
            try await item.moveToTrash()
        }
    }

    @MainActor func restore() async throws {
        switch source {
        case .capture(let item):
            try await Task.detached(priority: .utility) { try OriginalStore.restore(item) }.value
        case .cloud(let item):
            try await item.restore()
        case .device:
            throw CocoaError(.featureUnsupported)
        }
    }
}
