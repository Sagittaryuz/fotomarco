import SwiftUI
import PhotosUI
import MapKit

struct StampLayoutEditor: View {
    @ObservedObject var store: StampProfilesStore
    @Binding var selectedLogo: PhotosPickerItem?
    let logoLoading: Bool
    let importLogo: () -> Void
    @State private var showLimit = false
    @State private var chooseStartup = false
    @State private var confirmRemove = false

    private var layout: Binding<StampLayout> {
        Binding(get: { store.selected.layout }, set: { store.setLayout($0) })
    }
    private var name: Binding<String> {
        Binding(get: { store.selected.name }, set: { store.rename($0) })
    }
    private var note: Binding<String> {
        Binding(get: { store.selected.note }, set: { store.setNote($0) })
    }
    private func flag(_ keyPath: WritableKeyPath<StampLayout, Bool>) -> Binding<Bool> {
        Binding(get: { store.selected.layout[keyPath: keyPath] },
                set: { value in var next = store.selected.layout; next[keyPath: keyPath] = value; store.setLayout(next) })
    }

    private func sizeControl(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: value, in: 0.5...2.0, step: 0.05).tint(.white)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                Text("\(Int((value.wrappedValue * 100).rounded()))%").font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func cornerControl(_ point: Binding<StampPoint>) -> some View {
        let corners: [(String, StampPoint, Alignment)] = [
            ("Superior esquerdo", StampPoint(x: 0, y: 0), .topLeading),
            ("Superior direito", StampPoint(x: 1, y: 0), .topTrailing),
            ("Inferior esquerdo", StampPoint(x: 0, y: 1), .bottomLeading),
            ("Inferior direito", StampPoint(x: 1, y: 1), .bottomTrailing)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Posição na foto").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { index in
                    let corner = corners[index]
                    let selected = (point.wrappedValue.x >= 0.5) == (corner.1.x >= 0.5) &&
                        (point.wrappedValue.y >= 0.5) == (corner.1.y >= 0.5)
                    Button { point.wrappedValue = corner.1 } label: {
                        RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.blue : Color.secondary, lineWidth: selected ? 2 : 1)
                            .frame(width: 48, height: 58)
                            .overlay(alignment: corner.2) {
                                RoundedRectangle(cornerRadius: 2).fill(selected ? Color.blue : Color.secondary)
                                    .frame(width: 15, height: 12).padding(5)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Menu {
                        ForEach(store.profiles) { item in
                            Button { store.select(item.id) } label: {
                                if item.id == store.selectedID { Label(item.name, systemImage: "checkmark") }
                                else { Text(item.name) }
                            }
                        }
                    } label: {
                        Label(store.selected.name.isEmpty ? "Sem nome" : store.selected.name, systemImage: "square.on.square")
                            .font(.headline)
                    }
                    Spacer()
                    Button {
                        let wasSingle = store.profiles.count == 1
                        if store.create() { if wasSingle { chooseStartup = true } }
                        else { showLimit = true }
                    } label: {
                        Image(systemName: "plus").font(.headline).padding(10)
                            .background(.thinMaterial, in: Circle())
                    }.accessibilityLabel("Criar perfil")
                }
                TextField("Nome do perfil", text: name)
                    .textFieldStyle(.roundedBorder)
                Picker("Composição", selection: layout.mode) {
                    Text("Carimbo único").tag(StampLayout.Mode.combined)
                    Text("Elementos separados").tag(StampLayout.Mode.separate)
                }.pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup("Mapa") {
                        Toggle("Mostrar mapa", isOn: flag(\.showsMap))
                        if layout.wrappedValue.mode == .separate { cornerControl(layout.map) }
                        Picker("Visualização do mapa", selection: layout.mapStyle) {
                            Text("Mapa").tag(StampLayout.MapAppearance.map)
                            Text("Satélite").tag(StampLayout.MapAppearance.satellite)
                        }.pickerStyle(.segmented)
                        sizeControl("Tamanho do mapa", value: layout.mapSize)
                    }
                    DisclosureGroup("Informações") {
                        Toggle("Mostrar informações", isOn: flag(\.showsInformation))
                        if layout.wrappedValue.mode == .separate { cornerControl(layout.information) }
                        Picker("Fonte", selection: layout.fontStyle) {
                            Text("Sistema").tag("system"); Text("Serifada").tag("serif"); Text("Monoespaçada").tag("mono")
                        }
                        Picker("Alinhamento dos textos", selection: layout.textAlignment) {
                            Text("Automático").tag("auto"); Text("Esquerda").tag("left"); Text("Centro").tag("center"); Text("Direita").tag("right")
                        }
                        Picker("Data e hora", selection: layout.dateFormat) {
                            Text("Numérica").tag("numeric"); Text("Por extenso").tag("long")
                        }
                        Toggle("Texto compacto", isOn: flag(\.compact))
                        Toggle("Incluir endereço", isOn: flag(\.showsAddress))
                        sizeControl("Tamanho das informações", value: layout.informationSize)
                    }
                    DisclosureGroup("Logotipo") {
                        Toggle("Mostrar logotipo", isOn: flag(\.showsLogo))
                        if layout.wrappedValue.mode == .separate { cornerControl(layout.logo) }
                        sizeControl("Tamanho do logotipo", value: layout.logoSize)
                        PhotosPicker(selection: $selectedLogo, matching: .images) {
                            Label("Escolher logotipo", systemImage: "photo")
                        }.disabled(logoLoading)
                        Button(action: importLogo) { Label("Escolher logotipo dos Arquivos", systemImage: "folder") }
                            .disabled(logoLoading)
                    }
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                if layout.wrappedValue.mode == .separate {
                    Text("Arraste os elementos sobre a foto para escolher onde aparecem.")
                        .font(.footnote).foregroundStyle(.secondary)
                }


                Group {
                    if layout.wrappedValue.mode == .combined {
                        Picker("Posição do carimbo", selection: layout.position) {
                            Text("Embaixo").tag("bottom")
                            Text("Em cima").tag("top")
                        }
                        Picker("Largura e posição", selection: layout.horizontal) {
                            Text("Largura total").tag("auto")
                            Text("Esquerda").tag("left")
                            Text("Direita").tag("right")
                        }
                    }
                }
                if layout.wrappedValue.mode == .combined {
                    sizeControl("Tamanho do carimbo", value: layout.combinedSize)
                }

                Text("Pré-visualização").font(.headline)
                StampLayoutPreview(layout: layout, logo: ProfileLogoStore.load(store.selected.logoName))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text("A prévia usa dados de exemplo. O carimbo final usa as informações disponíveis no momento da captura.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Observação na foto (opcional)", text: note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                if store.profiles.count > 1 {
                    Button("Apagar este perfil", role: .destructive) { confirmRemove = true }
                }
            }.padding()
        }
        .navigationTitle("Carimbos")
        .navigationBarTitleDisplayMode(.inline)
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
}

private struct StampLayoutPreview: View {
    @Binding var layout: StampLayout
    let logo: UIImage?

    private func rect(_ keyPath: WritableKeyPath<StampLayout, StampPoint>, in size: CGSize, element: CGSize) -> CGRect {
        StampRenderer.positionedRect(size: size, element: element, centre: layout[keyPath: keyPath],
                                     margin: min(size.width, size.height) * 0.025)
    }
    private func gesture(_ keyPath: WritableKeyPath<StampLayout, StampPoint>, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("stampPreview"))
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                layout[keyPath: keyPath] = StampPoint(x: Double(value.location.x / size.width),
                                                    y: Double(value.location.y / size.height))
            }
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
                        if layout.showsLogo, let logo {
                            Image(uiImage: logo).resizable().scaledToFit()
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
                            .contentShape(Rectangle()).position(x: box.midX, y: box.midY).gesture(gesture(\.map, in: size))
                    }
                    if layout.showsInformation {
                        let margin = min(size.width, size.height) * 0.025
                        let space = StampRenderer.availableSize(size: size, anchor: layout.information, margin: margin)
                        let width = min(space.width, size.width * 0.60 * max(1, layout.informationSize))
                        let paragraph = NSMutableParagraphStyle()
                        let measured = StampRenderer.fitText(previewString as NSString, width: width, maxHeight: space.height,
                            initialSize: 10 * layout.informationSize, style: layout.fontStyle, paragraph: paragraph)
                        let box = rect(\.information, in: size, element: CGSize(width: width, height: measured?.height ?? 0))
                        previewText.frame(width: box.width, height: box.height, alignment: layout.information.x >= 0.5 ? .topTrailing : .topLeading)
                            .position(x: box.midX, y: box.midY).gesture(gesture(\.information, in: size))
                    }
                    if layout.showsLogo, let logo {
                        let space = StampRenderer.availableSize(size: size, anchor: layout.logo, margin: min(size.width, size.height) * 0.025)
                        let side = min(space.width, space.height, size.width * 0.35, size.width * 0.15 * layout.logoSize)
                        let factor = min(side / max(1, logo.size.width), side / max(1, logo.size.height))
                        let box = rect(\.logo, in: size, element: CGSize(width: logo.size.width * factor, height: logo.size.height * factor))
                        Image(uiImage: logo).resizable().scaledToFit()
                            .frame(width: box.width, height: box.height)
                            .position(x: box.midX, y: box.midY).gesture(gesture(\.logo, in: size))
                    } else if layout.showsLogo {
                        let space = StampRenderer.availableSize(size: size, anchor: layout.logo, margin: min(size.width, size.height) * 0.025)
                        let side = min(space.width, space.height, size.width * 0.35, size.width * 0.15 * layout.logoSize)
                        let box = rect(\.logo, in: size, element: CGSize(width: side, height: side))
                        Image(systemName: "photo").font(.title2).foregroundStyle(.white)
                            .shadow(radius: 3).frame(width: box.width, height: box.height)
                            .position(x: box.midX, y: box.midY).gesture(gesture(\.logo, in: size))
                    }
                }
            }.coordinateSpace(name: "stampPreview")
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
        let coordinate = CLLocationCoordinate2D(latitude: -17.908894, longitude: -51.744607)
        return Map(position: .constant(.region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350))), interactionModes: []) {
            Annotation("Exemplo", coordinate: coordinate) {
                Circle().fill(.blue).frame(width: 9, height: 9).overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .mapStyle(layout.mapStyle == .satellite ? .imagery : .standard)
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 4))
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
        (layout.showsAddress ? "Endereço de exemplo\nJataí GO, Brasil\n" : "") +
             "Lat: -17,908894  Lon: -51,744607\n" +
             (layout.dateFormat == "long" ? "17 de novembro de 2026, 08:50" : "17/11/2026 08:50")
    }

    private var previewText: some View {
        Text(previewString)
            .font(.system(size: 10 * layout.informationSize * (layout.mode == .combined ? layout.combinedSize : 1), weight: .medium))
            .fontDesign(layout.fontStyle == "mono" ? .monospaced : layout.fontStyle == "serif" ? .serif : .default)
            .foregroundStyle(.white)
            .multilineTextAlignment(textAlignment)
            .shadow(color: .black, radius: 2)
    }
}
