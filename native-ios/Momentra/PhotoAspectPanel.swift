import SwiftUI

struct PhotoAspectPanel: View {
    @Binding var selection: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Text("PROPORÇÃO").font(.subheadline.weight(.medium)).tracking(1.2)
                HStack {
                    Button(action: close) {
                        Image(systemName: "chevron.left").font(.headline)
                            .frame(width: 40, height: 40).background(.black.opacity(0.35), in: Circle())
                    }.accessibilityLabel("Fechar proporções")
                    Spacer()
                }
            }
            Text(selection).font(.system(size: 32, weight: .regular))
                .contentTransition(.numericText())
            HStack(spacing: 0) {
                ForEach(PhotoAspect.allCases, id: \.rawValue) { aspect in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selection = aspect.rawValue }
                    } label: {
                        ZStack {
                            Image(systemName: "viewfinder").font(.system(size: 30, weight: .medium))
                            Text(aspect.rawValue).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(selection == aspect.rawValue ? Color.yellow : Color.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Proporção \(aspect.rawValue)")
                    .accessibilityAddTraits(selection == aspect.rawValue ? .isSelected : [])
                }
            }.padding(.horizontal, 36)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
        .background(Color(white: 0.11).opacity(0.94), in: RoundedRectangle(cornerRadius: 40))
        .overlay(RoundedRectangle(cornerRadius: 40).stroke(.white.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 8).padding(.bottom, 6)
    }
}
