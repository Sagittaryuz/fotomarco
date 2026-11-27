import SwiftUI

/// Camera tray editor; changes are stored immediately and frozen for each capture.
struct CameraPhotoStylesView: View {
    @Binding var selected: String
    @Binding var tone: Double
    @Binding var color: Double
    @Binding var palette: Double
    @State private var customizing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    FotomarcoHaptics.play(.buttons)
                    if customizing { withAnimation { customizing = false } } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left").frame(width: 40, height: 40)
                        .modifier(GalleryControlSurface(rounded: true, tint: .white))
                }.accessibilityLabel("Voltar").accessibilityIdentifier("camera.styles.back")
                Spacer(minLength: 0)
                if customizing {
                    Text("TOM \(Int(tone))   COR \(Int(color))   PALETA \(Int(palette))")
                        .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text(selected.uppercased()).font(.subheadline.weight(.semibold)).tracking(1)
                }
                Spacer(minLength: 0)
                Color.clear.frame(width: 40, height: 40).accessibilityHidden(true)
            }.padding(.horizontal, 16)
            if customizing {
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(LinearGradient(colors: [.white.opacity(0.4), .blue.opacity(0.35), .black.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .position(x: side * CGFloat((color + 100) / 200), y: side * CGFloat((100 - tone) / 200))
                    }
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard side > 0 else { return }
                        color = max(-100, min(100, Double(value.location.x / side) * 200 - 100)).rounded()
                        tone = max(-100, min(100, 100 - Double(value.location.y / side) * 200)).rounded()
                    })
                    .accessibilityLabel("Ajustar tom e cor")
                }.frame(width: 94, height: 94)
                HStack {
                    Image(systemName: "minus")
                    Slider(value: $palette, in: 0...200, step: 1).tint(.yellow)
                        .accessibilityLabel("Paleta")
                    Image(systemName: "plus")
                }.padding(.horizontal, 32)
                Button("Redefinir") { tone = 0; color = 0; palette = 100 }
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(MomentraPhotoStyle.allCases) { style in
                            Button {
                                FotomarcoHaptics.play(.buttons)
                                selected = style.rawValue
                            } label: {
                                VStack(spacing: 5) {
                                    StylePreview(style: style)
                                        .frame(width: 65, height: 65)
                                        .clipShape(RoundedRectangle(cornerRadius: 11))
                                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected == style.rawValue ? .yellow : .clear, lineWidth: 2))
                                    Text(style.rawValue).font(.caption2).foregroundStyle(.white)
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("camera.style.\(style.rawValue)")
                        }
                    }.padding(.horizontal, 16)
                }
                if selected != MomentraPhotoStyle.disabled.rawValue {
                    Button("Personalizar") { withAnimation { customizing = true } }
                        .accessibilityIdentifier("camera.styles.customize")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color.clear)
    }
}

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
            Text("Efeitos aplicados à cópia fotografada pelo Photomark. O original é preservado.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Estilos fotográficos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { candidate = MomentraPhotoStyle(rawValue: selected) ?? .natural }
    }
}

@MainActor
private enum StylePreviewCache {
    static let images = NSCache<NSString, UIImage>()
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
            let key = style.rawValue as NSString
            if let cached = StylePreviewCache.images.object(forKey: key) { image = cached; return }
            guard let source = UIImage(named: "StyleSample") else { return }
            let rendered = await Task.detached(priority: .userInitiated) { style.apply(to: source) }.value
            guard !Task.isCancelled else { return }
            StylePreviewCache.images.setObject(rendered, forKey: key)
            image = rendered
        }
    }
}
