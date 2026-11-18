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
                    Toggle("Mapa", isOn: flag(\.showsMap))
                    Toggle("Informações", isOn: flag(\.showsInformation))
                    Toggle("Logotipo", isOn: flag(\.showsLogo))
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                if layout.wrappedValue.mode == .separate {
                    Text("Arraste os elementos sobre a foto para escolher onde aparecem.")
                        .font(.footnote).foregroundStyle(.secondary)
                }


                Picker("Visualização do mapa", selection: layout.mapStyle) {
                    Text("Mapa").tag(StampLayout.MapAppearance.map)
                    Text("Satélite").tag(StampLayout.MapAppearance.satellite)
                }.pickerStyle(.segmented)

                Group {
                    Picker("Fonte", selection: layout.fontStyle) {
                        Text("Sistema").tag("system")
                        Text("Serifada").tag("serif")
                        Text("Monoespaçada").tag("mono")
                    }
                    Picker("Alinhamento dos textos", selection: layout.textAlignment) {
                        Text("Automático").tag("auto")
                        Text("Esquerda").tag("left")
                        Text("Centro").tag("center")
                        Text("Direita").tag("right")
                    }
                    Picker("Data e hora", selection: layout.dateFormat) {
                        Text("Numérica").tag("numeric")
                        Text("Por extenso").tag("long")
                    }
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
                    Toggle("Texto compacto", isOn: flag(\.compact))
                    Toggle("Incluir endereço", isOn: flag(\.showsAddress))
                }
                if layout.wrappedValue.mode == .combined {
                    sizeControl("Tamanho do carimbo", value: layout.combinedSize)
                }
                sizeControl("Tamanho do mapa", value: layout.mapSize)
                sizeControl("Tamanho das informações", value: layout.informationSize)
                sizeControl("Tamanho do logotipo", value: layout.logoSize)

                Text("Pré-visualização").font(.headline)
                StampLayoutPreview(layout: layout, logo: ProfileLogoStore.load(store.selected.logoName))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text("A prévia usa dados de exemplo. O carimbo final usa as informações disponíveis no momento da captura.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Observação na foto (opcional)", text: note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                PhotosPicker(selection: $selectedLogo, matching: .images) {
                    Label("Escolher logotipo", systemImage: "photo")
                }.disabled(logoLoading)
                Button(action: importLogo) { Label("Escolher logotipo dos Arquivos", systemImage: "folder") }
                    .disabled(logoLoading)
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

    private func point(_ keyPath: WritableKeyPath<StampLayout, StampPoint>, in size: CGSize) -> CGPoint {
        let point = layout[keyPath: keyPath]
        return CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.height)
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
                        previewMap.frame(width: min(size.width * 0.5, size.width * previewMapFraction * layout.mapSize),
                                         height: min(size.width * 0.5, size.width * previewMapFraction * layout.mapSize))
                            .contentShape(Rectangle()).position(point(\.map, in: size)).gesture(gesture(\.map, in: size))
                    }
                    if layout.showsInformation {
                        previewText.frame(width: min(size.width * 0.95, size.width * 0.60 * max(1, layout.informationSize)), alignment: layout.information.x >= 0.5 ? .trailing : .leading)
                            .position(point(\.information, in: size)).gesture(gesture(\.information, in: size))
                    }
                    if layout.showsLogo, let logo {
                        Image(uiImage: logo).resizable().scaledToFit()
                            .frame(width: min(size.width * 0.35, size.width * 0.15 * layout.logoSize),
                                   height: min(size.width * 0.35, size.width * 0.15 * layout.logoSize))
                            .position(point(\.logo, in: size)).gesture(gesture(\.logo, in: size))
                    } else if layout.showsLogo {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.white)
                            .shadow(radius: 3).frame(width: min(size.width * 0.35, size.width * 0.15 * layout.logoSize),
                                   height: min(size.width * 0.35, size.width * 0.15 * layout.logoSize))
                            .position(point(\.logo, in: size)).gesture(gesture(\.logo, in: size))
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

    private var previewText: some View {
        Text((layout.showsAddress ? "Endereço de exemplo\nJataí GO, Brasil\n" : "") +
             "Lat: -17,908894  Lon: -51,744607\n" +
             (layout.dateFormat == "long" ? "17 de novembro de 2026, 08:50" : "17/11/2026 08:50"))
            .font(.system(size: 10 * layout.informationSize * (layout.mode == .combined ? layout.combinedSize : 1), weight: .medium))
            .fontDesign(layout.fontStyle == "mono" ? .monospaced : layout.fontStyle == "serif" ? .serif : .default)
            .foregroundStyle(.white)
            .multilineTextAlignment(textAlignment)
            .shadow(color: .black, radius: 2)
    }
}
