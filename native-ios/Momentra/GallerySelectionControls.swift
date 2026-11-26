import SwiftUI

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
            Button(action: { FotomarcoHaptics.play(.gallery); review() }) {
                Text("Mostrar seleção (\(count))").font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.72)
                    .frame(minHeight: 44).padding(.horizontal, 12)
                    .modifier(GalleryControlSurface(rounded: true, tint: .yellow))
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: { FotomarcoHaptics.play(.gallery); delete() }) {
                Image(systemName: "trash").frame(width: 44, height: 44)
                    .modifier(GalleryControlSurface(rounded: true, tint: .red))
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
            .modifier(GalleryControlSurface(rounded: true))
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
                Button { FotomarcoHaptics.play(.gallery); columns = columns == 3 ? 2 : 3 } label: {
                    Image(systemName: "square.grid.2x2").frame(width: 44, height: 44)
                        .modifier(GalleryControlSurface(rounded: true))
                }.accessibilityLabel("Alterar tamanho das miniaturas")
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    Text("Seleção").font(.caption).foregroundStyle(.yellow)
                    Text(selection.count == 1 ? "1 item selecionado" : "\(selection.count) itens selecionados")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                Button { FotomarcoHaptics.play(.gallery); dismiss() } label: {
                    Image(systemName: "checkmark").font(.body.weight(.bold))
                        .frame(width: 44, height: 44).modifier(GalleryControlSurface(rounded: true, tint: .yellow))
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
            Button { FotomarcoHaptics.play(.gallery); selected.removeAll() } label: {
                Text("Desmarcar tudo").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .modifier(GalleryControlSurface(rounded: true))
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
    static func prepare<Item>(_ items: [Item], progress: ((Int, Int) -> Void)? = nil,
                              copy: (Item, URL) async throws -> URL) async throws -> GalleryShareBatch {
        progress?(0, items.count)
        if progress != nil { await Task.yield() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            var files: [URL] = []
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                let target = directory.appendingPathComponent(String(index), isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                files.append(try await copy(item, target))
                try Task.checkCancellation()
                progress?(index + 1, items.count)
            }
            try Task.checkCancellation()
            return GalleryShareBatch(directory: directory, files: files)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    @MainActor
    static func prepareWithTransferProgress<Item>(
        _ items: [Item], progress: @escaping (GalleryShareProgress) -> Void,
        copy: (Item, URL, @escaping @Sendable (Double) -> Void) async throws -> URL
    ) async throws -> GalleryShareBatch {
        let tracker = GalleryShareProgressTracker(total: items.count, report: progress)
        progress(GalleryShareProgress(completed: 0, total: items.count))
        await Task.yield()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            var files: [URL] = []
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                tracker.index = index
                let target = directory.appendingPathComponent(String(index), isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let file = try await copy(item, target) { fraction in
                    Task { @MainActor in tracker.update(index: index, fraction: fraction) }
                }
                files.append(file)
                try Task.checkCancellation()
                tracker.index = index + 1
                progress(GalleryShareProgress(completed: index + 1, total: items.count))
            }
            tracker.active = false
            return GalleryShareBatch(directory: directory, files: files)
        } catch {
            tracker.active = false
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func sheet(onSuccess: @escaping @MainActor () -> Void) -> GalleryActivitySheet {
        GalleryActivitySheet(files: files, resource: self, onSuccess: onSuccess)
    }
}

struct GalleryShareProgress: Equatable {
    let completed: Int
    let total: Int
    var currentFraction: Double = 0
    var fraction: Double { total > 0 ? min(1, max(0, (Double(completed) + currentFraction) / Double(total))) : 0 }
    var percent: Int { Int(fraction * 100) }
}

@MainActor
private final class GalleryShareProgressTracker {
    let total: Int
    let report: (GalleryShareProgress) -> Void
    var index = 0
    var active = true
    private var lastFraction: Double = 0
    private var lastIndex = 0

    init(total: Int, report: @escaping (GalleryShareProgress) -> Void) {
        self.total = total
        self.report = report
    }

    func update(index: Int, fraction: Double) {
        guard active, self.index == index, fraction.isFinite else { return }
        if lastIndex != index { lastIndex = index; lastFraction = 0 }
        let value = min(0.99, max(0, fraction))
        guard value > lastFraction else { return }
        lastFraction = value
        report(GalleryShareProgress(completed: index, total: total, currentFraction: value))
    }
}

struct GalleryShareProgressOverlay: View {
    let progress: GalleryShareProgress
    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Preparando compartilhamento")
                    .font(.headline).multilineTextAlignment(.center)
                Text("Aguarde enquanto as fotos são preparadas e, se necessário, baixadas da nuvem.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("\(progress.percent)%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                ProgressView(value: progress.fraction).tint(.yellow)
                Text("\(progress.completed) de \(progress.total) itens preparados")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24).frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .padding(24)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GalleryShareComposer<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let current: Item
    let copy: (Item, URL, @escaping @Sendable (Double) -> Void) async throws -> URL
    let tile: (Item) -> Tile
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Item.ID>
    @State private var batch: GalleryShareBatch?
    @State private var shareSucceeded = false
    @State private var preparation: Task<Void, Never>?
    @State private var progress: GalleryShareProgress?
    @State private var failed = false

    init(items: [Item], current: Item, copy: @escaping (Item, URL) async throws -> URL,
         onSuccess: @escaping () -> Void, @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.current = current
        self.copy = { item, directory, _ in try await copy(item, directory) }
        self.tile = tile
        self.onSuccess = onSuccess
        _selected = State(initialValue: [current.id])
    }

    init(items: [Item], current: Item,
         copyWithProgress: @escaping (Item, URL, @escaping @Sendable (Double) -> Void) async throws -> URL,
         onSuccess: @escaping () -> Void, @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.current = current
        self.copy = copyWithProgress
        self.tile = tile
        self.onSuccess = onSuccess
        _selected = State(initialValue: [current.id])
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(selected.count == 1 ? "1 item selecionado" : "\(selected.count) itens selecionados")
                    .font(.title2.bold()).padding(.horizontal, 20)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    FotomarcoHaptics.play(.gallery)
                                    if !selected.insert(item.id).inserted { selected.remove(item.id) }
                                } label: {
                                    tile(item).frame(width: 136, height: 180).clipped()
                                        .clipShape(.rect(cornerRadius: 16))
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.title2.weight(.semibold))
                                                .foregroundStyle(selected.contains(item.id) ? .yellow : .white)
                                                .padding(5).background(.black.opacity(0.75), in: Circle()).padding(8)
                                        }
                                }
                                .buttonStyle(.plain).id(item.id)
                                .accessibilityLabel("Item \(index + 1)")
                                .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                            }
                        }.padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden).frame(height: 182)
                    .onAppear { proxy.scrollTo(current.id, anchor: .center) }
                }
                Button(action: { FotomarcoHaptics.play(.gallery); prepare() }) {
                    HStack {
                        if preparation != nil { ProgressView() }
                        Label("Compartilhar seleção", systemImage: "square.and.arrow.up")
                    }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                .disabled(selected.isEmpty || preparation != nil).padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .navigationTitle("Compartilhar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fechar") { FotomarcoHaptics.play(.gallery); preparation?.cancel(); dismiss() } }
            .sheet(item: $batch, onDismiss: {
                if shareSucceeded { onSuccess() }
            }) { batch in
                batch.sheet {
                    if self.batch != nil { shareSucceeded = true } else { onSuccess() }
                }
            }
            .alert("Não foi possível preparar os itens", isPresented: $failed) {
                Button("OK", role: .cancel) { FotomarcoHaptics.play(.gallery) }
            }
        }
        .preferredColorScheme(.dark)
        .overlay { if let progress { GalleryShareProgressOverlay(progress: progress) } }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(preparation != nil)
    }

    private func prepare() {
        guard preparation == nil else { return }
        let chosen = items.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        preparation = Task {
            defer { preparation = nil; progress = nil }
            do {
                let prepared = try await GalleryShareBatch.prepareWithTransferProgress(chosen, progress: { value in
                    progress = value
                }, copy: copy)
                if !Task.isCancelled { batch = prepared }
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}
