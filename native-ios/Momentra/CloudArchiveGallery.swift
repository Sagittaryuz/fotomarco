import ImageIO
import SwiftUI

struct CloudArchiveGallery: View {
    @ObservedObject var accounts: CloudArchiveAccounts
    @ObservedObject var googlePhotos: GooglePhotosManager
    @ObservedObject var picker: GooglePickerFlow
    let profileLookup: PhotoProfileLookup
    @ObservedObject var stampProfiles: StampProfilesStore

    private enum Source: Hashable {
        case account(CloudDeliveryPlan.Destination)
        case legacy
        case none
    }

    @State private var requestedSource: Source = .none

    private var source: Source {
        switch requestedSource {
        case .legacy: return .legacy
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
                Text("Google Fotos · arquivo anterior").tag(Source.legacy)
            }
            .pickerStyle(.menu).padding(.horizontal).padding(.bottom, 8)

            switch source {
            case .account(let destination):
                ArchiveAccountGallery(destination: destination, profileLookup: profileLookup, stampProfiles: stampProfiles)
                    .id(destination)
            case .legacy:
                GalleryStorageSummary(cloud: true)
                CloudPhotoGallery(googlePhotos: googlePhotos, picker: picker,
                                  profileLookup: profileLookup, stampProfiles: stampProfiles)
            case .none:
                ContentUnavailableView("Nenhuma conta de armazenamento", systemImage: "cloud",
                    description: Text("Adicione uma conta Google Drive ou OneDrive nos Ajustes do Momentra."))
            }
        }
        .onChange(of: source) { previous, _ in
            if previous == .legacy { picker.cancel() }
        }
    }
}

private struct ArchiveGalleryPhoto: Identifiable {
    let id: String
    let name: String
    let date: Date?
    let captureID: UUID
    let isOriginal: Bool
    let profile: CaptureProfileTag?

    init?(id: String, name: String, date: Date?) {
        guard let metadata = CloudArchiveFilename(name) else { return nil }
        self.id = id
        self.name = name
        self.date = metadata.capturedAt ?? date
        self.captureID = metadata.captureID
        isOriginal = metadata.isOriginal
        profile = metadata.profile
    }

    var versionLabel: String { isOriginal ? "Original" : "Com carimbo" }
}

private struct ArchiveAccountGallery: View {
    private struct ListRequest: Equatable {
        let id = UUID()
        let pageToken: String?
    }

    let destination: CloudDeliveryPlan.Destination
    let profileLookup: PhotoProfileLookup
    @ObservedObject var stampProfiles: StampProfilesStore
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

    init(destination: CloudDeliveryPlan.Destination, profileLookup: PhotoProfileLookup,
         stampProfiles: StampProfilesStore) {
        self.destination = destination
        self.profileLookup = profileLookup
        self.stampProfiles = stampProfiles
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
                ContentUnavailableView("Nenhuma foto do Momentra", systemImage: "photo.on.rectangle")
            } else if !photos.isEmpty {
                GalleryGrid(groups: groups, selecting: $selecting, selected: $selectedIDs, columns: $columns,
                            refreshKey: images.revision.hashValue) { photo in
                    ArchiveGalleryImage(photo: photo, images: images)
                        .overlay(alignment: .bottomLeading) {
                            if photo.isOriginal {
                                Text(photo.versionLabel).font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(4).background(.black.opacity(0.7), in: Capsule()).padding(4)
                            }
                        }
                        .accessibilityLabel(photo.versionLabel)
                } open: { openPhoto = $0 }
            } else {
                Spacer(minLength: 0)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }

            HStack {
                if selecting {
                    Text("\(selectedIDs.count) selecionada(s)")
                    Spacer()
                    Button("Selecionar exibidas") { selectedIDs = Set(photos.map(\.id)) }
                } else {
                    Button(errorMessage == nil ? "Atualizar" : "Tentar novamente") {
                        request = ListRequest(pageToken: errorMessage == nil ? nil : request.pageToken)
                    }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    if let nextPage {
                        Button("Carregar mais") { request = ListRequest(pageToken: nextPage) }
                    }
                }
            }
            .disabled(busy).font(.footnote).padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(selecting ? "Cancelar" : "Selecionar") {
                    selecting.toggle()
                    if !selecting { selectedIDs.removeAll() }
                }
                .disabled(photos.isEmpty)
            }
        }
        .task(id: currentRequest) { await load(currentRequest) }
        .sheet(item: $openPhoto) { photo in
            ArchiveGalleryPager(items: groups.flatMap(\.items), initialID: photo.id, images: images)
        }
    }

    private func load(_ current: ListRequest) async {
        guard !Task.isCancelled, current == request else { return }
        busy = true
        errorMessage = nil
        defer { if current == request { busy = false } }
        do {
            let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
            let page: (items: [ArchiveGalleryPhoto], nextPage: String?)
            switch destination.provider {
            case .googleDrive:
                let result = try await images.drive.list(pageToken: current.pageToken, accessToken: token)
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let standard = ISO8601DateFormatter()
                page = (result.files.compactMap { item in
                    guard item.mimeType.hasPrefix("image/"), item.appProperties?["momentraArchivePhoto"] == "1",
                          item.trashed == false else { return nil }
                    let date = item.createdTime.flatMap { fractional.date(from: $0) ?? standard.date(from: $0) }
                    return ArchiveGalleryPhoto(id: item.id, name: item.name, date: date)
                }, result.nextPageToken)
            case .oneDrive:
                let result = try await OneDriveArchive().list(accessToken: token, nextPage: current.pageToken)
                page = (result.items.compactMap { ArchiveGalleryPhoto(id: $0.id, name: $0.name, date: $0.date) },
                        result.nextPage)
            }
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
private final class ArchiveGalleryImages: ObservableObject {
    let drive = GoogleDriveArchive()
    private let destination: CloudDeliveryPlan.Destination
    private let cache = NSCache<NSString, UIImage>()
    private var activeDownloads = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var revision = UUID()

    init(destination: CloudDeliveryPlan.Destination) {
        self.destination = destination
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func clear() {
        cache.removeAllObjects()
        revision = UUID()
    }

    func image(_ photo: ArchiveGalleryPhoto, maximumPixels: Int) async throws -> UIImage {
        let version = revision
        let key = "\(version.uuidString):\(photo.id):\(maximumPixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        await acquireDownload()
        defer { releaseDownload() }
        try Task.checkCancellation()
        if let cached = cache.object(forKey: key) { return cached }

        let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
        let file: URL
        switch destination.provider {
        case .googleDrive: file = try await drive.downloadFile(id: photo.id, accessToken: token)
        case .oneDrive: file = try await OneDriveArchive().download(id: photo.id, accessToken: token)
        }
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        let bitmap = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixels
            ] as CFDictionary)
        }.value
        try Task.checkCancellation()
        guard let bitmap else { throw CocoaError(.fileReadCorruptFile) }
        let image = UIImage(cgImage: bitmap)
        if revision == version { cache.setObject(image, forKey: key, cost: bitmap.bytesPerRow * bitmap.height) }
        return image
    }

    private func acquireDownload() async {
        if activeDownloads < 3 { activeDownloads += 1 }
        else { await withCheckedContinuation { waiting.append($0) } }
    }

    private func releaseDownload() {
        if waiting.isEmpty { activeDownloads -= 1 }
        else { waiting.removeFirst().resume() }
    }
}

private struct ArchiveGalleryImage: View {
    let photo: ArchiveGalleryPhoto
    let images: ArchiveGalleryImages
    var fullView = false
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = UUID()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.secondary.opacity(0.15)
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: fullView ? .fit : .fill)
                } else if failed && fullView {
                    Button("Tentar abrir novamente") { retry = UUID() }.buttonStyle(.bordered)
                } else if fullView {
                    ProgressView()
                } else {
                    Image(systemName: failed ? "exclamationmark.circle" : "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: proxy.size.width, height: fullView ? proxy.size.height : proxy.size.width)
            .clipped()
        }
        .aspectRatio(fullView ? nil : 1, contentMode: .fit)
        .task(id: "\(images.revision):\(photo.id):\(retry)") {
            failed = false
            image = nil
            do {
                let preview = try await images.image(photo, maximumPixels: fullView ? 1800 : 320)
                guard !Task.isCancelled else { return }
                image = preview
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct ArchiveGalleryPager: View {
    let items: [ArchiveGalleryPhoto]
    let images: ArchiveGalleryImages
    @State private var selection: String
    @Environment(\.dismiss) private var dismiss

    init(items: [ArchiveGalleryPhoto], initialID: String, images: ArchiveGalleryImages) {
        self.items = items
        self.images = images
        _selection = State(initialValue: initialID)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(items) { photo in
                    VStack(spacing: 8) {
                        if photo.id == selection {
                            ArchiveGalleryImage(photo: photo, images: images, fullView: true)
                        } else {
                            Color.secondary.opacity(0.15)
                        }
                        Text(photo.versionLabel).font(.footnote).foregroundStyle(.secondary).padding(.bottom)
                    }.tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle("Foto na nuvem").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { dismiss() } }
        }
    }
}
