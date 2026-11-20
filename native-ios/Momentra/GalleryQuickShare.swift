import AVKit
import SwiftUI

struct GalleryQuickShare: View {
    let load: () async throws -> PhotoEditorInput
    var isVideo = false

    @Environment(\.dismiss) private var dismiss
    @State private var source: PhotoEditorInput?
    @State private var picture: CGImage?
    @State private var player: AVPlayer?
    @State private var sharePresented = false
    @State private var shareSucceeded = false
    @State private var attempted = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Fechar") { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); dismiss() }.frame(minHeight: 44)
                Spacer()
                Text(isVideo ? "Vídeo ampliado" : "Foto ampliada").font(.headline)
                Spacer()
                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); sharePresented = true } label: {
                    GalleryShareIcon()
                }.accessibilityLabel("Compartilhar").disabled(source == nil)
            }.padding(.horizontal, 16)
            Group {
                if let picture {
                    Image(decorative: picture, scale: 1).resizable().scaledToFit()
                } else if let player {
                    VideoPlayer(player: player)
                } else if failed {
                    ContentUnavailableView("Não foi possível abrir o arquivo", systemImage: "photo.badge.exclamationmark")
                } else {
                    ProgressView("Preparando compartilhamento…")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { Color.black.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .task { await prepare() }
        .task(id: source?.url) {
            guard source != nil, !attempted else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            attempted = true
            sharePresented = true
        }
        .sheet(isPresented: $sharePresented, onDismiss: {
            if shareSucceeded { dismiss() }
        }) {
            if let source {
                GalleryActivitySheet(files: [source.url], resource: source) {
                    if sharePresented { shareSucceeded = true } else { dismiss() }
                }
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func prepare() async {
        guard source == nil else { return }
        do {
            let input = try await load()
            do {
                if !isVideo {
                    picture = try await Task.detached(priority: .userInitiated) {
                        try PhotoEditRenderer.previewSource(input.url, maximumPixels: 1800)
                    }.value
                }
                try Task.checkCancellation()
                if isVideo { player = AVPlayer(url: input.url) }
                source = input
            } catch {
                input.close()
                throw error
            }
        } catch { if !Task.isCancelled { failed = true } }
    }
}
