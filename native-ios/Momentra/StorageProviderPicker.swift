import SwiftUI

/// Shared provider chooser for personal accounts and organization storage.
struct StorageProviderPicker<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form {
            Section {
                content
            } header: {
                VStack(spacing: 18) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "calendar")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .padding(5).background(.black, in: Circle()).offset(x: 5, y: 5)
                    }.accessibilityHidden(true)
                    Text("Adicionar Conta").font(.title.bold()).foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    Text("Escolha seu provedor").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                }.frame(maxWidth: .infinity).padding(.top, 36)
            }.textCase(nil)
        }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }
}

struct StorageProviderLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    let asset: String

    var body: some View {
        Label {
            Text(name).font(.title3).foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
        } icon: {
            Image(asset).renderingMode(.original).resizable().scaledToFit().frame(width: 40, height: 40)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(name)
    }
}
