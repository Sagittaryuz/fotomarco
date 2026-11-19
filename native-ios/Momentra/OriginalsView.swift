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
    static func delete(_ item: OriginalFile) throws {
        let root = item.url.deletingLastPathComponent().deletingLastPathComponent()
        let archive = CloudArchiveJournal(root: root)
        try archive.serializeCleanup {
            if let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent),
               archive.hasPendingDelivery(id: id) { throw CocoaError(.fileWriteFileExists) }
            try FileManager.default.removeItem(at: item.url)
        }
    }

    static func files() throws -> [OriginalFile] {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
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
    @Environment(\.dismiss) private var dismiss
    @State private var files: [OriginalFile] = []
    @State private var message: String?
    @State private var isSaving = false
    @State private var gallerySection = 0
    @State private var profileLookup = PhotoProfileLookup()
    @State private var reloadToken = UUID()
    @State private var captureColumns = 3
    @State private var selectedCapture: URL?
    @State private var selectingCaptures = false
    @State private var selectedCaptureIDs: Set<URL> = []
    @State private var showCaptureSelection = false
    @State private var confirmBatchDelete = false
    @State private var deletingSelection = false
    @StateObject private var archiveAccounts = CloudArchiveAccounts.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GallerySectionTabs(selection: $gallerySection)
                    .padding(.horizontal, 12).padding(.bottom, 10)
                GalleryCapacitySummary(section: gallerySection, accounts: archiveAccounts.accounts)
                if gallerySection == 0 {
                    captures
                } else if gallerySection == 1 {
                    DevicePhotoGallery(profileLookup: profileLookup, stampProfiles: stampProfiles)
                } else {
                    CloudArchiveGallery(accounts: archiveAccounts,
                                        profileLookup: profileLookup, stampProfiles: stampProfiles)
                }
            }
            .navigationTitle("Galeria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { dismiss() } }
            .onAppear { reload() }
            .sheet(isPresented: Binding(get: { selectedCapture != nil }, set: { if !$0 { selectedCapture = nil } }), onDismiss: reload) {
                if let selectedCapture {
                    CapturePager(items: captureGroups.flatMap(\.items), initialURL: selectedCapture,
                                 message: $message, profiles: stampProfiles, save: save)
                        .presentationDragIndicator(.hidden)
                }
            }
            .sheet(isPresented: $showCaptureSelection) {
                CaptureSelectionSheet(items: files, selected: $selectedCaptureIDs)
                    .presentationDragIndicator(.hidden)
            }
            .confirmationDialog("Excluir as capturas selecionadas?", isPresented: $confirmBatchDelete,
                                titleVisibility: .visible) {
                Button("Excluir \(selectedCaptureIDs.count) itens", role: .destructive) { deleteSelection() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("A exclusão se aplica aos arquivos locais selecionados.")
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
                    GalleryGrid(groups: captureGroups, selecting: $selectingCaptures, selected: $selectedCaptureIDs, columns: $captureColumns) { item in
                        ZStack(alignment: .bottomTrailing) {
                            Thumbnail(url: item.url, isVideo: item.isVideo)
                                .overlay(alignment: .topLeading) {
                                    if item.isVideo {
                                        Text(item.isProcessed ? "Com carimbo" : "Original")
                                            .font(.caption2.bold()).foregroundStyle(.white).padding(4)
                                            .background(.black.opacity(0.7), in: Capsule()).padding(4)
                                    }
                                }
                            Menu {
                                ShareLink(item: item.url) { Label("Compartilhar", systemImage: "square.and.arrow.up") }
                                Button { save(item) } label: { Label("Salvar no Fotos", systemImage: "square.and.arrow.down") }.disabled(isSaving)
                            } label: {
                                Image(systemName: "ellipsis.circle.fill").font(.title3).foregroundStyle(.white).shadow(radius: 2).padding(6)
                            }.accessibilityLabel("Opções da captura")
                        }
                    } open: { item in selectedCapture = item.url }
                }
                if selectingCaptures { selectionBar }

        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(selectingCaptures ? "Cancelar" : "Selecionar") {
                    selectingCaptures.toggle(); if !selectingCaptures { selectedCaptureIDs.removeAll() }
                }.disabled(deletingSelection)
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
        return HStack(spacing: 12) {
            ShareLink(items: urls) {
                Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                    .modifier(GalleryControlSurface())
            }
            .accessibilityLabel("Compartilhar seleção")
            Spacer(minLength: 0)
            Button { showCaptureSelection = true } label: {
                Text("Mostrar seleção (\(urls.count))").font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.72)
                    .frame(minHeight: 44).padding(.horizontal, 12)
                    .modifier(GalleryControlSurface(tint: .yellow))
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { confirmBatchDelete = true } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
                    .modifier(GalleryControlSurface(tint: .red))
            }
            .accessibilityLabel("Excluir seleção")
        }
        .buttonStyle(.plain)
        .disabled(urls.isEmpty || deletingSelection)
        .opacity(urls.isEmpty ? 0.52 : 1)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.background)
    }

    private func deleteSelection() {
        guard !deletingSelection else { return }
        let items = files.filter { selectedCaptureIDs.contains($0.id) }
        deletingSelection = true
        Task {
            let removed = await Task.detached(priority: .utility) {
                items.compactMap { item -> URL? in
                    do { try OriginalStore.delete(item); return item.id }
                    catch { return nil }
                }
            }.value
            selectedCaptureIDs.subtract(removed)
            deletingSelection = false
            if removed.count != items.count {
                message = "Alguns itens não puderam ser excluídos. Confira se há envios pendentes."
            }
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

private struct CaptureSelectionSheet: View {
    let items: [OriginalFile]
    @Binding var selected: Set<URL>
    @State private var columns = 3
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let selection = items.filter { selected.contains($0.id) }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { columns = columns == 3 ? 2 : 3 } label: {
                    Image(systemName: "square.grid.2x2").frame(width: 44, height: 44)
                        .modifier(GalleryControlSurface())
                }.accessibilityLabel("Alterar tamanho das miniaturas")
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    Text("Seleção").font(.caption).foregroundStyle(.yellow)
                    Text(selection.count == 1 ? "1 item selecionado" : "\(selection.count) itens selecionados")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "checkmark").font(.body.weight(.bold))
                        .frame(width: 44, height: 44).modifier(GalleryControlSurface(tint: .yellow))
                }.accessibilityLabel("Concluir revisão")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 12)
            if selection.isEmpty {
                ContentUnavailableView("Nenhum item selecionado", systemImage: "checkmark.circle")
                    .frame(maxHeight: .infinity)
            } else {
                GalleryGrid(groups: [GalleryGroup(date: nil, profile: nil, items: selection)], selecting: .constant(true),
                            selected: $selected, columns: $columns, showsSectionHeaders: false) { item in
                    Thumbnail(url: item.url, isVideo: item.isVideo)
                } open: { _ in }
            }
            Button { selected.removeAll() } label: {
                Text("Desmarcar tudo").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .modifier(GalleryControlSurface())
            }
            .buttonStyle(.plain).disabled(selection.isEmpty)
            .opacity(selection.isEmpty ? 0.52 : 1)
            .padding(.vertical, 12)
        }
        .background(.background)
        .preferredColorScheme(.dark)
    }
}

private struct CapturePager: View {
    private enum Panel: String, Identifiable {
        case information, adjustments, text
        var id: String { rawValue }
    }

    let save: (OriginalFile) -> Void
    @ObservedObject var profiles: StampProfilesStore
    @Binding var message: String?
    @AppStorage("native.gallery.favoriteCaptureKeys") private var storedFavorites = Data()
    @State private var items: [OriginalFile]
    @State private var selection: URL
    @State private var panel: Panel?
    @State private var removing: OriginalFile?
    @State private var fullscreen = false
    @State private var stamping = false
    @State private var selectedProfile: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(items: [OriginalFile], initialURL: URL, message: Binding<String?>, profiles: StampProfilesStore,
         save: @escaping (OriginalFile) -> Void) {
        self.save = save
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
                                    count: items.count, close: { dismiss() }) {
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
        .sheet(item: $panel) { route in
            if let current { detailSheet(route, item: current) }
        }
        .confirmationDialog("Excluir esta captura do Momentra?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible, presenting: removing) { item in
            Button("Excluir captura", role: .destructive) { delete(item) }
            Button("Cancelar", role: .cancel) { removing = nil }
        } message: { _ in
            Text("A exclusão se aplica a este arquivo local.")
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
                Button { openAdjustments() } label: { Label("Adicionar carimbo", systemImage: "slider.horizontal.3") }
                Button { panel = .text } label: { Label("Ler texto", systemImage: "text.viewfinder") }
            }
        } label: {
            controlIcon("ellipsis")
        }.accessibilityLabel("Mais opções")
    }

    private func controls(_ item: OriginalFile) -> some View {
        HStack(spacing: 8) {
            ShareLink(item: item.url) { controlIcon("square.and.arrow.up") }
                .accessibilityLabel("Compartilhar")
            Spacer(minLength: 2)
            let favorite = favorites.contains(favoriteKey(item))
            galleryButton(favorite ? "heart.fill" : "heart",
                          label: favorite ? "Remover dos favoritos" : "Favoritar",
                          tint: favorite ? .yellow : .primary) { toggleFavorite(item) }
            galleryButton("info.circle", label: "Informações") { panel = .information }
            galleryButton("slider.horizontal.3", label: "Ajustes da foto") { openAdjustments() }
                .disabled(item.isVideo)
            Spacer(minLength: 2)
            galleryButton("trash", label: "Excluir captura", tint: .red) { removing = item }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.black)
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

    private func openAdjustments() {
        selectedProfile = profiles.selected.id
        panel = .adjustments
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
                case .adjustments:
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
                }
            }
            .navigationTitle(route == .information ? "Informações" : route == .adjustments ? "Ajustes da foto" : "Texto da foto")
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
        removing = nil
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try OriginalStore.delete(item)
                }.value
                if favorites.contains(favoriteKey(item)) { toggleFavorite(item) }
                if let index = items.firstIndex(where: { $0.id == item.id }) { items.remove(at: index) }
                if let next = items.first { selection = next.id } else { dismiss() }
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                message = "A foto tem um envio pendente. Aguarde a conclusão antes de excluir."
            } catch { message = "Não foi possível excluir a captura." }
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
