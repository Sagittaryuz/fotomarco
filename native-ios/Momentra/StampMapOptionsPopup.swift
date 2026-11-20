import SwiftUI

struct StampMapOptionsPopup: View {
    @ObservedObject var store: StampProfilesStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StampLayout

    init(store: StampProfilesStore) {
        self.store = store
        _draft = State(initialValue: store.selected.layout)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        .modifier(GalleryControlSurface(rounded: true))
                }.accessibilityLabel("Voltar")
                Spacer()
                Text("Mapa").font(.headline)
                Spacer()
                Button("Salvar") { store.setLayout(draft); dismiss() }
                    .padding(.horizontal, 16).frame(height: 44)
                    .modifier(GalleryControlSurface(rounded: true))
            }
            HStack(spacing: 12) {
                option("Desligar", image: nil, selected: !draft.showsMap) { draft.showsMap = false }
                option("Mapa", image: "StampSampleMap", selected: draft.showsMap && draft.mapStyle == .map) {
                    draft.showsMap = true; draft.mapStyle = .map
                }
                option("Satélite", image: "StampSampleAerial", selected: draft.showsMap && draft.mapStyle == .satellite) {
                    draft.showsMap = true; draft.mapStyle = .satellite
                }
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 20).padding(.top, 22)
            .preferredColorScheme(.dark)
    }

    private func option(_ title: String, image: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let image { Image(image).resizable().scaledToFill() }
                    else { Image(systemName: "eye.slash").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.08)) }
                }
                .frame(height: 105).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.yellow : Color.white.opacity(0.16), lineWidth: selected ? 2 : 1) }
                Text(title).font(.subheadline).foregroundStyle(selected ? .yellow : .primary)
            }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
