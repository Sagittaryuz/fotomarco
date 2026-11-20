import ImageIO
import SwiftUI
import Vision

struct GalleryContentSearch<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let keywords: (Item) -> String
    let imageURL: (Item) async throws -> PhotoEditorInput?
    let onOpen: (Item) -> Void
    @ViewBuilder let tile: (Item) -> Tile

    @AppStorage("native.gallery.recentSearches") private var recentData = Data()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var submittedTerm = ""
    @State private var matches: Set<Item.ID> = []
    @State private var searchRun = UUID()
    @State private var isSearching = false
    @State private var unavailable = 0
    @State private var index = GalleryContentSearchIndex<Item.ID>()

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recent: [String] { (try? JSONDecoder().decode([String].self, from: recentData)) ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Buscar").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                if term.isEmpty {
                    startContent
                } else {
                    results
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { searchBar }
        .background(.black)
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(for: .milliseconds(280))
            if !Task.isCancelled { searchFocused = true }
        }
        .task(id: searchRun) {
            await analyze(term: submittedTerm)
        }
        .onChange(of: query) { _, _ in
            if term != submittedTerm { clearAnalysis() }
        }
    }

    private var startContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Busque por texto nas fotos, assunto, data ou perfil.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !recent.isEmpty {
                HStack {
                    Label("Buscas recentes", systemImage: "clock")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Limpar") { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); recentData = Data() }
                        .foregroundStyle(.yellow)
                }
                ForEach(recent, id: \.self) { value in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2)
                        query = value
                        submit()
                    } label: {
                        HStack {
                            Text(value).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .modifier(GalleryControlSurface(rounded: true))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var results: some View {
        let shown = items.filter { item in
            GallerySearchText.contains(term, in: keywords(item)) ||
                (submittedTerm == term && matches.contains(item.id))
        }
        return VStack(alignment: .leading, spacing: 12) {
            if submittedTerm != term {
                Text("Toque em Buscar para analisar o conteúdo das fotos.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if isSearching {
                ProgressView("Analisando fotos…")
                    .font(.footnote)
            } else if unavailable > 0 {
                Text("Algumas fotos estavam indisponíveis para análise.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if shown.isEmpty, !isSearching {
                ContentUnavailableView("Nenhum resultado", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            } else {
                Text(shown.count == 1 ? "1 resultado" : "\(shown.count) resultados")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(shown) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2)
                            searchFocused = false
                            onOpen(item)
                        } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { tile(item).accessibilityHidden(true) }
                                .clipShape(.rect(cornerRadius: 7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Abrir resultado")
                        .accessibilityHint(keywords(item))
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                TextField("Buscar fotos", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit(submit)
                    .accessibilityIdentifier("gallery-content-search-field")
                if !query.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2)
                        query = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Limpar texto")
                }
            }
            .padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 0)
            .frame(minHeight: 48)
            .modifier(GalleryControlSurface(rounded: true, interactive: false))

            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2)
                searchFocused = false
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .modifier(GalleryControlSurface(rounded: true))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar busca")
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.black)
    }

    private func submit() {
        guard !term.isEmpty else { return }
        let value = String(term.prefix(160))
        let history = [value] + recent.filter {
            $0.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        if let data = try? JSONEncoder().encode(Array(history.prefix(8))) { recentData = data }
        query = value
        matches = []
        unavailable = 0
        submittedTerm = value
        isSearching = true
        searchRun = UUID()
        searchFocused = false
    }

    private func clearAnalysis() {
        guard !submittedTerm.isEmpty else { return }
        submittedTerm = ""
        matches = []
        unavailable = 0
        isSearching = false
        searchRun = UUID()
    }

    @MainActor
    private func analyze(term: String) async {
        guard !term.isEmpty, !Task.isCancelled else { return }
        for item in items {
            guard !Task.isCancelled else { return }
            let metadata = keywords(item)
            if GallerySearchText.contains(term, in: metadata) { continue }
            do {
                let text: String
                if let cached = index.content[item.id] {
                    text = cached
                } else if let input = try await imageURL(item) {
                    defer { input.close() }
                    let url = input.url
                    try Task.checkCancellation()
                    text = await GallerySearchText.inspect(url)
                    try Task.checkCancellation()
                    index.content[item.id] = text
                } else {
                    continue
                }
                if GallerySearchText.contains(term, in: metadata + "\n" + text) { matches.insert(item.id) }
            } catch {
                guard !Task.isCancelled else { return }
                unavailable += 1
            }
        }
        if !Task.isCancelled { isSearching = false }
    }
}

private final class GalleryContentSearchIndex<ID: Hashable> {
    var content: [ID: String] = [:]
}

private enum GallerySearchText {
    private static let queue = DispatchQueue(label: "br.com.momentra.gallery-search", qos: .utility)
    private static let translatedLabels = [
        "animal": "animal animais",
        "basketball": "basquete",
        "bicycle": "bicicleta bicicletas",
        "bird": "pássaro pássaros ave aves",
        "building": "prédio prédios edifício edifícios",
        "bus": "ônibus",
        "car": "carro carros automóvel automóveis",
        "cat": "gato gatos",
        "computer": "computador computadores",
        "construction": "obra obras construção construções",
        "dog": "cão cães cachorro cachorros",
        "flower": "flor flores",
        "food": "comida comidas alimento alimentos",
        "house": "casa casas residência residências",
        "motorcycle": "moto motos motocicleta motocicletas",
        "person": "pessoa pessoas",
        "plant": "planta plantas",
        "receipt": "recibo recibos",
        "road": "rua ruas estrada estradas rodovia rodovias",
        "tool": "ferramenta ferramentas",
        "tree": "árvore árvores",
        "truck": "caminhão caminhões",
        "watch": "relógio relógios",
        "water": "água"
    ]

    static func contains(_ term: String, in value: String) -> Bool {
        let checks = term.split(whereSeparator: { $0.isWhitespace })
        return !checks.isEmpty && checks.allSatisfy {
            value.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func inspect(_ url: URL) async -> String {
        await withCheckedContinuation { continuation in
            queue.async {
                let recognized = (try? GalleryPhotoActions.recognizeText(in: url)) ?? ""
                let categories = classify(url)
                continuation.resume(returning: recognized + "\n" + categories)
            }
        }
    }

    private static func classify(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768
              ] as CFDictionary) else { return "" }
        let request = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: thumbnail).perform([request])) != nil else { return "" }
        return (request.results ?? [])
            .filter { $0.confidence >= 0.24 }
            .prefix(10)
            .map { result in
                let label = result.identifier.replacingOccurrences(of: "_", with: " ")
                let words = label.split(whereSeparator: { !$0.isLetter })
                let aliases = words.compactMap { translatedLabels[String($0).lowercased()] }
                return ([label] + aliases).joined(separator: " ")
            }
            .joined(separator: " ")
    }
}
