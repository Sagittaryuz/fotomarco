import SwiftUI

struct PhotoAspectPanel: View {
    @Binding var selection: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Text("PROPORÇÃO").font(.subheadline.weight(.medium)).tracking(1.2)
                HStack {
                    Button(action: { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); close() }) {
                        Image(systemName: "chevron.left").font(.headline)
                            .frame(width: 44, height: 44)
                            .modifier(GalleryControlSurface(rounded: true))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar proporções")
                    Spacer()
                }
            }
            Text(selection).font(.system(size: 32, weight: .regular))
                .contentTransition(.numericText())
            HStack(spacing: 0) {
                ForEach(PhotoAspect.allCases, id: \.rawValue) { aspect in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2)
                        withAnimation(.easeInOut(duration: 0.2)) { selection = aspect.rawValue }
                    } label: {
                        ZStack {
                            Image(systemName: "viewfinder").font(.system(size: 30, weight: .medium))
                            Text(aspect.rawValue).font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .contentShape(Capsule())
                        .modifier(GalleryControlSurface(rounded: true, tint: selection == aspect.rawValue ? .yellow : .white))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Proporção \(aspect.rawValue)")
                    .accessibilityAddTraits(selection == aspect.rawValue ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 8).padding(.bottom, 6)
    }
}
