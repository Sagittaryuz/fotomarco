import SwiftUI
import UIKit

struct AppIconPicker: View {
    private struct Choice: Identifiable {
        let id: String
        let title: String
        var iconName: String? { id == "original" ? nil : id }
        var preview: String { id == "original" ? "IconPreviewOriginal" : "Preview" + id }
    }
    private let choices = [
        Choice(id: "original", title: "Original"),
        Choice(id: "MomentraIcon1", title: "Câmera"),
        Choice(id: "MomentraIcon2", title: "Essencial"),
        Choice(id: "MomentraIcon3", title: "Lente"),
        Choice(id: "MomentraIcon4", title: "Localização"),
        Choice(id: "MomentraIcon5", title: "Bússola"),
        Choice(id: "MomentraIcon6", title: "Instante"),
        Choice(id: "MomentraIcon7", title: "Clássico"),
        Choice(id: "MomentraIcon8", title: "Monograma")
    ]
    @State private var selected = UIApplication.shared.alternateIconName
    @State private var changing = false
    @State private var message: String?
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(choices) { choice in
                    Button { choose(choice) } label: {
                        VStack(spacing: 7) {
                            Image(choice.preview).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    if selected == choice.iconName {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .blue)
                                            .font(.title3).padding(4)
                                    }
                                }
                            Text(choice.title).font(.caption).foregroundStyle(.primary)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(changing || !UIApplication.shared.supportsAlternateIcons)
                    .accessibilityLabel("Ícone \(choice.title)")
                    .accessibilityAddTraits(selected == choice.iconName ? .isSelected : [])
                }
            }.padding()
            Text("O iPhone usa a versão clara ou escura conforme a aparência escolhida na Tela de Início.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
        }
        .navigationTitle("Ícone do aplicativo")
        .alert("Não foi possível alterar o ícone", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func choose(_ choice: Choice) {
        guard selected != choice.iconName else { return }
        changing = true
        UIApplication.shared.setAlternateIconName(choice.iconName) { error in
            DispatchQueue.main.async {
                changing = false
                if let error { message = error.localizedDescription }
                else { selected = UIApplication.shared.alternateIconName }
            }
        }
    }
}
