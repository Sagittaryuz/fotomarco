import SwiftUI
import Photos

struct OriginalsView: View {
    @ObservedObject var stampProfiles: StampProfilesStore
    let returnToCamera: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var archive = CloudArchiveAccounts.shared
    @AppStorage("native.gallery.favoriteCaptureKeys") private var captureFavorites = Data()
    @AppStorage("native.gallery.favoriteCloudKeys") private var cloudFavorites = Data()
    @State private var deviceFavorites: [String: Bool] = [:]
    @State private var local: [GalleryItem] = []
    @State private var localTrash: [GalleryItem] = []
    @State private var remote: [GalleryItem] = []
    @State private var remoteTrash: [GalleryItem] = []
    @State private var tab: Tab = .captures
    @State private var origin: GalleryOrigin?
    @State private var profile: UUID?
    @State private var columns = 3
    @State private var selecting = false
    @State private var selected: Set<GalleryItem.ID> = []
    @State private var pane: Pane?
    @State private var detail: GalleryItem?
    @State private var trashItem: GalleryItem?
    @State private var quickShare: GalleryItem?
    @State private var shared: GalleryShareBatch?
    @State private var leavingToCamera = false
    @State private var confirmBatch = false
    @State private var busy = false
    @State private var loading = false
    @State private var message: String?
    @State private var cloudError = false
    @State private var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var reloadVersion = 0
    @State private var scrollRequest = 0

    private enum Tab: String, CaseIterable {
        case captures = "Capturas", favorites = "Favoritos", trash = "Lixeira"

        var icon: String {
            switch self {
            case .captures: "photo.on.rectangle"
            case .favorites: "heart.fill"
            case .trash: "trash"
            }
        }
    }

    private enum Pane: String, Identifiable {
        case search, selection
        var id: Self { self }
    }

    private var visibleItems: [GalleryItem] {
        let items = tab == .trash ? localTrash + remoteTrash : local + remote
        let captures = Self.decode(captureFavorites)
        let cloud = Self.decode(cloudFavorites)
        return items.filter {
            (origin == nil || $0.origin == origin) && (profile == nil || $0.profile?.id == profile) &&
            (tab != .favorites || $0.isFavorite(in: captures, cloud: cloud, device: deviceFavorites))
        }.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        }
    }

    var body: some View {
        let items = visibleItems
        let groups = GalleryGrouping.groups(items, date: \.date, profile: { _ in nil }).reversed().map {
            GalleryGroup(date: $0.date, profile: nil, items: $0.items, showsProfile: false)
        }
        VStack(spacing: 0) {
            header(total: items.count, latest: items.last?.date)
            if tab == .captures {
                ScrollView {
                    GalleryCapacitySummary(section: 0, accounts: archive.accounts, compact: true)
                }
                .scrollIndicators(.hidden)
                .frame(height: min(CGFloat(archive.accounts.count + 1) * 24, 76))
            }
            if cloudError, origin != .local {
                Button { reloadVersion += 1 } label: {
                    Label("Algumas contas estão indisponíveis. Tentar novamente", systemImage: "arrow.clockwise")
                        .font(.caption).lineLimit(2)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
            }
            if tab == .trash {
                trashSources
            }
            if items.isEmpty {
                emptyState
            } else {
                GalleryGrid(groups: groups, selecting: $selecting, selected: $selected, columns: $columns,
                            newestScrollRequest: scrollRequest, tile: tile,
                            open: open, longPress: tab == .trash ? nil : { quickShare = $0 })
                    .accessibilityIdentifier("momentra-gallery-grid")
            }
            if selecting {
                GallerySelectionBar(count: selected.count, busy: busy,
                                    review: { pane = .selection }, delete: { confirmBatch = true }) {
                    Button { shareSelection(items) } label: { GalleryShareIcon() }
                }
            } else { footer }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .task(id: reloadVersion) { await reload() }
        .onChange(of: archive.accounts.map(\.id)) { _, _ in reloadVersion += 1 }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reloadVersion += 1 } }
        .onChange(of: tab) { oldTab, newTab in
            resetSelection()
            scrollRequest += 1
            if oldTab == .trash || newTab == .trash { reloadVersion += 1 }
        }
        .onChange(of: origin) { _, _ in resetSelection(); scrollRequest += 1 }
        .onChange(of: profile) { _, _ in resetSelection(); scrollRequest += 1 }
        .fullScreenCover(item: $detail, onDismiss: detailDismissed) { item in
            MomentraGalleryDetail(items: detailItems(fallback: item), initial: item,
                                  profiles: stampProfiles.profiles,
                                  isFavorite: isFavorite, favorite: toggleFavorite,
                                  onTrash: { item in
                                      local.removeAll { $0.id == item.id }
                                      remote.removeAll { $0.id == item.id }
                                  },
                                  onSavedCopy: { reloadVersion += 1 },
                                  returnToCamera: { leavingToCamera = true; detail = nil })
        }
        .fullScreenCover(item: $quickShare) { item in
            GalleryQuickShare(load: { try await item.input() }, isVideo: item.isVideo)
        }
        .sheet(item: $trashItem) { item in trashDetail(item) }
        .sheet(item: $shared) { GalleryShareBatch.Sheet(batch: $0) }
        .fullScreenCover(item: $pane, onDismiss: searchDismissed) { active in
            if active == .search {
                GalleryContentSearch(items: Array(items.reversed()), keywords: \.keywordText,
                                     imageURL: { item in
                                         guard !item.isVideo else { return nil }
                                         return try await item.input()
                                     }, onOpen: { item in
                                         pendingSearchResult = item
                                         pane = nil
                                     }) { item in item.thumbnail() }
            } else {
                GallerySelectionSheet(items: items, selected: $selected) { $0.thumbnail() }
            }
        }
        .confirmationDialog("Mover a seleção para a lixeira?", isPresented: $confirmBatch, titleVisibility: .visible) {
            Button("Mover para a lixeira", role: .destructive) { trashSelection(items) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Cada item vai para a lixeira da sua origem.")
        }
        .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    @State private var pendingSearchResult: GalleryItem?

    private func header(total: Int, latest: Date?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").frame(width: 44, height: 44)
                        .modifier(GalleryControlSurface())
                }.accessibilityLabel("Fechar galeria")
                Text(tab.rawValue).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.65)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                originMenu
                profileMenu
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(total == 1 ? "1 item" : "\(total.formatted()) itens")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let latest {
                        Text((Calendar.current.isDateInToday(latest) ? "Hoje · " : "") +
                             latest.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if tab != .trash, total > 0 {
                    Button {
                        if selecting { resetSelection() } else { selecting = true }
                    } label: {
                        Text(selecting ? "Cancelar" : "Selecionar").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: 42)
                            .modifier(GalleryControlSurface())
                    }.disabled(busy)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 7)
    }

    private var originMenu: some View {
        Menu {
            Button { origin = nil } label: { menuLabel("Todos", active: origin == nil) }
            ForEach(GalleryOrigin.allCases) { source in
                Button { origin = source } label: { menuLabel(source.title, active: origin == source) }
            }
            if authorization == .notDetermined {
                Button("Permitir acesso ao Fotos") {
                    Task { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite); reloadVersion += 1 }
                }
            } else if authorization == .denied || authorization == .restricted {
                if let url = URL(string: UIApplication.openSettingsURLString) { Link("Ajustes do Fotos", destination: url) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44)
                .modifier(GalleryControlSurface(tint: origin == nil ? .primary : .yellow))
        }
        .accessibilityLabel("Filtrar por origem")
        .accessibilityValue(origin?.title ?? "Todos")
    }

    private var profileMenu: some View {
        Menu {
            Button { profile = nil } label: { menuLabel("Todos os perfis", active: profile == nil) }
            ForEach(stampProfiles.profiles) { item in
                Button { profile = item.id } label: {
                    menuLabel(item.name.isEmpty ? "Sem nome" : item.name, active: profile == item.id)
                }
            }
        } label: {
            Image(systemName: "person.crop.circle").frame(width: 44, height: 44)
                .modifier(GalleryControlSurface(tint: profile == nil ? .primary : .yellow))
        }
        .accessibilityLabel("Filtrar por perfil")
    }

    @ViewBuilder private func menuLabel(_ title: String, active: Bool) -> some View {
        if active { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { choice in
                    Button { tab = choice } label: {
                        VStack(spacing: 3) {
                            Image(systemName: choice.icon).font(.callout.weight(.semibold))
                            Text(choice.rawValue).font(.caption2.weight(.semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(tab == choice ? .yellow : .white)
                        .background(tab == choice ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .accessibilityLabel(choice.rawValue)
                    .accessibilityAddTraits(tab == choice ? .isSelected : [])
                }
            }
            .padding(4).modifier(GalleryControlSurface(interactive: false))
            Button { pane = .search } label: {
                Image(systemName: "magnifyingglass").font(.title3.weight(.medium))
                    .frame(width: 54, height: 54)
                    .modifier(GalleryControlSurface(tint: .yellow))
            }.accessibilityLabel("Buscar")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 13).padding(.vertical, 7)
    }

    private var trashSources: some View {
        VStack(alignment: .leading, spacing: 4) {
            if origin == nil || origin == .local {
                Text("Apagados do Fotos fica no app Fotos.")
            }
            if origin == nil || origin == .oneDrive {
                Text("Arquivos excluídos no OneDrive podem ser recuperados na lixeira da conta.")
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
    }

    @ViewBuilder private var emptyState: some View {
        if loading {
            ProgressView("Carregando galeria…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(tab == .trash ? "Lixeira vazia" : tab == .favorites ?
                                   "Nenhum favorito" : "Nenhuma captura",
                                   systemImage: tab.icon).frame(maxHeight: .infinity)
        }
    }

    private func tile(_ item: GalleryItem) -> some View {
        item.thumbnail().overlay(alignment: .bottomTrailing) {
            if tab == .trash {
                let days = item.daysRemaining()
                Text(days.map { $0 == 1 ? "1 dia" : "\($0) dias" } ?? "Prazo no provedor")
                    .font(.caption2.weight(.semibold)).padding(5)
                    .background(.black.opacity(0.8), in: Capsule()).padding(4)
            }
        }
    }

    private func trashDetail(_ item: GalleryItem) -> some View {
        NavigationStack {
            VStack(spacing: 14) {
                item.preview(active: true)
                if let days = item.daysRemaining() {
                    Text(days == 1 ? "1 dia para exclusão definitiva" : "\(days) dias para exclusão definitiva")
                        .font(.footnote)
                } else { Text("Consulte o prazo na lixeira do provedor.").font(.footnote) }
                if item.canRestore {
                    Button("Restaurar") { restore(item) }.buttonStyle(.borderedProminent)
                        .tint(.yellow).foregroundStyle(.black).disabled(busy)
                }
            }.padding()
                .navigationTitle("Lixeira")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Concluído") { trashItem = nil }.disabled(busy) }
                .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK") { message = nil }
                } message: { Text(message ?? "") }
        }
        .interactiveDismissDisabled(busy)
    }

    private func open(_ item: GalleryItem) {
        if tab == .trash { trashItem = item } else { detail = item }
    }

    private func detailItems(fallback: GalleryItem) -> [GalleryItem] {
        let items = visibleItems
        return items.contains { $0.id == fallback.id } ? items : [fallback]
    }

    private func searchDismissed() {
        if let item = pendingSearchResult {
            pendingSearchResult = nil
            open(item)
        }
    }

    private func detailDismissed() {
        if leavingToCamera {
            leavingToCamera = false
            returnToCamera()
        } else { reloadVersion += 1 }
    }

    private func resetSelection() { selecting = false; selected.removeAll() }

    private func reload() async {
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        let source = await Task.detached(priority: .utility) {
            (PhotoProfileIndex.load(), try? OriginalStore.files(), try? OriginalStore.files(inTrash: true))
        }.value
        guard !Task.isCancelled else { return }
        let lookup = source.0
        if let files = source.1 {
            local = files.map { Self.capture($0, lookup: lookup) }
            authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if authorization == .authorized || authorization == .limited {
                let assets = PHAsset.fetchAssets(with: .image, options: nil)
                var photos: [GalleryItem] = []
                assets.enumerateObjects { asset, _, _ in
                    photos.append(GalleryItem(source: .device(asset), date: asset.creationDate,
                                              profile: lookup.assets[asset.localIdentifier]))
                }
                local.append(contentsOf: photos)
            }
        }
        if let files = source.2 { localTrash = files.map { Self.capture($0, lookup: lookup) } }
        if remote.isEmpty { scrollRequest += 1 }
        let accounts = archive.accounts
        let showingTrash = tab == .trash
        if accounts.isEmpty { remote = []; remoteTrash = []; cloudError = false; return }
        var results: [GalleryItem] = []
        var failed = false
        for account in accounts {
            do {
                var next: String?
                var prior: GalleryCloudItem.Page?
                var seen: Set<String> = []
                repeat {
                    try Task.checkCancellation()
                    let page: GalleryCloudItem.Page
                    if showingTrash {
                        page = try await GalleryCloudItem.loadTrash(for: account, pageToken: next, reusing: prior)
                    } else {
                        page = try await GalleryCloudItem.load(for: account, pageToken: next, reusing: prior)
                    }
                    results.append(contentsOf: page.items.map {
                        GalleryItem(source: .cloud($0), date: $0.captureDate(lookup: lookup), profile: $0.profileTag(lookup: lookup))
                    })
                    prior = page
                    next = page.nextPage.flatMap { seen.insert($0).inserted ? $0 : nil }
                } while next != nil
            } catch {
                if Task.isCancelled { return }
                failed = true
            }
        }
        guard !Task.isCancelled else { return }
        var ids = Set<String>()
        let unique = results.filter { ids.insert($0.id).inserted }
        if showingTrash { remoteTrash = unique } else { remote = unique }
        cloudError = failed
        scrollRequest += 1
    }

    private static func capture(_ item: OriginalFile, lookup: PhotoProfileLookup) -> GalleryItem {
        let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent)
        return GalleryItem(source: .capture(item), date: id.flatMap { lookup.dates[$0] } ?? item.date,
                           profile: id.flatMap { lookup.captures[$0] })
    }

    private static func decode(_ value: Data) -> Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: value)) ?? []
    }

    private func isFavorite(_ item: GalleryItem) -> Bool {
        item.isFavorite(in: Self.decode(captureFavorites), cloud: Self.decode(cloudFavorites), device: deviceFavorites)
    }

    private func toggleFavorite(_ item: GalleryItem) async throws {
        switch item.source {
        case .capture(let capture):
            captureFavorites = try toggled(captureFavorites, key: GalleryItem.captureFavoriteKey(capture))
        case .cloud(let cloud):
            cloudFavorites = try toggled(cloudFavorites, key: cloud.favoriteKey)
        case .device(let asset):
            let value = !isFavorite(item)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = value
            }
            deviceFavorites[asset.localIdentifier] = value
        }
    }

    private func toggled(_ data: Data, key: String) throws -> Data {
        var keys = Self.decode(data)
        if !keys.insert(key).inserted { keys.remove(key) }
        return try JSONEncoder().encode(keys)
    }

    private func shareSelection(_ items: [GalleryItem]) {
        let chosen = items.filter { selected.contains($0.id) }
        guard !busy, !chosen.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do { shared = try await GalleryShareBatch.prepare(chosen) { try await $0.copy(to: $1) } }
            catch { message = "Não foi possível preparar os itens selecionados." }
        }
    }

    private func trashSelection(_ items: [GalleryItem]) {
        let chosen = items.filter { selected.contains($0.id) }
        guard !busy, !chosen.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            var failed = false
            var deleted = Set<String>()
            for item in chosen {
                if case .device = item.source { continue }
                do { try await item.moveToTrash(); deleted.insert(item.id) } catch { failed = true }
            }
            let assets = chosen.compactMap { item -> PHAsset? in
                if case .device(let asset) = item.source { return asset }
                return nil
            }
            if !assets.isEmpty {
                if assets.allSatisfy({ $0.canPerform(.delete) }) {
                    do {
                        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets as NSArray) }
                        deleted.formUnion(assets.map { "device/" + $0.localIdentifier })
                    } catch {
                        if (error as NSError).code != PHPhotosError.Code.userCancelled.rawValue { failed = true }
                    }
                } else { failed = true }
            }
            if !deleted.isEmpty {
                local.removeAll { deleted.contains($0.id) }
                remote.removeAll { deleted.contains($0.id) }
                resetSelection()
            }
            if failed { message = "Alguns itens não puderam ser movidos. Verifique as permissões e os envios pendentes." }
            reloadVersion += 1
        }
    }

    private func restore(_ item: GalleryItem) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await item.restore()
                localTrash.removeAll { $0.id == item.id }
                remoteTrash.removeAll { $0.id == item.id }
                trashItem = nil
                reloadVersion += 1
            } catch { message = "Não foi possível restaurar este item." }
        }
    }
}
