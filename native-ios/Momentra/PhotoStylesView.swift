import SwiftUI

struct PhotoStylesView: View {
    @Binding var selected: String
    @State private var candidate: MomentraPhotoStyle = .natural
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Passe o dedo para escolher um estilo fotográfico.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            TabView(selection: $candidate) {
                ForEach(MomentraPhotoStyle.allCases) { style in
                    StylePreview(style: style).tag(style).padding(.horizontal, 16)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: 450)
            Text(candidate.detail).multilineTextAlignment(.center).frame(minHeight: 44).padding(.horizontal)
            Button {
                FotomarcoHaptics.play(.editor)
                selected = candidate.rawValue
                dismiss()
            } label: {
                Text("Usar \(candidate.rawValue)")
                    .padding(.horizontal, 20).frame(minHeight: 44)
                    .contentShape(Capsule())
                    .modifier(GalleryControlSurface(rounded: true))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            Text("Efeitos aplicados à cópia fotografada pelo Fotomarco. O original é preservado.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Estilos fotográficos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { candidate = MomentraPhotoStyle(rawValue: selected) ?? .natural }
    }
}

private struct StylePreview: View {
    let style: MomentraPhotoStyle
    @State private var image: UIImage?
    var body: some View {
        ZStack(alignment: .bottom) {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Color.gray.opacity(0.3) }
            Text(style.rawValue.uppercased()).font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .modifier(GalleryControlSurface(rounded: true, tint: .white, interactive: false))
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 45)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: style) {
            guard let source = UIImage(named: "StyleSample") else { return }
            image = style.apply(to: source)
        }
    }
}
