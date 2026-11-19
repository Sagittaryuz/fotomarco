import SwiftUI
import Photos
import ImageIO
import AVKit

private struct OriginalFile: Identifiable {
    let url: URL
    let isVideo: Bool
    let isProcessed: Bool
    let date: Date?
    var id: URL { url }
}

private enum OriginalStore {
    static func moveToTrash(_ item: OriginalFile) throws {
        let root = item.url.deletingLastPathComponent().deletingLastPathComponent()
        let archive = CloudArchiveJournal(root: root)
        try archive.serializeCleanup {
            if let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent),
               archive.hasPendingDelivery(id: id) { throw CocoaError(.fileWriteFileExists) }
            let destination = root.appendingPathComponent("CaptureTrash", isDirectory: true)
                .appendingPathComponent(item.url.deletingLastPathComponent().lastPathComponent, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: item.url, to: destination.appendingPathComponent(item.url.lastPathComponent))
        }
    }

    static func restore(_ item: OriginalFile) throws {
        let folder = item.url.deletingLastPathComponent()
        let root = folder.deletingLastPathComponent().deletingLastPathComponent()
        try CloudArchiveJournal(root: root).serializeCleanup {
            let destination = root.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: item.url, to: destination.appendingPathComponent(item.url.lastPathComponent))
        }
    }

    static func files(inTrash: Bool = false) throws -> [OriginalFile] {
        var root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        if inTrash { root.appendPathComponent("CaptureTrash", isDirectory: true) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        return try [("Originals", false, false), ("Processed", false, true), ("Videos", true, false), ("ProcessedVideos", true, true)].flatMap { folder, isVideo, isProcessed -> [OriginalFile] in
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]).compactMap { url in
                let info = try url.resourceValues(forKeys: Set(keys))
                guard info.isRegularFile == true else { return nil }
                return OriginalFile(url: url, isVideo: isVideo, isProcessed: isProcessed, date: info.contentModificationDate)
            }
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

struct OriginalsView: View {
    @ObservedObject var stampProfiles: StampProfilesStore
    let returnToCamera: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var files: [OriginalFile] = []
    @State private var message: String?
    @State private var isSaving = false
    @State private var gallerySection = 0
    @State private var profileLookup = PhotoProfileLookup()
    @State private var reloadToken = UUID()
    @State private var captureColumns = 3
    @State private var selectedCapture: URL?
    @State private var exitingToCamera = false
    @State private var showingTrash = false
    @State private var quickShare: OriginalFile?
    @State private var selectingCaptures = false
    @State private var selectedCaptureIDs: Set<URL> = []
    @State private var showCaptureSelection = false
    @State private var confirmBatchDelete = false
    @State private var deletingSelection = false
    @StateObject private var archiveAccounts = CloudArchiveAccounts.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Origem das fotos", selection: $gallerySection) {
                    Text("Capturas").tag(0)
                    Text("Celular").tag(1)
                    Text("Nuvem").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.bottom, 10)
                GalleryCapacitySummary(section: gallerySection, accounts: archiveAccounts.accounts)
                if gallerySection == 0 {
                    captures
                } else if gallerySection == 1 {
                    DevicePhotoGallery(profileLookup: profileLookup, stampProfiles: stampProfiles, returnToCamera: returnToCamera)
                } else {
                    CloudArchiveGallery(accounts: archiveAccounts,
                                        profileLookup: profileLookup, stampProfiles: stampProfiles, returnToCamera: returnToCamera)
                }
            }
            .navigationTitle("Galeria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { dismiss() } }
            .onAppear { reload() }
            .fullScreenCover(item: $quickShare) { item in
                GalleryQuickShare(load: { PhotoEditorInput(url: item.url) }, isVideo: item.isVideo)
            }
            .fullScreenCover(isPresented: Binding(get: { selectedCapture != nil }, set: { if !$0 { selectedCapture = nil } }),
                             onDismiss: detailDismissed) {
                if let selectedCapture {
                    CapturePager(items: captureGroups.flatMap(\.items), initialURL: selectedCapture,
                                 message: $message, profiles: stampProfiles, save: save,
                                 returnToCamera: { exitingToCamera = true; self.selectedCapture = nil })
                }
            }
            .sheet(isPresented: $showingTrash, onDismiss: reload) {
                CaptureTrashView()
            }
            .sheet(isPresented: $showCaptureSelection) {
                GallerySelectionSheet(items: files, selected: $selectedCaptureIDs) { item in
                    Thumbnail(url: item.url, isVideo: item.isVideo)
                }
            }
            .confirmationDialog("Mover as capturas selecionadas para a lixeira?", isPresented: $confirmBatchDelete,
                                titleVisibility: .visible) {
                Button("Mover \(selectedCaptureIDs.count) itens para a lixeira", role: .destructive) { deleteSelection() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Você pode restaurar os arquivos na Lixeira de Capturas do Momentra.")
            }
            .onChange(of: gallerySection) { _, _ in
                selectingCaptures = false; selectedCaptureIDs.removeAll()
                reload()
            }
            .alert("Momentra", isPresented: Binding(get: { selectedCapture == nil && message != nil },
                                                     set: { if !$0, selectedCapture == nil { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func resolved(_ tag: CaptureProfileTag?) -> CaptureProfileTag? {
        guard let tag else { return nil }
        if let profile = stampProfiles.profiles.first(where: { $0.id == tag.id }) {
            return CaptureProfileTag(id: tag.id, name: profile.name)
        }
        return tag
    }

    private var captureGroups: [GalleryGroup<OriginalFile>] {
        GalleryGrouping.groups(files, date: { item in
            guard let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent) else { return item.date }
            return profileLookup.dates[id] ?? item.date
        }, profile: { item in
            guard let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent) else { return nil }
            return resolved(profileLookup.captures[id])
        })
    }

    private var captures: some View {
        VStack(spacing: 0) {
                if files.isEmpty {
                    ContentUnavailableView("Nenhuma captura disponível", systemImage: "photo")
                } else {
                    GalleryGrid(groups: captureGroups, selecting: $selectingCaptures, selected: $selectedCaptureIDs,
                                columns: $captureColumns, tile: { item in
                        Thumbnail(url: item.url, isVideo: item.isVideo)
                            .overlay(alignment: .topLeading) {
                                if item.isVideo {
                                    Text(item.isProcessed ? "Com carimbo" : "Original")
                                        .font(.caption2.bold()).foregroundStyle(.white).padding(4)
                                        .background(.black.opacity(0.7), in: Capsule()).padding(4)
                                }
                            }
                    }, open: { selectedCapture = $0.url }, longPress: { quickShare = $0 })
                }
                if selectingCaptures { selectionBar }

        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(selectingCaptures ? "Cancelar" : "Selecionar") {
                    selectingCaptures.toggle(); if !selectingCaptures { selectedCaptureIDs.removeAll() }
                }.disabled(deletingSelection)
            }
            if !selectingCaptures {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingTrash = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Lixeira de Capturas")
                }
            }
            if selectingCaptures {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Selecionar todas") { selectedCaptureIDs = Set(files.map(\.id)) }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .disabled(deletingSelection)
                    .accessibilityLabel("Opções da seleção")
                }
            }
        }
    }

    private var selectionBar: some View {
        let urls = files.filter { selectedCaptureIDs.contains($0.id) }.map(\.url)
        return GallerySelectionBar(count: urls.count, busy: deletingSelection,
                                   review: { showCaptureSelection = true }, delete: { confirmBatchDelete = true }) {
            ShareLink(items: urls) { GalleryShareIcon() }
        }
    }

    private func deleteSelection() {
        guard !deletingSelection else { return }
        let items = files.filter { selectedCaptureIDs.contains($0.id) }
        deletingSelection = true
        Task {
            let removed = await Task.detached(priority: .utility) {
                items.compactMap { item -> URL? in
                    do { try OriginalStore.moveToTrash(item); return item.id }
                    catch { return nil }
                }
            }.value
            if !removed.isEmpty {
                selectingCaptures = false
                selectedCaptureIDs.removeAll()
            }
            deletingSelection = false
            if removed.count != items.count {
                message = "Alguns itens não puderam ser movidos para a lixeira. Confira se há envios pendentes."
            }
            reload()
        }
    }

    private func detailDismissed() {
        if exitingToCamera {
            exitingToCamera = false
            returnToCamera()
        } else {
            reload()
        }
    }

    private func reload() {
        let token = UUID()
        reloadToken = token
        Task {
            let result = await Task.detached(priority: .utility) { () -> (PhotoProfileLookup, [OriginalFile]?) in
                (PhotoProfileIndex.load(), try? OriginalStore.files())
            }.value
            guard reloadToken == token else { return }
            profileLookup = result.0
            if let loaded = result.1 {
                files = loaded
                selectedCaptureIDs.formIntersection(Set(loaded.map(\.id)))
            }
            else { message = "Não foi possível abrir as capturas guardadas." }
        }
    }

    private func save(_ item: OriginalFile) {
        guard !isSaving else { return }
        isSaving = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { isSaving = false; message = "Permita o acesso ao Fotos nos Ajustes do iPhone." }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: item.isVideo ? .video : .photo, fileURL: item.url, options: nil)
            }) { success, _ in
                DispatchQueue.main.async {
                    isSaving = false
                    message = success ? "Arquivo salvo no Fotos." : "Não foi possível salvar. O arquivo continua no aplicativo."
                }
            }
        }
    }
}

private struct CaptureTrashView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var files: [OriginalFile] = []
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty, !busy {
                    ContentUnavailableView("Lixeira vazia", systemImage: "trash")
                } else {
                    List(files) { item in
                        HStack(spacing: 12) {
                            Thumbnail(url: item.url, isVideo: item.isVideo)
                                .frame(width: 60, height: 60).clipped()
                                .clipShape(.rect(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text(item.isVideo ? "Vídeo" : "Foto")
                                if let date = item.date {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Restaurar") { restore(item) }.disabled(busy)
                        }
                    }
                }
            }
            .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: Capsule()) } }
            .navigationTitle("Lixeira de Capturas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { dismiss() }.disabled(busy) }
            .task {
                busy = true
                do {
                    files = try await Task.detached(priority: .utility) { try OriginalStore.files(inTrash: true) }.value
                } catch { message = "Não foi possível abrir a lixeira." }
                busy = false
            }
            .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
        .interactiveDismissDisabled(busy)
    }

    private func restore(_ item: OriginalFile) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await Task.detached(priority: .utility) { try OriginalStore.restore(item) }.value
                files.removeAll { $0.id == item.id }
            } catch { message = "Não foi possível restaurar este item. Ele continua na lixeira." }
        }
    }
}

private struct CapturePager: View {
    private enum Panel: String, Identifiable {
        case information, editor, stamp, text
        var id: String { rawValue }
    }

    let save: (OriginalFile) -> Void
    let returnToCamera: () -> Void
    @ObservedObject var profiles: StampProfilesStore
    @Binding var message: String?
    @AppStorage("native.gallery.favoriteCaptureKeys") private var storedFavorites = Data()
    @State private var items: [OriginalFile]
    @State private var selection: URL
    @State private var panel: Panel?
    @State private var removing = false
    @State private var showGrid = false
    @State private var shareItem: OriginalFile?
    @State private var fullscreen = false
    @State private var stamping = false
    @State private var selectedProfile: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(items: [OriginalFile], initialURL: URL, message: Binding<String?>, profiles: StampProfilesStore,
         save: @escaping (OriginalFile) -> Void, returnToCamera: @escaping () -> Void) {
        self.save = save
        self.returnToCamera = returnToCamera
        self.profiles = profiles
        _message = message
        _items = State(initialValue: items)
        _selection = State(initialValue: initialURL)
    }

    var body: some View {
        let index = items.firstIndex { $0.id == selection }
        let current = index.map { items[$0] }
        VStack(spacing: 0) {
            if !fullscreen {
                GalleryDetailHeader(date: current?.date, position: (index ?? 0) + 1,
                                    count: items.count, close: { dismiss() }, overview: { showGrid = true }) {
                    if let current { captureMenu(current) }
                }
            }
            TabView(selection: $selection) {
                ForEach(items) { item in
                    CapturePage(item: item, active: item.id == selection).tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .topTrailing) {
                galleryButton(fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                              label: fullscreen ? "Mostrar controles" : "Expandir visualização") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { fullscreen.toggle() }
                }.padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                if let current, !current.isVideo, !fullscreen {
                    galleryButton("text.viewfinder", label: "Ler texto da foto") { panel = .text }.padding(12)
                }
            }
            if !fullscreen {
                GalleryFilmstrip(items: items, selection: $selection) { item in
                    Thumbnail(url: item.url, isVideo: item.isVideo)
                }
                if let current { controls(current) }
            }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .modifier(GalleryCameraSwipe(action: {
            if !removing { returnToCamera() }
        }))
        .sheet(isPresented: $showGrid) {
            GalleryDetailGrid(items: items, choose: { selection = $0.id }) { item in
                Thumbnail(url: item.url, isVideo: item.isVideo)
            }
        }
        .sheet(item: $shareItem) { item in
            GalleryShareComposer(items: items, current: item, copy: { item, directory in
                try await Task.detached(priority: .utility) {
                    let url = directory.appendingPathComponent(item.url.lastPathComponent)
                    try FileManager.default.copyItem(at: item.url, to: url)
                    return url
                }.value
            }) { item in
                Thumbnail(url: item.url, isVideo: item.isVideo)
            }
        }
        .sheet(item: $panel) { route in
            if let current {
                if route == .editor {
                    MomentraPhotoEditor(load: { PhotoEditorInput(url: current.url) }, date: current.date,
                                        stampProfiles: profiles.profiles) { url in
                        let copy = OriginalFile(url: url, isVideo: false, isProcessed: true, date: current.date)
                        items.insert(copy, at: 0)
                        selection = copy.id
                    }
                } else {
                    detailSheet(route, item: current)
                }
            }
        }
        .alert("Momentra", isPresented: Binding(get: { message != nil && panel == nil }, set: { if !$0, panel == nil { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func captureMenu(_ item: OriginalFile) -> some View {
        Menu {
            Button { save(item) } label: { Label("Salvar no Fotos", systemImage: "square.and.arrow.down") }
            Button { panel = .information } label: { Label("Informações", systemImage: "info.circle") }
            if !item.isVideo {
                Button { panel = .editor } label: { Label("Editar foto", systemImage: "slider.horizontal.3") }
                Button { openStamp() } label: { Label("Adicionar carimbo", systemImage: "seal") }
                Button { panel = .text } label: { Label("Ler texto", systemImage: "text.viewfinder") }
            }
        } label: {
            controlIcon("ellipsis")
        }.accessibilityLabel("Mais opções")
    }

    private func controls(_ item: OriginalFile) -> some View {
        HStack(spacing: 8) {
            galleryButton("square.and.arrow.up", label: "Compartilhar") { shareItem = item }
            Spacer(minLength: 2)
            HStack(spacing: 4) {
                let favorite = favorites.contains(favoriteKey(item))
                groupedButton(favorite ? "heart.fill" : "heart",
                              label: favorite ? "Remover dos favoritos" : "Favoritar",
                              tint: favorite ? .yellow : .primary) { toggleFavorite(item) }
                groupedButton("info.circle", label: "Informações") { panel = .information }
                groupedButton("slider.horizontal.3", label: "Editar foto") { panel = .editor }
                    .disabled(item.isVideo)
            }
            .padding(.horizontal, 4).modifier(GalleryControlSurface())
            Spacer(minLength: 2)
            GalleryTrashButton(label: "Excluir captura",
                               message: "Você poderá restaurar esta captura na Lixeira de Capturas do Momentra.") {
                delete(item)
            }
            .disabled(removing)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.black)
    }

    private func groupedButton(_ icon: String, label: String, tint: Color = .primary,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func galleryButton(_ icon: String, label: String, tint: Color = .primary,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { controlIcon(icon, tint: tint) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func controlIcon(_ name: String, tint: Color = .primary) -> some View {
        Image(systemName: name).font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .modifier(GalleryControlSurface(tint: tint))
    }

    private var favorites: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: storedFavorites)) ?? []
    }

    private func favoriteKey(_ item: OriginalFile) -> String {
        item.url.deletingLastPathComponent().lastPathComponent + "/" + item.url.lastPathComponent
    }

    private func toggleFavorite(_ item: OriginalFile) {
        var keys = favorites
        let key = favoriteKey(item)
        if !keys.insert(key).inserted { keys.remove(key) }
        if let data = try? JSONEncoder().encode(keys) { storedFavorites = data }
    }

    private func openStamp() {
        selectedProfile = profiles.selected.id
        panel = .stamp
    }

    @ViewBuilder
    private func detailSheet(_ route: Panel, item: OriginalFile) -> some View {
        NavigationStack {
            Group {
                switch route {
                case .information:
                    let details = GalleryFileInformation(url: item.url)
                    Form {
                        LabeledContent("Tipo", value: item.isVideo ? "Vídeo" : "Foto")
                        if let date = item.date { LabeledContent("Data", value: date.formatted(date: .abbreviated, time: .shortened)) }
                        if let text = details.originalDate { LabeledContent("Data original", value: text) }
                        if let dimensions = details.dimensions { LabeledContent("Dimensões", value: dimensions) }
                        if let size = details.size { LabeledContent("Tamanho", value: size) }
                        if let point = details.location?.coordinate {
                            LabeledContent("Coordenadas", value: String(format: "%.6f, %.6f", point.latitude, point.longitude))
                        }
                    }
                case .stamp:
                    Form {
                        Picker("Perfil do carimbo", selection: $selectedProfile) {
                            ForEach(profiles.profiles) { profile in
                                Text(profile.name.isEmpty ? "Sem nome" : profile.name).tag(Optional(profile.id))
                            }
                        }
                        Button("Adicionar carimbo em uma cópia") { applyStamp(item) }
                            .disabled(stamping || selectedProfile == nil || item.date == nil)
                        if stamping { ProgressView("Aplicando carimbo…") }
                        if item.date == nil { Text("A data da captura não está disponível.").font(.footnote) }
                    }
                case .text:
                    CaptureTextPanel(url: item.url)
                case .editor:
                    EmptyView()
                }
            }
            .navigationTitle(route == .information ? "Informações" : route == .stamp ? "Adicionar carimbo" : "Texto da foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { panel = nil }.disabled(stamping) }
        }
        .interactiveDismissDisabled(stamping)
    }

    private func applyStamp(_ item: OriginalFile) {
        guard !stamping, let date = item.date,
              let profile = profiles.profiles.first(where: { $0.id == selectedProfile }) else { return }
        stamping = true
        Task {
            do {
                _ = try await GalleryPhotoActions.copyWithStamp(url: item.url, date: date, profile: profile)
                message = "Cópia com carimbo criada em Capturas."
            } catch { message = "Não foi possível criar a cópia com carimbo." }
            stamping = false
            panel = nil
        }
    }

    private func delete(_ item: OriginalFile) {
        guard !removing else { return }
        removing = true
        Task {
            defer { removing = false }
            do {
                try await Task.detached(priority: .utility) {
                    try OriginalStore.moveToTrash(item)
                }.value
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items.remove(at: index)
                    if items.isEmpty { dismiss() }
                    else if selection == item.id { selection = items[min(index, items.count - 1)].id }
                }
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                message = "A captura tem um envio pendente. Aguarde a conclusão para movê-la à lixeira."
            } catch { message = "Não foi possível mover a captura para a lixeira." }
        }
    }
}

private struct CaptureTextPanel: View {
    let url: URL
    @State private var text: String?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                ContentUnavailableView("Não foi possível ler o texto", systemImage: "text.viewfinder")
            } else if let text {
                if text.isEmpty {
                    ContentUnavailableView("Nenhum texto reconhecido", systemImage: "text.viewfinder")
                } else {
                    ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                    Button("Copiar texto") { UIPasteboard.general.string = text }.padding()
                }
            } else {
                ProgressView("Lendo texto…")
            }
        }
        .task(id: url) {
            do { text = try await Task.detached(priority: .userInitiated) { try GalleryPhotoActions.recognizeText(in: url) }.value }
            catch { failed = true }
        }
    }
}

private struct CapturePage: View {
    let item: OriginalFile
    let active: Bool
    @State private var preview: UIImage?
    @State private var player: AVPlayer?
    @State private var failed = false
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .scaleEffect(magnification)
                        .gesture(MagnifyGesture().updating($magnification) { value, scale, _ in
                            scale = min(5, max(1, value.magnification))
                        })
                } else if failed {
                    ContentUnavailableView("Não foi possível abrir a captura", systemImage: "photo.badge.exclamationmark")
                } else if active {
                    ProgressView("Abrindo captura…")
                } else {
                    Color.clear
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .task(id: active) {
            guard active else { player?.pause(); return }
            if item.isVideo {
                if player == nil { player = AVPlayer(url: item.url) }
            } else if preview == nil {
                let url = item.url
                let image = await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 2600
                          ] as CFDictionary) else { return nil as UIImage? }
                    return UIImage(cgImage: image)
                }.value
                if !Task.isCancelled { preview = image; failed = image == nil }
            }
        }.onDisappear { player?.pause() }
    }
}

private struct Thumbnail: View {
    let url: URL
    let isVideo: Bool
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(.gray.opacity(0.2))
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: isVideo ? "video.fill" : "photo").foregroundStyle(.secondary) }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: url) {
            guard !isVideo else { return }
            let fileURL = url
            let thumbnail = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 160
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: image)
            }.value
            image = thumbnail
        }
    }
}
