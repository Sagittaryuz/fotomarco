import SwiftUI
import Photos
import CoreLocation

struct MomentraGalleryDetail: View {
    private enum Panel: String, Identifiable {
        case grid, share, information, edit, stamp, text
        var id: Self { self }
    }

    let profiles: [StampProfile]
    let isFavorite: (GalleryItem) -> Bool
    let favorite: (GalleryItem) async throws -> Void
    let onTrash: (GalleryItem) -> Void
    let onSavedCopy: () -> Void
    @State private var items: [GalleryItem]
    @State private var selection: GalleryItem.ID
    @State private var favoriteStates: [GalleryItem.ID: Bool] = [:]
    @State private var panel: Panel?
    @State private var fullscreen = false
    @State private var shareSucceeded = false
    @State private var zoomed = false
    @State private var busy = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(items: [GalleryItem], initial: GalleryItem, profiles: [StampProfile],
         isFavorite: @escaping (GalleryItem) -> Bool, favorite: @escaping (GalleryItem) async throws -> Void,
         onTrash: @escaping (GalleryItem) -> Void, onSavedCopy: @escaping () -> Void) {
        self.profiles = profiles
        self.isFavorite = isFavorite
        self.favorite = favorite
        self.onTrash = onTrash
        self.onSavedCopy = onSavedCopy
        _items = State(initialValue: items)
        _selection = State(initialValue: initial.id)
    }

    var body: some View {
        let index = items.firstIndex { $0.id == selection }
        let current = index.map { items[$0] }
        VStack(spacing: 0) {
            if !fullscreen {
                GalleryDetailHeader(date: current?.date, position: (index ?? 0) + 1, count: items.count,
                                    close: { dismiss() }, overview: { panel = .grid }) {
                    if let current { menu(current) }
                }
            }
            TabView(selection: $selection) {
                ForEach(items) { item in
                    let active = item.id == selection
                    if item.isVideo {
                        item.preview(active: active).tag(item.id)
                    } else {
                        GalleryPhotoViewport(active: active, controlsHidden: $fullscreen, zoomed: $zoomed) {
                            item.preview(active: active)
                        }.tag(item.id)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if current?.isVideo == true {
                    button(fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           label: fullscreen ? "Mostrar controles" : "Expandir visualização") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { fullscreen.toggle() }
                    }.padding(12)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let current, !current.isVideo, !fullscreen {
                    button("text.viewfinder", label: "Ler texto da foto") { panel = .text }.padding(12)
                }
            }
            if !fullscreen {
                GalleryFilmstrip(items: items, selection: $selection) { $0.thumbnail() }
                if let current { footer(current) }
            }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .modifier(GalleryCameraSwipe(action: { if !busy && !zoomed { dismiss() } }))
        .onChange(of: selection) { _, _ in zoomed = false }
        .sheet(item: $panel, onDismiss: {
            if shareSucceeded { dismiss() }
        }) { route in
            if let current { sheet(route, item: current) }
        }
        .alert("Momentra", isPresented: Binding(get: { message != nil && panel == nil },
                                                set: { if !$0, panel == nil { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func menu(_ item: GalleryItem) -> some View {
        Menu {
            if case .capture = item.source {
                Button { saveToPhotos(item) } label: { Label("Salvar no Fotos", systemImage: "square.and.arrow.down") }
            }
            Button { panel = .information } label: { Label("Informações", systemImage: "info.circle") }
            if !item.isVideo {
                Button { panel = .edit } label: { Label("Editar foto", systemImage: "slider.horizontal.3") }
                Button { panel = .stamp } label: { Label("Adicionar carimbo", systemImage: "seal") }
                Button { panel = .text } label: { Label("Ler texto", systemImage: "text.viewfinder") }
            }
        } label: { icon("ellipsis").modifier(GalleryControlSurface(rounded: true)) }
            .accessibilityLabel("Mais opções")
            .disabled(busy)
    }

    private func footer(_ item: GalleryItem) -> some View {
        let starred = favoriteStates[item.id] ?? isFavorite(item)
        return HStack(spacing: 8) {
            button("square.and.arrow.up", label: "Compartilhar") { panel = .share }
            Spacer(minLength: 1)
            HStack(spacing: 4) {
                grouped(starred ? "heart.fill" : "heart", label: starred ? "Remover dos favoritos" : "Favoritar",
                        tint: starred ? .yellow : .primary) { markFavorite(item, starred: starred) }
                    .disabled(!item.canFavorite)
                grouped("info.circle", label: "Informações") { panel = .information }
                grouped("slider.horizontal.3", label: "Editar foto") { panel = .edit }.disabled(item.isVideo)
            }
            .padding(.horizontal, 4).modifier(GalleryControlSurface(rounded: true, interactive: false))
            Spacer(minLength: 1)
            GalleryTrashButton(label: "Excluir captura", message: item.trashMessage) { trash(item) }
                .disabled(!item.canTrash)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .disabled(busy)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.body.weight(.semibold))
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    private func grouped(_ name: String, label: String, tint: Color = .primary,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(name).foregroundStyle(tint) }.accessibilityLabel(label)
    }

    private func button(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(name).modifier(GalleryControlSurface(rounded: true)) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    @ViewBuilder private func sheet(_ route: Panel, item: GalleryItem) -> some View {
        switch route {
        case .grid:
            GalleryDetailGrid(items: items, choose: { selection = $0.id }) { $0.thumbnail() }
        case .share:
            GalleryShareComposer(items: items, current: item, copy: { try await $0.copy(to: $1) }, onSuccess: {
                shareSucceeded = true
                panel = nil
            }) { $0.thumbnail() }
        case .information:
            NavigationStack {
                GalleryItemInformation(item: item)
                    .navigationTitle("Informações")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Concluído") { panel = nil } }
            }
        case .edit:
            MomentraPhotoEditor(load: { try await item.input() }, date: item.date,
                                profile: item.profile, stampProfiles: profiles) { url in
                let original = OriginalFile(url: url, isVideo: false, isProcessed: true, date: item.date)
                let copy = GalleryItem(source: .capture(original), date: item.date, profile: item.profile)
                items.append(copy)
                selection = copy.id
                onSavedCopy()
            }
        case .stamp:
            NavigationStack {
                GalleryItemStamp(item: item, profiles: profiles) {
                    onSavedCopy()
                    message = "Cópia com carimbo criada em Capturas."
                    panel = nil
                }
            }
        case .text:
            NavigationStack {
                GalleryLoadedText(item: item)
                    .navigationTitle("Texto da foto").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Concluído") { panel = nil } }
            }
        }
    }

    private func markFavorite(_ item: GalleryItem, starred: Bool) {
        guard !busy, item.canFavorite else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await favorite(item); favoriteStates[item.id] = !starred }
            catch { message = "Não foi possível atualizar os favoritos." }
        }
    }

    private func trash(_ item: GalleryItem) {
        guard !busy, item.canTrash else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await item.moveToTrash()
                onTrash(item)
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items.remove(at: index)
                    if items.isEmpty { dismiss() }
                    else if selection == item.id { selection = items[min(index, items.count - 1)].id }
                }
            } catch {
                if (error as NSError).code != PHPhotosError.Code.userCancelled.rawValue {
                    message = "Não foi possível mover o item para a lixeira. Verifique as permissões e os envios pendentes."
                }
            }
        }
    }

    private func saveToPhotos(_ item: GalleryItem) {
        guard !busy, case .capture(let capture) = item.source else { return }
        busy = true
        Task {
            defer { busy = false }
            let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard access == .authorized || access == .limited else {
                message = "Permita o acesso ao Fotos nos Ajustes do iPhone."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: item.isVideo ? .video : .photo,
                                                                  fileURL: capture.url, options: nil)
                }
                message = "Arquivo salvo no Fotos."
            } catch { message = "Não foi possível salvar a captura no Fotos." }
        }
    }
}

private struct GalleryItemInformation: View {
    let item: GalleryItem
    @State private var details: GalleryFileInformation?

    var body: some View {
        Form {
            LabeledContent("Origem", value: item.displaySource)
            LabeledContent("Tipo", value: item.isVideo ? "Vídeo" : "Foto")
            if let date = item.date { LabeledContent("Data", value: date.formatted(date: .abbreviated, time: .shortened)) }
            if let profile = item.profile { LabeledContent("Perfil", value: profile.name) }
            if let originalDate = details?.originalDate { LabeledContent("Data original", value: originalDate) }
            if let dimensions = details?.dimensions { LabeledContent("Dimensões", value: dimensions) }
            if let size = details?.size { LabeledContent("Tamanho", value: size) }
            if let point = details?.location?.coordinate {
                LabeledContent("Coordenadas", value: String(format: "%.6f, %.6f", point.latitude, point.longitude))
            }
        }
        .task(id: item.id) {
            if let input = try? await item.input() { details = GalleryFileInformation(url: input.url) }
        }
    }
}

private struct GalleryLoadedText: View {
    let item: GalleryItem
    @State private var input: PhotoEditorInput?
    @State private var failed = false

    var body: some View {
        Group {
            if let input { CaptureTextPanel(url: input.url) }
            else if failed { ContentUnavailableView("Foto indisponível", systemImage: "photo.badge.exclamationmark") }
            else { ProgressView("Abrindo foto…") }
        }
        .task(id: item.id) {
            do { input = try await item.input() }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}

private struct GalleryItemStamp: View {
    let item: GalleryItem
    let profiles: [StampProfile]
    let didSave: () -> Void
    @State private var profileID: UUID?
    @State private var saving = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Picker("Perfil do carimbo", selection: $profileID) {
                Text("Selecione").tag(UUID?.none)
                ForEach(profiles) { profile in
                    Text(profile.name.isEmpty ? "Sem nome" : profile.name).tag(Optional(profile.id))
                }
            }
            Button("Adicionar carimbo em uma cópia", action: save)
                .disabled(saving || item.date == nil || profileID == nil)
            if saving { ProgressView("Aplicando carimbo…") }
            if item.date == nil { Text("A data da foto não está disponível.").font(.footnote) }
        }
        .onAppear { profileID = item.profile?.id ?? profiles.first?.id }
        .navigationTitle("Adicionar carimbo").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Cancelar") { dismiss() }.disabled(saving) }
        .interactiveDismissDisabled(saving)
        .alert("Não foi possível criar a cópia com carimbo", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func save() {
        guard !saving, let date = item.date, let profile = profiles.first(where: { $0.id == profileID }) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let input = try await item.input()
                _ = try await GalleryPhotoActions.copyWithStamp(url: input.url, date: date, profile: profile)
                didSave()
            } catch { failed = true }
        }
    }
}
