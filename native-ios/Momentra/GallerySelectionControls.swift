import SwiftUI
import UIKit

struct GallerySelectionBar<Share: View>: View {
    let count: Int
    let busy: Bool
    let review: () -> Void
    let delete: () -> Void
    @ViewBuilder let share: () -> Share

    var body: some View {
        HStack(spacing: 12) {
            share()
                .accessibilityLabel("Compartilhar seleção")
            Spacer(minLength: 0)
            Button(action: review) {
                Text("Mostrar seleção (\(count))").font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.72)
                    .frame(minHeight: 44).padding(.horizontal, 12)
                    .modifier(GalleryControlSurface(tint: .yellow))
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash").frame(width: 44, height: 44)
                    .modifier(GalleryControlSurface(tint: .red))
            }
            .accessibilityLabel("Excluir seleção")
        }
        .buttonStyle(.plain)
        .disabled(count == 0 || busy)
        .opacity(count == 0 ? 0.52 : 1)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.background)
    }
}

struct GalleryShareIcon: View {
    var body: some View {
        Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
            .modifier(GalleryControlSurface())
    }
}

struct GallerySelectionSheet<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    @Binding var selected: Set<Item.ID>
    @ViewBuilder let tile: (Item) -> Tile
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
                            selected: $selected, columns: $columns, showsSectionHeaders: false,
                            tile: tile, open: { _ in })
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
        .presentationDragIndicator(.hidden)
    }
}

final class GalleryShareBatch: Identifiable {
    private let directory: URL
    private let files: [URL]

    private init(directory: URL, files: [URL]) {
        self.directory = directory
        self.files = files
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    @MainActor
    static func prepare<Item>(_ items: [Item], copy: (Item, URL) async throws -> URL) async throws -> GalleryShareBatch {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            var files: [URL] = []
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                let target = directory.appendingPathComponent(String(index), isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                files.append(try await copy(item, target))
            }
            try Task.checkCancellation()
            return GalleryShareBatch(directory: directory, files: files)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    struct Sheet: UIViewControllerRepresentable {
        let batch: GalleryShareBatch

        func makeUIViewController(context: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: batch.files, applicationActivities: nil)
            controller.completionWithItemsHandler = { [batch] _, _, _, _ in
                try? FileManager.default.removeItem(at: batch.directory)
            }
            return controller
        }

        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }
}
