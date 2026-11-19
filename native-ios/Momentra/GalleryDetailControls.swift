import SwiftUI

struct GalleryDetailHeader<Actions: View>: View {
    let date: Date?
    let position: Int
    let count: Int
    let close: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 8) {
            Capsule().fill(.white.opacity(0.38)).frame(width: 32, height: 3)
                .accessibilityHidden(true)
            HStack(spacing: 12) {
                Button(action: close) {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .foregroundStyle(.yellow).frame(width: 44, height: 44)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                }
                .accessibilityLabel("Voltar à galeria")
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    if let date {
                        Text(date, format: .dateTime.day().month(.abbreviated).year()).font(.subheadline.weight(.semibold))
                        Text(date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Visualização").font(.subheadline.weight(.semibold))
                    }
                    Text("\(position) de \(count)").font(.caption2.monospacedDigit()).foregroundStyle(.yellow)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                actions().frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.94))
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { gesture in
            let y = gesture.translation.height
            if y > 42, y > abs(gesture.translation.width) * 1.25 { close() }
        })
    }
}

struct GalleryFilmstrip<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    @Binding var selection: Item.ID
    @ViewBuilder let tile: (Item) -> Tile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(items) { item in
                        Button { selection = item.id } label: {
                            tile(item)
                                .frame(width: 40, height: 44).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5).strokeBorder(
                                        selection == item.id ? .yellow : .clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityLabel("Abrir item")
                        .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear { reader.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, id in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: 54)
        .background(.black)
    }
}
