import SwiftUI
import UIKit

private struct OfflineCloudPreview: Identifiable {
    let id: UUID
    let date: Date
    let url: URL
    let profile: CaptureProfileTag?
}

/// Reduced local previews are explicitly labelled; they are not the cloud original.
struct CloudOfflinePreviews: View {
    let ownerHash: String
    let columnCount: Int
    let profiles: PhotoProfileLookup
    @State private var items: [OfflineCloudPreview] = []
    @State private var selected: OfflineCloudPreview?

    private var groups: [GalleryGroup<OfflineCloudPreview>] {
        GalleryGrouping.groups(items, date: { $0.date }, profile: { $0.profile })
    }

    var body: some View {
        Group {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prévias disponíveis neste iPhone").font(.headline).padding(.horizontal)
                Text("Estas prévias têm resolução reduzida. Para abrir os originais, conecte-se à internet.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(.headline).padding(.horizontal, 12)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: columnCount), spacing: 3) {
                            ForEach(group.items) { item in
                                Button { selected = item } label: {
                                    if let image = UIImage(contentsOfFile: item.url.path) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fill).clipped()
                                    }
                                }
                                .accessibilityLabel("Abrir prévia reduzida")
                            }
                        }
                    }
                }
            }
            .sheet(item: $selected) { item in
                NavigationStack {
                    Group {
                        if let image = UIImage(contentsOfFile: item.url.path) {
                            Image(uiImage: image).resizable().scaledToFit().padding()
                        }
                    }
                    .navigationTitle("Prévia reduzida")
                    .toolbar { Button("Concluído") { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.2); selected = nil } }
                }
            }
        }
        }
        .task(id: ownerHash) {
            guard !ownerHash.isEmpty,
                  let root = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                          appropriateFor: nil, create: false),
                  let entries = try? CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending")).entries(ownerHash: ownerHash)
            else { items = []; return }
            items = entries.filter { $0.phase == .cleaned || $0.phase == .cleaning }.compactMap { entry in
                let url = root.appendingPathComponent("CloudThumbnails").appendingPathComponent(entry.id.uuidString + ".jpg")
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return OfflineCloudPreview(id: entry.id, date: entry.createdAt, url: url, profile: profiles.captures[entry.id])
            }
        }
    }
}
