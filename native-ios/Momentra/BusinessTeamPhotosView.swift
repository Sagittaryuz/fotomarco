import SwiftUI
import UIKit

/// Thumbnails remain in memory only and are isolated by the signed-in account.
@MainActor private final class TeamPhotoCache {
    static let shared = TeamPhotoCache()
    let images = NSCache<NSString, UIImage>()
    private init() { images.countLimit = 160; images.totalCostLimit = 32 * 1024 * 1024 }
}

struct BusinessTeamPhotosView: View {
    let api: BusinessAPIClient
    let organizationID: String
    var authorID: String? = nil
    var title: String = "Fotos da organização"
    @State private var photos: [BusinessAPIClient.TeamPhoto] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: BusinessAPIClient.TeamPhoto?
    @State private var loadID: UUID?
    @State private var loadedForUser: String?
    @ObservedObject private var identity = BusinessIdentity.shared

    var body: some View {
        ScrollView {
            if photos.isEmpty && loading { ProgressView("Carregando fotos…").padding() }
            if photos.isEmpty && !loading && error == nil {
                ContentUnavailableView("Nenhuma foto", systemImage: "photo.on.rectangle", description: Text("As capturas da organização aparecerão aqui."))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(photos) { photo in
                    Button { selected = photo } label: {
                        TeamPhotoImage(api: api, organizationID: organizationID, photo: photo, thumbnail: true)
                            .aspectRatio(1, contentMode: .fill).frame(maxWidth: .infinity).clipped()
                    }.buttonStyle(.plain)
                }
            }
            if let error {
                VStack(spacing: 8) {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("Tentar novamente") { Task { await load() } }
                }.padding()
            } else if loading && !photos.isEmpty { ProgressView().padding() }
        }
        .background(.black)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(organizationID):\(identity.userID ?? "")") { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $selected) { photo in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                TeamPhotoImage(api: api, organizationID: organizationID, photo: photo, thumbnail: false)
                    .scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                Button { selected = nil } label: {
                    Image(systemName: "xmark").font(.headline).padding(16).background(.ultraThinMaterial, in: Circle())
                }.padding()
            }
        }
    }

    @MainActor private func load() async {
        guard let userID = identity.userID else { photos = []; selected = nil; loadedForUser = nil; loadID = nil; loading = false; return }
        if loadedForUser != userID { photos = []; selected = nil; loadedForUser = userID }
        let requestID = UUID()
        loadID = requestID
        loading = true; error = nil
        defer { if loadID == requestID { loading = false } }
        do {
            let token = try await identity.verifiedToken()
            var cursor = "", seen = Set<String>(), collected: [String: BusinessAPIClient.TeamPhoto] = [:]
            repeat {
                guard !Task.isCancelled, identity.userID == userID, loadID == requestID else { return }
                let page = try await api.listTeamPhotos(organizationID: organizationID, cursor: cursor, token: token)
                guard page.photos.count <= 200 else { throw BusinessAPIClient.Failure.invalidResponse }
                for photo in page.photos where authorID == nil || photo.authorId == authorID { collected[photo.id] = photo }
                guard identity.userID == userID, loadID == requestID else { return }
                photos = collected.values.sorted { $0.createdAt < $1.createdAt }
                cursor = page.nextCursor
                guard cursor.isEmpty || seen.insert(cursor).inserted else { throw BusinessAPIClient.Failure.invalidResponse }
            } while !cursor.isEmpty
        } catch {
            if !Task.isCancelled && identity.userID == userID && loadID == requestID {
                if case .unauthorized? = error as? BusinessAPIClient.Failure {
                    // Never keep presenting cached organization photos after the
                    // server has explicitly rejected the current membership.
                    photos = []
                    selected = nil
                    TeamPhotoCache.shared.images.removeAllObjects()
                }
                self.error = "Não foi possível carregar as fotos. Confira sua conexão e seu acesso."
            }
        }
    }
}

private struct TeamPhotoImage: View {
    let api: BusinessAPIClient
    let organizationID: String
    let photo: BusinessAPIClient.TeamPhoto
    let thumbnail: Bool
    @ObservedObject private var identity = BusinessIdentity.shared
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Image(systemName: "photo").foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .task(id: "\(identity.userID ?? ""):\(photo.id):\(thumbnail)") { await load() }
    }

    @MainActor private func load() async {
        image = nil; failed = false
        guard let userID = identity.userID else { return }
        let key = "\(userID):\(organizationID):\(photo.id):\(thumbnail)" as NSString
        if let cached = TeamPhotoCache.shared.images.object(forKey: key) { image = cached; return }
        do {
            let token = try await identity.cachedVerifiedToken()
            let data = try await api.teamPhotoData(organizationID: organizationID, captureID: photo.id, thumbnail: thumbnail, token: token)
            guard !Task.isCancelled, identity.userID == userID, let decoded = UIImage(data: data) else { return }
            TeamPhotoCache.shared.images.setObject(decoded, forKey: key, cost: decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count)
            image = decoded
        } catch { if !Task.isCancelled && identity.userID == userID { failed = true } }
    }
}
