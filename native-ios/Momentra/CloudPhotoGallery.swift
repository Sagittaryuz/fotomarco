import SwiftUI
import ImageIO

struct CloudPhotoGallery: View {
    @ObservedObject var googlePhotos: GooglePhotosManager
    @ObservedObject var picker: GooglePickerFlow
    let profileLookup: PhotoProfileLookup
    @ObservedObject var stampProfiles: StampProfilesStore
    @State private var showPickerConsent = false
    @State private var columnCount = 3
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var selectedPhoto: CloudPhoto?

    private var groups: [GalleryGroup<CloudPhoto>] {
        GalleryGrouping.groups(googlePhotos.cloudPhotos, date: { $0.date }, profile: { item in
            let locallyRecorded = googlePhotos.ownerID.flatMap { owner in
                profileLookup.cloud[PhotoProfileIndex.cloudKey(owner: owner, mediaID: item.id)]
            }
            guard let tag = locallyRecorded ?? CloudProfileFilename.decode(item.name) else { return nil }
            guard let profile = stampProfiles.profiles.first(where: { $0.id == tag.id }) else { return tag }
            return CaptureProfileTag(id: tag.id, name: profile.name)
        })
    }

    var body: some View {
        Group {
            if !googlePhotos.configured {
                ContentUnavailableView("Google Fotos indisponível", systemImage: "cloud", description: Text("A conexão Google ainda não foi configurada nesta versão."))
            } else if !googlePhotos.connected {
                ScrollView {
                    ContentUnavailableView("Conecte o Google Fotos", systemImage: "cloud", description: Text("Conecte sua conta em Ajustes do Momentra para acessar os originais na nuvem."))
                    if let ownerHash = CloudStoragePreference.selectedHash(),
                       googlePhotos.ownerID == nil || googlePhotos.ownerID.map({ CloudCaptureQueue.ownerHash($0) == ownerHash }) == true {
                        CloudOfflinePreviews(ownerHash: ownerHash, columnCount: columnCount, profiles: profileLookup)
                    }
                }
                .simultaneousGesture(MagnifyGesture().onEnded { value in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnCount = GalleryZoom.next(columns: columnCount, magnification: value.magnification)
                    }
                })
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        if picker.waitingForSelection {
                            Text("Depois de escolher a foto no Google Fotos, volte para cá.")
                                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                            Button("Já selecionei") { picker.retrieve() }.buttonStyle(.borderedProminent).disabled(picker.busy)
                            Button("Cancelar seleção") { picker.cancel() }.disabled(picker.busy)
                        } else {
                            Button("Escolher outra foto do Google Fotos") { showPickerConsent = true }
                                .buttonStyle(.bordered).disabled(picker.busy || googlePhotos.busy)
                        }
                        if picker.busy { ProgressView("Preparando seleção…").padding() }
                        Text("Aqui aparecem fotos pessoais criadas pelo Momentra no Google Fotos. Outras fotos da sua conta não aparecem nesta lista.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        if googlePhotos.busy { ProgressView().padding() }
                        if let error = googlePhotos.cloudError {
                            Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                            Button("Tentar novamente") { googlePhotos.loadCloudPhotos() }.disabled(googlePhotos.busy)
                            if let owner = googlePhotos.ownerID {
                                CloudOfflinePreviews(ownerHash: CloudCaptureQueue.ownerHash(owner), columnCount: columnCount, profiles: profileLookup)
                            }
                        }
                        if googlePhotos.cloudLoaded && googlePhotos.cloudPhotos.isEmpty {
                            ContentUnavailableView("Nenhuma foto criada pelo Momentra", systemImage: "photo.on.rectangle")
                        }
                    }.padding(.vertical, 8)
                    if !groups.isEmpty {
                        GalleryGrid(groups: groups, selecting: $selecting, selected: $selectedIDs, columns: $columnCount,
                                    refreshKey: googlePhotos.cloudPhotos.map(\.thumbnailURL).hashValue) { item in
                            CloudThumbnail(url: item.thumbnailURL)
                                .overlay(alignment: .bottomLeading) {
                                    if CloudProfileFilename.isOriginal(item.name) {
                                        Text("Original").font(.caption2.bold()).padding(4).background(.black.opacity(0.7), in: Capsule()).padding(4)
                                    }
                                }.accessibilityLabel(item.name)
                        } open: { selectedPhoto = $0 }
                    }
                    HStack {
                        if selecting {
                            Text("\(selectedIDs.count) selecionada(s)")
                            Spacer()
                            Button("Selecionar exibidas") { selectedIDs = Set(googlePhotos.cloudPhotos.map(\.id)) }
                        } else {
                            Button("Atualizar") { googlePhotos.loadCloudPhotos() }.disabled(googlePhotos.busy)
                            Spacer()
                            if googlePhotos.cloudNextPage != nil {
                                Button("Carregar mais") { googlePhotos.loadCloudPhotos(nextPage: true) }.disabled(googlePhotos.busy)
                            }
                        }
                    }.font(.footnote).padding()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selecting ? "Cancelar" : "Selecionar") {
                            selecting.toggle(); if !selecting { selectedIDs.removeAll() }
                        }
                    }
                }
                .task(id: googlePhotos.connected) {
                    if !googlePhotos.cloudLoaded && !googlePhotos.busy { googlePhotos.loadCloudPhotos() }
                }
                .confirmationDialog("Escolha uma foto pessoal no Google Fotos. O Google solicitará permissão para acessar somente as fotos selecionadas. Nenhuma foto será enviada automaticamente.", isPresented: $showPickerConsent, titleVisibility: .visible) {
                    Button("Escolher foto pessoal") { picker.start() }
                    Button("Cancelar", role: .cancel) {}
                }
                .alert("Google Fotos", isPresented: Binding(get: { picker.message != nil }, set: { if !$0 { picker.message = nil } })) {
                    Button("OK") { picker.message = nil }
                } message: { Text(picker.message ?? "") }
                .sheet(item: $picker.picked) { item in PickedCloudPhotoView(item: item) }
                .sheet(item: $selectedPhoto) { item in
                    CloudPhotoPager(items: groups.flatMap(\.items), initialID: item.id)
                }
            }
        }
    }
}

private struct CloudPhotoPager: View {
    let items: [CloudPhoto]
    @State private var selection: String
    @Environment(\.dismiss) private var dismiss
    init(items: [CloudPhoto], initialID: String) { self.items = items; _selection = State(initialValue: initialID) }
    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(items) { item in
                    VStack {
                        CloudThumbnail(url: item.thumbnailURL, fullView: true)
                        if let url = item.productURL { Link("Abrir no Google Fotos", destination: url).padding() }
                    }.tag(item.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
                .navigationTitle("Foto na nuvem").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Concluído") { dismiss() } }
        }
    }
}

private final class NoCloudImageRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct CloudThumbnail: View {
    let url: URL?
    var fullView = false
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.gray.opacity(0.2)
                if let image {
                    if fullView { Image(uiImage: image).resizable().scaledToFit() }
                    else { Image(uiImage: image).resizable().scaledToFill() }
                }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }.frame(width: proxy.size.width, height: fullView ? proxy.size.height : proxy.size.width).clipped()
        }
        .aspectRatio(fullView ? nil : 1, contentMode: .fit)
        .task(id: url) {
            image = nil
            guard let url, url.scheme == "https", let host = url.host?.lowercased(),
                  host.hasSuffix(".googleusercontent.com"), url.user == nil, url.password == nil,
                  url.port == nil, url.query == nil, url.fragment == nil else { return }
            let remote = fullView && url.absoluteString.hasSuffix("=w360-h360-c")
                ? URL(string: String(url.absoluteString.dropLast("=w360-h360-c".count)) + "=w1600-h1600") ?? url : url
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil; config.httpCookieStorage = nil; config.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: config, delegate: NoCloudImageRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            do {
                let (bytes, response) = try await session.bytes(from: remote)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      response.expectedContentLength <= (fullView ? 12_000_000 : 2_000_000) else { return }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < (fullView ? 12_000_000 : 2_000_000) else { return }
                    data.append(byte)
                }
                guard !Task.isCancelled, let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: fullView ? 1600 : 360
                      ] as CFDictionary) else { return }
                image = UIImage(cgImage: thumbnail)
            } catch { return }
        }
    }
}
