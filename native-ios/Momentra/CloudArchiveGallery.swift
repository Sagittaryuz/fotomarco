import ImageIO
import CoreLocation
import SwiftUI

struct CloudArchiveGallery: View {
    @ObservedObject var accounts: CloudArchiveAccounts
    let profileLookup: PhotoProfileLookup
    @ObservedObject var stampProfiles: StampProfilesStore
    let returnToCamera: () -> Void

    private enum Source: Hashable {
        case account(CloudDeliveryPlan.Destination)
        case none
    }

    @State private var requestedSource: Source = .none

    private var source: Source {
        switch requestedSource {
        case .account(let id) where accounts.accounts.contains(where: { $0.id == id }): return requestedSource
        default: return accounts.accounts.first.map { .account($0.id) } ?? .none
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Conta da nuvem", selection: Binding(get: { source }, set: { requestedSource = $0 })) {
                if accounts.accounts.isEmpty { Text("Contas conectadas").tag(Source.none) }
                ForEach(accounts.accounts) { account in
                    let service = account.id.provider == .googleDrive ? "Google Drive" : "OneDrive"
                    Text("\(service) · \(account.label)").tag(Source.account(account.id))
                }
            }
            .pickerStyle(.menu).padding(.horizontal).padding(.bottom, 8)

            switch source {
            case .account(let destination):
                ArchiveAccountGallery(destination: destination, profileLookup: profileLookup, stampProfiles: stampProfiles,
                                      returnToCamera: returnToCamera)
                    .id(destination)
            case .none:
                ContentUnavailableView("Nenhuma conta de armazenamento", systemImage: "cloud",
                    description: Text("Adicione uma conta Google Drive ou OneDrive nos Ajustes do Photomark."))
            }
        }

    }
}

fileprivate struct ArchiveGalleryPhoto: Identifiable {
    let id: String
    let name: String
    let date: Date?
    let captureID: UUID
    let isOriginal: Bool
    let profile: CaptureProfileTag?
    let thumbnailLink: String?
    let revision: String?
    let providerCaptureDate: Date?

    init?(id: String, name: String, date: Date?, thumbnailLink: String? = nil, revision: String? = nil, providerCaptureDate: Date? = nil) {
        guard let metadata = CloudArchiveFilename(name) else { return nil }
        self.id = id
        self.name = name
        self.date = metadata.capturedAt ?? providerCaptureDate ?? date
        self.captureID = metadata.captureID
        isOriginal = metadata.isOriginal
        profile = metadata.profile
        self.thumbnailLink = thumbnailLink
        self.revision = revision
        self.providerCaptureDate = providerCaptureDate
    }

    var versionLabel: String { isOriginal ? "Original" : "Com carimbo" }

    func favoriteKey(in destination: CloudDeliveryPlan.Destination) -> String {
        "\(destination.provider.rawValue)/\(destination.accountHash)/\(id)"
    }
}


struct GalleryCloudItem: Identifiable {
    struct Page {
        let items: [GalleryCloudItem]
        let nextPage: String?
        fileprivate let destination: CloudDeliveryPlan.Destination
        fileprivate let images: ArchiveGalleryImages
    }

    private let photo: ArchiveGalleryPhoto
    private let images: ArchiveGalleryImages
    let destination: CloudDeliveryPlan.Destination
    let accountLabel: String
    let trashedAt: Date?
    let canRestore: Bool

    var id: String { favoriteKey }
    var favoriteKey: String { photo.favoriteKey(in: destination) }
    var provider: CloudDeliveryPlan.Provider { destination.provider }
    var captureID: UUID { photo.captureID }
    var date: Date? { photo.date }
    var providerCaptureDate: Date? { photo.providerCaptureDate }
    var name: String { photo.name }
    var isOriginal: Bool { photo.isOriginal }

    var catalogEntry: CloudGalleryCatalog.Entry {
        .init(id: photo.id, name: photo.name, date: photo.date, revision: photo.revision)
    }

    func profileTag(lookup: PhotoProfileLookup) -> CaptureProfileTag? {
        lookup.captures[captureID] ?? photo.profile
    }

    func captureDate(lookup: PhotoProfileLookup) -> Date? {
        lookup.dates[captureID] ?? date
    }

    @MainActor func mapLocation() async throws -> CLLocationCoordinate2D? {
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        if provider == .googleDrive { return try await images.drive.mapLocation(id: photo.id, accessToken: token) }
        return try await OneDriveArchive().mapLocation(id: photo.id, accessToken: token)
    }

    @MainActor func renameForCaptureDate(_ date: Date) async throws {
        guard let updated = CloudArchiveFilename.renamed(name, provider: provider, timeZone: .current, knownCaptureDate: date) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard updated != name else { return }
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        if provider == .googleDrive { try await images.drive.renamePhoto(id: photo.id, from: name, to: updated, accessToken: token) }
        else { try await OneDriveArchive().renamePhoto(id: photo.id, from: name, to: updated, accessToken: token) }
        await CloudGalleryCatalog.shared.invalidate(destination)
    }

    @MainActor
    func thumb() -> some View {
        ArchiveGalleryImage(photo: photo, images: images)
    }

    @MainActor func mapThumb() -> some View {
        ArchiveMapThumbnail(photo: photo, images: images)
    }

    @MainActor
    func fullImage(active: Bool = true) -> some View {
        ArchiveGalleryImage(photo: photo, images: images, fullView: true, active: active)
    }

    @MainActor
    func load() async throws -> PhotoEditorInput {
        try await images.editorInput(photo)
    }

    @MainActor
    func copy(to directory: URL) async throws -> URL {
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        return try await images.copy(photo, to: directory, accessToken: token)
    }

    @MainActor
    func moveToTrash() async throws {
        let journal = try CloudArchiveJournal.documents()
        guard !journal.hasPendingDelivery(id: captureID) else { throw GalleryError.pendingDelivery }
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        try await images.trash(photo, accessToken: token)
        await CloudGalleryCatalog.shared.invalidate(destination, removing: photo.id)
    }

    @MainActor
    func restore() async throws {
        guard canRestore else { throw GalleryError.providerRestore }
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        try await images.drive.restorePhoto(id: photo.id, name: photo.name, accessToken: token)
        await CloudGalleryCatalog.shared.invalidate(destination)
    }

    private enum GalleryError: LocalizedError {
        case pendingDelivery, providerRestore

        var errorDescription: String? {
            switch self {
            case .pendingDelivery:
                return "A foto tem um envio pendente. Aguarde a conclusão antes de movê-la para a lixeira."
            case .providerRestore:
                return "Abra a lixeira do provedor para recuperar esse arquivo."
            }
        }
    }

    @MainActor
    static func load(for account: CloudArchiveAccounts.Account, pageToken: String? = nil,
                     reusing previousPage: Page? = nil) async throws -> Page {
        let images = imageLoader(for: account, previousPage: previousPage)
        let page = try await images.list(pageToken: pageToken)
        return Page(items: page.items.map {
            GalleryCloudItem(photo: $0, images: images, destination: account.id, accountLabel: account.label,
                             trashedAt: nil, canRestore: false)
        }, nextPage: page.nextPage, destination: account.id, images: images)
    }

    @MainActor
    static func cachedPage(_ entries: [CloudGalleryCatalog.Entry], for account: CloudArchiveAccounts.Account,
                           reusing previousPage: Page? = nil) -> Page {
        let images = imageLoader(for: account, previousPage: previousPage)
        let items = entries.compactMap { entry -> GalleryCloudItem? in
            guard let photo = ArchiveGalleryPhoto(id: entry.id, name: entry.name, date: entry.date,
                                                  revision: entry.revision) else { return nil }
            return GalleryCloudItem(photo: photo, images: images, destination: account.id, accountLabel: account.label,
                                    trashedAt: nil, canRestore: false)
        }
        return Page(items: items, nextPage: nil, destination: account.id, images: images)
    }

    @MainActor
    static func loadTrash(for account: CloudArchiveAccounts.Account, pageToken: String? = nil,
                          reusing previousPage: Page? = nil) async throws -> Page {
        let images = imageLoader(for: account, previousPage: previousPage)
        guard account.id.provider == .googleDrive else {
            return Page(items: [], nextPage: nil, destination: account.id, images: images)
        }
        let token = try await CloudArchiveAccounts.shared.accessToken(for: account.id)
        let result = try await images.drive.listTrash(pageToken: pageToken, accessToken: token)
        let items = result.files.compactMap { item -> GalleryCloudItem? in
            guard let photo = ArchiveGalleryImages.googlePhoto(item, trashed: true) else { return nil }
            return GalleryCloudItem(photo: photo, images: images, destination: account.id, accountLabel: account.label,
                                    trashedAt: ArchiveGalleryImages.parseDate(item.trashedTime),
                                    canRestore: item.capabilities?.canUntrash == true)
        }
        return Page(items: items, nextPage: result.nextPageToken == pageToken ? nil : result.nextPageToken,
                    destination: account.id, images: images)
    }

    @MainActor
    private static func imageLoader(for account: CloudArchiveAccounts.Account, previousPage: Page?) -> ArchiveGalleryImages {
        if let previousPage, previousPage.destination == account.id { return previousPage.images }
        return ArchiveGalleryImages(destination: account.id)
    }
}

private struct ArchiveAccountGallery: View {
    private struct ListRequest: Equatable {
        let id = UUID()
        let pageToken: String?
    }

    let destination: CloudDeliveryPlan.Destination
    let profileLookup: PhotoProfileLookup
    @ObservedObject var stampProfiles: StampProfilesStore
    let returnToCamera: () -> Void
    @StateObject private var images: ArchiveGalleryImages
    @State private var photos: [ArchiveGalleryPhoto] = []
    @State private var nextPage: String?
    @State private var request = ListRequest(pageToken: nil)
    @State private var loaded = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var columns = 3
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var openPhoto: ArchiveGalleryPhoto?
    @State private var leavingForCamera = false
    @State private var quickShare: ArchiveGalleryPhoto?
    @State private var showingSelection = false
    @State private var confirmingDelete = false
    @State private var actionInProgress = false
    @State private var share: GalleryShareBatch?
    @State private var actionError: String?

    init(destination: CloudDeliveryPlan.Destination, profileLookup: PhotoProfileLookup,
         stampProfiles: StampProfilesStore, returnToCamera: @escaping () -> Void) {
        self.destination = destination
        self.profileLookup = profileLookup
        self.stampProfiles = stampProfiles
        self.returnToCamera = returnToCamera
        _images = StateObject(wrappedValue: ArchiveGalleryImages(destination: destination))
    }

    private var groups: [GalleryGroup<ArchiveGalleryPhoto>] {
        GalleryGrouping.groups(photos, date: date, profile: { photo in
            guard let tag = profileLookup.captures[photo.captureID] ?? photo.profile else { return nil }
            let liveProfile = stampProfiles.profiles.first { $0.id == tag.id }
            return CaptureProfileTag(id: tag.id, name: liveProfile?.name ?? tag.name)
        })
    }

    private func date(_ photo: ArchiveGalleryPhoto) -> Date? {
        profileLookup.dates[photo.captureID] ?? photo.date
    }

    var body: some View {
        let currentRequest = request
        VStack(spacing: 0) {
            if busy && photos.isEmpty {
                ProgressView("Carregando fotos…").frame(maxHeight: .infinity)
            } else if loaded && photos.isEmpty && nextPage == nil && errorMessage == nil {
                ContentUnavailableView("Nenhuma foto do Photomark", systemImage: "photo.on.rectangle")
            } else if !photos.isEmpty {
                GalleryGrid(groups: groups, selecting: $selecting, selected: $selectedIDs, columns: $columns,
                            refreshKey: images.revision.hashValue, tile: { photo in
                    ArchiveGalleryImage(photo: photo, images: images)
                        .overlay(alignment: .bottomLeading) {
                            if photo.isOriginal {
                                Text(photo.versionLabel).font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(4).background(.black.opacity(0.7), in: Capsule()).padding(4)
                            }
                        }
                        .accessibilityLabel(photo.versionLabel)
                }, open: { openPhoto = $0 }, longPress: { quickShare = $0 })
            } else {
                Spacer(minLength: 0)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }

            if selecting {
                GallerySelectionBar(count: selectedIDs.count, busy: busy || actionInProgress,
                                    review: { showingSelection = true }, delete: { confirmingDelete = true }) {
                    Button(action: shareSelection) { GalleryShareIcon() }
                }
            } else {
                HStack {
                    Button(errorMessage == nil ? "Atualizar" : "Tentar novamente") {
                        request = ListRequest(pageToken: errorMessage == nil ? nil : request.pageToken)
                    }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    if let nextPage {
                        Button("Carregar mais") { request = ListRequest(pageToken: nextPage) }
                    }
                }
                .disabled(busy || actionInProgress).font(.footnote).padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(selecting ? "Cancelar" : "Selecionar") {
                    selecting.toggle()
                    if !selecting { selectedIDs.removeAll() }
                }
                .disabled(actionInProgress || (!selecting && photos.isEmpty))
            }
            if selecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Selecionar exibidas") { selectedIDs = Set(photos.map(\.id)) }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Opções da seleção")
                    .disabled(actionInProgress)
                }
            }
        }
        .task(id: currentRequest) { await load(currentRequest) }
        .fullScreenCover(item: $openPhoto, onDismiss: {
            if leavingForCamera {
                leavingForCamera = false
                returnToCamera()
            }
        }) { photo in
            ArchiveGalleryPager(items: groups.flatMap(\.items), initialID: photo.id, images: images,
                                stampProfiles: stampProfiles.profiles, destination: destination,
                                returnToCamera: { leavingForCamera = true; openPhoto = nil },
                                didTrash: { id in
                photos.removeAll { $0.id == id }
                selectedIDs.remove(id)
                request = ListRequest(pageToken: nil)
            })
        }
        .fullScreenCover(item: $quickShare) { photo in
            GalleryQuickShare(load: { try await images.editorInput(photo) })
        }
        .sheet(isPresented: $showingSelection) {
            GallerySelectionSheet(items: photos, selected: $selectedIDs) { ArchiveGalleryImage(photo: $0, images: images) }
        }
        .sheet(item: $share) { batch in
            batch.sheet {
                selecting = false
                selectedIDs.removeAll()
            }
        }
        .confirmationDialog("Excluir as fotos selecionadas?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Excluir \(selectedIDs.count) itens", role: .destructive, action: deleteSelection)
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Os arquivos vão para a lixeira desta conta. As outras cópias ficam disponíveis.") }
        .alert("Photomark", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func shareSelection() {
        let items = photos.filter { selectedIDs.contains($0.id) }
        guard !items.isEmpty, !actionInProgress else { return }
        actionInProgress = true
        Task {
            defer { actionInProgress = false }
            do {
                let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
                share = try await GalleryShareBatch.prepare(items) { photo, directory in
                    try await images.copy(photo, to: directory, accessToken: token)
                }
            } catch { actionError = "Não foi possível baixar todos os arquivos selecionados para compartilhar." }
        }
    }

    private func deleteSelection() {
        let items = photos.filter { selectedIDs.contains($0.id) }
        guard !items.isEmpty, !actionInProgress else { return }
        actionInProgress = true
        Task {
            defer { actionInProgress = false }
            do {
                let journal = try CloudArchiveJournal.documents()
                let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
                var removed: Set<String> = []
                for photo in items where !journal.hasPendingDelivery(id: photo.captureID) {
                    do {
                        try await images.trash(photo, accessToken: token)
                        removed.insert(photo.id)
                    } catch { continue }
                }
                if !removed.isEmpty {
                    photos.removeAll { removed.contains($0.id) }
                    selecting = false
                    selectedIDs.removeAll()
                    request = ListRequest(pageToken: nil)
                }
                if removed.count != items.count {
                    actionError = "Nem todos os arquivos foram movidos para a lixeira. Confira o acesso à conta e se há envios pendentes."
                }
            } catch { actionError = error.localizedDescription }
        }
    }

    private func load(_ current: ListRequest) async {
        guard !Task.isCancelled, current == request else { return }
        busy = true
        errorMessage = nil
        defer { if current == request { busy = false } }
        do {
            let page = try await images.list(pageToken: current.pageToken)
            try Task.checkCancellation()
            guard current == request else { return }
            let existing = current.pageToken == nil ? [] : photos
            var ids = Set(existing.map(\.id))
            photos = (existing + page.items.filter { ids.insert($0.id).inserted }).sorted { left, right in
                let leftDate = date(left) ?? .distantPast
                let rightDate = date(right) ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                if left.captureID != right.captureID { return left.captureID.uuidString < right.captureID.uuidString }
                if left.isOriginal != right.isOriginal { return !left.isOriginal }
                return left.id < right.id
            }
            selectedIDs.formIntersection(ids)
            nextPage = page.nextPage == current.pageToken ? nil : page.nextPage
            loaded = true
            if current.pageToken == nil { images.clear() }
        } catch {
            guard !Task.isCancelled, current == request else { return }
            if let failure = error as? GoogleDriveArchive.ArchiveError { errorMessage = failure.errorDescription }
            else if let failure = error as? OneDriveArchive.Failure { errorMessage = failure.errorDescription }
            else if let failure = error as? CloudArchiveOAuth.Failure { errorMessage = failure.errorDescription }
            else { errorMessage = "Não foi possível abrir a conta. Confira a conexão e tente novamente." }
        }
    }
}

@MainActor
fileprivate final class ArchiveGalleryImages: ObservableObject {
    let drive = GoogleDriveArchive()
    let destination: CloudDeliveryPlan.Destination
    private let cache = NSCache<NSString, UIImage>()
    private var activeDownloads = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var revision = UUID()

    init(destination: CloudDeliveryPlan.Destination) {
        self.destination = destination
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func list(pageToken: String?) async throws -> (items: [ArchiveGalleryPhoto], nextPage: String?) {
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        let page: (items: [ArchiveGalleryPhoto], nextPage: String?)
        switch destination.provider {
        case .googleDrive:
            let result = try await drive.list(pageToken: pageToken, accessToken: token)
            page = (result.files.compactMap { Self.googlePhoto($0, trashed: false) }, result.nextPageToken)
        case .oneDrive:
            let result = try await OneDriveArchive().list(accessToken: token, nextPage: pageToken)
            page = (result.items.compactMap { ArchiveGalleryPhoto(id: $0.id, name: $0.name, date: $0.date, revision: $0.revision, providerCaptureDate: $0.captureDate) },
                    result.nextPage)
        }
        try Task.checkCancellation()
        return (page.items, page.nextPage == pageToken ? nil : page.nextPage)
    }

    static func googlePhoto(_ item: GoogleDriveArchive.Item, trashed: Bool) -> ArchiveGalleryPhoto? {
        guard item.mimeType.hasPrefix("image/"), item.appProperties?["momentraArchivePhoto"] == "1",
              item.trashed == trashed else { return nil }
        return ArchiveGalleryPhoto(id: item.id, name: item.name, date: parseDate(item.createdTime),
                                   thumbnailLink: item.thumbnailLink, revision: item.version)
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    func clear() {
        cache.removeAllObjects()
        revision = UUID()
    }

    func download(_ photo: ArchiveGalleryPhoto, accessToken: String) async throws -> URL {
        switch destination.provider {
        case .googleDrive: try await drive.downloadFile(id: photo.id, accessToken: accessToken)
        case .oneDrive: try await OneDriveArchive().download(id: photo.id, accessToken: accessToken)
        }
    }

    func copy(_ photo: ArchiveGalleryPhoto, to directory: URL, accessToken: String) async throws -> URL {
        let downloaded = try await download(photo, accessToken: accessToken)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        let target = directory.appendingPathComponent(photo.name)
        try FileManager.default.moveItem(at: downloaded, to: target)
        return target
    }

    func trash(_ photo: ArchiveGalleryPhoto, accessToken: String) async throws {
        switch destination.provider {
        case .googleDrive: try await drive.trashPhoto(id: photo.id, name: photo.name, accessToken: accessToken)
        case .oneDrive: try await OneDriveArchive().trashPhoto(id: photo.id, name: photo.name, accessToken: accessToken)
        }
    }

    func editorInput(_ photo: ArchiveGalleryPhoto) async throws -> PhotoEditorInput {
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        let downloaded = try await download(photo, accessToken: token)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        let suffix = (photo.name as NSString).pathExtension
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(suffix)
        try FileManager.default.moveItem(at: downloaded, to: file)
        return PhotoEditorInput(url: file, temporary: true)
    }

    private static let gridPixels = 320

    func image(_ photo: ArchiveGalleryPhoto, maximumPixels: Int) async throws -> UIImage {
        if maximumPixels <= Self.gridPixels {
            if let key = persistentThumbnailKey(photo) {
                let bitmap = try await GalleryThumbnailCache.shared.image(for: key, maximumPixels: maximumPixels) {
                    try await self.acquireGridPreview(photo, pixels: maximumPixels)
                }
                try Task.checkCancellation()
                guard let bitmap else { throw CocoaError(.fileReadCorruptFile) }
                return UIImage(cgImage: bitmap)
            }

            // Older responses sometimes omit the revision. Keep those previews in
            // this loader's memory only, and never share them across accounts.
            let version = revision
            let key = thumbnailMemoryKey(photo, pixels: maximumPixels, version: version)
            if let cached = cache.object(forKey: key) { return cached }
            await acquireDownload()
            defer { releaseDownload() }
            try Task.checkCancellation()
            if let cached = cache.object(forKey: key) { return cached }
            let bitmap = try await gridPreview(photo, pixels: maximumPixels)
            let image = UIImage(cgImage: bitmap)
            if revision == version { cache.setObject(image, forKey: key, cost: bitmap.bytesPerRow * bitmap.height) }
            return image
        }

        if let key = persistentThumbnailKey(photo) {
            let bitmap = try await GalleryThumbnailCache.viewer.image(for: key, maximumPixels: maximumPixels) {
                try await self.acquireFullPreview(photo, pixels: maximumPixels)
            }
            guard let bitmap else { throw CocoaError(.fileReadCorruptFile) }
            return UIImage(cgImage: bitmap)
        }
        return UIImage(cgImage: try await acquireFullPreview(photo, pixels: maximumPixels))
    }

    func cachedGridImage(_ photo: ArchiveGalleryPhoto) async -> UIImage? {
        if let key = persistentThumbnailKey(photo),
           let bitmap = await GalleryThumbnailCache.shared.cachedImage(for: key, maximumPixels: Self.gridPixels) {
            return UIImage(cgImage: bitmap)
        }
        if let cached = cache.object(forKey: thumbnailMemoryKey(photo, pixels: Self.gridPixels, version: revision)) {
            return cached
        }
        return await offlineGridPreview(photo, pixels: 640).map { UIImage(cgImage: $0) }
    }

    func mapThumbnail(_ photo: ArchiveGalleryPhoto) async -> UIImage? {
        if let cached = await cachedGridImage(photo) { return cached }
        if let key = persistentThumbnailKey(photo) {
            guard let bitmap = try? await GalleryThumbnailCache.shared.image(for: key, maximumPixels: Self.gridPixels,
                generate: { try await self.strictMapImage(photo) }) else { return nil }
            return UIImage(cgImage: bitmap)
        }
        guard let bitmap = try? await strictMapImage(photo) else { return nil }
        let result = UIImage(cgImage: bitmap)
        cache.setObject(result, forKey: thumbnailMemoryKey(photo, pixels: Self.gridPixels, version: revision))
        return result
    }

    private func strictMapImage(_ photo: ArchiveGalleryPhoto) async throws -> CGImage? {
        guard let token = try? await CloudArchiveAccounts.shared.accessToken(for: destination) else { return nil }
        let bytes: Data?
        if destination.provider == .googleDrive { bytes = try? await googleThumbnail(photo, token: token) }
        else { bytes = try? await OneDriveArchive().thumbnail(id: photo.id, accessToken: token) }
        guard let bytes,
              let bitmap = await Task.detached(priority: .utility, operation: {
                  Self.downsample(CGImageSourceCreateWithData(bytes as CFData, nil), pixels: Self.gridPixels)
              }).value else { return nil }
        return bitmap
    }

    private func acquireFullPreview(_ photo: ArchiveGalleryPhoto, pixels: Int) async throws -> CGImage {
        await acquireDownload(priority: true)
        defer { releaseDownload() }
        try Task.checkCancellation()
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        return try await originalPreview(photo, pixels: pixels, token: token)
    }

    private func persistentThumbnailKey(_ photo: ArchiveGalleryPhoto) -> String? {
        guard let revision = photo.revision, !revision.isEmpty else { return nil }
        return "cloud/\(photo.favoriteKey(in: destination))/\(revision)"
    }

    private func thumbnailMemoryKey(_ photo: ArchiveGalleryPhoto, pixels: Int, version: UUID) -> NSString {
        "\(version.uuidString):\(photo.id):\(pixels)" as NSString
    }

    private func acquireGridPreview(_ photo: ArchiveGalleryPhoto, pixels: Int) async throws -> CGImage {
        await acquireDownload()
        defer { releaseDownload() }
        try Task.checkCancellation()
        return try await gridPreview(photo, pixels: pixels)
    }

    private func offlineGridPreview(_ photo: ArchiveGalleryPhoto, pixels: Int) async -> CGImage? {
        guard !photo.isOriginal else { return nil }
        // Successful deliveries already leave a stamped thumbnail on this iPhone.
        let captureID = photo.captureID
        return await Task.detached(priority: .utility) {
            guard let root = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false) else { return nil as CGImage? }
            let file = root.appendingPathComponent("CloudThumbnails", isDirectory: true)
                .appendingPathComponent(captureID.uuidString).appendingPathExtension("jpg")
            let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes?.isRegularFile == true, attributes?.isSymbolicLink != true,
                  let size = attributes?.fileSize, (1...2_000_000).contains(size) else { return nil }
            let source = CGImageSourceCreateWithURL(file as CFURL, nil)
            return Self.downsample(source, pixels: pixels)
        }.value
    }

    private func gridPreview(_ photo: ArchiveGalleryPhoto, pixels: Int) async throws -> CGImage {
        if let offline = await offlineGridPreview(photo, pixels: pixels) { return offline }
        try Task.checkCancellation()
        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        if destination.provider == .googleDrive,
           let thumbnail = try await googleThumbnail(photo, token: token) {
            let bitmap = await Task.detached(priority: .utility) {
                Self.downsample(CGImageSourceCreateWithData(thumbnail as CFData, nil), pixels: pixels)
            }.value
            try Task.checkCancellation()
            guard let bitmap else { throw CocoaError(.fileReadCorruptFile) }
            return bitmap
        }

        return try await originalPreview(photo, pixels: pixels, token: token)
    }

    private func googleThumbnail(_ photo: ArchiveGalleryPhoto, token: String) async throws -> Data? {
        if let link = photo.thumbnailLink, let thumbnail = try await drive.thumbnail(link: link, accessToken: token) {
            return thumbnail
        }
        guard let link = try await drive.thumbnailLink(id: photo.id, accessToken: token) else { return nil }
        return try await drive.thumbnail(link: link, accessToken: token)
    }

    private func originalPreview(_ photo: ArchiveGalleryPhoto, pixels: Int, token: String) async throws -> CGImage {
        let file = try await download(photo, accessToken: token)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        let bitmap = await Task.detached(priority: .utility) {
            Self.downsample(CGImageSourceCreateWithURL(file as CFURL, nil), pixels: pixels)
        }.value
        try Task.checkCancellation()
        guard let bitmap else { throw CocoaError(.fileReadCorruptFile) }
        return bitmap
    }

    nonisolated private static func downsample(_ source: CGImageSource?, pixels: Int) -> CGImage? {
        guard let source else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels
        ] as CFDictionary)
    }

    private func acquireDownload(priority: Bool = false) async {
        if activeDownloads < 3 {
            activeDownloads += 1
        } else {
            await withCheckedContinuation { continuation in
                if priority { waiting.insert(continuation, at: 0) }
                else { waiting.append(continuation) }
            }
        }
    }

    private func releaseDownload() {
        if waiting.isEmpty { activeDownloads -= 1 }
        else { waiting.removeFirst().resume() }
    }
}

private struct ArchiveMapThumbnail: View {
    let photo: ArchiveGalleryPhoto
    let images: ArchiveGalleryImages
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Color.gray.opacity(0.25).overlay(Image(systemName: "photo").foregroundStyle(.white)) }
        }
        .task(id: photo.id) { image = await images.mapThumbnail(photo) }
    }
}

private struct ArchiveGalleryImage: View {
    let photo: ArchiveGalleryPhoto
    let images: ArchiveGalleryImages
    var fullView = false
    var active = true
    @State private var loaded: (key: String, image: UIImage)?
    @State private var failed = false
    @State private var retry = UUID()

    var body: some View {
        let key = photo.favoriteKey(in: images.destination)
        GeometryReader { proxy in
            ZStack {
                Color.secondary.opacity(0.15)
                if let loaded, loaded.key == key {
                    Image(uiImage: loaded.image).resizable()
                        .aspectRatio(contentMode: fullView ? .fit : .fill)
                        .accessibilityLabel(fullView ? "Imagem" : "Miniatura disponível")
                } else if fullView {
                    if failed && active {
                        Button("Tentar abrir novamente") { retry = UUID() }.buttonStyle(.bordered)
                    } else if active {
                        ProgressView()
                    }
                } else {
                    Image(systemName: failed ? "exclamationmark.circle" : "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(failed ? "Miniatura indisponível" : "Miniatura pendente")
                }
            }
            .frame(width: proxy.size.width, height: fullView ? proxy.size.height : proxy.size.width)
            .clipped()
        }
        .aspectRatio(fullView ? nil : 1, contentMode: .fit)
        .task(id: "\(images.revision):\(key):\(photo.revision ?? ""):\(retry):\(active)") {
            failed = false
            if fullView || loaded?.key != key { loaded = nil }
            guard !fullView || active else { return }
            if fullView, let thumbnail = await images.cachedGridImage(photo), !Task.isCancelled {
                loaded = (key, thumbnail)
            }
            do {
                let preview = try await images.image(photo, maximumPixels: fullView ? 1800 : 320)
                guard !Task.isCancelled else { return }
                loaded = (key, preview)
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct ArchiveGalleryPager: View {
    private enum Panel: String, Identifiable {
        case overview, share, information, editing
        var id: Self { self }
    }

    let images: ArchiveGalleryImages
    let stampProfiles: [StampProfile]
    let destination: CloudDeliveryPlan.Destination
    let returnToCamera: () -> Void
    let didTrash: (String) -> Void
    @AppStorage("native.gallery.favoriteCloudKeys") private var storedFavorites = Data()
    @State private var items: [ArchiveGalleryPhoto]
    @State private var selection: String
    @State private var panel: Panel?
    @State private var updating = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    init(items: [ArchiveGalleryPhoto], initialID: String, images: ArchiveGalleryImages, stampProfiles: [StampProfile],
         destination: CloudDeliveryPlan.Destination, returnToCamera: @escaping () -> Void,
         didTrash: @escaping (String) -> Void) {
        self.images = images
        self.stampProfiles = stampProfiles
        self.destination = destination
        self.returnToCamera = returnToCamera
        self.didTrash = didTrash
        _items = State(initialValue: items)
        _selection = State(initialValue: initialID)
    }

    private var provider: String { destination.provider == .googleDrive ? "Google Drive" : "OneDrive" }

    var body: some View {
        let index = items.firstIndex { $0.id == selection }
        let current = index.map { items[$0] }
        VStack(spacing: 0) {
            GalleryDetailHeader(date: current?.date, position: (index ?? 0) + 1,
                                count: items.count, close: { dismiss() }, overview: { panel = .overview }) {
                if current != nil {
                    Menu {
                        Button("Informações da foto", systemImage: "info.circle") { panel = .information }
                        Button("Editar ou adicionar carimbo", systemImage: "slider.horizontal.3") { panel = .editing }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44).modifier(GalleryControlSurface())
                    }.accessibilityLabel("Mais opções")
                }
            }
            TabView(selection: $selection) {
                ForEach(items) { photo in
                    Group {
                        if photo.id == selection {
                            ArchiveGalleryImage(photo: photo, images: images, fullView: true)
                        } else {
                            Color.clear
                        }
                    }.tag(photo.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            GalleryFilmstrip(items: items, selection: $selection) { photo in
                ArchiveGalleryImage(photo: photo, images: images)
            }
            if let current { controls(current) }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .modifier(GalleryCameraSwipe(action: { if !updating { returnToCamera() } }))
        .sheet(item: $panel) { route in
            if let current { sheet(route, current: current) }
        }
        .alert("Photomark", isPresented: Binding(get: { message != nil && panel == nil },
                                                set: { if !$0 && panel == nil { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func controls(_ photo: ArchiveGalleryPhoto) -> some View {
        let favorite = favorites.contains(favoriteKey(photo))
        return HStack(spacing: 10) {
            Button { panel = .share } label: { GalleryShareIcon() }
                .accessibilityLabel("Compartilhar")
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                button(favorite ? "heart.fill" : "heart",
                       label: favorite ? "Remover dos favoritos" : "Favoritar",
                       tint: favorite ? .yellow : .primary) { toggleFavorite(photo) }
                button("info.circle", label: "Informações") { panel = .information }
                button("slider.horizontal.3", label: "Editar foto") { panel = .editing }
            }
            .padding(.horizontal, 3)
            .modifier(GalleryControlSurface())
            Spacer(minLength: 4)
            GalleryTrashButton(label: "Excluir foto",
                               message: "A foto vai para a lixeira desta conta do \(provider). Você pode recuperá-la por lá.") {
                trash(photo)
            }
        }
        .disabled(updating)
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 7)
    }

    private func button(_ icon: String, label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.accessibilityLabel(label)
    }

    @ViewBuilder
    private func sheet(_ route: Panel, current: ArchiveGalleryPhoto) -> some View {
        switch route {
        case .overview:
            GalleryDetailGrid(items: items, choose: {
                selection = $0.id
                panel = nil
            }) { ArchiveGalleryImage(photo: $0, images: images) }
        case .share:
            GalleryShareComposer(items: items, current: current, copy: { photo, directory in
                let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
                return try await images.copy(photo, to: directory, accessToken: token)
            }, onSuccess: { panel = nil }) { ArchiveGalleryImage(photo: $0, images: images) }
        case .information:
            NavigationStack {
                Form {
                    LabeledContent("Origem", value: provider)
                    LabeledContent("Versão", value: current.versionLabel)
                    if let date = current.date {
                        LabeledContent("Data", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let profile = current.profile, !profile.name.isEmpty {
                        LabeledContent("Perfil", value: profile.name)
                    }
                }
                .navigationTitle("Informações")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Concluído") { panel = nil } }
            }
        case .editing:
            MomentraPhotoEditor(load: { try await images.editorInput(current) }, date: current.date,
                                profile: current.profile, stampProfiles: stampProfiles) { _ in message = "Cópia salva em Capturas." }
        }
    }

    private var favorites: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: storedFavorites)) ?? []
    }

    private func favoriteKey(_ photo: ArchiveGalleryPhoto) -> String {
        photo.favoriteKey(in: destination)
    }

    private func toggleFavorite(_ photo: ArchiveGalleryPhoto) {
        var keys = favorites
        let key = favoriteKey(photo)
        if !keys.insert(key).inserted { keys.remove(key) }
        if let data = try? JSONEncoder().encode(keys) { storedFavorites = data }
    }

    private func trash(_ photo: ArchiveGalleryPhoto) {
        guard !updating else { return }
        updating = true
        Task {
            defer { updating = false }
            do {
                let journal = try CloudArchiveJournal.documents()
                let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
                guard !journal.hasPendingDelivery(id: photo.captureID) else {
                    message = "A foto tem um envio pendente. Aguarde a conclusão antes de movê-la para a lixeira."
                    return
                }
                try await images.trash(photo, accessToken: token)
                didTrash(photo.id)
                if let index = items.firstIndex(where: { $0.id == photo.id }) {
                    items.remove(at: index)
                    if items.isEmpty { dismiss() }
                    else if selection == photo.id { selection = items[min(index, items.count - 1)].id }
                }
            } catch { message = "Não foi possível mover a foto para a lixeira do \(provider)." }
        }
    }
}
