import SwiftUI
import UIKit

struct AppIconPicker: View {
    private static let originalIconName = "MomentraIconOriginal"

    private struct Choice: Identifiable {
        let id: String
        let title: String
        var preview: String { id == AppIconPicker.originalIconName ? "IconPreviewOriginal" : "Preview" + id }
    }
    private let choices = [
        Choice(id: AppIconPicker.originalIconName, title: "Padrão"),
        Choice(id: "MomentraIcon1", title: "Câmera"),
        Choice(id: "MomentraIcon2", title: "Essencial"),
        Choice(id: "MomentraIcon3", title: "Lente"),
        Choice(id: "MomentraIcon4", title: "Localização"),
        Choice(id: "MomentraIcon5", title: "Bússola"),
        Choice(id: "MomentraIcon6", title: "Instante"),
        Choice(id: "MomentraIcon7", title: "Clássico"),
        Choice(id: "MomentraIcon8", title: "Monograma")
    ]
    @AppStorage("native.appIcon.lastApplied") private var lastApplied = ""
    @State private var selected = AppIconPicker.originalIconName
    @State private var changing = false
    @State private var message: String?
    @Environment(\.scenePhase) private var scenePhase
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        ScrollView {
            Text(choices.first(where: { $0.id == selected }).map { "Ícone atual: \($0.title)" } ?? "Não foi possível identificar o ícone atual.")
                .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(choices) { choice in
                    Button { choose(choice) } label: {
                        VStack(spacing: 7) {
                            Image(choice.preview).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(selected == choice.id ? Color.blue : Color.clear, lineWidth: 3))
                                .overlay(alignment: .topTrailing) {
                                    if selected == choice.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .blue)
                                            .font(.title3).padding(4)
                                    }
                                }
                            Text(choice.title).font(.caption).foregroundStyle(.primary)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(changing || !UIApplication.shared.supportsAlternateIcons)
                    .accessibilityLabel("Ícone \(choice.title)")
                    .accessibilityAddTraits(selected == choice.id ? .isSelected : [])
                }
            }.padding()
            Text("O iPhone usa a versão clara ou escura conforme a aparência escolhida na Tela de Início.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
        }
        .onAppear { refreshSelection() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !changing { refreshSelection() }
        }
        .navigationTitle("Ícone do aplicativo")
        .alert("Não foi possível alterar o ícone", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func refreshSelection() {
        if let name = UIApplication.shared.alternateIconName {
            selected = name
            lastApplied = name
        } else {
            selected = choices.contains { $0.id == lastApplied } ? lastApplied : Self.originalIconName
        }
    }

    private func choose(_ choice: Choice) {
        let app = UIApplication.shared
        guard app.alternateIconName != choice.id else { return }
        changing = true
        // The named default remains selectable even when iOS reports no alternate.
        app.setAlternateIconName(choice.id) { error in
            DispatchQueue.main.async {
                changing = false
                if let error { message = error.localizedDescription }
                else {
                    lastApplied = choice.id
                    selected = choice.id
                }
            }
        }
    }
}
