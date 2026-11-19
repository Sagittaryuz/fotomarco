import SwiftUI

struct GallerySectionTabs: View {
    @Binding var selection: Int
    @GestureState private var translation: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let titles = ["Capturas", "Celular", "Nuvem"]

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - 10) / 3)
            let position = min(2 * width, max(0, CGFloat(selection) * width + (translation ?? 0)))
            let highlighted = Int((position / width).rounded())
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 19).fill(.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: 15).fill(Color.yellow.opacity(0.13))
                    .frame(width: width, height: 38)
                    .modifier(GalleryControlSurface(tint: .yellow, interactive: false))
                    .offset(x: 5 + position)
                HStack(spacing: 0) {
                    ForEach(titles.indices, id: \.self) { index in
                        Button { selection = index } label: {
                            Text(titles[index]).font(.subheadline.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.65)
                                .foregroundStyle(highlighted == index ? Color.yellow : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == index ? .isSelected : [])
                    }
                }.padding(.horizontal, 5)
            }
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.82), value: selection)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.82), value: translation == nil)
            .simultaneousGesture(DragGesture(minimumDistance: 10)
                .updating($translation) { value, state, _ in
                    if state != nil || abs(value.translation.width) > abs(value.translation.height) {
                        state = value.translation.width
                    }
                }
                .onEnded { value in
                    guard translation != nil || abs(value.translation.width) > abs(value.translation.height) else { return }
                    let offset = value.translation.width / width
                    let delta = abs(offset) < 0.25 ? 0 :
                        Int(max(1, abs(offset).rounded())) * (offset < 0 ? -1 : 1)
                    selection = min(2, max(0, selection + delta))
                })
        }
        .frame(height: 48)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Origem das fotos")
    }
}
