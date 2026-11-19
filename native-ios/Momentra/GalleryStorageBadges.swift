import SwiftUI

struct GalleryStorageBadges: View {
    let badges: [GalleryItem.StorageBadge]

    var body: some View {
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
        .accessibilityLabel(badges.map(\.label).joined(separator: ", "))
        .allowsHitTesting(false)
    }

    private func row(_ badges: ArraySlice<GalleryItem.StorageBadge>) -> some View {
        HStack(spacing: 3) {
            ForEach(badges) { badge in
                Group {
                    if badge.usesInternalDrive {
                        Image(systemName: "internaldrive").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.black)
                    } else {
                        GalleryOriginMark(origin: badge.origin, size: badge.origin == .local ? 14 : 11)
                    }
                }
                .frame(width: 16, height: 16)
                .background(.white.opacity(0.88), in: Circle())
                .overlay { Circle().strokeBorder(.black.opacity(0.26), lineWidth: 0.5) }
            }
        }
    }
}
