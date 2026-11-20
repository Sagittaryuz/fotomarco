import SwiftUI
import PhotosUI
import CoreLocation

struct StampLayoutEditor: View {
    @ObservedObject private var originalStore: StampProfilesStore
    @StateObject private var store: StampProfilesStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLogo: PhotosPickerItem?
    @State private var logoLoading = false
    @State private var importLogo = false
    @State private var importMessage: String?
    @State private var showPhotoPicker = false
    @State private var previewLogo: UIImage?
    @State private var previewExtraLogos: [UIImage?] = []
    @State private var logoSlot = 0
    @State private var showLimit = false
    @State private var chooseStartup = false
    @State private var confirmRemove = false
    @State private var renameProfile = false
    @State private var editNote = false
    @State private var draftName = ""
    @State private var draftNote = ""
    @State private var editingElement: Element = .map
    fileprivate enum Element: String, CaseIterable { case combined = "Carimbo", map = "Mapa", information = "Informações", logo = "Logotipo" }

    init(store: StampProfilesStore) {
        originalStore = store
        _store = StateObject(wrappedValue: StampProfilesStore(draftOf: store))
    }

    private var layout: Binding<StampLayout> {
        Binding(get: { store.selected.layout }, set: { store.setLayout($0) })
    }
    private func flag(_ keyPath: WritableKeyPath<StampLayout, Bool>) -> Binding<Bool> {
        Binding(get: { store.selected.layout[keyPath: keyPath] },
                set: { value in var next = store.selected.layout; next[keyPath: keyPath] = value; store.setLayout(next) })
    }

    private func sizeControl(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: value, in: 0.5...2.0, step: 0.05).tint(.white).accessibilityLabel(title)
            Text("\(Int((value.wrappedValue * 100).rounded()))%").font(.subheadline.monospacedDigit()).frame(width: 48, alignment: .trailing)
        }
    }

    private func cornerControl(_ point: Binding<StampPoint>) -> some View {
        let corners: [(String, StampPoint, Alignment)] = [
            ("Superior esquerdo", StampPoint(x: 0, y: 0), .topLeading),
            ("Superior direito", StampPoint(x: 1, y: 0), .topTrailing),
            ("Inferior esquerdo", StampPoint(x: 0, y: 1), .bottomLeading),
            ("Inferior direito", StampPoint(x: 1, y: 1), .bottomTrailing)
        ]
        return VStack(alignment: .leading, spacing: 2) {
            Text("Posição na foto").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { index in
                    let corner = corners[index]
                    let selected = point.wrappedValue == corner.1
                    Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); point.wrappedValue = corner.1 } label: {
                        RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.yellow : Color.secondary, lineWidth: selected ? 2 : 1)
                            .frame(width: 36, height: 42)
                            .overlay(alignment: corner.2) {
                                RoundedRectangle(cornerRadius: 2).fill(selected ? Color.yellow : Color.secondary)
                                    .frame(width: 12, height: 9).padding(4)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                            .contentShape(Capsule())
                            .modifier(GalleryControlSurface(rounded: true))
                    }
                    .buttonStyle(.plain).accessibilityLabel(corner.0)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func elementButton(_ element: Element) -> some View {
        Button(element.rawValue) { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); editingElement = element }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .modifier(GalleryControlSurface(rounded: true))
            .overlay {
                if editingElement == element {
                    Capsule().strokeBorder(.yellow, lineWidth: 1.5).allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(editingElement == element ? .isSelected : [])
    }

    private var editorContent: some View {
        VStack(spacing: 8) {
            HStack {
                Menu {
                    ForEach(store.profiles) { item in
                        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); store.select(item.id) } label: {
                            if item.id == store.selectedID { Label(item.name, systemImage: "checkmark") }
                            else { Text(item.name) }
                        }
                    }
                    Divider()
                    Button("Renomear perfil") { draftName = store.selected.name; renameProfile = true }
                    if store.profiles.count > 1 { Button("Apagar perfil", role: .destructive) { confirmRemove = true } }
                } label: {
                    Label(store.selected.name.isEmpty ? "Sem nome" : store.selected.name, systemImage: "square.on.square")
                        .font(.headline).lineLimit(1)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .modifier(GalleryControlSurface(rounded: true))
                }
                Spacer()
                Button {
                    let wasSingle = store.profiles.count == 1
                    if store.create() { if wasSingle { chooseStartup = true } } else { showLimit = true }
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                        .modifier(GalleryControlSurface(rounded: true))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Criar perfil")
            }
            Picker("Modelo", selection: layout.template) {
                Text("Atual").tag(StampLayout.Template.original)
                Text("Relatório de trabalho").tag(StampLayout.Template.workReport)
                Text("Planilha").tag(StampLayout.Template.spreadsheet)
                Text("Localização e clima").tag(StampLayout.Template.locationWeather)
                Text("Hora e localização").tag(StampLayout.Template.timeLocation)
                Text("Personalizado").tag(StampLayout.Template.custom)
                Text("Mapa").tag(StampLayout.Template.map)
                Text("Mapa grande").tag(StampLayout.Template.largeMap)
                Text("Registro de visita").tag(StampLayout.Template.visit)
                Text("Entrega").tag(StampLayout.Template.delivery)
                Text("Limpo").tag(StampLayout.Template.clean)
                Text("Registrar entrada").tag(StampLayout.Template.checkIn)
                Text("Patrulha").tag(StampLayout.Template.patrol)
                Text("Concluído").tag(StampLayout.Template.completed)
                Text("Prova de entrega").tag(StampLayout.Template.deliveryProof)
                Text("Inspeção").tag(StampLayout.Template.inspection)
                Text("Retrato").tag(StampLayout.Template.portrait)
                Text("Shopee").tag(StampLayout.Template.shopee)
                Text("Construção").tag(StampLayout.Template.construction)
            }
            if layout.wrappedValue.template == .original {
            Picker("Composição", selection: layout.mode) {
                Text("Carimbo único").tag(StampLayout.Mode.combined)
                Text("Elementos separados").tag(StampLayout.Mode.separate)
            }.pickerStyle(.segmented)
            }
            StampLayoutPreview(layout: layout, selectedElement: editingElement, logo: previewLogo, extraLogos: previewExtraLogos)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Pré-visualização do carimbo")
            if layout.wrappedValue.template == .original {
            HStack(spacing: 4) {
                ForEach(Element.allCases, id: \.self) { element in
                    if element != .combined || layout.wrappedValue.mode == .combined {
                        elementButton(element)
                    }
                }
            }
            elementEditor.padding(10).modifier(GalleryControlSurface(interactive: false))
            } else {
                ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if layout.wrappedValue.template.usesLogo {
                        ForEach(0..<(layout.wrappedValue.template == .construction ? 3 : 1), id: \.self) { slot in
                            Menu(layout.wrappedValue.template == .portrait ? "Escolher retrato" : "Escolher logotipo \(slot + 1)") {
                                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); logoSlot = slot; showPhotoPicker = true } label: { Label("Fotos", systemImage: "photo") }
                                Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); logoSlot = slot; importLogo = true } label: { Label("Arquivos", systemImage: "folder") }
                            }.disabled(logoLoading)
                        }
                    }
                    if layout.wrappedValue.template.usesMap {
                        Picker("Visualização do mapa", selection: layout.mapStyle) {
                            Text("Mapa").tag(StampLayout.MapAppearance.map)
                            Text("Satélite").tag(StampLayout.MapAppearance.satellite)
                        }.pickerStyle(.segmented)
                        Toggle("Mostrar mapa", isOn: flag(\.showsMap)).toggleStyle(DirectionalSwitchStyle())
                    }
                    ForEach(layout.wrappedValue.template.fields, id: \.self) { field in
                        TextField(field, text: Binding(
                            get: { layout.wrappedValue.templateValue(field) },
                            set: { value in var next = layout.wrappedValue; next.setTemplateValue(value, for: field); layout.wrappedValue = next }
                        )).textFieldStyle(.roundedBorder)
                    }
                }.padding(10).modifier(GalleryControlSurface(interactive: false))
                }.frame(maxHeight: 220)
                    .scrollDismissesKeyboard(.interactively)
            }
        }.padding(.horizontal, 12).padding(.vertical, 6)
    }

    var body: some View {
        editorContent
        .task(id: ([store.selected.effectiveLogoName] + store.selected.additionalLogoNames).joined(separator: "|")) {
            let name = store.selected.effectiveLogoName
            let extraNames = store.selected.additionalLogoNames
            let images = await Task.detached(priority: .utility) { (ProfileLogoStore.load(name), extraNames.map { ProfileLogoStore.load($0) }) }.value
            guard !Task.isCancelled else { return }
            previewLogo = images.0
            previewExtraLogos = images.1
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedLogo, matching: .images)
        .fileImporter(isPresented: $importLogo, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            let profileID = store.selectedID
            let template = store.selected.layout.template
            let slot = logoSlot
            logoLoading = true
            Task {
                defer { logoLoading = false }
                do {
                    let name = try await Task.detached(priority: .utility) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let file = try FileHandle(forReadingFrom: url)
                        defer { try? file.close() }
                        return try ProfileLogoStore.save(file.read(upToCount: 20_000_001) ?? Data())
                    }.value
                    store.setLogo(name, for: profileID, template: template, slot: slot)
                } catch {
                    importMessage = "Não foi possível importar o logotipo."
                }
            }
        }
        .onChange(of: selectedLogo) { _, item in
            guard let item else { return }
            let profileID = store.selectedID
            let template = store.selected.layout.template
            let slot = logoSlot
            logoLoading = true
            Task {
                defer { logoLoading = false; selectedLogo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ProfileLogoStore.LogoError.invalid }
                    let name = try await Task.detached(priority: .utility) { try ProfileLogoStore.save(data) }.value
                    store.setLogo(name, for: profileID, template: template, slot: slot)
                } catch {
                    importMessage = "Não foi possível importar o logotipo."
                }
            }
        }
        .navigationTitle("Carimbos")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Voltar") { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); dismiss() }.disabled(logoLoading)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); originalStore.applyDraft(store); dismiss() }.disabled(logoLoading)
            }
        }
        .alert("Momentra", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: { Text(importMessage ?? "") }
        .onChange(of: layout.wrappedValue.mode) { _, mode in if mode == .separate && editingElement == .combined { editingElement = .map } }
        .alert("Renomear perfil", isPresented: $renameProfile) {
            TextField("Nome", text: $draftName)
            Button("Salvar") { store.rename(draftName) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Observação na foto", isPresented: $editNote) {
            TextField("Observação", text: $draftNote)
            Button("Salvar") { store.setNote(draftNote) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Limite de perfis atingido", isPresented: $showLimit) {
            Button("OK", role: .cancel) {}
        } message: { Text("Você pode criar até cinco perfis de carimbo.") }
        .confirmationDialog("Qual perfil deve abrir com o aplicativo?", isPresented: $chooseStartup, titleVisibility: .visible) {
            Button("Usar o último perfil") { store.setStartup("last") }
            ForEach(store.profiles) { item in
                Button("Sempre abrir com \(item.name.isEmpty ? "Sem nome" : item.name)") {
                    store.setStartup(item.id.uuidString)
                }
            }
        } message: { Text("Você poderá alterar essa escolha nas configurações.") }
        .confirmationDialog("Apagar este perfil?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Apagar perfil", role: .destructive) { store.removeSelected() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("As fotos existentes não serão alteradas.") }
    }

    @ViewBuilder private var elementEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(editingElement.rawValue).font(.subheadline.bold())
                Spacer()
                switch editingElement {
                case .combined:
                    Menu("Posição") {
                        Picker("Vertical", selection: layout.position) { Text("Em cima").tag("top"); Text("Embaixo").tag("bottom") }
                        Picker("Largura e posição", selection: layout.horizontal) { Text("Largura total").tag("auto"); Text("Esquerda").tag("left"); Text("Direita").tag("right") }
                    }
                case .map:
                    Menu(layout.wrappedValue.mapStyle == .map ? "Mapa" : "Satélite") {
                        Picker("Visualização", selection: layout.mapStyle) { Text("Mapa").tag(StampLayout.MapAppearance.map); Text("Satélite").tag(StampLayout.MapAppearance.satellite) }
                    }
                    Toggle("Mostrar mapa", isOn: flag(\.showsMap)).labelsHidden()
                        .toggleStyle(DirectionalSwitchStyle(showsLabel: false))
                case .information:
                    Menu("Opções") {
                        Picker("Fonte", selection: layout.fontStyle) { Text("Sistema").tag("system"); Text("Serifada").tag("serif"); Text("Monoespaçada").tag("mono") }
                        Picker("Alinhamento", selection: layout.textAlignment) { Text("Automático").tag("auto"); Text("Esquerda").tag("left"); Text("Centro").tag("center"); Text("Direita").tag("right") }
                        Picker("Data e hora", selection: layout.dateFormat) { Text("Numérica").tag("numeric"); Text("Por extenso").tag("long") }
                        Toggle("Texto compacto", isOn: flag(\.compact))
                        Toggle("Incluir endereço", isOn: flag(\.showsAddress))
                        Toggle("Incluir previsão do tempo", isOn: flag(\.showsForecast))
                        Button("Observação") { draftNote = store.selected.note; editNote = true }
                    }
                    Toggle("Mostrar informações", isOn: flag(\.showsInformation)).labelsHidden()
                        .toggleStyle(DirectionalSwitchStyle(showsLabel: false))
                case .logo:
                    Menu("Escolher") {
                        Button { showPhotoPicker = true } label: { Label("Fotos", systemImage: "photo") }
                        Button { importLogo = true } label: { Label("Arquivos", systemImage: "folder") }
                    }.disabled(logoLoading)
                    Toggle("Mostrar logotipo", isOn: flag(\.showsLogo)).labelsHidden()
                        .toggleStyle(DirectionalSwitchStyle(showsLabel: false))
                }
            }
            if layout.wrappedValue.mode == .separate {
                switch editingElement {
                case .map: cornerControl(layout.map)
                case .information: cornerControl(layout.information)
                case .logo: cornerControl(layout.logo)
                case .combined: EmptyView()
                }
            }
            switch editingElement {
            case .combined: sizeControl("Tamanho do carimbo", value: layout.combinedSize)
            case .map: sizeControl("Tamanho do mapa", value: layout.mapSize)
            case .information: sizeControl("Tamanho das informações", value: layout.informationSize)
            case .logo: sizeControl("Tamanho do logotipo", value: layout.logoSize)
            }
        }
    }
}

private struct StampLayoutPreview: View {
    @Binding var layout: StampLayout
    let selectedElement: StampLayoutEditor.Element
    let logo: UIImage?
    let extraLogos: [UIImage?]

    private func highlight(_ element: StampLayoutEditor.Element) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(.white.opacity(selectedElement == element ? 0.9 : 0), lineWidth: 1.5)
            .shadow(color: .black.opacity(selectedElement == element ? 0.8 : 0), radius: 4)
            .allowsHitTesting(false)
    }

    private func rect(_ keyPath: WritableKeyPath<StampLayout, StampPoint>, in size: CGSize, element: CGSize) -> CGRect {
        StampRenderer.positionedRect(size: size, element: element, centre: layout[keyPath: keyPath],
                                     margin: min(size.width, size.height) * 0.025)
    }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Image("StampPreview").resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                if layout.template.hasFixedRenderer {
                    let date = Date()
                    let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.7812, longitude: -73.9665), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: date)
                    let sample = StampSnapshot(capturedAt: date, gpsEnabled: true, addressEnabled: true,
                                               logo: logo, extraLogos: extraLogos, location: location, heading: nil, layout: layout)
                    let map = layout.showsMap ? UIImage(named: layout.mapStyle == .satellite ? "StampSampleAerial" : "StampSampleMap") : nil
                    if let overlay = StampRenderer.overlay(size: size, snapshot: sample, map: map, address: "Central Park · Nova York") {
                        Image(uiImage: overlay).resizable().frame(width: size.width, height: size.height)
                    }
                } else if layout.mode == .combined {
                    HStack(alignment: .top, spacing: 8) {
                        if layout.showsMap {
                            previewMap.frame(width: min(size.width * 0.4, size.width * previewMapFraction * layout.mapSize * layout.combinedSize),
                                             height: min(size.width * 0.4, size.width * previewMapFraction * layout.mapSize * layout.combinedSize))
                                .overlay { highlight(.map) }
                        }
                        if layout.showsInformation { previewText.overlay { highlight(.information) } }
                        Spacer(minLength: 0)
                        if layout.showsLogo {
                            previewLogo
                                .frame(width: min(size.width * 0.35, size.width * 0.15 * layout.logoSize * layout.combinedSize))
                                .overlay { highlight(.logo) }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: layout.horizontal == "auto" ? .infinity : size.width * 0.75, alignment: .leading)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { highlight(.combined) }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: combinedAlignment)
                } else {
                    if layout.showsMap {
                        let margin = min(size.width, size.height) * 0.025
                        let space = StampRenderer.availableSize(size: size, anchor: layout.map, margin: margin)
                        let side = min(space.width, space.height, size.width * 0.5, size.width * previewMapFraction * layout.mapSize)
                        let box = rect(\.map, in: size, element: CGSize(width: side, height: side))
                        previewMap.frame(width: box.width, height: box.height)
                            .overlay { highlight(.map) }
                            .position(x: box.midX, y: box.midY)
                    }
                    if layout.showsInformation {
                        let margin = min(size.width, size.height) * 0.025
                        let space = StampRenderer.availableSize(size: size, anchor: layout.information, margin: margin)
                        let width = min(space.width, size.width * 0.60 * max(1, layout.informationSize))
                        let paragraph = NSMutableParagraphStyle()
                        let measured = StampRenderer.fitText(previewString as NSString, width: width, maxHeight: space.height,
                            initialSize: 10 * layout.informationSize, style: layout.fontStyle, paragraph: paragraph)
                        let box = rect(\.information, in: size, element: CGSize(width: width, height: measured?.height ?? 0))
                        previewText(size: measured?.font.pointSize).frame(width: box.width, height: box.height, alignment: layout.information.x >= 0.5 ? .topTrailing : .topLeading)
                            .overlay { highlight(.information) }
                            .position(x: box.midX, y: box.midY)
                    }
                    if layout.showsLogo {
                        let space = StampRenderer.availableSize(size: size, anchor: layout.logo, margin: min(size.width, size.height) * 0.025)
                        let side = min(space.width, space.height, size.width * 0.35, size.width * 0.15 * layout.logoSize)
                        let box = rect(\.logo, in: size, element: CGSize(width: side, height: side))
                        previewLogo.frame(width: box.width, height: box.height)
                            .overlay { highlight(.logo) }
                            .position(x: box.midX, y: box.midY)
                    }
                }
            }.allowsHitTesting(false)
        }
    }

    private var previewMapFraction: CGFloat {
        layout.mapScale == "small" ? 0.14 : layout.mapScale == "large" ? 0.27 : 0.20
    }

    private var combinedAlignment: Alignment {
        switch (layout.position, layout.horizontal) {
        case ("top", "left"): return .topLeading
        case ("top", "right"): return .topTrailing
        case ("top", _): return .top
        case (_, "left"): return .bottomLeading
        case (_, "right"): return .bottomTrailing
        default: return .bottom
        }
    }

    private var previewMap: some View {
        Image(layout.mapStyle == .satellite ? "StampSampleAerial" : "StampSampleMap")
            .resizable().scaledToFit()
            .overlay {
                Circle().fill(.blue).frame(width: 9, height: 9)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
            }
            .accessibilityLabel(layout.mapStyle == .satellite ? "Imagem aérea de exemplo" : "Mapa de exemplo")
    }

    private var previewLogo: some View {
        Image(systemName: "building.2.crop.circle.fill").resizable().scaledToFit()
            .foregroundStyle(.white).shadow(radius: 3)
            .accessibilityLabel("Logotipo de exemplo")
    }
    private var textAlignment: TextAlignment {
        switch layout.textAlignment {
        case "left": return .leading
        case "center": return .center
        case "right": return .trailing
        default: return layout.information.x >= 0.5 ? .trailing : .leading
        }
    }

    private var previewString: String {
        (layout.showsAddress ? "Central Park · Nova York\n" : "") +
             "Lat: 40,7812  Lon: -73,9665\n" +
             (layout.dateFormat == "long" ? "17 de novembro de 2026, 08:50" : "17/11/2026 08:50")
    }

    private var previewText: some View { previewText(size: nil) }

    private func previewText(size: CGFloat?) -> some View {
        Text(previewString)
            .font(.system(size: size ?? 10 * layout.informationSize * (layout.mode == .combined ? layout.combinedSize : 1), weight: .medium))
            .fontDesign(layout.fontStyle == "mono" ? .monospaced : layout.fontStyle == "serif" ? .serif : .default)
            .foregroundStyle(.white)
            .multilineTextAlignment(textAlignment)
            .shadow(color: .black, radius: 2)
    }
}
