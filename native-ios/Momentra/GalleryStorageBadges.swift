import SwiftUI

struct GalleryStorageBadges: View {
    let badges: [GalleryItem.StorageBadge]
    let captureID: UUID?
    @ObservedObject private var progress = CloudUploadProgress.shared

    private var displayedBadges: [GalleryItem.StorageBadge] {
        var result = badges
        let known = Set(badges.map(\.id))
        let queued = captureID.flatMap { progress.destinations[$0] } ?? [:]
        for state in queued.values.sorted(by: { $0.id < $1.id }) where !known.contains(state.id) {
            result.append(.init(id: state.id, origin: state.origin, label: state.label))
        }
        return result
    }

    var body: some View {
        let badges = displayedBadges
        ViewThatFits(in: .horizontal) {
            row(badges[...]).fixedSize()
            GeometryReader { proxy in
                let columns = max(1, Int((proxy.size.width - 5) / 19))
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(Array(stride(from: 0, to: badges.count, by: columns)), id: \.self) { start in
                        row(badges[start..<min(start + columns, badges.count)])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
        }
        .padding(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badges.map { badge in
            guard let id = captureID, let state = progress.destinations[id]?[badge.id], state.fraction < 1 else { return badge.label }
            return "\(badge.label), envio \(Int(state.fraction * 100)) por cento"
        }.joined(separator: ", "))
        .allowsHitTesting(false)
    }

    private func row(_ badges: ArraySlice<GalleryItem.StorageBadge>) -> some View {
        HStack(spacing: 3) {
            ForEach(badges) { badge in
                let value = captureID.flatMap { progress.destinations[$0]?[badge.id]?.fraction }
                ZStack(alignment: .bottom) {
                    GalleryOriginMark(origin: badge.origin, size: badge.origin == .local ? 14 : 11)
                        .grayscale(value == nil || value == 1 ? 0 : 1)
                        .opacity(value == nil || value == 1 ? 1 : 0.35)
                    if let value, value < 1 {
                        GalleryOriginMark(origin: badge.origin, size: badge.origin == .local ? 14 : 11)
                            .mask(alignment: .bottom) { Rectangle().frame(height: CGFloat(value) * 11) }
                    }
                }
                .frame(width: 16, height: 16)
                .background(.white.opacity(0.88), in: Circle())
                .overlay { Circle().strokeBorder(.black.opacity(0.26), lineWidth: 0.5) }
            }
        }
    }
}
