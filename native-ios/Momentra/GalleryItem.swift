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

struct GalleryOriginMark: View {
    let origin: GalleryOrigin
    let size: CGFloat

    var body: some View {
        switch origin {
        case .local:
            Image(systemName: "photo.on.rectangle.fill")
                .font(.system(size: size * 0.60, weight: .medium)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(AngularGradient(colors: [.purple, .blue, .mint, .orange, .pink, .purple],
                                            center: .center), in: Circle())
        case .google, .oneDrive:
            Image(origin == .google ? "GoogleDriveMark" : "OneDriveMark")
                .renderingMode(.original).resizable().scaledToFit().frame(width: size, height: size)
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
    var deviceCaptureID: UUID? = nil
    var copies: [Source] = []

    struct StorageBadge: Identifiable {
        let id: String
        let origin: GalleryOrigin
        let label: String
        var usesInternalDrive = false
    }

    var photoIdentity: String? {
        let captureID: UUID?
        let variant: String
        switch source {
        case .capture(let item):
            guard !item.isVideo else { return nil }
            captureID = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent)
            variant = item.isProcessed ? "processed" : "original"
        case .device(let asset):
            guard asset.mediaType == .image else { return nil }
            captureID = deviceCaptureID
            variant = "processed"
        case .cloud(let item):
            captureID = item.captureID
            variant = item.isOriginal ? "original" : "processed"
        }
        return captureID.map { "photo/\($0.uuidString)/\(variant)" }
    }

    var id: String { photoIdentity ?? storageID }

    var storageID: String {
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

    private var sources: [Source] { [source] + copies }

    var storageBadges: [StorageBadge] {
        var seen = Set<String>()
        let hasPhotosCopy = sources.contains { if case .device = $0 { true } else { false } }
        return sources.compactMap { source in
            let badge: StorageBadge
            switch source {
            case .capture:
                badge = .init(id: "local/momentra", origin: .local, label: "No iPhone · Momentra",
                              usesInternalDrive: hasPhotosCopy)
            case .device:
                badge = .init(id: "local/photos", origin: .local, label: "No iPhone · Fotos")
            case .cloud(let item):
                let origin: GalleryOrigin = item.provider == .googleDrive ? .google : .oneDrive
                badge = .init(id: origin.rawValue + "/" + item.destination.accountHash,
                              origin: origin, label: "\(origin.title) · \(item.accountLabel)")
            }
            return seen.insert(badge.id).inserted ? badge : nil
        }
    }

    static func grouped(_ items: [GalleryItem], origin: GalleryOrigin?, profile: UUID?) -> [GalleryItem] {
        Dictionary(grouping: items, by: \.id).values.compactMap { copies in
            guard profile == nil || copies.contains(where: { $0.profile?.id == profile }),
                  let primary = copies.first(where: { origin == nil || $0.origin == origin }) else { return nil }
            var unique = Set([primary.storageID])
            guard copies.count > 1 else { return primary }
            return GalleryItem(source: primary.source, date: copies.compactMap(\.date).first,
                               profile: copies.compactMap(\.profile).first, deviceCaptureID: primary.deviceCaptureID,
                               copies: copies.compactMap { unique.insert($0.storageID).inserted ? $0.source : nil })
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
        let names = sources.compactMap { source -> String? in
            if case .cloud(let item) = source { return item.name }
            return nil
        }
        return ([isVideo ? "Vídeo" : "Foto", displaySource, profile?.name ?? "",
                 date?.formatted(date: .long, time: .omitted) ?? ""] + storageBadges.map(\.label) + names)
            .joined(separator: " ")
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
        let message = switch source {
        case .capture: "Restaure pela Lixeira do Momentra em até 30 dias."
        case .device: "O item vai para o álbum Apagados do app Fotos, onde pode ser recuperado por até 30 dias."
        case .cloud: "O arquivo vai para a lixeira da conta \(origin.title)."
        }
        guard !copies.isEmpty else { return message }
        return "A cópia de \(displaySource) será movida. As demais continuam disponíveis. \(message)"
    }

    var canFavorite: Bool {
        if case .device(let asset) = source { return asset.canPerform(.properties) }
        return true
    }

    func isFavorite(in captures: Set<String>, cloud: Set<String>, device: [String: Bool]) -> Bool {
        if let photoIdentity {
            if captures.contains("unfavorite/" + photoIdentity) { return false }
            if captures.contains(photoIdentity) { return true }
        }
        return sources.contains { source in
            switch source {
            case .capture(let item): captures.contains(Self.captureFavoriteKey(item))
            case .device(let asset): device[asset.localIdentifier] ?? asset.isFavorite
            case .cloud(let item): cloud.contains(item.favoriteKey)
            }
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
