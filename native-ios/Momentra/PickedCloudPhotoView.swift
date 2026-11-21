import SwiftUI
import ImageIO

struct PickedCloudPhotoView: View {
    let item: PickedCloudImage
    @Environment(\.dismiss) private var dismiss
    @State private var preview: UIImage?
    @State private var originalDateText: String?
    @State private var saving = false
    @State private var message: String?

    private var lines: [String] {
        ExistingPhotoStamp.lines(date: item.date, location: nil, originalDateText: originalDateText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let preview { Image(uiImage: preview).resizable().scaledToFit() }
                    else { ContentUnavailableView("Não foi possível abrir a imagem", systemImage: "photo.badge.exclamationmark") }
                    Text(ExistingPhotoStamp.description(date: item.date, location: nil, originalDateText: originalDateText))
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("O Google não fornece a localização neste download. A cópia com carimbo ficará em Capturas e não alterará a foto na nuvem. A cópia não mantém os metadados originais.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Criar cópia com carimbo") { FotomarcoHaptics.play(.gallery); save() }
                        .buttonStyle(.borderedProminent).disabled(preview == nil || lines.isEmpty || saving)
                    if saving { ProgressView("Criando cópia…") }
                }.padding()
            }
            .navigationTitle("Foto selecionada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { FotomarcoHaptics.play(.gallery); dismiss() } }
            .onAppear { load() }
            .alert("Fotomarco", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func load() {
        guard let source = CGImageSourceCreateWithData(item.data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200
              ] as CFDictionary) else { return }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        originalDateText = ExistingPhotoStamp.exifDateText(properties: properties)
        preview = UIImage(cgImage: image)
    }

    private func save() {
        guard !saving, !lines.isEmpty else { return }
        let data = item.data
        let stamp = lines
        saving = true
        Task {
            let success = await Task.detached(priority: .userInitiated) { ExistingPhotoStamp.saveCopy(data, lines: stamp) }.value
            saving = false
            message = success ? "Cópia criada em Capturas. A foto na nuvem foi preservada." : "Não foi possível criar a cópia. A foto na nuvem foi preservada."
        }
    }
}
