import SwiftUI

final class PhotoEditorInput {
    let url: URL
    private let temporary: Bool

    init(url: URL, temporary: Bool = false) {
        self.url = url
        self.temporary = temporary
    }

    deinit { close() }

    func close() {
        if temporary { try? FileManager.default.removeItem(at: url) }
    }
}

@MainActor
struct MomentraPhotoEditor: View {
    let load: () async throws -> PhotoEditorInput
    let date: Date?
    var profile: CaptureProfileTag? = nil
    var stampProfiles: [StampProfile] = []
    var saved: (URL) -> Void = { _ in }

    private enum Section: String, CaseIterable {
        case adjust = "Ajustar", filters = "Filtros", crop = "Recortar", tools = "Ferramentas"
    }
    private enum CropControl: String, CaseIterable {
        case straighten = "Endireitar", vertical = "Vertical", horizontal = "Horizontal", size = "Escala"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .adjust
    @State private var adjustment: PhotoAdjustment = .exposure
    @State private var cropControl: CropControl = .straighten
    @State private var recipe = PhotoEditRecipe()
    @State private var undo: [PhotoEditRecipe] = []
    @State private var redo: [PhotoEditRecipe] = []
    @State private var beforeSlider: PhotoEditRecipe?
    @State private var input: PhotoEditorInput?
    @State private var original: CGImage?
    @State private var preview: CGImage?
    @State private var previewQueue = PhotoEditPreviewQueue()
    @State private var filterPreviews: [PhotoEditFilter: CGImage] = [:]
    @State private var showingOriginal = false
    @State private var markup = false
    @State private var ink: PhotoInk = .yellow
    @State private var draftStroke: [CGPoint] = []
    @State private var panStart: CGPoint?
    @State private var stampID: UUID?
    @State private var saving = false
    @State private var confirmCancel = false
    @State private var errorMessage: String?
    @State private var failedToLoad = false

    private var changed: Bool { recipe != PhotoEditRecipe() || stampID != nil }

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 10) { header; canvas.frame(minHeight: 140); controls; sections }
            ScrollView {
                VStack(spacing: 10) { header; canvas.frame(height: 200); controls; sections }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(changed || saving)
        .task { await open() }
        .onChange(of: recipe) { _, _ in updatePreview() }
        .onDisappear {
            previewQueue.discardPending()
            input?.close()
        }
        .confirmationDialog("Descartar as alterações?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { dismiss() }
            Button("Continuar editando", role: .cancel) {}
        }
        .alert("Editor Photomark", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Cancelar") { lightEditorTap(); if changed { confirmCancel = true } else { dismiss() } }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.primary)
                    .disabled(saving)
                Spacer()
                Text("Editor Photomark").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Salvar cópia") { lightEditorTap(); save() }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.yellow).foregroundStyle(.black)
                    .disabled(!changed || input == nil || saving)
            }
            editorGlassGroup {
                HStack(spacing: 10) {
                    icon("arrow.uturn.backward", label: "Desfazer", action: undoEdit).disabled(undo.isEmpty)
                    icon("arrow.uturn.forward", label: "Refazer", action: redoEdit).disabled(redo.isEmpty)
                    Spacer()
                    icon("pencil.tip", label: "Marcação") { section = .tools; markup.toggle() }
                    Menu {
                        Button(showingOriginal ? "Mostrar edição" : "Comparar com o original") { lightEditorTap(); showingOriginal.toggle() }
                        Button("Redefinir ajustes", role: .destructive) {
                            lightEditorTap()
                            commit { $0 = PhotoEditRecipe() }
                            stampID = nil
                        }.disabled(!changed)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44).modifier(GalleryControlSurface(rounded: true))
                    }.accessibilityLabel("Mais opções de edição")
                }
            }
            .disabled(input == nil || saving)
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.black)
                if let image = (showingOriginal ? original : preview ?? original) {
                    let ratio = min(proxy.size.width / CGFloat(image.width), proxy.size.height / CGFloat(image.height))
                    let width = CGFloat(image.width) * ratio
                    let height = CGFloat(image.height) * ratio
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .frame(width: width, height: height)
                        .overlay {
                            if !showingOriginal {
                                Canvas { context, size in
                                    let box = CGRect(origin: .zero, size: size)
                                    let pending = draftStroke.isEmpty ? [] : [PhotoStroke(ink: ink, points: draftStroke)]
                                    for stroke in recipe.strokes + pending {
                                        context.stroke(Path(stroke.path(in: box)), with: .color(Color(uiColor: stroke.ink.color)),
                                            style: StrokeStyle(lineWidth: max(1, min(size.width, size.height) * 0.012),
                                                               lineCap: .round, lineJoin: .round))
                                    }
                                }.allowsHitTesting(false)
                                if section == .crop {
                                    Rectangle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                                        .overlay {
                                            Canvas { context, size in
                                                var lines = Path()
                                                for i in 1...2 {
                                                    let fraction = CGFloat(i) / 3
                                                    lines.move(to: CGPoint(x: size.width * fraction, y: 0))
                                                    lines.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                                                    lines.move(to: CGPoint(x: 0, y: size.height * fraction))
                                                    lines.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                                                }
                                                context.stroke(lines, with: .color(.white.opacity(0.45)), lineWidth: 1)
                                            }
                                        }.allowsHitTesting(false)
                                }
                            }
                        }
                        .frame(width: width, height: height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(photoGesture(size: CGSize(width: width, height: height)))
                        .accessibilityLabel(showingOriginal ? "Foto original" : "Prévia da edição")
                } else if failedToLoad {
                    Text("Não foi possível abrir a foto.").foregroundStyle(.secondary)
                } else {
                    ProgressView("Abrindo foto…")
                }
                if saving {
                    ProgressView("Salvando cópia…").padding(14)
                        .modifier(GalleryControlSurface(rounded: true, interactive: false))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        editorGlassGroup {
            switch section {
            case .adjust: adjustments
            case .filters: filters
            case .crop: crop
            case .tools: tools
            }
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
        .disabled(input == nil || saving)
    }

    private var sections: some View {
        Picker("Ferramentas de edição", selection: $section) {
            ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented)
        .onChange(of: section) { _, selected in if selected != .tools { markup = false } }
    }

    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 7) {
                    chip("Auto", active: recipe.automatic, icon: "wand.and.stars") { commit { $0.automatic.toggle() } }
                    ForEach(PhotoAdjustment.allCases, id: \.self) { value in
                        chip(value.rawValue, active: adjustment == value) { adjustment = value }
                    }
                }
            }.scrollIndicators(.hidden)
            let nonnegative = [PhotoAdjustment.sharpness, .definition, .noise, .vignette].contains(adjustment)
            valueSlider(adjustment.rawValue, value: Binding(get: { recipe[adjustment] }, set: { recipe[adjustment] = $0 }),
                        range: (nonnegative ? 0.0 : -1.0)...1.0, display: "\(Int((recipe[adjustment] * 100).rounded()))")
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(PhotoEditFilter.allCases, id: \.self) { filter in
                        Button { lightEditorTap(); commit { $0.filter = filter; $0.strength = 1 } } label: {
                            VStack(spacing: 4) {
                                if let image = filterPreviews[filter] {
                                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                                        .frame(width: 52, height: 36).clipped()
                                        .clipShape(.rect(cornerRadius: 8))
                                        .overlay {
                                            if recipe.filter == filter {
                                                RoundedRectangle(cornerRadius: 8).strokeBorder(.yellow, lineWidth: 2)
                                            }
                                        }
                                }
                                Text(filter.rawValue).font(.caption2).lineLimit(1)
                            }.foregroundStyle(recipe.filter == filter ? .yellow : .primary)
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(recipe.filter == filter ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)
            valueSlider("Intensidade", value: $recipe.strength, range: 0...1, display: "\(Int(recipe.strength * 100))%")
                .disabled(recipe.filter == .original)
        }
    }

    private var crop: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                icon("rotate.left", label: "Girar 90 graus") { commit { $0.turns = ($0.turns + 3) % 4 } }
                icon("arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Espelhar") { commit { $0.flipped.toggle() } }
                Menu {
                    ForEach(PhotoCropRatio.allCases, id: \.self) { ratio in
                        Button(ratio.rawValue) { lightEditorTap(); commit { $0.crop = ratio } }
                    }
                } label: {
                    Label(recipe.crop.rawValue, systemImage: "rectangle.ratio.4.to.3")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).frame(minHeight: 40)
                        .modifier(GalleryControlSurface(rounded: true, tint: recipe.crop == .free ? .primary : .yellow))
                }
                .accessibilityLabel("Proporção")
                .accessibilityValue(recipe.crop.rawValue)
                Spacer()
            }
            Picker("Controle de recorte", selection: $cropControl) {
                ForEach(CropControl.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            switch cropControl {
            case .straighten: valueSlider("Endireitar", value: $recipe.angle, range: -45...45, display: "\(Int(recipe.angle.rounded()))°")
            case .vertical: valueSlider("Perspectiva vertical", value: $recipe.vertical, range: -1...1, display: "\(Int(recipe.vertical * 100))")
            case .horizontal: valueSlider("Perspectiva horizontal", value: $recipe.horizontal, range: -1...1, display: "\(Int(recipe.horizontal * 100))")
            case .size: valueSlider("Escala", value: $recipe.cropScale, range: 0.2...1, display: "\(Int(recipe.cropScale * 100))%")
            }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                chip("Marcação", active: markup, icon: "pencil.tip") { markup.toggle() }
                chip("Original", active: showingOriginal, icon: "eye") { showingOriginal.toggle() }
                if date != nil, !stampProfiles.isEmpty {
                    Menu {
                        Button("Sem carimbo") { lightEditorTap(); stampID = nil }
                        ForEach(stampProfiles) { profile in
                            Button(profile.name.isEmpty ? "Sem nome" : profile.name) { lightEditorTap(); stampID = profile.id }
                        }
                    } label: {
                        Label(stampID == nil ? "Carimbo" : "Com carimbo", systemImage: "seal")
                            .font(.caption.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 10).frame(minHeight: 40)
                            .modifier(GalleryControlSurface(rounded: true, tint: stampID == nil ? .primary : .yellow))
                    }
                    .accessibilityLabel("Adicionar carimbo")
                    .accessibilityValue(stampID == nil ? "Sem carimbo" : "Com carimbo")
                }
            }
            if markup {
                HStack {
                    ForEach(PhotoInk.allCases, id: \.self) { color in
                        Button { lightEditorTap(); ink = color } label: {
                            Circle().fill(Color(uiColor: color.color)).frame(width: 25, height: 25)
                                .padding(3).overlay(Circle().strokeBorder(ink == color ? .white : .secondary))
                                .frame(width: 44, height: 44)
                                .modifier(GalleryControlSurface(rounded: true))
                        }.buttonStyle(.plain).accessibilityLabel(color.rawValue)
                        .accessibilityAddTraits(ink == color ? .isSelected : [])
                    }
                    Spacer()
                    Button("Limpar traços") { lightEditorTap(); commit { $0.strokes.removeAll() } }
                        .font(.caption).disabled(recipe.strokes.isEmpty)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func editorGlassGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 0) { content() }
        } else {
            content()
        }
    }

    private func lightEditorTap() {
        FotomarcoHaptics.play(.editor)
    }

    private func icon(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: { lightEditorTap(); action() }) {
            Image(systemName: image).frame(width: 44, height: 44).modifier(GalleryControlSurface(rounded: true))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private func chip(_ title: String, active: Bool, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: { lightEditorTap(); action() }) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(.caption.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 40)
            .background(active ? Color.yellow.opacity(0.15) : .clear, in: Capsule())
            .modifier(GalleryControlSurface(rounded: true, tint: active ? .yellow : .primary))
        }.buttonStyle(.plain).accessibilityAddTraits(active ? .isSelected : [])
    }

    private func valueSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption.weight(.medium)).lineLimit(1)
            Slider(value: value, in: range, onEditingChanged: { moving in
                if moving { beforeSlider = recipe; showingOriginal = false }
                else if let beforeSlider { record(beforeSlider); self.beforeSlider = nil }
            }).tint(.yellow).accessibilityLabel(label)
            Text(display).font(.caption.monospacedDigit()).frame(minWidth: 36, alignment: .trailing)
        }
    }

    private func photoGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0, !showingOriginal, !saving else { return }
                if section == .tools, markup, draftStroke.count < 10000 {
                    draftStroke.append(CGPoint(x: min(1, max(0, value.location.x / size.width)),
                                               y: min(1, max(0, value.location.y / size.height))))
                } else if section == .crop {
                    if panStart == nil { panStart = recipe.cropCenter; beforeSlider = recipe }
                    guard let panStart else { return }
                    recipe.cropCenter = CGPoint(x: min(1, max(0, panStart.x - value.translation.width / size.width)),
                                                y: min(1, max(0, panStart.y - value.translation.height / size.height)))
                }
            }
            .onEnded { _ in
                if !draftStroke.isEmpty {
                    let stroke = PhotoStroke(ink: ink, points: draftStroke)
                    draftStroke.removeAll()
                    commit { $0.strokes.append(stroke) }
                }
                if panStart != nil {
                    if let beforeSlider { record(beforeSlider) }
                    panStart = nil
                    beforeSlider = nil
                }
            }
    }

    private func commit(_ change: (inout PhotoEditRecipe) -> Void) {
        let initial = recipe
        change(&recipe)
        showingOriginal = false
        record(initial)
    }

    private func record(_ previous: PhotoEditRecipe) {
        guard previous != recipe else { return }
        if undo.count >= 50 { undo.removeFirst() }
        undo.append(previous)
        redo.removeAll()
    }

    private func undoEdit() {
        guard let previous = undo.popLast() else { return }
        redo.append(recipe); recipe = previous; showingOriginal = false
    }

    private func redoEdit() {
        guard let next = redo.popLast() else { return }
        undo.append(recipe); recipe = next; showingOriginal = false
    }

    private func open() async {
        guard input == nil else { return }
        do {
            let source = try await load()
            do {
                let bitmap = try await Task.detached(priority: .userInitiated) { try PhotoEditRenderer.previewSource(source.url) }.value
                try Task.checkCancellation()
                input = source
                original = bitmap
                if recipe != PhotoEditRecipe() { updatePreview() }
                let thumbnails = await Task.detached(priority: .utility) { () -> [PhotoEditFilter: CGImage] in
                    guard let small = try? PhotoEditRenderer.previewSource(source.url, maximumPixels: 100) else { return [:] }
                    return Dictionary(uniqueKeysWithValues: PhotoEditFilter.allCases.compactMap { filter in
                        var sample = PhotoEditRecipe()
                        sample.filter = filter
                        return PhotoEditRenderer.preview(small, recipe: sample).map { (filter, $0) }
                    })
                }.value
                if !Task.isCancelled { filterPreviews = thumbnails }
            } catch {
                source.close()
                throw error
            }
        } catch { if !Task.isCancelled { failedToLoad = true } }
    }

    private func updatePreview() {
        guard let original else { return }
        previewQueue.submit(original, recipe: recipe) { preview = $0 }
    }

    private func save() {
        guard let input, !saving, changed else { return }
        saving = true
        let current = recipe
        let stamp = stampProfiles.first { $0.id == stampID }
        Task {
            defer { saving = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try PhotoEditRenderer.export(input.url, recipe: current)
                }.value
                let destination: URL
                if let stamp, let date {
                    let temporary = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                    try data.write(to: temporary, options: .atomic)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    destination = try await GalleryPhotoActions.copyWithStamp(url: temporary, date: date, profile: stamp)
                } else {
                    let id = UUID()
                    destination = try ProcessedFileStore.save(data, captureID: id)
                    if let profile { try? PhotoProfileIndex.register(captureID: id, profile: profile, captureDate: date) }
                }
                saved(destination)
                dismiss()
            } catch { errorMessage = "Não foi possível salvar uma cópia da foto." }
        }
    }
}


@MainActor
private final class PhotoEditPreviewQueue {
    private struct Request {
        let image: CGImage
        let recipe: PhotoEditRecipe
        let generation: UUID
        let apply: (CGImage?) -> Void
    }

    private var pending: Request?
    private var rendering = false
    private var generation = UUID()

    func submit(_ image: CGImage, recipe: PhotoEditRecipe, apply: @escaping (CGImage?) -> Void) {
        pending = Request(image: image, recipe: recipe, generation: generation, apply: apply)
        guard !rendering else { return }
        rendering = true
        Task { await renderPending() }
    }

    func discardPending() {
        pending = nil
        generation = UUID()
    }

    private func renderPending() async {
        defer { rendering = false }
        while pending != nil {
            // Let rapid slider and crop events replace the pending recipe before starting a render.
            try? await Task.sleep(for: .milliseconds(32))
            guard let request = pending else { return }
            pending = nil
            let image = request.image
            let recipe = request.recipe
            let output = await Task.detached(priority: .userInitiated) {
                PhotoEditRenderer.preview(image, recipe: recipe)
            }.value
            if request.generation == generation { request.apply(output) }
        }
    }
}
