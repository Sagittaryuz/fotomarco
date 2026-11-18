import SwiftUI
import PhotosUI

struct StampLayoutEditor: View {
    @ObservedObject var store: StampProfilesStore
    @Binding var selectedLogo: PhotosPickerItem?
    let logoLoading: Bool
    let importLogo: () -> Void
    let importSettings: () -> Void
    @Binding var mapEnabled: Bool
    @State private var showLimit = false
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
                    Button { if !store.create() { showLimit = true } } label: {
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

                if layout.wrappedValue.mode == .separate {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Mapa", isOn: flag(\.showsMap))
                        Toggle("Informações", isOn: flag(\.showsInformation))
                        Toggle("Logotipo", isOn: flag(\.showsLogo))
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    Text("Arraste os elementos sobre a foto para escolher onde aparecem.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Text("Pré-visualização").font(.headline)
                StampLayoutPreview(layout: layout, logo: ProfileLogoStore.load(store.selected.logoName))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text("A prévia usa dados de exemplo. O carimbo final usa as informações disponíveis no momento da captura.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Incluir mapa nas fotos", isOn: $mapEnabled)
                TextField("Observação na foto (opcional)", text: note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                PhotosPicker(selection: $selectedLogo, matching: .images) {
                    Label("Escolher logotipo", systemImage: "photo")
                }.disabled(logoLoading)
                Button(action: importLogo) { Label("Escolher logotipo dos Arquivos", systemImage: "folder") }
                    .disabled(logoLoading)
                if !store.selected.logoName.isEmpty {
                    Button("Remover logotipo", role: .destructive) {
                        store.setLogo("", for: store.selectedID)
                    }.disabled(logoLoading)
                }
                Button("Importar ajustes do Scripting", action: importSettings)
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
                        previewMap.frame(width: size.width * 0.2, height: size.width * 0.2)
                        previewText
                        Spacer(minLength: 0)
                    }.padding(10).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        .padding(10).frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    if layout.showsMap {
                        previewMap.frame(width: size.width * 0.20, height: size.width * 0.20)
                            .position(point(\.map, in: size)).gesture(gesture(\.map, in: size))
                    }
                    if layout.showsInformation {
                        previewText.frame(width: size.width * 0.60, alignment: layout.information.x >= 0.5 ? .trailing : .leading)
                            .position(point(\.information, in: size)).gesture(gesture(\.information, in: size))
                    }
                    if layout.showsLogo, let logo {
                        Image(uiImage: logo).resizable().scaledToFit()
                            .frame(width: size.width * 0.15, height: size.width * 0.15)
                            .position(point(\.logo, in: size)).gesture(gesture(\.logo, in: size))
                    } else if layout.showsLogo {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.white)
                            .shadow(radius: 3).frame(width: size.width * 0.15, height: size.width * 0.15)
                            .position(point(\.logo, in: size)).gesture(gesture(\.logo, in: size))
                    }
                }
            }.coordinateSpace(name: "stampPreview")
        }
    }

    private var previewMap: some View {
        ZStack {
            Color(red: 0.18, green: 0.29, blue: 0.38)
            Image(systemName: "map.fill").resizable().scaledToFit().padding(8).foregroundStyle(.white.opacity(0.6))
            Image(systemName: "location.circle.fill").foregroundStyle(.blue, .white)
        }.clipShape(RoundedRectangle(cornerRadius: 4))
    }
    private var previewText: some View {
        Text("Endereço de exemplo\nJataí GO, Brasil\nLat: -17,908894  Lon: -51,744607\n17/11/2026 08:50")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
            .multilineTextAlignment(layout.information.x >= 0.5 ? .trailing : .leading)
            .shadow(color: .black, radius: 2)
    }
}
