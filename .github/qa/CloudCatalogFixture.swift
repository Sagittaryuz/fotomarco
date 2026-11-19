import SwiftUI

struct CloudCatalogFixture: ViewModifier {
    @State private var ready = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if ready {
                    Text("Catálogo disponível").font(.caption2)
                        .accessibilityIdentifier("cloud-catalog-fixture")
                }
            }
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                guard arguments.contains("-galleryCloudFixture") else { return }
                let destination = CloudDeliveryPlan.Destination(provider: .googleDrive,
                    accountHash: String(repeating: "a", count: 64))!
                if arguments.contains("-seedGalleryCloudFixture") {
                    let entry = CloudGalleryCatalog.Entry(id: "fixture", name: "00000000-0000-0000-0000-000000000010-stamped.jpg",
                                                         date: .now, revision: "1")
                    let existing = await CloudGalleryCatalog.shared.snapshot(for: destination)
                    await CloudGalleryCatalog.shared.replace([entry], for: destination, replacing: existing?.revision)
                    GalleryCapacityCache().store(.init(total: 100, used: 31), for: destination)
                }
                CloudArchiveAccounts.shared.installCloudCatalogFixture(destination)
                ready = true
            }
    }
}
