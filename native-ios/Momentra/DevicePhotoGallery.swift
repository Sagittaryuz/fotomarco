import SwiftUI
import Photos
import CoreLocation
import ImageIO

private struct DeviceAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

/// Displays only assets that the user has authorized PhotoKit to reveal.
struct DevicePhotoGallery: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var assets: [DeviceAsset] = []
    @State private var selected: DeviceAsset?
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 3)]

    var body: some View {
        Group {
            if authorization == .authorized || authorization == .limited {
                ScrollView {
                    if authorization == .limited {
                        Text("Acesso limitado: aparecem somente as fotos autorizadas nos Ajustes do iPhone.")
                            .font(.footnote).foregroundStyle(.secondary).padding()
                    }
                    if assets.isEmpty {
                        ContentUnavailableView("Nenhuma foto disponível", systemImage: "photo", description: Text("Confira as fotos e a permissão de acesso no iPhone."))
                    } else {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(assets) { item in
                                Button { selected = item } label: { DeviceThumbnail(asset: item.asset) }
                                    .buttonStyle(.plain).accessibilityLabel("Abrir foto")
                            }
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
        .sheet(item: $selected, onDismiss: refresh) { item in DevicePhotoDetail(asset: item.asset) }
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
    }
}

private struct DeviceThumbnail: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.gray.opacity(0.2)
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }.frame(width: proxy.size.width, height: proxy.size.width).clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = false
            requestID = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 330, height: 330), contentMode: .aspectFill, options: options) { image, _ in
                DispatchQueue.main.async { if let image { thumbnail = image } }
            }
        }
        .onDisappear { if let requestID { PHImageManager.default().cancelImageRequest(requestID) }; requestID = nil }
    }
}

private struct DevicePhotoDetail: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var data: Data?
    @State private var preview: UIImage?
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let preview { Image(uiImage: preview).resizable().scaledToFit() }
                    else if loading { ProgressView("Abrindo foto…").padding(50) }
                    else { ContentUnavailableView("Não foi possível abrir", systemImage: "photo.badge.exclamationmark") }
                    Text(ExistingPhotoStamp.description(date: asset.creationDate, location: asset.location))
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("O carimbo cria uma cópia em Capturas. O original não será alterado. A cópia não mantém os metadados do arquivo original.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Criar cópia com carimbo") { createCopy() }
                        .buttonStyle(.borderedProminent)
                        .disabled(data == nil || saving || ExistingPhotoStamp.lines(date: asset.creationDate, location: asset.location).isEmpty)
                    if saving { ProgressView("Criando cópia…") }
                }.padding()
            }
            .navigationTitle("Foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { dismiss() } }
            .onAppear { load() }
            .onDisappear { if let requestID { PHImageManager.default().cancelImageRequest(requestID) } }
            .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
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
            }
        }
    }

    private func createCopy() {
        guard let data, !saving else { return }
        let lines = ExistingPhotoStamp.lines(date: asset.creationDate, location: asset.location)
        guard !lines.isEmpty else { return }
        saving = true
        Task {
            let success = await Task.detached(priority: .userInitiated) { () -> Bool in
                guard let result = ExistingPhotoStamp.render(data, lines: lines) else { return false }
                do {
                    let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    let directory = root.appendingPathComponent("Processed", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                    try result.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    return true
                } catch { return false }
            }.value
            saving = false
            message = success ? "Cópia criada em Capturas. O original foi preservado." : "Não foi possível criar a cópia. O original foi preservado."
        }
    }
}

enum ExistingPhotoStamp {
    static func lines(date: Date?, location: CLLocation?, timeZone: TimeZone = .current) -> [String] {
        var result: [String] = []
        if let date, date.timeIntervalSince1970.isFinite {
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

    static func description(date: Date?, location: CLLocation?) -> String {
        let fields = lines(date: date, location: location)
        return fields.isEmpty ? "Data e localização indisponíveis nesta foto." : fields.joined(separator: "\n") + (date == nil ? "" : "\nHorário exibido no fuso atual do iPhone.")
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
