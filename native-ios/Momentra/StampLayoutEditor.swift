import SwiftUI
import PhotosUI

struct StampLayoutEditor: View {
    @ObservedObject var store: StampProfilesStore
    @Binding var selectedLogo: PhotosPickerItem?
    let logoLoading: Bool
    let importLogo: () -> Void
    @State private var showLimit = false
    @State private var chooseStartup = false
    @State private var confirmRemove = false
    @State private var renameProfile = false
    @State private var editNote = false
    @State private var draftName = ""
    @State private var draftNote = ""
    @State private var editingElement: Element = .map
    private enum Element: String, CaseIterable { case combined = "Carimbo", map = "Mapa", information = "Informações", logo = "Logotipo" }

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
                    Button { point.wrappedValue = corner.1 } label: {
                        RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.blue : Color.secondary, lineWidth: selected ? 2 : 1)
                            .frame(width: 36, height: 42)
                            .overlay(alignment: corner.2) {
                                RoundedRectangle(cornerRadius: 2).fill(selected ? Color.blue : Color.secondary)
                                    .frame(width: 12, height: 9).padding(4)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(corner.0)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Menu {
                    ForEach(store.profiles) { item in
                        Button { store.select(item.id) } label: {
                            if item.id == store.selectedID { Label(item.name, systemImage: "checkmark") }
                            else { Text(item.name) }
                        }
                    }
                    Divider()
                    Button("Renomear perfil") { draftName = store.selected.name; renameProfile = true }
                    if store.profiles.count > 1 { Button("Apagar perfil", role: .destructive) { confirmRemove = true } }
                } label: {
                    Label(store.selected.name.isEmpty ? "Sem nome" : store.selected.name, systemImage: "square.on.square").font(.headline)
                }
                Spacer()
                Button {
                    let wasSingle = store.profiles.count == 1
                    if store.create() { if wasSingle { chooseStartup = true } } else { showLimit = true }
                } label: { Image(systemName: "plus").padding(8).background(.thinMaterial, in: Circle()) }
                    .accessibilityLabel("Criar perfil")
            }
            Picker("Composição", selection: layout.mode) {
                Text("Carimbo único").tag(StampLayout.Mode.combined)
                Text("Elementos separados").tag(StampLayout.Mode.separate)
            }.pickerStyle(.segmented)
            StampLayoutPreview(layout: layout)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Pré-visualização do carimbo")
            HStack(spacing: 4) {
                ForEach(Element.allCases, id: \.self) { element in
                    if element != .combined || layout.wrappedValue.mode == .combined {
                        Button(element.rawValue) { editingElement = element }
                            .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(editingElement == element ? Color.blue : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(editingElement == element ? Color.white : Color.primary)
                    }
                }
            }
            elementEditor.padding(10).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }.padding(.horizontal, 12).padding(.vertical, 6)
        .navigationTitle("Carimbos")
        .navigationBarTitleDisplayMode(.inline)
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
                case .logo:
                    Menu("Escolher") {
                        PhotosPicker(selection: $selectedLogo, matching: .images) { Label("Fotos", systemImage: "photo") }
                        Button(action: importLogo) { Label("Arquivos", systemImage: "folder") }
                    }.disabled(logoLoading)
                    Toggle("Mostrar logotipo", isOn: flag(\.showsLogo)).labelsHidden()
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
                if layout.mode == .combined {
                    HStack(alignment: .top, spacing: 8) {
                        if layout.showsMap {
                            previewMap.frame(width: min(size.width * 0.4, size.width * previewMapFraction * layout.mapSize * layout.combinedSize),
                                             height: min(size.width * 0.4, size.width * previewMapFraction * layout.mapSize * layout.combinedSize))
                        }
                        if layout.showsInformation { previewText }
                        Spacer(minLength: 0)
                        if layout.showsLogo {
                            previewLogo
                                .frame(width: min(size.width * 0.35, size.width * 0.15 * layout.logoSize * layout.combinedSize))
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: layout.horizontal == "auto" ? .infinity : size.width * 0.75, alignment: .leading)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: combinedAlignment)
                } else {
                    if layout.showsMap {
                        let margin = min(size.width, size.height) * 0.025
                        let space = StampRenderer.availableSize(size: size, anchor: layout.map, margin: margin)
                        let side = min(space.width, space.height, size.width * 0.5, size.width * previewMapFraction * layout.mapSize)
                        let box = rect(\.map, in: size, element: CGSize(width: side, height: side))
                        previewMap.frame(width: box.width, height: box.height)
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
                            .position(x: box.midX, y: box.midY)
                    }
                    if layout.showsLogo {
                        let space = StampRenderer.availableSize(size: size, anchor: layout.logo, margin: min(size.width, size.height) * 0.025)
                        let side = min(space.width, space.height, size.width * 0.35, size.width * 0.15 * layout.logoSize)
                        let box = rect(\.logo, in: size, element: CGSize(width: side, height: side))
                        previewLogo.frame(width: box.width, height: box.height)
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
