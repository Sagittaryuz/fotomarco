import SwiftUI
import Photos
import CoreLocation
import ImageIO
import UniformTypeIdentifiers

private struct DeviceAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

/// Displays only assets that the user has authorized PhotoKit to reveal.
struct DevicePhotoGallery: View {
    let profileLookup: PhotoProfileLookup
    @ObservedObject var stampProfiles: StampProfilesStore
    let returnToCamera: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var assets: [DeviceAsset] = []
    @State private var selected: DeviceAsset?
    @State private var leavingForCamera = false
    @State private var quickShare: DeviceAsset?
    @State private var columnCount = 3
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showingSelection = false
    @State private var confirmingDelete = false
    @State private var actionInProgress = false
    @State private var share: GalleryShareBatch?
    @State private var actionError: String?

    private var groups: [GalleryGroup<DeviceAsset>] {
        GalleryGrouping.groups(assets, date: { $0.asset.creationDate }, profile: { item in
            guard let tag = profileLookup.assets[item.id] else { return nil }
            guard let profile = stampProfiles.profiles.first(where: { $0.id == tag.id }) else { return tag }
            return CaptureProfileTag(id: tag.id, name: profile.name)
        })
    }

    var body: some View {
        Group {
            if authorization == .authorized || authorization == .limited {
                VStack(spacing: 0) {
                    if authorization == .limited {
                        Text("Acesso limitado: aparecem somente as fotos autorizadas nos Ajustes do iPhone.")
                            .font(.footnote).foregroundStyle(.secondary).padding()
                    }
                    if assets.isEmpty {
                        ContentUnavailableView("Nenhuma foto disponível", systemImage: "photo", description: Text("Confira as fotos e a permissão de acesso no iPhone."))
                    } else {
                        GalleryGrid(groups: groups, selecting: $selecting, selected: $selectedIDs, columns: $columnCount,
                                    tile: { DeviceThumbnail(asset: $0.asset).accessibilityLabel("Foto") },
                                    open: { selected = $0 }, longPress: { quickShare = $0 })
                    }
                    if selecting {
                        GallerySelectionBar(count: selectedIDs.count, busy: actionInProgress,
                                            review: { showingSelection = true }, delete: { confirmingDelete = true }) {
                            Button(action: shareSelection) { GalleryShareIcon() }
                        }
                    }
                }
            } else if authorization == .notDetermined {
                ContentUnavailableView {
                    Label("Fotos do iPhone", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Permita o acesso para visualizar suas fotos e criar cópias com carimbo.")
                } actions: {
                    Button("Permitir acesso") { requestAccess() }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("Acesso ao Fotos desativado", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("Você pode alterar a permissão nos Ajustes do iPhone.")
                } actions: {
                    if let url = URL(string: UIApplication.openSettingsURLString) { Link("Abrir Ajustes", destination: url) }
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if authorization == .authorized || authorization == .limited {
                    Button(selecting ? "Cancelar" : "Selecionar") {
                        selecting.toggle(); if !selecting { selectedIDs.removeAll() }
                    }.disabled(actionInProgress)
                }
            }
            if selecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Selecionar todas") { selectedIDs = Set(assets.map(\.id)) }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Opções da seleção")
                    .disabled(actionInProgress)
                }
            }
        }
        .fullScreenCover(item: $selected, onDismiss: {
            if leavingForCamera {
                leavingForCamera = false
                returnToCamera()
            } else {
                refresh()
            }
        }) { item in
            DevicePhotoPager(items: groups.flatMap(\.items), initialID: item.id,
                             profile: CaptureProfileTag(id: stampProfiles.selected.id, name: stampProfiles.selected.name),
                             stampProfiles: stampProfiles.profiles,
                             returnToCamera: { leavingForCamera = true; selected = nil })
        }
        .fullScreenCover(item: $quickShare) { item in
            GalleryQuickShare(load: { try await DevicePhotoFile.editorInput(item.asset) })
        }
        .sheet(isPresented: $showingSelection) {
            GallerySelectionSheet(items: assets, selected: $selectedIDs) { DeviceThumbnail(asset: $0.asset) }
        }
        .sheet(item: $share) { GalleryShareBatch.Sheet(batch: $0) }
        .confirmationDialog("Excluir as fotos selecionadas?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Mover \(selectedIDs.count) itens para Apagados", role: .destructive, action: deleteSelection)
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Você pode recuperar os itens no álbum Apagados do app Fotos.") }
        .alert("Momentra", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func shareSelection() {
        let items = assets.filter { selectedIDs.contains($0.id) }
        guard !items.isEmpty, !actionInProgress else { return }
        actionInProgress = true
        Task {
            defer { actionInProgress = false }
            do {
                share = try await GalleryShareBatch.prepare(items) { item, directory in
                    try await DevicePhotoFile.copy(item.asset, to: directory.appendingPathComponent("Foto"))
                }
            } catch { actionError = "Não foi possível preparar as fotos selecionadas para compartilhar." }
        }
    }

    private func deleteSelection() {
        let items = assets.filter { selectedIDs.contains($0.id) }.map(\.asset)
        guard !items.isEmpty, !actionInProgress else { return }
        guard items.allSatisfy({ $0.canPerform(.delete) }) else {
            actionError = "A biblioteca Fotos não permite excluir um ou mais dos itens selecionados."
            return
        }
        actionInProgress = true
        Task {
            defer { actionInProgress = false }
            do {
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(items as NSArray) }
                selecting = false
                selectedIDs.removeAll()
                refresh()
            } catch {
                if (error as NSError).code != PHPhotosError.Code.userCancelled.rawValue {
                    actionError = "Não foi possível excluir as fotos selecionadas da biblioteca do iPhone."
                }
            }
        }
    }

    private func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
            DispatchQueue.main.async { refresh() }
        }
    }

    private func refresh() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else { assets = []; return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var list: [DeviceAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(DeviceAsset(asset: asset)) }
        assets = list
        selectedIDs.formIntersection(Set(list.map(\.id)))
    }
}

enum DevicePhotoFile {
    static func editorInput(_ asset: PHAsset) async throws -> PhotoEditorInput {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return PhotoEditorInput(url: try await copy(asset, to: temporary), temporary: true)
    }

    static func copy(_ asset: PHAsset, to target: URL) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizePhoto }) ??
                resources.first(where: { $0.type == .photo }) else { throw CocoaError(.fileReadUnknown) }
        let file = target.appendingPathExtension(UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? "jpg")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: file, options: options)
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}

private struct DevicePhotoPager: View {
    private enum Panel: String, Identifiable {
        case overview, share, information, editing
        var id: Self { self }
    }

    let profile: CaptureProfileTag
    let stampProfiles: [StampProfile]
    let returnToCamera: () -> Void
    @State private var items: [DeviceAsset]
    @State private var selection: String
    @State private var panel: Panel?
    @State private var updating = false
    @State private var favorites: [String: Bool] = [:]
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    init(items: [DeviceAsset], initialID: String, profile: CaptureProfileTag, stampProfiles: [StampProfile],
         returnToCamera: @escaping () -> Void) {
        self.profile = profile
        self.stampProfiles = stampProfiles
        self.returnToCamera = returnToCamera
        _items = State(initialValue: items)
        _selection = State(initialValue: initialID)
    }

    var body: some View {
        let index = items.firstIndex { $0.id == selection }
        let current = index.map { items[$0] }
        VStack(spacing: 0) {
            GalleryDetailHeader(date: current?.asset.creationDate,
                                position: (index ?? 0) + 1, count: items.count,
                                close: { dismiss() }, overview: { panel = .overview }) {
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
                ForEach(items) { item in
                    Group {
                        if item.id == selection {
                            DeviceThumbnail(asset: item.asset, fullView: true)
                        } else {
                            Color.clear
                        }
                    }.tag(item.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            GalleryFilmstrip(items: items, selection: $selection) { item in
                DeviceThumbnail(asset: item.asset)
            }
            if let current { controls(current) }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .modifier(GalleryCameraSwipe(action: { if !updating { returnToCamera() } }))
        .sheet(item: $panel) { route in
            if let current { sheet(route, current: current) }
        }
        .alert("Momentra", isPresented: Binding(get: { message != nil && panel == nil },
                                                set: { if !$0 && panel == nil { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func controls(_ item: DeviceAsset) -> some View {
        let favorite = favorites[item.id] ?? item.asset.isFavorite
        return HStack(spacing: 10) {
            Button { panel = .share } label: { GalleryShareIcon() }
                .accessibilityLabel("Compartilhar")
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                button(favorite ? "heart.fill" : "heart",
                       label: favorite ? "Remover dos favoritos" : "Favoritar",
                       tint: favorite ? .yellow : .primary) { favoritePhoto(item, makeFavorite: !favorite) }
                    .disabled(!item.asset.canPerform(.properties))
                button("info.circle", label: "Informações") { panel = .information }
                button("slider.horizontal.3", label: "Editar foto") { panel = .editing }
            }
            .padding(.horizontal, 3)
            .modifier(GalleryControlSurface())
            Spacer(minLength: 4)
            GalleryTrashButton(label: "Excluir foto",
                               message: "A foto vai para Apagados no app Fotos. Você pode recuperá-la por lá.") {
                trash(item)
            }
            .disabled(!item.asset.canPerform(.delete))
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
    private func sheet(_ route: Panel, current: DeviceAsset) -> some View {
        switch route {
        case .overview:
            GalleryDetailGrid(items: items, choose: {
                selection = $0.id
                panel = nil
            }) { DeviceThumbnail(asset: $0.asset) }
        case .share:
            GalleryShareComposer(items: items, current: current, copy: { item, directory in
                try await DevicePhotoFile.copy(item.asset, to: directory.appendingPathComponent("Foto"))
            }) { DeviceThumbnail(asset: $0.asset) }
        case .information:
            NavigationStack {
                DevicePhotoDetail(asset: current.asset, profile: profile)
                    .navigationTitle("Informações")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Concluído") { panel = nil } }
            }
        case .editing:
            MomentraPhotoEditor(load: { try await DevicePhotoFile.editorInput(current.asset) }, date: current.asset.creationDate,
                                profile: profile, stampProfiles: stampProfiles) { _ in message = "Cópia salva em Capturas." }
        }
    }

    private func favoritePhoto(_ item: DeviceAsset, makeFavorite: Bool) {
        guard !updating, item.asset.canPerform(.properties) else { return }
        updating = true
        Task {
            defer { updating = false }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest(for: item.asset).isFavorite = makeFavorite
                }
                favorites[item.id] = makeFavorite
            } catch { message = "Não foi possível atualizar os favoritos do Fotos." }
        }
    }

    private func trash(_ item: DeviceAsset) {
        guard !updating, item.asset.canPerform(.delete) else { return }
        updating = true
        Task {
            defer { updating = false }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets([item.asset] as NSArray)
                }
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items.remove(at: index)
                    if items.isEmpty { dismiss() }
                    else if selection == item.id { selection = items[min(index, items.count - 1)].id }
                }
            } catch {
                if (error as NSError).code != PHPhotosError.Code.userCancelled.rawValue {
                    message = "Não foi possível mover a foto para Apagados."
                }
            }
        }
    }
}

struct DeviceThumbnail: View {
    let asset: PHAsset
    var fullView = false
    @State private var thumbnail: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var loading = true

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                fullView ? Color.black : Color.gray.opacity(0.2)
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().aspectRatio(contentMode: fullView ? .fit : .fill)
                }
                else if fullView && loading { ProgressView("Abrindo foto…") }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }.frame(width: proxy.size.width, height: fullView ? proxy.size.height : proxy.size.width).clipped()
        }
        .aspectRatio(fullView ? nil : 1, contentMode: .fit)
        .onAppear {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = fullView
            let pixels: CGFloat = fullView ? 1800 : 330
            requestID = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: pixels, height: pixels),
                contentMode: fullView ? .aspectFit : .aspectFill, options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                DispatchQueue.main.async {
                    if let image { thumbnail = image }
                    if !degraded { loading = false }
                }
            }
        }
        .onDisappear { if let requestID { PHImageManager.default().cancelImageRequest(requestID) }; requestID = nil }
    }
}

struct DevicePhotoDetail: View {
    let asset: PHAsset
    let profile: CaptureProfileTag
    @State private var data: Data?
    @State private var preview: UIImage?
    @State private var originalDateText: String?
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ScrollView {
                VStack(spacing: 16) {
                    if let preview { Image(uiImage: preview).resizable().scaledToFit() }
                    else if loading { ProgressView("Abrindo foto…").padding(50) }
                    else { ContentUnavailableView("Não foi possível abrir", systemImage: "photo.badge.exclamationmark") }
                    Text(ExistingPhotoStamp.description(date: asset.creationDate, location: asset.location, originalDateText: originalDateText))
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("O carimbo cria uma cópia em Capturas. O original não será alterado. A cópia não mantém os metadados do arquivo original.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Criar cópia com carimbo") { createCopy() }
                        .buttonStyle(.borderedProminent)
                        .disabled(data == nil || saving || ExistingPhotoStamp.lines(date: asset.creationDate, location: asset.location, originalDateText: originalDateText).isEmpty)
                    if saving { ProgressView("Criando cópia…") }
                }.padding()
            }
            .onAppear { load() }
            .onDisappear { if let requestID { PHImageManager.default().cancelImageRequest(requestID) } }
            .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }

    private func load() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        requestID = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { bytes, _, _, info in
            guard (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
            DispatchQueue.main.async {
                loading = false
                guard let bytes, bytes.count <= 100 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1200
                      ] as CFDictionary) else { return }
                data = bytes
                preview = UIImage(cgImage: image)
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
                originalDateText = ExistingPhotoStamp.exifDateText(properties: properties)
            }
        }
    }

    private func createCopy() {
        guard let data, !saving else { return }
        let lines = ExistingPhotoStamp.lines(date: asset.creationDate, location: asset.location, originalDateText: originalDateText)
        guard !lines.isEmpty else { return }
        saving = true
        Task {
            let success = await Task.detached(priority: .userInitiated) { () -> Bool in
                ExistingPhotoStamp.saveCopy(data, lines: lines, profile: profile, captureDate: asset.creationDate)
            }.value
            saving = false
            message = success ? "Cópia criada em Capturas. O original foi preservado." : "Não foi possível criar a cópia. O original foi preservado."
        }
    }
}

enum ExistingPhotoStamp {
    static func saveCopy(_ data: Data, lines: [String], profile: CaptureProfileTag? = nil, captureDate: Date? = nil) -> Bool {
        guard let result = render(data, lines: lines) else { return false }
        do {
            let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = root.appendingPathComponent("Processed", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = UUID()
            let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
            try result.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            if let profile { try? PhotoProfileIndex.register(captureID: id, profile: profile, captureDate: captureDate) }
            return true
        } catch { return false }
    }

    static func lines(date: Date?, location: CLLocation?, originalDateText: String? = nil, timeZone: TimeZone = .current) -> [String] {
        var result: [String] = []
        if let originalDateText {
            result.append(originalDateText)
        } else if let date, date.timeIntervalSince1970.isFinite {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "pt_BR")
            formatter.timeZone = timeZone
            formatter.dateFormat = "dd/MM/yyyy HH:mm:ss 'GMT'XXXXX"
            result.append(formatter.string(from: date))
        }
        if let location, CLLocationCoordinate2DIsValid(location.coordinate) {
            result.append(String(format: "Lat: %.6f  Lon: %.6f", location.coordinate.latitude, location.coordinate.longitude))
        }
        return result
    }

    static func description(date: Date?, location: CLLocation?, originalDateText: String? = nil) -> String {
        let fields = lines(date: date, location: location, originalDateText: originalDateText)
        guard !fields.isEmpty else { return "Data e localização indisponíveis nesta foto." }
        let explanation = originalDateText != nil ? "\nHorário original informado pela foto." : date == nil ? "" : "\nData informada pelo Fotos, exibida no fuso atual do iPhone."
        return fields.joined(separator: "\n") + explanation
    }

    static func exifDateText(properties: [String: Any]) -> String? {
        guard let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
              raw.utf8.count == 19 else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(secondsFromGMT: 0)
        input.calendar = Calendar(identifier: .gregorian)
        input.isLenient = false
        input.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = input.date(from: raw), input.string(from: date) == raw else { return nil }
        input.dateFormat = "dd/MM/yyyy HH:mm:ss"
        let text = input.string(from: date)
        guard let offset = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String else {
            return text + " (fuso não informado)"
        }
        let chars = Array(offset.utf8)
        guard chars.count == 6, (chars[0] == 43 || chars[0] == 45), chars[3] == 58,
              [chars[1], chars[2], chars[4], chars[5]].allSatisfy({ (48...57).contains($0) }) else {
            return text + " (fuso não informado)"
        }
        let hours = Int(chars[1] - 48) * 10 + Int(chars[2] - 48)
        let minutes = Int(chars[4] - 48) * 10 + Int(chars[5] - 48)
        guard hours <= 14, minutes < 60, hours < 14 || minutes == 0 else { return text + " (fuso não informado)" }
        return text + " GMT" + offset
    }

    static func render(_ data: Data, lines: [String]) -> Data? {
        guard !lines.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 12000, height <= 12000,
              Double(width) * Double(height) <= 80_000_000,
              let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        var fits = true
        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
            let margin = min(size.width, size.height) * 0.035
            let font = UIFont.systemFont(ofSize: max(12, min(size.width, size.height) * 0.027))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let text = lines.joined(separator: "\n") as NSString
            let width = size.width - margin * 4
            guard width > 0 else { fits = false; return }
            let textSize = text.boundingRect(with: CGSize(width: width, height: size.height), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            let boxHeight = ceil(textSize.height) + margin * 2
            guard boxHeight <= size.height - margin * 2 else { fits = false; return }
            let box = CGRect(x: margin, y: size.height - margin - boxHeight, width: size.width - margin * 2, height: boxHeight)
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.65).cgColor)
            context.cgContext.fill(box)
            text.draw(in: box.insetBy(dx: margin, dy: margin), withAttributes: attrs)
        }
        return fits ? result.jpegData(compressionQuality: 0.95) : nil
    }
}
