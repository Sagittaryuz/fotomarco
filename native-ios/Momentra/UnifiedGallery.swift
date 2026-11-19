import SwiftUI
import Photos

struct OriginalsView: View {
    @ObservedObject var stampProfiles: StampProfilesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var storageBandHeight = 44.0
    @StateObject private var archive = CloudArchiveAccounts.shared
    @AppStorage("native.gallery.favoriteCaptureKeys") private var captureFavorites = Data()
    @AppStorage("native.gallery.favoriteCloudKeys") private var cloudFavorites = Data()
    @State private var deviceFavorites: [String: Bool] = [:]
    @State private var local: [GalleryItem] = []
    @State private var trackedPhotos: [GalleryItem] = []
    @State private var favoritePhotos: [GalleryItem] = []
    @State private var localTrash: [GalleryItem] = []
    @State private var remote: [GalleryItem] = []
    @State private var remoteTrash: [GalleryItem] = []
    @State private var cloudPages: [CloudDeliveryPlan.Destination: GalleryCloudItem.Page] = [:]
    @State private var projection = GalleryProjection()
    @State private var projectionVersion = 0
    @State private var catalogLoaded = false
    @State private var cloudRefresh = 0
    @State private var cloudActivation = 0
    @State private var cloudSyncing = false
    @State private var quotaSyncing = false
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
    @State private var confirmBatch = false
    @State private var busy = false
    @State private var loading = false
    @State private var message: String?
    @State private var cloudError = false
    @State private var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var reloadVersion = 0
    @State private var scrollRequest = 0
    @State private var galleryVisible = false
    @State private var galleryDrag = CGSize.zero
    @State private var galleryExit: ExitDirection?
    @State private var galleryFooterHeight: CGFloat = 74

    private enum ExitDirection { case left, down }

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

    private struct GalleryProjection {
        var items: [GalleryItem] = []
        var sections: [GalleryGroup<GalleryItem>] = []
    }

    private func updateProjection() {
        let photos = tab == .favorites ? favoritePhotos : trackedPhotos
        let source = tab == .trash ? localTrash + remoteTrash : local + remote + photos
        let captures = tab == .favorites ? Self.decode(captureFavorites) : []
        let cloud = tab == .favorites ? Self.decode(cloudFavorites) : []
        let items = source.filter {
            (origin == nil || $0.origin == origin) && (profile == nil || $0.profile?.id == profile) &&
            (tab != .favorites || $0.isFavorite(in: captures, cloud: cloud, device: deviceFavorites))
        }.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        }
        let sections = GalleryGrouping.groups(items, date: \.date, profile: { _ in nil }).reversed().map {
            GalleryGroup(date: $0.date, profile: nil, items: $0.items, showsProfile: false)
        }
        projection = GalleryProjection(items: items, sections: sections)
        projectionVersion += 1
    }

    var body: some View {
        GeometryReader { geometry in
            let distance = max(abs(galleryDrag.width), abs(galleryDrag.height))
            let dragOpacity = 1 - min(0.22, Double(distance) / 650)
            galleryContent
                .blur(radius: reduceMotion ? 0 : !galleryVisible || galleryExit != nil ? 16 : min(9, distance / 20))
                .opacity(reduceMotion ? 1 : !galleryVisible || galleryExit != nil ? 0 : dragOpacity)
                .offset(x: galleryExit == .left ? -geometry.size.width - 30 : galleryDrag.width,
                        y: galleryExit == .down ? geometry.size.height + 30 : galleryDrag.height)
                .allowsHitTesting(galleryExit == nil)
        }
        .presentationBackground(.clear)
        .task {
            guard !galleryVisible else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26)) { galleryVisible = true }
        }
    }

    private var galleryContent: some View {
        let items = projection.items
        VStack(spacing: 0) {
            header(total: items.count, latest: items.last?.date)
                .contentShape(Rectangle())
                .simultaneousGesture(gallerySwipe(toward: .down))
            GalleryCapacitySummary(section: 0, accounts: archive.accounts, compact: true,
                                   syncingCatalog: cloudSyncing, syncingQuota: $quotaSyncing,
                                   refresh: cloudActivation + cloudRefresh)
                .frame(height: tab == .captures ? storageBandHeight : 0)
                .clipped()
                .accessibilityHidden(tab != .captures)
            if cloudError, origin != .local {
                Button { cloudRefresh += 1 } label: {
                    Label("Algumas contas estão indisponíveis. Tentar novamente", systemImage: "arrow.clockwise")
                        .font(.caption).lineLimit(2)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
            }
            if tab == .trash {
                trashSources
            }
            Group {
                if items.isEmpty {
                    emptyState
                        .contentShape(Rectangle())
                        .simultaneousGesture(gallerySwipe(toward: .left))
                } else {
                    GalleryGrid(groups: projection.sections, selecting: $selecting, selected: $selected, columns: $columns,
                                contentVersion: projectionVersion, newestScrollRequest: scrollRequest,
                                bottomInset: selecting ? 0 : galleryFooterHeight,
                                tile: tile, open: open, longPress: tab == .trash ? nil : { quickShare = $0 },
                                reachedEnd: tab == .captures && !archive.accounts.isEmpty ? refreshFromEnd : nil,
                                dragToCamera: { distance, ended in trackSwipe(distance, toward: .left, ended: ended) })
                        .accessibilityIdentifier("momentra-gallery-grid")
                }
            }
            .overlay(alignment: .bottom) {
                if !selecting {
                    footer.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { galleryFooterHeight = $0 }
                }
            }
            if selecting {
                GallerySelectionBar(count: selected.count, busy: busy,
                                    review: { pane = .selection }, delete: { confirmBatch = true }) {
                    Button { shareSelection(items) } label: { GalleryShareIcon() }
                }
            }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .task(id: reloadVersion) { await reloadLocal() }
        .task(id: CatalogRequest(trash: tab == .trash, destinations: archive.accounts.map(\.id),
                                 refresh: cloudRefresh, activation: cloudActivation)) {
            await reloadCloud(trash: tab == .trash)
        }
        .onChange(of: archive.accounts.map(\.id)) { _, destinations in
            remote.removeAll { item in
                if case .cloud(let cloud) = item.source { return !destinations.contains(cloud.destination) }
                return false
            }
            remoteTrash.removeAll { item in
                if case .cloud(let cloud) = item.source { return !destinations.contains(cloud.destination) }
                return false
            }
            cloudPages = cloudPages.filter { destinations.contains($0.key) }
            catalogLoaded = false
            updateProjection()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reloadVersion += 1; cloudActivation += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudGalleryCatalog.deliveryChanged)) { _ in
            reloadVersion += 1
            cloudActivation += 1
        }
        .onChange(of: tab) { _, _ in
            resetSelection()
            scrollRequest += 1
            updateProjection()
            reloadVersion += 1
        }
        .onChange(of: origin) { _, _ in resetSelection(); scrollRequest += 1; updateProjection() }
        .onChange(of: profile) { _, _ in resetSelection(); scrollRequest += 1; updateProjection() }
        .onChange(of: captureFavorites) { _, _ in if tab == .favorites { updateProjection() } }
        .onChange(of: cloudFavorites) { _, _ in if tab == .favorites { updateProjection() } }
        .fullScreenCover(item: $detail, onDismiss: { reloadVersion += 1 }) { item in
            MomentraGalleryDetail(items: detailItems(fallback: item), initial: item,
                                  profiles: stampProfiles.profiles,
                                  isFavorite: isFavorite, favorite: toggleFavorite,
                                  onTrash: { item in
                                      local.removeAll { $0.id == item.id }
                                      trackedPhotos.removeAll { $0.id == item.id }
                                      favoritePhotos.removeAll { $0.id == item.id }
                                      remote.removeAll { $0.id == item.id }
                                      updateProjection()
                                      if item.origin != .local { cloudRefresh += 1 }
                                  },
                                  onSavedCopy: { reloadVersion += 1 })
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button { closeGallery(toward: .down) } label: {
                    Image(systemName: "chevron.down").frame(width: 44, height: 44)
                        .modifier(GalleryControlSurface(rounded: true))
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
                            .modifier(GalleryControlSurface(rounded: true))
                    }.disabled(busy)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 13).padding(.top, 8).padding(.bottom, 5)
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
                .modifier(GalleryControlSurface(rounded: true, tint: origin == nil ? .primary : .yellow))
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
                .modifier(GalleryControlSurface(rounded: true, tint: profile == nil ? .primary : .yellow))
        }
        .accessibilityLabel("Filtrar por perfil")
    }

    @ViewBuilder private func menuLabel(_ title: String, active: Bool) -> some View {
        if active { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    @ViewBuilder private var footer: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 0) { footerControls }
        } else {
            footerControls
        }
    }

    private var footerControls: some View {
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
                        .background(tab == choice ? Color.white.opacity(0.08) : .clear, in: Capsule())
                    }
                    .accessibilityLabel(choice.rawValue)
                    .accessibilityAddTraits(tab == choice ? .isSelected : [])
                }
            }
            .padding(5).modifier(GalleryControlSurface(rounded: true, interactive: false))
            Button { pane = .search } label: {
                Image(systemName: "magnifyingglass").font(.title3.weight(.medium))
                    .frame(width: 54, height: 54)
                    .modifier(GalleryControlSurface(rounded: true, tint: .yellow))
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
        let items = projection.items
        return items.contains { $0.id == fallback.id } ? items : [fallback]
    }

    private func searchDismissed() {
        if let item = pendingSearchResult {
            pendingSearchResult = nil
            open(item)
        }
    }

    private func resetSelection() { selecting = false; selected.removeAll() }

    private func gallerySwipe(toward direction: ExitDirection) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { trackSwipe(swipeDistance($0.translation, toward: direction), toward: direction, ended: false) }
            .onEnded { trackSwipe(swipeDistance($0.translation, toward: direction), toward: direction, ended: true) }
    }

    private func swipeDistance(_ translation: CGSize, toward direction: ExitDirection) -> CGFloat {
        let primary = direction == .left ? -translation.width : translation.height
        let cross = direction == .left ? translation.height : translation.width
        return primary > abs(cross) * 1.35 ? primary : 0
    }

    private func trackSwipe(_ distance: CGFloat, toward direction: ExitDirection, ended: Bool) {
        guard !busy, !selecting, galleryExit == nil else { return }
        if ended {
            if distance >= 82 { closeGallery(toward: direction) }
            else { withAnimation(.easeOut(duration: 0.19)) { galleryDrag = .zero } }
        } else if !reduceMotion {
            let movement = min(220, max(0, distance) * 0.76)
            galleryDrag = direction == .left ? CGSize(width: -movement, height: 0) : CGSize(width: 0, height: movement)
        }
    }

    private func closeGallery(toward direction: ExitDirection) {
        guard galleryExit == nil else { return }
        if reduceMotion { dismissWithoutAnimation(); return }
        withAnimation(.easeInOut(duration: 0.24), completionCriteria: .logicallyComplete) {
            galleryExit = direction
            galleryDrag = .zero
        } completion: {
            dismissWithoutAnimation()
        }
    }

    private func dismissWithoutAnimation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { dismiss() }
    }

    private func refreshFromEnd() {
        guard !cloudSyncing, !quotaSyncing, cloudRefresh == lastCatalogRefresh else { return }
        cloudRefresh += 1
    }

    private struct CatalogRequest: Equatable {
        let trash: Bool
        let destinations: [CloudDeliveryPlan.Destination]
        let refresh: Int
        let activation: Int
    }

    private func reloadLocal() async {
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        let activeTab = tab
        let source = await Task.detached(priority: .utility) { () -> (files: [GalleryItem], photos: [GalleryItem])? in
            let lookup = PhotoProfileIndex.load()
            guard let files = try? OriginalStore.files(inTrash: activeTab == .trash) else { return nil }
            let items = files.map { Self.capture($0, lookup: lookup) }
            if activeTab == .trash { return (items, []) }
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else { return (items, []) }
            let options = PHFetchOptions()
            let imageTypes = [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue]
            let assets: PHFetchResult<PHAsset>
            if activeTab == .favorites {
                options.predicate = NSPredicate(format: "favorite == YES AND mediaType IN %@", imageTypes)
                assets = PHAsset.fetchAssets(with: options)
            } else {
                let ids = Array(lookup.assets.keys)
                guard !ids.isEmpty else { return (items, []) }
                options.predicate = NSPredicate(format: "mediaType IN %@", imageTypes)
                assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
            }
            var photos: [GalleryItem] = []
            photos.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in
                photos.append(GalleryItem(source: .device(asset), date: asset.creationDate,
                                         profile: lookup.assets[asset.localIdentifier]))
            }
            return (items, photos)
        }.value
        guard !Task.isCancelled, activeTab == tab, let source else { return }
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let wasEmpty = projection.items.isEmpty
        if activeTab == .trash {
            localTrash = source.files
        } else {
            local = source.files
            if activeTab == .favorites { favoritePhotos = source.photos }
            else { trackedPhotos = source.photos }
        }
        updateProjection()
        if wasEmpty { scrollRequest += 1 }
    }

    private func reloadCloud(trash: Bool) async {
        cloudSyncing = false
        let accounts = archive.accounts
        let refresh = cloudRefresh
        guard !accounts.isEmpty else { remote = []; remoteTrash = []; cloudError = false; updateProjection(); return }
        let catalog = CloudGalleryCatalog.shared
        let force = refresh != lastCatalogRefresh
        var snapshots: [CloudDeliveryPlan.Destination: CloudGalleryCatalog.Snapshot] = [:]
        if !trash {
            for account in accounts { snapshots[account.id] = await catalog.snapshot(for: account.id) }
            guard !Task.isCancelled else { return }
        }
        let stale = accounts.filter { snapshots[$0.id]?.needsRefresh() != false }
        if !trash && catalogLoaded && !force && stale.isEmpty { return }
        let lookup = await Task.detached(priority: .utility) { PhotoProfileIndex.load() }.value
        guard !Task.isCancelled else { return }
        if !trash && !catalogLoaded && !snapshots.isEmpty {
            let alreadyShown = Set(remote.compactMap { item -> CloudDeliveryPlan.Destination? in
                if case .cloud(let cloud) = item.source { return cloud.destination }
                return nil
            })
            let cached = accounts.flatMap { account -> [GalleryCloudItem] in
                guard !alreadyShown.contains(account.id), let snapshot = snapshots[account.id] else { return [] }
                let page = GalleryCloudItem.cachedPage(snapshot.entries, for: account, reusing: cloudPages[account.id])
                cloudPages[account.id] = page
                return page.items
            }
            catalogLoaded = true
            if !cached.isEmpty { applyCloud(remote + cached.map { galleryItem($0, lookup: lookup) }, trash: false) }
        }
        if !trash && !force && stale.isEmpty { return }
        cloudSyncing = !trash
        defer { if !Task.isCancelled { cloudSyncing = false } }
        var results: [GalleryItem] = []
        var failed = false
        let priorItems = Dictionary(grouping: trash ? remoteTrash : remote) { item -> CloudDeliveryPlan.Destination? in
            if case .cloud(let cloud) = item.source { return cloud.destination }
            return nil
        }
        for account in accounts {
            let previous = priorItems[account.id] ?? []
            let snapshot = snapshots[account.id]
            if !trash && !force && snapshot?.needsRefresh() == false {
                results += previous
                continue
            }
            do {
                var next: String?
                var prior = cloudPages[account.id]
                var seen: Set<String> = []
                var accountItems: [GalleryCloudItem] = []
                repeat {
                    try Task.checkCancellation()
                    let page: GalleryCloudItem.Page
                    if trash {
                        page = try await GalleryCloudItem.loadTrash(for: account, pageToken: next, reusing: prior)
                    } else {
                        page = try await GalleryCloudItem.load(for: account, pageToken: next, reusing: prior)
                    }
                    try Task.checkCancellation()
                    if next == nil { cloudPages[account.id] = page }
                    accountItems.append(contentsOf: page.items)
                    prior = page
                    next = page.nextPage
                    if let next, !seen.insert(next).inserted { throw URLError(.cannotParseResponse) }
                } while next != nil
                if !trash {
                    let saved = await catalog.replace(accountItems.map(\.catalogEntry), for: account.id,
                                                      replacing: snapshot?.revision)
                    try Task.checkCancellation()
                    if !saved {
                        guard let current = await catalog.snapshot(for: account.id) else {
                            results += previous
                            continue
                        }
                        accountItems = GalleryCloudItem.cachedPage(current.entries, for: account, reusing: prior).items
                    }
                }
                results += accountItems.map { galleryItem($0, lookup: lookup) }
            } catch {
                if Task.isCancelled { return }
                failed = true
                results += previous
            }
        }
        guard !Task.isCancelled else { return }
        if !trash {
            catalogLoaded = true
            lastCatalogRefresh = refresh
        }
        cloudError = failed
        applyCloud(results, trash: trash)
    }

    private func galleryItem(_ cloud: GalleryCloudItem, lookup: PhotoProfileLookup) -> GalleryItem {
        GalleryItem(source: .cloud(cloud), date: cloud.captureDate(lookup: lookup), profile: cloud.profileTag(lookup: lookup))
    }

    private func applyCloud(_ results: [GalleryItem], trash: Bool) {
        var ids = Set<String>()
        let unique = results.filter { ids.insert($0.id).inserted }
        let wasEmpty = projection.items.isEmpty
        if trash {
            remoteTrash = unique
        } else {
            remote = unique
        }
        updateProjection()
        if wasEmpty || !selecting && openedAtNewest { scrollRequest += 1; openedAtNewest = false }
    }

    @State private var lastCatalogRefresh = 0
    @State private var openedAtNewest = true

    nonisolated private static func capture(_ item: OriginalFile, lookup: PhotoProfileLookup) -> GalleryItem {
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
            if tab == .favorites { updateProjection() }
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
                trackedPhotos.removeAll { deleted.contains($0.id) }
                favoritePhotos.removeAll { deleted.contains($0.id) }
                remote.removeAll { deleted.contains($0.id) }
                resetSelection()
                updateProjection()
                if chosen.contains(where: { $0.origin != .local && deleted.contains($0.id) }) { cloudRefresh += 1 }
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
                updateProjection()
                if item.origin != .local { catalogLoaded = false; cloudRefresh += 1 }
                reloadVersion += 1
            } catch { message = "Não foi possível restaurar este item." }
        }
    }
}
