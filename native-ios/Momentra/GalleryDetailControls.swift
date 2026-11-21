import SwiftUI

struct GalleryDetailHeader<Actions: View>: View {
    let date: Date?
    let position: Int
    let count: Int
    let close: () -> Void
    var overview: (() -> Void)? = nil
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { FotomarcoHaptics.play(.gallery); close() }) {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .modifier(GalleryControlSurface(rounded: true, tint: .yellow))
            }
            .accessibilityLabel("Voltar à galeria")
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                if let date {
                    Text(dayLabel(date)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Visualização").font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 20).frame(minHeight: 44)
            .modifier(GalleryControlSurface(rounded: true))
            .accessibilityElement(children: .combine)
            .accessibilityHint("\(position) de \(count)")
            Spacer(minLength: 0)
            if let overview {
                Button(action: { FotomarcoHaptics.play(.gallery); overview() }) {
                    Image(systemName: "square.grid.3x3").frame(width: 44, height: 44)
                        .modifier(GalleryControlSurface(rounded: true))
                }
                .accessibilityLabel("Mostrar grade")
            }
            actions()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.black)
        .foregroundStyle(.white)
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Hoje" }
        if Calendar.current.isDateInYesterday(date) { return "Ontem" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct GalleryCameraSwipe: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 16, coordinateSpace: .global).onEnded { gesture in
                let distance = gesture.translation
                if distance.height > 55, distance.height > abs(distance.width) * 1.4 { action() }
            })
    }
}

struct GalleryTrashButton: View {
    let label: String
    let message: String
    let confirm: () -> Void
    @State private var showingConfirmation = false

    var body: some View {
        Button { FotomarcoHaptics.play(.gallery); showingConfirmation = true } label: {
            Image(systemName: "trash").frame(width: 44, height: 44)
                .modifier(GalleryControlSurface(rounded: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .popover(isPresented: $showingConfirmation, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Mover para a lixeira?", systemImage: "trash")
                    .font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    FotomarcoHaptics.play(.gallery)
                    showingConfirmation = false
                    confirm()
                } label: {
                    Text("Mover para a lixeira").fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
            .padding(18).frame(idealWidth: 275, maxWidth: 290)
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct GalleryDetailGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let choose: (Item) -> Void
    @ViewBuilder let tile: (Item) -> Tile
    @Environment(\.dismiss) private var dismiss
    @State private var columns = 3

    var body: some View {
        NavigationStack {
            GalleryGrid(groups: [GalleryGroup(date: nil, profile: nil, items: items)],
                        selecting: .constant(false), selected: .constant([]), columns: $columns,
                        showsSectionHeaders: false, tile: tile, open: { item in
                choose(item)
                dismiss()
            })
            .navigationTitle("Nesta galeria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Concluído") { FotomarcoHaptics.play(.gallery); dismiss() } }
        }
    }
}

struct GalleryFilmstrip<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    @Binding var selection: Item.ID
    var overlayBackground = false
    @ViewBuilder let tile: (Item) -> Tile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(items) { item in
                        Button { FotomarcoHaptics.play(.gallery); selection = item.id } label: {
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
        .background(overlayBackground ? Color.clear : Color.black)
    }
}
