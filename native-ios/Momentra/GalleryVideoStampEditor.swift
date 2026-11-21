import AVKit
import SwiftUI

@MainActor
struct GalleryVideoStampEditor: View {
    let item: GalleryItem
    let profiles: [StampProfile]
    let saved: (URL, StampProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProfile: UUID?
    @State private var prepared: Preview?
    @State private var saving = false
    @State private var failed = false

    private struct Preview {
        let input: PhotoEditorInput
        let player: AVPlayer
        let snapshot: StampSnapshot?
    }

    init(item: GalleryItem, profiles: [StampProfile], activeProfileID: UUID,
         saved: @escaping (URL, StampProfile) -> Void) {
        self.item = item
        self.profiles = profiles
        self.saved = saved
        let recordedProfile = item.profile?.id
        _selectedProfile = State(initialValue: profiles.first { $0.id == recordedProfile }?.id ??
            profiles.first { $0.id == activeProfileID }?.id ?? profiles.first?.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Group {
                    if let prepared {
                        VideoPlayer(player: prepared.player)
                    } else if failed {
                        ContentUnavailableView("Não foi possível abrir a prévia", systemImage: "video.slash")
                    } else {
                        ProgressView("Abrindo prévia…")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if prepared?.snapshot != nil {
                    Picker("Perfil do carimbo", selection: $selectedProfile) {
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }.disabled(saving)
                    Button("Salvar cópia com carimbo") { FotomarcoHaptics.play(.buttons); save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(saving)
                    if saving { ProgressView("Aplicando carimbo…") }
                } else if prepared != nil {
                    if let profile = item.profile { Text("Perfil · \(profile.name)") }
                    if item.date == nil { Text("A data do vídeo não está disponível.").font(.footnote) }
                }
            }
            .padding()
            .navigationTitle("Carimbo do vídeo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fechar") { FotomarcoHaptics.play(.buttons); dismiss() }.disabled(saving) }
        }
        .interactiveDismissDisabled(saving)
        .task(id: selectedProfile) { await preparePreview() }
        .onDisappear { prepared?.player.pause() }
        .alert("Não foi possível preparar o vídeo", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func preparePreview() async {
        prepared?.player.pause()
        prepared = nil
        failed = false
        do {
            let stamped = storedStampedVideo()
            let input: PhotoEditorInput
            if let stamped { input = PhotoEditorInput(url: stamped) }
            else { input = try await item.input() }
            let asset = AVURLAsset(url: input.url)
            let playerItem = AVPlayerItem(asset: asset)
            let snapshot: StampSnapshot?
            if stamped == nil, let date = item.date, let profile = profiles.first(where: { $0.id == selectedProfile }) {
                let layout = profile.layout
                let stamp = StampSnapshot(capturedAt: date, gpsEnabled: false, note: profile.note,
                    logo: ProfileLogoStore.load(profile.effectiveLogoName), extraLogos: profile.additionalLogoNames.map { ProfileLogoStore.load($0) }, compact: layout.compact,
                    position: layout.position, horizontal: layout.horizontal, longDate: layout.dateFormat == "long",
                    fontStyle: layout.fontStyle, mapScale: layout.mapScale, mapCorner: layout.mapCorner,
                    location: nil, heading: nil, layout: layout)
                playerItem.videoComposition = try await VideoStampRenderer.previewComposition(
                    asset: asset, snapshot: stamp, map: nil, address: nil)
                snapshot = stamp
            } else { snapshot = nil }
            try Task.checkCancellation()
            prepared = Preview(input: input, player: AVPlayer(playerItem: playerItem), snapshot: snapshot)
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func storedStampedVideo() -> URL? {
        guard case .capture(let file) = item.source else { return nil }
        if file.isProcessed { return file.url }
        guard file.url.deletingLastPathComponent().lastPathComponent == "Videos" else { return nil }
        let sibling = file.url.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ProcessedVideos", isDirectory: true)
            .appendingPathComponent(file.url.lastPathComponent)
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
    }

    private func save() {
        guard !saving, let prepared, let snapshot = prepared.snapshot,
              let profile = profiles.first(where: { $0.id == selectedProfile }) else { return }
        saving = true
        prepared.player.pause()
        Task {
            defer { saving = false }
            do {
                let id = UUID()
                let root = try CloudArchiveJournal.documents().root
                let file = root.appendingPathComponent("ProcessedVideos", isDirectory: true)
                    .appendingPathComponent(id.uuidString + ".mov")
                try await VideoStampRenderer.export(source: prepared.input.url, destination: file,
                                                    snapshot: snapshot, map: nil, address: nil)
                try? PhotoProfileIndex.register(captureID: id, profile: .init(id: profile.id, name: profile.name),
                                                captureDate: snapshot.capturedAt)
                saved(file, profile)
            } catch { failed = true }
        }
    }
}
